#!/usr/bin/env python3
"""Offline source restoration/full native build; no signing/deployment/repin.

Requires a locally available upstream Git repository containing the pinned
commit. Exports only source/Makefile/license, never profiles, keys or old objects.
Every output belongs to a new explicit work directory; existing paths refuse.
"""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile

HERE=Path(__file__).resolve().parent

def run(command,**kwargs):
    return subprocess.run(list(map(str,command)),capture_output=True,check=True,**kwargs)

def sha(data):return hashlib.sha256(data).hexdigest()

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--upstream-repo',type=Path,required=True)
    parser.add_argument('--work-dir',type=Path,required=True)
    parser.add_argument('--restore-only',action='store_true',help='Validate patched sources without invoking a compiler')
    args=parser.parse_args()
    manifest=json.loads((HERE/'native-manifest.json').read_text())
    patch=HERE/'native.patch'
    if sha(patch.read_bytes())!=manifest['patch_sha256']:raise ValueError('native patch changed')
    upstream=args.upstream_repo.resolve(strict=True);work=args.work_dir.resolve()
    if work.exists() or 'ipa-signing-work' in work.parts:raise ValueError('work directory must be fresh and outside production signing material')
    try:work.relative_to(upstream)
    except ValueError:pass
    else:raise ValueError('work directory cannot be inside upstream input repository')
    commit=manifest['commit']
    if run(['git','-C',upstream,'rev-parse',commit+'^{commit}'],text=True).stdout.strip()!=commit:raise ValueError('pinned source commit unavailable')
    archive=run(['git','-C',upstream,'archive','--format=tar',commit,'src','build/macos/Makefile','LICENSE']).stdout
    files={}
    with tarfile.open(fileobj=io.BytesIO(archive)) as tree:
        for entry in tree:
            if entry.isdir():continue
            if not entry.isfile() or entry.name not in manifest['baseline_hashes']:raise ValueError('source-only archive contains unexpected entry')
            if entry.name in files:raise ValueError('source archive contains duplicate input')
            data=tree.extractfile(entry).read()
            if sha(data)!=manifest['baseline_hashes'][entry.name]:raise ValueError('baseline source differs from pinned manifest')
            files[entry.name]=data
    if set(files)!=set(manifest['baseline_hashes']):raise ValueError('source-only archive is incomplete')
    work.mkdir(parents=True);source=work/'source';source.mkdir()
    for name,data in files.items():
        path=source/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(data)
    # A scratch Git root prevents git-apply from resolving the parent application's
    # repository. No commit, hooks, credential helper or remote command is used.
    run(['git','-c','init.templateDir=','init','--quiet',source])
    run(['git','apply','--check','--whitespace=error-all',patch],cwd=source)
    run(['git','apply','--whitespace=error-all',patch],cwd=source)
    for name,expected in manifest['current_hashes'].items():
        if sha((source/name).read_bytes())!=expected:raise ValueError('restored source differs from applied native manifest')
    (work/'restored-source-hashes.json').write_text(json.dumps(manifest['current_hashes'],indent=2)+'\n')
    if args.restore_only:
        print('source-only restoration PASS:',len(files),'baseline inputs,',len(manifest['current_hashes']),'exact current inputs; no compiler/signing/pin update')
        return 0
    version=run(['pkg-config','--modversion','openssl'],text=True).stdout.strip()
    if version!=manifest['build']['openssl_required_version']:raise ValueError('reviewed OpenSSL build dependency version required')
    environment=dict(os.environ)
    for name in ['MAKEFLAGS','MFLAGS','MAKEOVERRIDES']:environment.pop(name,None)
    objects=work/'objects';binaries=work/'bin'
    command=['make','-C',source/'build/macos','OBJDIR='+str(objects),'BINDIR='+str(binaries),
             'VERSION='+manifest['build']['version'],'SYSTEM_MINIZIP=0','CXX=c++','CC=cc']
    with (work/'build.log').open('wb') as log:
        result=subprocess.run(command,env=environment,stdout=log,stderr=subprocess.STDOUT)
    if result.returncode:raise ValueError('fresh native compile failed; inspect owned build.log')
    binary=binaries/'zsign'
    if not binary.is_file():raise ValueError('fresh native compile did not produce its isolated output')
    object_count=len(list(objects.rglob('*.o')))
    if object_count!=34:raise ValueError('unexpected full-source translation unit inventory')
    evidence={'source_commit':commit,'patch_sha256':manifest['patch_sha256'],'fresh_objects':object_count,
      'binary':str(binary),'binary_sha256':sha(binary.read_bytes()),'openssl_version':version,
      'openssl_cflags':run(['pkg-config','--cflags','openssl'],text=True).stdout.strip(),
      'openssl_libs':run(['pkg-config','--libs','openssl'],text=True).stdout.strip(),
      'compiler':run(['c++','--version'],text=True).stdout.splitlines()[0],
      'sdk':run(['xcrun','--show-sdk-version'],text=True).stdout.strip(),
      'runtime_pin_unchanged':manifest['runtime_binary_sha256'],'requires_separate_review_before_repin':True,
      'credential_profile_signing_deployment_actions':False}
    (work/'build-evidence.json').write_text(json.dumps(evidence,indent=2)+'\n')
    print('full-source native build PASS:',object_count,'fresh objects; isolated SHA256',evidence['binary_sha256'])
    print('No production binary overwrite or automatic runtime pin update; separate review required.')
    return 0

if __name__=='__main__':
    try:raise SystemExit(main())
    except (OSError,ValueError,subprocess.CalledProcessError) as error:
        print('preservation build failed:',str(error));raise SystemExit(1)
