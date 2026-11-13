#!/usr/bin/env python3
"""Prepare private public-metadata inputs; no password, private key or signing.

The separately reviewed preflight binary must provide a positive read-only
contract. The original approved signing candidate has no such CLI contract.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import plistlib
import stat
import subprocess

import validate_notification_package as validator

# Pinned after independent and root review of the non-instrumented CLI branch.
# Changing this binary requires fresh review; the legacy deployed signer is separate.
PREFLIGHT_SIGNER_SHA256 = "f704d3ba0185310884a0fa891fd842810514666e5442debd7f9bfa766e030513"
PREFLIGHT_SUCCESS = "SUPERGRAM_STRICT_PREFLIGHT_V1_OK\n"


read_public_file = validator.read_bounded_public_file

def write_private(path, data):
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "wb") as stream:
        stream.write(data)


def signer_identity(path):
    if not Path(path).is_file() or not os.access(path, os.X_OK):
        raise ValueError("explicit executable preflight signer is required")
    if len(PREFLIGHT_SIGNER_SHA256) != 64:
        raise ValueError("integration is disabled until the new preflight binary is independently reviewed and pinned")
    value = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1048576), b""):
            value.update(block)
    if value.hexdigest() != PREFLIGHT_SIGNER_SHA256:
        raise ValueError("explicit preflight signer does not match the reviewed binary")


def prepare(app, expected, main_profile, service_profile, main_entitlements, certificate_file, signer, directory):
    # A missing NSE profile fails before any other material, including the signer.
    service_bytes = read_public_file(service_profile, 8388608)
    main_bytes = read_public_file(main_profile, 8388608)
    template_bytes = read_public_file(main_entitlements, 1048576)
    certificate = validator.decode_public_certificate(read_public_file(certificate_file, 262144))
    signer_identity(signer)
    directory = Path(directory).resolve(strict=True)
    app = Path(app).resolve(strict=True)
    stage = app.parent.parent if app.parent.name == "Payload" else app
    try:
        directory.relative_to(stage)
    except ValueError:
        pass
    else:
        raise ValueError("private signing inputs must be outside the archive staging root")
    info = directory.stat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o700 or any(directory.iterdir()):
        raise ValueError("a fresh private owned input directory with mode700 is required")
    profiles = [validator.decode_profile(main_bytes), validator.decode_profile(service_bytes)]
    try:
        desired_main = plistlib.loads(template_bytes)
    except ValueError as error:
        raise ValueError("approved main entitlement template is invalid") from error
    desired_service = {
        "application-identifier": expected.team_id + "." + expected.bundle_id + ".NotificationService",
        "com.apple.developer.team-identifier": expected.team_id,
        "com.apple.security.application-groups": [expected.app_group],
        "get-task-allow": False,
    }
    identifiers = [expected.bundle_id, expected.bundle_id + ".NotificationService"]
    desired = [desired_main, desired_service]
    for profile, rights, identifier in zip(profiles, desired, identifiers):
        errors = validator.strict_profile_errors(profile, identifier, expected, datetime.now(timezone.utc), certificate)
        if not isinstance(rights, dict):
            errors.append("desired rights are not a dictionary")
        elif isinstance(profile, dict) and isinstance(profile.get("Entitlements"), dict):
            errors.extend(validator.signed_entitlement_errors(rights, profile, identifier, expected))
        if errors:
            raise ValueError("notification signing metadata preflight failed: " + "; ".join(errors))
    paths = [directory / "main.mobileprovision", directory / "service.mobileprovision"]
    for path, data in zip(paths, [main_bytes, service_bytes]):
        write_private(path, data)
    public_certificate = directory / "intended-certificate.der"
    write_private(public_certificate, certificate)
    entitlements = [directory / "main.entitlements", directory / "service.entitlements"]
    # Preserve approved main template bytes: normalizing with plistlib would hide
    # duplicate keys or binary input from the native strict XML/DER admission.
    write_private(entitlements[0], template_bytes)
    write_private(entitlements[1], plistlib.dumps(desired_service, fmt=plistlib.FMT_XML, sort_keys=True))
    package = validator.Package(app)
    try:
        result = validator.validate(package, expected, {"main": paths[0], "NotificationService": paths[1]}, signing_certificate=certificate)
    finally:
        package.close()
    if not result["valid"] or result["extension_count"] != 1:
        raise ValueError("NSE-only package/profile preflight failed")
    mapping = [{"bundle_id": identifier, "profile_path": str(path), "entitlements_path": str(rights)}
               for identifier, path, rights in zip(identifiers, paths, entitlements)]
    manifest = directory / "bundle-signing-map.json"
    write_private(manifest, (json.dumps(mapping, indent=2) + "\n").encode())
    result = subprocess.run([str(Path(signer).resolve()), "--preflight-only", "--bundle-signing-map", str(manifest), str(app)],
                            capture_output=True, text=True, timeout=120)
    if result.returncode != 0 or result.stdout != PREFLIGHT_SUCCESS or result.stderr:
        raise ValueError("reviewed signer did not return its positive read-only preflight contract")
    return {"signing_map": str(manifest), "certificate": str(public_certificate), "signer_sha256": PREFLIGHT_SIGNER_SHA256}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    for option in ("main-profile", "service-profile", "main-entitlements", "signing-certificate", "strict-signer", "input-directory", "output"):
        parser.add_argument("--" + option, type=Path, required=True)
    for option in ("build", "version", "bundle-id", "team-id", "app-group", "device-id"):
        parser.add_argument("--" + option, required=True)
    a = parser.parse_args()
    try:
        result = prepare(a.app, a, a.main_profile, a.service_profile, a.main_entitlements, a.signing_certificate,
                         a.strict_signer, a.input_directory)
        a.output.write_text(json.dumps(result) + "\n")
        print("strict notification public-metadata/resource preflight PASS; no password or private key read")
        return 0
    except (OSError, ValueError, subprocess.TimeoutExpired) as error:
        print("strict notification preflight failed: " + str(error))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
