#!/usr/bin/env python3
"""Actual complete downloaded-original helper +26 realSwiftSignalKit. File-probe MediaBox/Core are explicit typed adapters; no actual cache/decode/account/phone access."""
from pathlib import Path
import argparse,hashlib,json,subprocess,tempfile
ROOT=Path(__file__).resolve().parent
while not (ROOT/'CLAUDE.md').is_file():ROOT=ROOT.parent
p=argparse.ArgumentParser();p.add_argument('--source',type=Path,default=ROOT/'submodules/TelegramUniversalVideoContent/Sources/SuperGramDownloadedOriginal.swift');p.add_argument('--fixtures-dir',type=Path,default=ROOT/'scripts/supergram/tests/downloaded_original_storage');p.add_argument('--output',type=Path,required=True);p.add_argument('--expect-regression',action='store_true');a=p.parse_args()
source=a.source.resolve();fixtures=a.fixtures_dir.resolve();runtime=sorted((ROOT/'submodules/SSignalKit/SwiftSignalKit/Source').glob('*.swift'));assert len(runtime)==26
paths=[source,fixtures/'postbox.swift',fixtures/'core.swift',fixtures/'cases.swift',Path(__file__),*runtime]
sha=lambda x:hashlib.sha256(x.read_bytes()).hexdigest();before={str(x):sha(x) for x in paths}
with tempfile.TemporaryDirectory(prefix='sg-original-store-compile-') as temp:
 d=Path(temp)
 def run(cmd):
  r=subprocess.run(cmd,capture_output=True,text=True,timeout=90)
  if r.returncode:print(r.stdout+r.stderr);raise SystemExit(r.returncode)
 run(['xcrun','swiftc','-swift-version','5','-module-name','SwiftSignalKit','-parse-as-library','-emit-module','-emit-module-path',str(d/'SwiftSignalKit.swiftmodule'),'-emit-library','-o',str(d/'libSwiftSignalKit.dylib'),*map(str,runtime)])
 run(['xcrun','swiftc','-swift-version','5','-module-name','Postbox','-parse-as-library','-emit-module','-emit-module-path',str(d/'Postbox.swiftmodule'),'-emit-library','-o',str(d/'libPostbox.dylib'),str(fixtures/'postbox.swift')])
 run(['xcrun','swiftc','-swift-version','5','-module-name','TelegramCore','-I',str(d),'-L',str(d),'-lPostbox','-parse-as-library','-emit-module','-emit-module-path',str(d/'TelegramCore.swiftmodule'),'-emit-library','-o',str(d/'libTelegramCore.dylib'),str(fixtures/'core.swift')])
 main=d/'main.swift';main.write_text(source.read_text()+'\n'+(fixtures/'cases.swift').read_text())
 run(['xcrun','swiftc','-swift-version','5','-warnings-as-errors','-I',str(d),'-L',str(d),'-lSwiftSignalKit','-lPostbox','-lTelegramCore','-Xlinker','-rpath','-Xlinker',str(d),str(main),'-o',str(d/'control')])
 r=subprocess.run([str(d/'control')],capture_output=True,text=True,timeout=15)
 after={str(x):sha(x) for x in paths};assert before==after
 out={'source':str(source),'input_sha256_before':before,'input_sha256_after':after,'inputs_unchanged':True,'exit':r.returncode,'stdout':r.stdout,'stderr':r.stderr,'limits':__doc__};a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(out,indent=2)+'\n');print(r.stdout+r.stderr);assert r.returncode==(42 if a.expect_regression else 0)
