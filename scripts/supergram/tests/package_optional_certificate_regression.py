#!/usr/bin/env python3
"""Exercise both actual optional-certificate validator calls with macOS Bash3.2.

The validator is an argv-recording shell function. No profile, key, signer, IPA,
network or device is accessed. Before-code controls must reproduce the empty
array failure while preserving populated strict arguments.
"""
import argparse
import hashlib
import json
import shlex
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=ROOT / 'scripts/supergram/make_ipa.sh')
    parser.add_argument('--expect-empty-array-bug', action='store_true')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    source = args.source.read_text()
    calls = [line.strip() for line in source.splitlines()
             if line.strip().startswith('python3 "$VALIDATOR"')
             and '--signed' in line and 'SIGNED_CERTIFICATE_ARGS' in line]
    assert len(calls) == 2, calls
    syntax = subprocess.run(['/bin/bash', '-n', str(args.source)], capture_output=True)
    assert syntax.returncode == 0, syntax.stderr.decode()
    validator = '/tmp/validator with space.py'
    stage = '/tmp/stage with space'
    verify = '/tmp/verify with space'
    common_validation = ['--build', '10034', '--version', '12.8', '--bundle-id', 'app.tomato7991.lime1486',
                  '--team-id', 'G6TLPRYW6Y', '--app-group', 'group.ffcd1c12e1a9728e.1',
                  '--device-id', '00008130-0004298110698D3A']
    certificates = [None, '/tmp/certificate with space.cer', '/tmp/certificate*.cer', "/tmp/certificate'quoted;$().cer"]
    rows = []
    for index, call in enumerate(calls):
        location = stage if '$STAGE/' in call else verify
        for certificate in certificates:
            cert_args = [] if certificate is None else ['--signing-certificate', certificate]
            validation = common_validation + (['--allow-no-notification-extensions'] if certificate is None else [])
            setup = ('set -eu\n'
                     'python3() { printf \'%s\\0\' "$@"; }\n'
                     f'VALIDATOR={shlex.quote(validator)}\n'
                     f'STAGE={shlex.quote(stage)}\nVERIFY={shlex.quote(verify)}\n'
                     'VALIDATION_ARGS=(' + ' '.join(map(shlex.quote, validation)) + ')\n'
                     'SIGNED_CERTIFICATE_ARGS=(' + ' '.join(map(shlex.quote, cert_args)) + ')\n')
            result = subprocess.run(['/bin/bash', '-c', setup + call], capture_output=True)
            if args.expect_empty_array_bug and certificate is None:
                assert result.returncode != 0 and b'unbound variable' in result.stderr, result
                assert not result.stdout, result.stdout
                rows.append({'site': index, 'certificate': certificate, 'expected_empty_array_failure': True, 'exit': result.returncode})
            else:
                assert result.returncode == 0, result.stderr.decode()
                actual = result.stdout.split(b'\0')
                assert actual[-1] == b'', actual
                actual = [part.decode() for part in actual[:-1]]
                expected = [validator, location + '/Payload/Telegram.app', *validation, '--signed', *cert_args]
                assert actual == expected, (actual, expected)
                rows.append({'site': index, 'certificate': certificate, 'exact_validator_argv_preserved': True, 'exit': result.returncode})
    record = {'source': str(args.source), 'source_sha256': hashlib.sha256(args.source.read_bytes()).hexdigest(),
              'test_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(), 'syntax_passed': True,
              'expected_before_bug': args.expect_empty_array_bug, 'cases': rows,
              'no_signing_profile_key_ipa_network_device_access': True}
    if args.output:
        args.output.write_text(json.dumps(record, indent=2) + '\n')
    print(f'PASS {len(rows)} actual validator argv cases on /bin/bash; before-bug={args.expect_empty_array_bug}')

if __name__ == '__main__':
    main()
