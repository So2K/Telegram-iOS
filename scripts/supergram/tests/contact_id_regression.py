#!/usr/bin/env python3
"""Compile exact contact parser bodies against production PeerId.Id validation.

Also reproduce the previous bounds failure in a subprocess, without opening a
malformed URL on the real account or sending contacts/messages.
"""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]

def block(source, marker):
    start = source.index(marker)
    opening = source.index("{", start)
    depth, end = 1, opening + 1
    while depth:
        if source[end] == "{":
            depth += 1
        elif source[end] == "}":
            depth -= 1
        end += 1
    return source[start:end] + "\n"

peer = (ROOT / "submodules/Postbox/Sources/Peer.swift").read_text()
url = (ROOT / "submodules/UrlHandling/Sources/UrlHandling.swift").read_text()
device = (ROOT / "submodules/AccountContext/Sources/DeviceContactData.swift").read_text()
siri = (ROOT / "Telegram/SiriIntents/IntentContacts.swift").read_text()
peer_id = block(peer, "public struct Id: Comparable, Hashable, Codable")
device_parser = block(device, "public func parseAppSpecificContactReference(").replace("parseAppSpecificContactReference", "parseDeviceContactReference", 1)
siri_parser = block(siri, "private func parseAppSpecificContactReference(").replace("parseAppSpecificContactReference", "parseSiriContactReference", 1)
branch_start = url.index("} else if pathComponents[0].hasPrefix(phonebookUsernamePathPrefix), let idValue")
condition_start = branch_start + len("} else if ")
condition_end = url.index(" {", condition_start)
url_condition = url[condition_start:condition_end]

swift = "import Foundation\npublic struct PeerId {\n" + peer_id + "public let namespace: Int32\npublic let id: Id\npublic init(namespace: Int32, id: Id) { self.namespace = namespace; self.id = id }\n}\n"
swift += r'''
public enum EnginePeer { public typealias Id = PeerId }
enum Namespaces { enum Peer { static let CloudUser: Int32 = 0 } }
let phonebookUsernamePathPrefix = "@id"
let phonebookUsernamePrefix = "https://t.me/" + phonebookUsernamePathPrefix
'''
swift += device_parser + siri_parser
swift += "func parseContactUrlPath(_ path: String) -> PeerId? { let pathComponents = [path]; if " + url_condition + " { return PeerId(namespace: 0, id: ._internalFromInt64Value(idValue)) }; return nil }\n"
swift += r'''
if CommandLine.arguments.contains("--reproduce-old-bounds") {
    // This is the exact old predicate: Int64 parsing succeeded and id > 0.
    let oldId = Int64("9223372036854775807")!
    precondition(oldId > 0)
    _ = PeerId.Id._internalFromInt64Value(oldId)
    fatalError("expected production assertion before reaching this line")
}
let invalid = ["0", "-1", "-9223372036854775808", "72057594037927936", "9223372036854775807", "9223372036854775808", "-9223372036854775809", "", "12x", " 12"]
for id in invalid {
    let value = "https://t.me/@id" + id
    precondition(parseDeviceContactReference(value) == nil, "device accepted invalid id: " + id)
    precondition(parseSiriContactReference(value) == nil, "Siri accepted invalid id: " + id)
    precondition(parseContactUrlPath("@id" + id) == nil, "URL accepted invalid id: " + id)
}
for id in [Int64(1), 42, 7_000_000_000, 0x00ffffffffffffff] {
    let value = "https://t.me/@id" + String(id)
    precondition(parseDeviceContactReference(value)?.id._internalGetInt64Value() == id)
    precondition(parseSiriContactReference(value)?.id._internalGetInt64Value() == id)
    precondition(parseContactUrlPath("@id" + String(id))?.id._internalGetInt64Value() == id)
}
precondition(parseDeviceContactReference("https://example.com/@id1") == nil)
precondition(parseSiriContactReference("https://example.com/@id1") == nil)
precondition(parseContactUrlPath("username") == nil)
print("PASS: device/Siri/URL contact parsers reject negative, zero, overflow and >56-bit ids; valid ids preserved")
'''
with tempfile.TemporaryDirectory(prefix="supergram-contact-id-") as temporary:
    source = Path(temporary) / "main.swift"
    executable = Path(temporary) / "regression"
    source.write_text(swift)
    subprocess.run(["xcrun", "swiftc", "-Onone", str(source), "-o", str(executable)], check=True)
    baseline = subprocess.run([str(executable), "--reproduce-old-bounds"], capture_output=True, text=True)
    if baseline.returncode == 0 or "Assertion failed" not in baseline.stderr:
        raise AssertionError("expected the old >0-only predicate to fail production PeerId.Id assertion")
    print("PASS: reproduced original positive Int64/PeerId 56-bit assertion mismatch in isolated process")
    subprocess.run([str(executable)], check=True)
