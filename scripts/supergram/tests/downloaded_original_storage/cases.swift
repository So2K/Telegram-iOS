
final class Resource: TelegramMediaResource { let id:MediaResourceId;init(_ s:String){id=MediaResourceId(s)} }
var checks=0;var failures=0
func check(_ v:Bool,_ n:String){checks+=1;if !v {failures+=1;print("FAIL: \(n)")}}
let root=FileManager.default.temporaryDirectory.appendingPathComponent("sg-original-storage-"+UUID().uuidString)
try! FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
defer {try? FileManager.default.removeItem(at:root)}
let a=MediaBox(basePath:root.appendingPathComponent("a").path);let b=MediaBox(basePath:root.appendingPathComponent("b").path)
let r1=Resource("same-video-complete");a.put(r1,complete:true,bytes:524288)
check(superGramPrefersDownloadedOriginal(mediaBox:a,resource:r1,size:524288,requirement:.complete),"A complete resource prefers original")
check(!superGramPrefersDownloadedOriginal(mediaBox:b,resource:r1,size:524288,requirement:.complete),"A cached complete answer cannot select nonexistent original in B")
let r2=Resource("same-video-absent-first");b.put(r2,complete:true,bytes:524288)
check(!superGramPrefersDownloadedOriginal(mediaBox:a,resource:r2,size:524288,requirement:.complete),"A absent first returnsfalse")
check(superGramPrefersDownloadedOriginal(mediaBox:b,resource:r2,size:524288,requirement:.complete),"A cached absent answer cannot suppress B complete original")
let r3=Resource("same-video-half");a.put(r3,complete:false,bytes:393216)
check(superGramPrefersDownloadedOriginal(mediaBox:a,resource:r3,size:524288,requirement:.completeOrHalfPresent),"head+midpoint A permits partial policy")
check(!superGramPrefersDownloadedOriginal(mediaBox:b,resource:r3,size:524288,requirement:.completeOrHalfPresent),"A partial answer cannot select absent original in B")
check(!superGramPrefersDownloadedOriginal(mediaBox:a,resource:r3,size:524288,requirement:.complete),"complete and half policies have separate cache entries")
let probes=a.probes
check(superGramPrefersDownloadedOriginal(mediaBox:a,resource:r1,size:524288,requirement:.complete),"same-store repeated positive cache preserved")
check(a.probes==probes,"same-store cache avoids another filesystemprobe")
let alias=MediaBox(basePath:a.basePath);let aliasProbes=alias.probes
check(superGramPrefersDownloadedOriginal(mediaBox:alias,resource:r1,size:524288,requirement:.complete),"same storage aliases reuse correct presence")
check(alias.probes==aliasProbes,"key stores path rather than retaining MediaBox")
for i in 0..<400 { _=superGramPrefersDownloadedOriginal(mediaBox:a,resource:Resource("bounded-\(i)"),size:524288,requirement:.complete) }
check(superGramDownloadedOriginalCache.with {$0.count}<=superGramDownloadedOriginalCacheLimit,"existing256entry bound survives addedstorekey")
print("RESULT \(checks) actual-helper controls; \(failures) failures")
exit(failures==0 ? 0 : 42)
