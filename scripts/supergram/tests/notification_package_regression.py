#!/usr/bin/env python3
"""Synthetic notification-package metadata tests; no signing, device or account.

Exercises the real validator against app/IPA fixtures and boundary/mismatch
profiles. Synthetic CMS/signature decoding is replaced with plist decoding;
actual signed IPA/profile inspection is a separate integration check.
"""
from copy import deepcopy
from datetime import datetime, timedelta, timezone
import importlib.util
from pathlib import Path
import plistlib
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
import zipfile

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("notification_package", ROOT / "scripts/supergram/validate_notification_package.py")
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)
NOW = datetime(2026, 10, 9, tzinfo=timezone.utc)
EXPECTED = SimpleNamespace(bundle_id="app.test.client", team_id="TEAM123456", app_group="group.test.shared",
                           device_id="selected-device", build="10029", version="12.8")


def profile(bundle_id):
    return {"TeamIdentifier": [EXPECTED.team_id], "ExpirationDate": (NOW + timedelta(days=365)).replace(tzinfo=None),
            "ProvisionedDevices": [EXPECTED.device_id], "DeveloperCertificates": [b"same-signing-certificate"],
            "Entitlements": {"application-identifier": EXPECTED.team_id + "." + bundle_id,
                             "com.apple.developer.team-identifier": EXPECTED.team_id, "get-task-allow": False,
                             "com.apple.security.application-groups": [EXPECTED.app_group],
                             "keychain-access-groups": [EXPECTED.team_id + ".*"], "aps-environment": "production"}}


def entitlements(bundle_id):
    result = deepcopy(profile(bundle_id)["Entitlements"])
    result["keychain-access-groups"] = [EXPECTED.team_id + "." + bundle_id]
    return result


def info(bundle_id, extension=None):
    result = {"CFBundleIdentifier": bundle_id, "CFBundleVersion": EXPECTED.build,
              "CFBundleShortVersionString": EXPECTED.version, "CFBundleExecutable": "executable"}
    if extension:
        point, principal = validator.EXTENSIONS[extension]
        result.update({"CFBundlePackageType": "XPC!", "NSExtension": {"NSExtensionPointIdentifier": point,
                        "NSExtensionPrincipalClass": principal}})
        if extension == "NotificationContent":
            result["NSExtension"]["NSExtensionAttributes"] = {"UNNotificationExtensionCategory": ["withMuteMedia", "withReplyMedia"]}
    return result


def fixture(path, extensions=True):
    path.mkdir()
    for name in [None] + (list(validator.EXTENSIONS) if extensions else []):
        bundle_id = EXPECTED.bundle_id + ("." + name if name else "")
        folder = path / ("PlugIns/" + name + ".appex" if name else "")
        folder.mkdir(parents=True, exist_ok=True)
        (folder / "Info.plist").write_bytes(plistlib.dumps(info(bundle_id, name)))
        (folder / "embedded.mobileprovision").write_bytes(plistlib.dumps(profile(bundle_id)))
        (folder / "executable").write_bytes(plistlib.dumps(entitlements(bundle_id)))


def run_package(path, **kwargs):
    package = validator.Package(path)
    try:
        with patch.object(validator, "decode_profile", plistlib.loads), patch.object(validator, "decode_entitlements", plistlib.loads):
            return validator.validate(package, EXPECTED, **kwargs)
    finally:
        package.close()


class NotificationPackageTests(unittest.TestCase):
    def test_valid_explicit_profile(self):
        self.assertEqual(validator.profile_errors(profile(EXPECTED.bundle_id), EXPECTED.bundle_id, EXPECTED, NOW), [])

    def test_profile_mismatches(self):
        cases = [
            (lambda p: p["Entitlements"].update({"application-identifier": EXPECTED.team_id + ".*"}), "exact bundle ID"),
            (lambda p: p["Entitlements"].update({"application-identifier": EXPECTED.team_id + ".other"}), "exact bundle ID"),
            (lambda p: p.update({"TeamIdentifier": ["OTHERTEAM"]}), "team mismatch"),
            (lambda p: p["Entitlements"].update({"com.apple.developer.team-identifier": "OTHERTEAM"}), "team mismatch"),
            (lambda p: p["Entitlements"].update({"com.apple.security.application-groups": ["group.other"]}), "shared app group"),
            (lambda p: p["Entitlements"].update({"get-task-allow": True}), "distribution profile"),
            (lambda p: p.update({"ExpirationDate": NOW.replace(tzinfo=None)}), "expired"),
            (lambda p: p.pop("ExpirationDate"), "expiration"),
            (lambda p: p.update({"ProvisionedDevices": ["other-device"]}), "selected device"),
            (lambda p: p.update({"DeveloperCertificates": []}), "signing certificate"),
            (lambda p: p["Entitlements"].update({"aps-environment": "development"}), "production APNs"),
        ]
        for mutate, message in cases:
            with self.subTest(message=message):
                value = profile(EXPECTED.bundle_id)
                mutate(value)
                self.assertTrue(any(message in error for error in validator.profile_errors(value, EXPECTED.bundle_id, EXPECTED, NOW)))

    def test_service_profile_does_not_require_independent_push(self):
        bundle_id = EXPECTED.bundle_id + ".NotificationService"
        value = profile(bundle_id)
        value["Entitlements"].pop("aps-environment")
        self.assertEqual(validator.profile_errors(value, bundle_id, EXPECTED, NOW), [])

    def test_signature_uses_extension_identifier(self):
        bundle_id = EXPECTED.bundle_id + ".NotificationService"
        self.assertEqual(validator.signed_entitlement_errors(entitlements(bundle_id), profile(bundle_id), bundle_id, EXPECTED), [])
        errors = validator.signed_entitlement_errors(entitlements(EXPECTED.bundle_id), profile(bundle_id), bundle_id, EXPECTED)
        self.assertTrue(any("application-identifier mismatch" in error for error in errors))

    def test_signature_requires_exact_shared_group(self):
        value = entitlements(EXPECTED.bundle_id)
        value["com.apple.security.application-groups"].append("group.extra")
        self.assertTrue(any("exactly the shared" in error for error in validator.signed_entitlement_errors(value, profile(EXPECTED.bundle_id), EXPECTED.bundle_id, EXPECTED)))

    def test_entitlement_permissions(self):
        self.assertTrue(validator.entitlement_allowed([EXPECTED.team_id + ".app.test.client"], [EXPECTED.team_id + ".*"]))
        self.assertFalse(validator.entitlement_allowed(["OTHERTEAM.app.test.client"], [EXPECTED.team_id + ".*"]))
        self.assertFalse(validator.entitlement_allowed(True, False))
        value = entitlements(EXPECTED.bundle_id)
        value["ungranted.capability"] = True
        self.assertTrue(any("not authorized" in error for error in validator.signed_entitlement_errors(value, profile(EXPECTED.bundle_id), EXPECTED.bundle_id, EXPECTED)))

    def test_info_mismatches(self):
        name = "NotificationContent"
        bundle_id = EXPECTED.bundle_id + "." + name
        cases = [
            (lambda i: i.update({"CFBundleIdentifier": "wrong"}), "bundle ID"),
            (lambda i: i.update({"CFBundleVersion": "10028"}), "build mismatch"),
            (lambda i: i.update({"CFBundleShortVersionString": "12.7"}), "version mismatch"),
            (lambda i: i.update({"CFBundleExecutable": "../outside"}), "executable"),
            (lambda i: i.update({"CFBundlePackageType": "APPL"}), "package type"),
            (lambda i: i["NSExtension"].update({"NSExtensionPointIdentifier": "wrong"}), "extension point"),
            (lambda i: i["NSExtension"].update({"NSExtensionPrincipalClass": "wrong"}), "principal class"),
            (lambda i: i["NSExtension"]["NSExtensionAttributes"].update({"UNNotificationExtensionCategory": ["withReply"]}), "categories"),
        ]
        for mutate, message in cases:
            with self.subTest(message=message):
                value = info(bundle_id, name)
                mutate(value)
                self.assertTrue(any(message in error for error in validator.info_errors(value, bundle_id, EXPECTED, name)))

    def test_valid_app_and_signed_ipa(self):
        with tempfile.TemporaryDirectory() as temp:
            app = Path(temp) / "Telegram.app"
            fixture(app)
            self.assertTrue(run_package(app, signed=True)["valid"])
            ipa = Path(temp) / "fixture.ipa"
            with zipfile.ZipFile(ipa, "w") as archive:
                for item in app.rglob("*"):
                    if item.is_file():
                        archive.write(item, "Payload/Telegram.app/" + item.relative_to(app).as_posix())
            self.assertTrue(run_package(ipa, signed=True)["valid"])

    def test_missing_extensions_rejected_unless_explicit_legacy(self):
        with tempfile.TemporaryDirectory() as temp:
            app = Path(temp) / "Telegram.app"
            fixture(app, extensions=False)
            self.assertFalse(run_package(app)["valid"])
            result = run_package(app, signed=True, allow_missing=True)
            self.assertTrue(result["valid"])
            self.assertEqual(result["mode"], "legacy-no-notification-extensions")

    def test_partial_extensions_rejected_even_in_legacy_mode(self):
        with tempfile.TemporaryDirectory() as temp:
            app = Path(temp) / "Telegram.app"
            fixture(app)
            import shutil
            shutil.rmtree(app / "PlugIns/NotificationService.appex")
            self.assertFalse(run_package(app, allow_missing=True)["valid"])

    def test_service_only_is_sufficient_for_minimal_packaging(self):
        with tempfile.TemporaryDirectory() as temp:
            app = Path(temp) / "Telegram.app"
            fixture(app)
            import shutil
            shutil.rmtree(app / "PlugIns/NotificationContent.appex")
            result = run_package(app, signed=True)
            self.assertTrue(result["valid"])
            self.assertEqual(result["extension_count"], 1)

    def test_legacy_opt_out_cannot_bypass_extension_signing(self):
        with tempfile.TemporaryDirectory() as temp:
            app = Path(temp) / "Telegram.app"
            fixture(app)
            self.assertFalse(run_package(app, allow_missing=True)["valid"])

    def test_empty_and_misplaced_extension_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            app = Path(temp) / "Telegram.app"
            fixture(app, extensions=False)
            (app / "Extensions/NotificationService.appex").mkdir(parents=True)
            self.assertFalse(run_package(app, allow_missing=True)["valid"])

    def test_different_signing_certificates_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            app = Path(temp) / "Telegram.app"
            fixture(app)
            path = app / "PlugIns/NotificationContent.appex/embedded.mobileprovision"
            value = plistlib.loads(path.read_bytes())
            value["DeveloperCertificates"] = [b"different-certificate"]
            path.write_bytes(plistlib.dumps(value))
            self.assertIn("bundle profiles have no common signing certificate", run_package(app)["errors"])

    def test_unapproved_and_missing_executable_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            app = Path(temp) / "Telegram.app"
            fixture(app)
            path = app / "PlugIns/NotificationService.appex/Info.plist"
            value = plistlib.loads(path.read_bytes())
            value["CFBundleIdentifier"] = "com.old.build.NotificationService"
            path.write_bytes(plistlib.dumps(value))
            (app / "executable").unlink()
            errors = run_package(app)["errors"]
            self.assertTrue(any("outside the two" in error for error in errors))
            self.assertTrue(any("executable missing" in error for error in errors))

    def test_packaging_gate_precedes_secret_read(self):
        source = (ROOT / "scripts/supergram/make_ipa.sh").read_text()
        self.assertLess(source.index('if ! python3 "$VALIDATOR"'), source.index('P12_PASSWORD='))
        self.assertIn('--allow-no-notification-extensions)', source)
        self.assertIn('per-bundle entitlement signing is required', source)
        self.assertIn('"${VALIDATION_ARGS[@]}" --signed', source)


if __name__ == "__main__":
    unittest.main(verbosity=2)
