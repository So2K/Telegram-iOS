#!/usr/bin/env python3
"""Exercise production HLS ownership/dispatch code using real SwiftSignalKit.

The private TempBox owner, request registry, subscription helper, range parser and
response reader are extracted unchanged. Only TempBox and the UIKit/JS context
shell are replaced; queue dispatch, cancellation, reactive delivery and file I/O
are real. The device/framework playback path still requires physical validation.
"""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
SOURCE = ROOT / "submodules/TelegramUniversalVideoContent/Sources/HLSVideoJSNativeContentNode.swift"


def block(source, marker):
    start = source.index(marker)
    opening = source.index("{", start)
    depth, cursor = 1, opening + 1
    while depth:
        depth += (source[cursor] == "{") - (source[cursor] == "}")
        cursor += 1
    return source[start:cursor]


def main():
    source = SOURCE.read_text()
    fixture = (HERE / "hls_request_regressions.swift").read_text()
    parts = {
        "// PRODUCTION_OWNER_AND_REGISTRY": source[source.index("private func parseRange"):source.index("final class HLSJSServerSource:")],
        "// PRODUCTION_START_REQUEST": block(source, "private func startSourceRequest<T>"),
        "// PRODUCTION_RESPONSE_ERROR": block(source, "private enum ResponseError"),
        "// PRODUCTION_SEND_ERROR": block(source, "private static func sendErrorAndClose"),
        "// PRODUCTION_SEND_FILE": block(source, "private static func sendResponseFileAndClose"),
        "// PRODUCTION_PROTOCOL_ADAPTER": block(source, "func fileData(id: Int64"),
        "// PRODUCTION_SOURCE_ID": source.split("self.id = ", 1)[1].split("\n", 1)[0],
    }
    for marker, replacement in parts.items():
        fixture = fixture.replace(marker, replacement)

    # Check that the exercised private machinery is connected to each production lifecycle hook.
    xhr = source.split('} else if className == "XMLHttpRequest"', 1)[1].split("private static func sendErrorAndClose", 1)[0]
    assert "signal: source.ownedFileData(" in xhr
    assert xhr.count("self.startSourceRequest(id:") == 3  # master, playlist, segment
    assert xhr.count("self.sourceRequests.cancel(id: id)") == 2  # replacement, abort
    assert "self.sourceRequests.cancel(contextId: contextInstanceId)" in block(source, "func register(context:")
    assert "self.sourceRequests.cancelAll()" in block(source, "private func disposeJsContext")
    assert "instanceId: instanceId" in source
    owned = block(source, "fileprivate func ownedFileData")
    assert "HLSJSTemporaryFile(file: TempBox.shared.tempFile" in owned
    assert owned.count("subscriber.putNext((partialFileOwner,") == 2
    assert "withExtendedLifetime(partialFileOwner)" in owned
    assert "subscriber.putNext((partialFile," not in owned

    paths = sorted((ROOT / "submodules/SSignalKit/SwiftSignalKit/Source").glob("*.swift"))
    with tempfile.TemporaryDirectory(prefix="supergram-hls-regression-") as directory:
        directory = Path(directory)
        main_swift = directory / "main.swift"
        main_swift.write_text("\n\n".join(path.read_text() for path in paths) + "\n\n" + fixture)
        binary = directory / "hls-regressions"
        result = subprocess.run(["xcrun", "swiftc", "-swift-version", "5", str(main_swift), "-o", str(binary)], capture_output=True, text=True)
        if result.returncode:
            print(result.stdout)
            print(result.stderr)
            raise SystemExit(result.returncode)
        subprocess.run([str(binary)], check=True, timeout=30)


if __name__ == "__main__":
    main()
