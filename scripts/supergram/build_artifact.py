#!/usr/bin/env python3
"""Read-only generated app/artifact checks and owned full-build receipts.

No profiles, credentials, signing or device services are read. Receipt capture
runs only after the wrapper's full-app command succeeds. No metadata is rewritten.
"""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile


class ArtifactError(ValueError):
    pass


def generated_output_base(objects):
    projects = [value for value in objects.values() if value.get('isa') == 'PBXProject']
    if len(projects) != 1:
        raise ArtifactError('generated graph must contain one project')
    configs = [objects[key] for key in objects[projects[0]['buildConfigurationList']]['buildConfigurations']
               if objects[key].get('name') == 'Release']
    if len(configs) != 1:
        raise ArtifactError('generated graph must contain one Release project configuration')
    settings = configs[0]['buildSettings']
    directory = settings.get('PROJECT_DIR')
    if not isinstance(directory, str) or not Path(directory).is_absolute() or '$' in directory:
        raise ArtifactError('generated Release project directory is not an absolute resolved path')
    directory = Path(directory).resolve()
    if directory.name != '_main' or directory.parent.name != 'execroot':
        raise ArtifactError('generated Release project directory is not the supported workspace execution root')
    if (settings.get('_BAZEL_OUTPUT_BASE') != '$(PROJECT_DIR)/../..' or
            settings.get('BAZEL_OUTPUT_BASE') != '$(_BAZEL_OUTPUT_BASE:standardizepath)'):
        raise ArtifactError('generated output-base expression is unsupported or inconsistent')
    # Mirror the actual generated expression, canonicalizing /var aliases.
    return str(directory.parent.parent), str(directory)


def generated_app(project, require_service=False):
    result = subprocess.run(['plutil', '-convert', 'json', '-o', '-', str(project)], capture_output=True, text=True)
    if result.returncode:
        raise ArtifactError('generated app project cannot be parsed')
    try:
        objects = json.loads(result.stdout)['objects']
        output_base, release_directory = generated_output_base(objects)
        apps = [v for v in objects.values() if v.get('isa') == 'PBXNativeTarget' and v.get('name') == 'Telegram']
        if len(apps) != 1:
            raise ArtifactError('generated graph must contain one Telegram app target')
        configs = [objects[c] for c in objects[apps[0]['buildConfigurationList']]['buildConfigurations'] if objects[c].get('name') == 'Release']
        if len(configs) != 1:
            raise ArtifactError('generated graph must contain one Release app configuration')
        settings = configs[0]['buildSettings']
        target = settings.get('BAZEL_TARGET_ID', '')
        product = settings.get('BAZEL_OUTPUTS_PRODUCT', '')
        match = re.fullmatch(r'(@@?//Telegram:Telegram) (ios_arm64-opt-[^ /]+)', target)
        if not match or product != f'bazel-out/{match.group(2)}/bin/Telegram/Telegram.app':
            raise ArtifactError('generated Release device app target/product path is inconsistent')
        source_bundle_id = settings.get('PRODUCT_BUNDLE_IDENTIFIER', '')
        if not isinstance(source_bundle_id, str) or not re.fullmatch(r'[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+', source_bundle_id):
            raise ArtifactError('generated app bundle identifier is missing or unresolved')
        service = [v.get('name') for v in objects.values() if v.get('isa') == 'PBXNativeTarget' and re.fullmatch(r'NotificationServiceExtension[^ /]*', v.get('name', ''))]
        if require_service and len(service) != 1:
            raise ArtifactError('generated graph is stale or does not contain exactly one NotificationService target')
        return {'target_id': target, 'config_id': match.group(2), 'output_group': 'bp ' + target,
                'app_execroot_relative_path': product, 'source_bundle_id': source_bundle_id, 'project_sha256': sha256_file(project),
                'service_targets': service, 'generated_output_base': output_base, 'project_release_dir': release_directory}
    except (KeyError, TypeError, json.JSONDecodeError) as error:
        raise ArtifactError('generated graph metadata is incomplete') from error


def sha256_file(path):
    value = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for data in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(data)
    return value.hexdigest()


def within(root, path):
    try:
        path.resolve(strict=True).relative_to(root.resolve(strict=True))
    except (ValueError, OSError):
        raise ArtifactError('artifact contains an unreadable or escaping bundle path')


def bundle_metadata(root, directory, build, version):
    within(root, directory)
    within(root, directory / 'Info.plist')
    try:
        info = plistlib.loads((directory / 'Info.plist').read_bytes())
    except (OSError, ValueError) as error:
        raise ArtifactError('artifact has missing or invalid bundle metadata') from error
    if not isinstance(info, dict) or info.get('CFBundleVersion') != build or info.get('CFBundleShortVersionString') != version:
        raise ArtifactError('artifact bundle build/version mismatch: ' + directory.relative_to(root).as_posix())
    executable = info.get('CFBundleExecutable')
    if not isinstance(executable, str) or not executable or '/' in executable or executable in ['.', '..']:
        raise ArtifactError('artifact has an invalid bundle executable')
    executable_path = directory / executable
    within(root, executable_path)
    if not executable_path.is_file() or executable_path.stat().st_size == 0:
        raise ArtifactError('artifact has a missing or empty bundle executable')
    return info


def artifact_metadata(app, build, version, require_service=False, legacy=False):
    app = Path(app)
    if not app.is_dir():
        raise ArtifactError('selected built app is missing')
    main = bundle_metadata(app, app, build, version)
    extensions = sorted(p for p in app.rglob('*.appex') if p.is_dir())
    if legacy and extensions:
        raise ArtifactError('legacy package requires zero extension bundles')
    if require_service and len(extensions) != 1:
        raise ArtifactError('NSE-only artifact must contain exactly one extension')
    extension_records = []
    for extension in extensions:
        if extension.parent != app / 'PlugIns':
            raise ArtifactError('extension is outside the direct PlugIns directory')
        info = bundle_metadata(app, extension, build, version)
        config = info.get('NSExtension', {})
        if require_service and (not isinstance(config, dict) or config.get('NSExtensionPointIdentifier') != 'com.apple.usernotifications.service' or config.get('NSExtensionPrincipalClass') != 'NotificationService'):
            raise ArtifactError('NSE-only artifact has wrong extension metadata')
        extension_records.append({'path': extension.relative_to(app).as_posix(), 'bundle_id': info.get('CFBundleIdentifier')})
    frameworks = sorted(p for p in app.rglob('*.framework') if p.is_dir())
    for framework in frameworks:
        bundle_metadata(app, framework, build, version)
    return {'source_bundle_id': main.get('CFBundleIdentifier'), 'extensions': extension_records,
            'framework_count': len(frameworks), 'fingerprint_sha256': fingerprint(app)}


def fingerprint(app):
    # Streaming fingerprint of built content; profiles are validated separately.
    value = hashlib.sha256()
    for path in sorted(app.rglob('*')):
        relative = path.relative_to(app).as_posix()
        if path.name == 'embedded.mobileprovision':
            continue
        value.update(relative.encode('utf-8') + b'\0')
        if path.is_symlink():
            within(app, path)
            value.update(b'link\0' + str(path.readlink()).encode('utf-8'))
        elif path.is_file():
            value.update(b'file\0' + sha256_file(path).encode('ascii'))
        elif path.is_dir():
            value.update(b'directory\0')
        else:
            raise ArtifactError('artifact contains unsupported filesystem entry')
        value.update(b'\0')
    return value.hexdigest()


def write_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode='w', dir=path.parent, prefix='.full-app-receipt-', delete=False) as stream:
            temporary = Path(stream.name)
            json.dump(value, stream, indent=2); stream.write('\n')
        temporary.replace(path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def validate_source_identity(graph, data, require_service):
    if data['source_bundle_id'] != graph['source_bundle_id']:
        raise ArtifactError('built app bundle identity differs from the selected generated target')
    if require_service and data['extensions'][0]['bundle_id'] != graph['source_bundle_id'] + '.NotificationService':
        raise ArtifactError('built service identity differs from the selected host target')


def capture(project, app, build, version, receipt, require_service=False):
    graph = generated_app(project, require_service)
    data = artifact_metadata(app, build, version, require_service)
    validate_source_identity(graph, data, require_service)
    result = {'kind': 'supergram-full-app-build-receipt-v1', 'build': build, 'version': version,
              'require_notification_service': require_service, 'graph': graph,
              'app_path': str(Path(app).resolve()), 'artifact': data}
    write_json(receipt, result)
    return result


def verify(project, app, build, version, receipt, require_service=False, legacy=False):
    try:
        previous = json.loads(Path(receipt).read_text())
    except (OSError, ValueError) as error:
        raise ArtifactError('successful full-app build receipt is required') from error
    if previous.get('kind') != 'supergram-full-app-build-receipt-v1' or previous.get('build') != build or previous.get('version') != version or previous.get('require_notification_service') != require_service:
        raise ArtifactError('full-app receipt build/version/mode mismatch')
    graph = generated_app(project, require_service)
    if previous.get('graph') != graph or previous.get('app_path') != str(Path(app).resolve()):
        raise ArtifactError('generated graph or selected app changed after successful build')
    data = artifact_metadata(app, build, version, require_service, legacy)
    validate_source_identity(graph, data, require_service)
    if previous.get('artifact') != data:
        raise ArtifactError('built app content changed after successful build')
    return previous


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('operation', choices=['derive', 'capture', 'verify'])
    parser.add_argument('--project', type=Path, required=True)
    parser.add_argument('--require-notification-service', action='store_true')
    parser.add_argument('--legacy', action='store_true')
    parser.add_argument('--app', type=Path)
    parser.add_argument('--build')
    parser.add_argument('--version')
    parser.add_argument('--receipt', type=Path)
    parser.add_argument('--output', type=Path)
    a = parser.parse_args()
    try:
        if a.require_notification_service and a.legacy:
            raise ArtifactError('service-only and legacy modes conflict')
        if a.operation == 'derive':
            result = generated_app(a.project, a.require_notification_service)
        else:
            if a.app is None or a.build is None or a.version is None or a.receipt is None:
                raise ArtifactError('artifact, build/version and receipt arguments are required')
            if a.operation == 'capture':
                result = capture(a.project, a.app, a.build, a.version, a.receipt, a.require_notification_service)
            else:
                result = verify(a.project, a.app, a.build, a.version, a.receipt, a.require_notification_service, a.legacy)
        if a.output:
            write_json(a.output, result)
        else:
            print(json.dumps(result, indent=2))
        return 0
    except (ArtifactError, OSError) as error:
        print('artifact preflight failed: ' + str(error))
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
