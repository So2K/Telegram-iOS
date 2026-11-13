import Foundation
public struct MediaResourceId: Hashable { public let stringRepresentation: String; public init(_ s:String){stringRepresentation=s} }
public protocol MediaResource { var id: MediaResourceId {get} }
// Typed file-probe boundary. Actual helper/Atomic are used; actual MediaBox internals/decoding are not.
public final class MediaBox {
 public let basePath:String; public private(set) var probes=0
 public init(basePath:String){self.basePath=basePath;try! FileManager.default.createDirectory(atPath:basePath,withIntermediateDirectories:true)}
 public func completedResourcePath(_ r:MediaResource)->String? { probes+=1;let p=basePath+"/"+r.id.stringRepresentation+".complete";return FileManager.default.fileExists(atPath:p) ? p : nil }
 public func internal_resourceDataIsCached(id:MediaResourceId,size:Int64,in range:Range<Int64>)->Bool { probes+=1;let p=basePath+"/"+id.stringRepresentation+".partial";guard let a=try? FileManager.default.attributesOfItem(atPath:p),let n=a[.size] as? NSNumber else{return false};return range.lowerBound>=0 && range.upperBound<=n.int64Value }
 public func put(_ r:MediaResource,complete:Bool,bytes:Int) { let p=basePath+"/"+r.id.stringRepresentation+(complete ? ".complete" : ".partial");try! Data(repeating:7,count:bytes).write(to:URL(fileURLWithPath:p)) }
}
