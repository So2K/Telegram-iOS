from pathlib import Path
import argparse,hashlib,json,subprocess,tempfile
ROOT=Path(__file__).resolve().parent
while not (ROOT/'CLAUDE.md').is_file(): ROOT=ROOT.parent
HERE=Path(__file__).resolve().parent
parser=argparse.ArgumentParser();parser.add_argument('--source',type=Path,default=ROOT/'submodules/MediaPlayer/Sources/MediaPlayer.swift');parser.add_argument('--output',type=Path,required=True);parser.add_argument('--artifacts-dir',type=Path,required=True);parser.add_argument('--expect-regression',action='store_true');parser.add_argument('--fixtures-dir',type=Path,default=ROOT/'scripts/supergram/tests/media_seek_recovery');args=parser.parse_args()
FIXTURES=args.fixtures_dir.resolve();SOURCE=args.source.resolve();args.artifacts_dir.mkdir(parents=True,exist_ok=True)
def extract(text,start,end):
 a=text.index(start);return text[a:text.index(end,a)]
t=SOURCE.read_text()
parts={
'// ACTUAL_EPISODE_GETTER':'return self.seekRecoveryGeneration' if 'private var seekRecoveryGeneration:' in t else 'return 0',
'// ACTUAL_ATTEMPT_GETTER':'return self.seekAttemptGeneration' if 'private var seekAttemptGeneration:' in t else 'return 0',
'            // ACTUAL_RETIRED_TIMER_CALLBACK':extract(t,'        let timer = SwiftSignalKit.Timer(timeout: delay, repeat: false, completion: { [weak self] in','        }, queue: self.queue)').split('completion: { [weak self] in',1)[1],
'    // ACTUAL_DEINIT':extract(t,'    deinit {','\n    fileprivate func seek(timestamp: Double)'),
'    // ACTUAL_PAUSE':extract(t,'    fileprivate func pause(lostAudioSession:','\n    fileprivate func togglePlayPause'),
'// ACTUAL_STATE_TYPES':extract(t,'private struct MediaPlayerControlTimebase','\npublic enum MediaPlayerActionAtEnd'),
'// ACTUAL_STREAMING_TYPE':extract(t,'public enum MediaPlayerStreaming','\nprivate final class MediaPlayerAudioRendererContext'),
'    // ACTUAL_RECOVERY_FIELDS':extract(t,'    private static let maxSeekRetryCount','\n    private var lastStatusUpdateTimestamp'),
'    // ACTUAL_SEEK_AND_RECOVERY':extract(t,'    fileprivate func seek(timestamp: Double, action:','\n    fileprivate func seekingCompleted')}
s=(FIXTURES/'adapters.swift').read_text()
for k,v in parts.items():s=s.replace(k,v)
s+=(FIXTURES/'cases.swift').read_text()
(args.artifacts_dir/'source-extracted.swift').write_text(s)
deps=sorted((ROOT/'submodules/SSignalKit/SwiftSignalKit/Source').glob('*.swift')); assert len(deps)==26
proofsources=[SOURCE,ROOT/'submodules/MediaPlayer/Sources/FFMpegMediaFrameSource.swift',ROOT/'submodules/MediaPlayer/Sources/FFMpegMediaFrameSourceContext.swift',ROOT/'submodules/Postbox/Sources/MediaBox.swift',FIXTURES/'adapters.swift',FIXTURES/'cases.swift',Path(__file__),*deps]
hashes={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in proofsources}
with tempfile.TemporaryDirectory(prefix='sg-independent-media-seek-') as temp:
 d=Path(temp);src=d/'main.swift';src.write_text(s)
 commands=[['xcrun','swiftc','-swift-version','5','-module-name','SwiftSignalKit','-parse-as-library','-emit-module','-emit-module-path',str(d/'SwiftSignalKit.swiftmodule'),'-emit-library','-o',str(d/'libSwiftSignalKit.dylib'),*map(str,deps)],['xcrun','swiftc','-swift-version','5','-warnings-as-errors','-I',str(d),'-L',str(d),'-lSwiftSignalKit','-Xlinker','-rpath','-Xlinker',str(d),str(src),'-o',str(d/'control')]]
 for cmd in commands:
  r=subprocess.run(cmd,capture_output=True,text=True,timeout=90)
  if r.returncode: print(r.stdout+r.stderr);raise SystemExit(r.returncode)
 r=subprocess.run([str(d/'control')]+(['--desired'] if args.expect_regression else []),capture_output=True,text=True,timeout=25)
 print(r.stdout+r.stderr)
 assert all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==h for p,h in hashes.items())
 args.output.write_text(json.dumps({'input_hashes':hashes,'exit':r.returncode,'stdout':r.stdout,'stderr':r.stderr,'source_parts':list(parts),'limit':'Actual complete seek method, recovery methods, state types, streaming type, fields, 26 real SwiftSignalKit sources. FFmpeg binding, Postbox/media engine/audio renderers/status payload are typed synthetic adapters. Cached observation cap12 protects original negative; candidate must use one arm per episode. Actual deinit also extracted. No production changes, full app build, network, user data or send.'},indent=2)+'\n')
 assert r.returncode==(42 if args.expect_regression else 0)
