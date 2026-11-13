#!/usr/bin/env python3
"""Read-only notification bundle/profile checks; never prints profile payloads or keys.

Accepts a staged .app or an IPA. CMS profiles and Mach-O entitlements are decoded
in memory (temporary input files are removed). This does not sign or install.
"""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import stat
import tempfile
import zipfile


EXTENSIONS = {
    "NotificationService": ("com.apple.usernotifications.service", "NotificationService"),
    "NotificationContent": ("com.apple.usernotifications.content-extension", "NotificationViewController"),
}
REQUIRED_EXTENSIONS = {"NotificationService"}
CONTENT_CATEGORIES = {"withReplyMedia", "withMuteMedia"}


def read_bounded_public_file(path, limit):
    descriptor = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
    try:
        info = os.fstat(descriptor)
        if not stat.S_ISREG(info.st_mode) or info.st_size <= 0 or info.st_size > limit:
            raise ValueError("public input must be a bounded nonempty regular file")
        with os.fdopen(descriptor, "rb", closefd=False) as stream:
            data = stream.read(limit + 1)
        if not data or len(data) > limit:
            raise ValueError("public input exceeds its bound")
        return data
    finally:
        os.close(descriptor)


def certificate_validity(certificate):
    # OpenSSL prints both UTC and GeneralizedTime as RFC822 GMT by default.
    result = subprocess.run(["openssl", "x509", "-inform", "DER", "-noout", "-startdate", "-enddate"],
                            input=certificate, capture_output=True, timeout=20)
    lines = result.stdout.decode("ascii").splitlines()
    if result.returncode or len(lines) != 2:
        raise ValueError("cannot read public certificate validity")
    months = {name: index + 1 for index, name in enumerate(
        ("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"))}
    values = []
    for prefix, line in zip(("notBefore=", "notAfter="), lines):
        if not line.startswith(prefix):
            raise ValueError("public certificate validity fields are missing or ambiguous")
        match = re.fullmatch(r"([A-Za-z]{3})\s+(\d{1,2}) (\d{2}):(\d{2}):(\d{2}) (\d{4}) GMT", line[len(prefix):])
        if not match or match[1] not in months:
            raise ValueError("public certificate validity is not supported UTC time")
        values.append(datetime(int(match[6]), months[match[1]], int(match[2]), int(match[3]), int(match[4]), int(match[5]), tzinfo=timezone.utc))
    if values[0] > values[1]:
        raise ValueError("public certificate validity interval is reversed")
    return tuple(values)


def require_certificate_time(certificate, now=None):
    start, end = certificate_validity(certificate)
    now = datetime.now(timezone.utc) if now is None else now
    if now.tzinfo is None:
        raise ValueError("certificate validity comparison requires an aware UTC time")
    # RFC5280 section4.1.2.5 includes the exact notBefore/notAfter instants.
    if not start <= now.astimezone(timezone.utc) <= end:
        raise ValueError("public signing certificate is expired or not yet valid")


def decode_public_certificate(data, now=None):
    if not data or len(data) > 262144 or b"PRIVATE KEY" in data:
        raise ValueError("a bounded public signing certificate is required")
    for encoding in ("DER", "PEM"):
        result = subprocess.run(["openssl", "x509", "-inform", encoding, "-outform", "DER"],
                                input=data, capture_output=True, timeout=20)
        if result.returncode == 0 and result.stdout:
            require_certificate_time(result.stdout, now)
            return result.stdout
    raise ValueError("cannot decode public signing certificate")


def selected_certificate_errors(profile, certificate):
    certificates = profile.get("DeveloperCertificates") if isinstance(profile, dict) else None
    if not isinstance(certificates, list) or not certificates or any(not isinstance(c, bytes) or not c for c in certificates):
        return ["profile signing certificates are malformed"]
    return [] if certificate in certificates else ["intended public signing certificate is not authorized by profile"]


def strict_profile_errors(profile, bundle_id, expected, now, certificate):
    if not isinstance(profile, dict) or not isinstance(profile.get("Entitlements"), dict):
        return ["profile metadata is not a dictionary"]
    if (profile.get("TeamIdentifier") != [expected.team_id]
            or not isinstance(profile.get("ProvisionedDevices"), list)
            or any(not isinstance(device, str) for device in profile["ProvisionedDevices"])
            or not isinstance(profile["Entitlements"].get("com.apple.security.application-groups"), list)
            or any(not isinstance(group, str) for group in profile["Entitlements"]["com.apple.security.application-groups"])):
        return ["profile team, device or shared-group metadata is malformed"]
    return profile_errors(profile, bundle_id, expected, now) + selected_certificate_errors(profile, certificate)


def decode_signed_certificate(data):
    with tempfile.TemporaryDirectory(prefix="supergram-signed-certificate-") as temp:
        path = Path(temp) / "executable"
        path.write_bytes(data)
        prefix = Path(temp) / "certificate"
        result = subprocess.run(["codesign", "--display", "--extract-certificates=" + str(prefix), str(path)],
                                capture_output=True, timeout=20)
        if result.returncode:
            raise ValueError("cannot read selected signed certificate")
        leaf = Path(str(prefix) + "0")
        return read_bounded_public_file(leaf, 262144)


def entitlement_allowed(value, grant):
    if isinstance(value, str) and isinstance(grant, str):
        return value == grant or (grant.endswith("*") and value.startswith(grant[:-1]))
    if isinstance(value, list) and isinstance(grant, list):
        return all(any(entitlement_allowed(item, permission) for permission in grant) for item in value)
    if isinstance(value, dict) and isinstance(grant, dict):
        return all(key in grant and entitlement_allowed(item, grant[key]) for key, item in value.items())
    return type(value) is type(grant) and value == grant


def profile_errors(profile, bundle_id, expected, now):
    errors = []
    entitlements = profile.get("Entitlements", {})
    if entitlements.get("application-identifier") != expected.team_id + "." + bundle_id:
        errors.append("profile does not authorize the exact bundle ID")
    if (entitlements.get("com.apple.developer.team-identifier") != expected.team_id
            or expected.team_id not in profile.get("TeamIdentifier", [])):
        errors.append("profile team mismatch")
    if expected.app_group not in entitlements.get("com.apple.security.application-groups", []):
        errors.append("profile does not authorize the shared app group")
    if entitlements.get("get-task-allow") is not False:
        errors.append("profile is not a distribution profile (get-task-allow must be false)")
    expiration = profile.get("ExpirationDate")
    if not isinstance(expiration, datetime) or expiration.replace(tzinfo=timezone.utc) <= now:
        errors.append("profile expired or has no expiration")
    if expected.device_id not in profile.get("ProvisionedDevices", []):
        errors.append("profile does not include the selected device")
    if not profile.get("DeveloperCertificates"):
        errors.append("profile has no signing certificate")
    if bundle_id == expected.bundle_id and entitlements.get("aps-environment") != "production":
        errors.append("main profile must authorize production APNs")
    return errors


def signed_entitlement_errors(entitlements, profile, bundle_id, expected):
    errors = []
    if entitlements.get("application-identifier") != expected.team_id + "." + bundle_id:
        errors.append("signature application-identifier mismatch")
    if entitlements.get("com.apple.developer.team-identifier") != expected.team_id:
        errors.append("signature team mismatch")
    if entitlements.get("com.apple.security.application-groups") != [expected.app_group]:
        errors.append("signature must use exactly the shared app group")
    if entitlements.get("get-task-allow") is not False:
        errors.append("signature get-task-allow must be false")
    if bundle_id == expected.bundle_id and entitlements.get("aps-environment") != "production":
        errors.append("main signature must use production APNs")
    for key, value in entitlements.items():
        grant = profile.get("Entitlements", {}).get(key)
        if grant is None or not entitlement_allowed(value, grant):
            errors.append("signature entitlement not authorized by profile: " + key)
    return errors


def info_errors(info, bundle_id, expected, extension=None):
    errors = []
    if info.get("CFBundleIdentifier") != bundle_id:
        errors.append("Info.plist bundle ID mismatch")
    if str(info.get("CFBundleVersion", "")) != expected.build:
        errors.append("Info.plist build mismatch")
    if info.get("CFBundleShortVersionString") != expected.version:
        errors.append("Info.plist version mismatch")
    executable = info.get("CFBundleExecutable")
    if not isinstance(executable, str) or not executable or "/" in executable or executable in (".", ".."):
        errors.append("missing or invalid executable name")
    if extension:
        if info.get("CFBundlePackageType") != "XPC!":
            errors.append("extension package type must be XPC!")
        config = info.get("NSExtension", {})
        point, principal = EXTENSIONS[extension]
        if config.get("NSExtensionPointIdentifier") != point:
            errors.append("extension point mismatch")
        if config.get("NSExtensionPrincipalClass") != principal:
            errors.append("extension principal class mismatch")
        if extension == "NotificationContent":
            categories = config.get("NSExtensionAttributes", {}).get("UNNotificationExtensionCategory")
            if not isinstance(categories, list) or set(categories) != CONTENT_CATEGORIES:
                errors.append("notification content categories mismatch")
    return errors


def framework_errors(package, expected):
    errors = []
    prefixes = set()
    for name in package.names:
        components = name.rstrip('/').split('/')
        for index, component in enumerate(components):
            if component.endswith('.framework'):
                prefixes.add('/'.join(components[:index + 1]) + '/')
    for prefix in sorted(prefixes):
        try:
            info = plistlib.loads(package.read(prefix + 'Info.plist'))
            if not isinstance(info, dict):
                raise ValueError('framework metadata is not a dictionary')
            if info.get('CFBundleVersion') != expected.build:
                errors.append(prefix + ': framework build mismatch or missing build')
            if info.get('CFBundleShortVersionString') != expected.version:
                errors.append(prefix + ': framework version mismatch or missing version')
        except (OSError, KeyError, ValueError, plistlib.InvalidFileException):
            errors.append(prefix + ': missing or invalid framework Info.plist')
    return errors


def decode_profile(data):
    with tempfile.TemporaryDirectory(prefix="supergram-profile-") as temp:
        path = Path(temp) / "profile.mobileprovision"
        path.write_bytes(data)
        result = subprocess.run(["security", "cms", "-D", "-i", str(path)], capture_output=True, timeout=20)
        if result.returncode:
            raise ValueError("cannot decode CMS provisioning profile")
        return plistlib.loads(result.stdout)


def decode_entitlements(data):
    with tempfile.TemporaryDirectory(prefix="supergram-entitlements-") as temp:
        path = Path(temp) / "executable"
        path.write_bytes(data)
        result = subprocess.run(["codesign", "-d", "--entitlements", ":-", str(path)], capture_output=True, timeout=20)
        if result.returncode:
            raise ValueError("cannot read executable signature entitlements")
        for output in (result.stdout, result.stderr):
            start, end = output.find(b"<?xml"), output.find(b"</plist>")
            if start >= 0 and end >= start:
                return plistlib.loads(output[start:end + len(b"</plist>")])
        raise ValueError("executable has no readable signature entitlements")


class Package:
    def __init__(self, path):
        self.path = Path(path)
        self.archive = None
        if self.path.is_dir():
            self.root = ""
            self.names = {p.relative_to(self.path).as_posix() + ("/" if p.is_dir() else "") for p in self.path.rglob("*")}
        else:
            self.archive = zipfile.ZipFile(self.path)
            self.names = set(self.archive.namelist())
            roots = [name[:-len("Info.plist")] for name in self.names
                     if name.startswith("Payload/") and name.count("/") == 2 and name.endswith(".app/Info.plist")]
            if len(roots) != 1:
                self.archive.close()
                raise ValueError("IPA must contain exactly one top-level app")
            self.root = roots[0]
            self.names = {name[len(self.root):] for name in self.names if name.startswith(self.root)}

    def read(self, name):
        return self.archive.read(self.root + name) if self.archive else (self.path / name).read_bytes()

    def close(self):
        if self.archive:
            self.archive.close()


def validate(package, expected, overrides=None, signed=False, allow_missing=False, signing_certificate=None):
    overrides = overrides or {}
    errors, bundles, profiles = framework_errors(package, expected), [], []
    prefixes = {name.split("/")[1] for name in package.names
                if name.startswith("PlugIns/") and len(name.split("/")) >= 3 and name.split("/")[1].endswith(".appex")}
    all_extensions = {name.split(".appex/")[0] + ".appex" for name in package.names if ".appex/" in name}
    if any(not name.startswith("PlugIns/") or name.count("/") != 1 for name in all_extensions):
        errors.append("extension bundle found outside the direct PlugIns directory")
    if allow_missing and all_extensions:
        errors.append("legacy opt-out requires zero extension bundles")
    specs = [("main", "", expected.bundle_id, None)]
    found = set()
    for folder in sorted(prefixes):
        prefix = "PlugIns/" + folder + "/"
        try:
            info = plistlib.loads(package.read(prefix + "Info.plist"))
            bundle_id = info.get("CFBundleIdentifier")
        except (OSError, KeyError, ValueError, plistlib.InvalidFileException):
            errors.append(folder + ": missing or invalid Info.plist")
            continue
        extension = next((suffix for suffix in EXTENSIONS if bundle_id == expected.bundle_id + "." + suffix), None)
        if extension is None:
            errors.append(folder + ": extension is outside the two approved notification bundle IDs")
            continue
        if extension in found:
            errors.append(extension + ": duplicate extension bundle")
        found.add(extension)
        specs.append((extension, prefix, bundle_id, extension))
    missing = sorted(REQUIRED_EXTENSIONS - found)
    if missing and not (allow_missing and not all_extensions):
        errors.extend(name + ": required extension missing" for name in missing)
    for label, prefix, bundle_id, extension in specs:
        bundle_errors = []
        try:
            info = plistlib.loads(package.read(prefix + "Info.plist"))
            bundle_errors.extend(info_errors(info, bundle_id, expected, extension))
            executable = info.get("CFBundleExecutable")
            if isinstance(executable, str) and "/" not in executable and prefix + executable not in package.names:
                bundle_errors.append("executable missing from package")
            data = Path(overrides[label]).read_bytes() if label in overrides else package.read(prefix + "embedded.mobileprovision")
            profile = decode_profile(data)
            if signing_certificate is not None:
                strict_errors = strict_profile_errors(profile, bundle_id, expected, datetime.now(timezone.utc), signing_certificate)
                bundle_errors.extend(strict_errors)
                if strict_errors:
                    raise ValueError("incompatible strict profile metadata")
            else:
                bundle_errors.extend(profile_errors(profile, bundle_id, expected, datetime.now(timezone.utc)))
            profiles.append(profile)
            if signed and not info_errors(info, bundle_id, expected, extension):
                entitlements = decode_entitlements(package.read(prefix + executable))
                bundle_errors.extend(signed_entitlement_errors(entitlements, profile, bundle_id, expected))
                if signing_certificate is not None and decode_signed_certificate(package.read(prefix + executable)) != signing_certificate:
                    bundle_errors.append("actual signed certificate differs from the intended public certificate")
        except (OSError, KeyError, ValueError, plistlib.InvalidFileException, subprocess.TimeoutExpired):
            bundle_errors.append("cannot read bundle, provisioning profile or signature metadata")
        errors.extend(label + ": " + error for error in bundle_errors)
        bundles.append({"bundle": label, "expected_bundle_id": bundle_id, "valid": not bundle_errors})
    if profiles and not set(profiles[0].get("DeveloperCertificates", [])).intersection(
            *(set(profile.get("DeveloperCertificates", [])) for profile in profiles[1:])):
        errors.append("bundle profiles have no common signing certificate")
    return {"valid": not errors, "mode": "legacy-no-notification-extensions" if allow_missing and not all_extensions else "notifications-required",
            "expected_build": expected.build, "extension_count": len(all_extensions), "bundles": bundles, "errors": errors,
            "signature_entitlements_checked": signed}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("package", type=Path)
    parser.add_argument("--build", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--bundle-id", default="app.tomato7991.lime1486")
    parser.add_argument("--team-id", default="G6TLPRYW6Y")
    parser.add_argument("--app-group", default="group.ffcd1c12e1a9728e.1")
    parser.add_argument("--device-id", default="00008130-0004298110698D3A")
    parser.add_argument("--main-profile", type=Path)
    parser.add_argument("--service-profile", type=Path)
    parser.add_argument("--content-profile", type=Path)
    parser.add_argument("--signed", action="store_true")
    parser.add_argument("--signing-certificate", type=Path, help="Public DER/PEM evidence; --signed also compares the actual leaf")
    parser.add_argument("--allow-no-notification-extensions", action="store_true")
    expected = parser.parse_args()
    overrides = {name: path for name, path in (("main", expected.main_profile), ("NotificationService", expected.service_profile),
                                               ("NotificationContent", expected.content_profile)) if path is not None}
    package = None
    try:
        if expected.signed and overrides:
            raise ValueError("signed validation must use embedded provisioning profiles")
        package = Package(expected.package)
        certificate = None
        if expected.signing_certificate is not None:
            certificate = decode_public_certificate(read_bounded_public_file(expected.signing_certificate, 262144))
        result = validate(package, expected, overrides, expected.signed, expected.allow_no_notification_extensions, certificate)
    except (OSError, ValueError, zipfile.BadZipFile, subprocess.TimeoutExpired):
        result = {"valid": False, "errors": ["cannot read app/IPA package metadata"]}
    finally:
        if package:
            package.close()
    print(json.dumps(result, indent=2))
    return 0 if result["valid"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
