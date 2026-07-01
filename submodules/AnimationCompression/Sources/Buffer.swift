import Foundation

class MemoryBuffer {
    var data: Data
    var length: Int
    
    init(data: Data) {
        self.data = data
        self.length = data.count
    }
}

final class WriteBuffer: MemoryBuffer {
    var offset = 0
    
    init() {
        super.init(data: Data())
    }
    
    func makeData() -> Data {
        return self.data
    }
    
    func reset() {
        self.offset = 0
    }
    
    func write(_ data: UnsafeRawPointer, offset: Int = 0, length: Int) {
        guard length > 0 else {
            return
        }
        if self.offset + length > self.data.count {
            self.data.count = self.offset + length + 256
        }
        self.data.withUnsafeMutableBytes { bytes in
            guard let baseAddress = bytes.baseAddress else {
                return
            }
            let _ = memcpy(baseAddress.advanced(by: self.offset), data.advanced(by: offset), length)
        }
        self.offset += length
        self.length = self.offset
    }
    
    func write(_ data: Data) {
        guard !data.isEmpty else {
            return
        }
        data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else {
                return
            }
            self.write(baseAddress, length: bytes.count)
        }
    }

    func writeInt8(_ value: Int8) {
        var value = value
        self.write(&value, length: 1)
    }

    func writeInt32(_ value: Int32) {
        var value = value
        self.write(&value, length: 4)
    }

    func writeFloat(_ value: Float) {
        var value: Float32 = value
        self.write(&value, length: 4)
    }
    
    func seek(offset: Int) {
        self.offset = offset
    }
}

final class ReadBuffer: MemoryBuffer {
    var offset = 0
    
    override init(data: Data) {
        super.init(data: data)
    }
    
    func read(_ data: UnsafeMutableRawPointer, length: Int) {
        guard length > 0 else {
            return
        }

        let availableLength = max(0, min(length, self.data.count - self.offset))
        if availableLength > 0 {
            self.data.copyBytes(to: data.assumingMemoryBound(to: UInt8.self), from: self.offset ..< (self.offset + availableLength))
        }
        if availableLength < length {
            memset(data.advanced(by: availableLength), 0, length - availableLength)
        }
        self.offset += length
    }
    
    func readDataNoCopy(length: Int) -> Data {
        guard length > 0 else {
            return Data()
        }

        let availableLength = max(0, min(length, self.data.count - self.offset))
        guard availableLength == length else {
            self.offset += length
            return Data()
        }

        let result = self.data.withUnsafeBytes { bytes -> Data in
            guard let baseAddress = bytes.baseAddress else {
                return Data()
            }
            return Data(bytes: baseAddress.advanced(by: self.offset), count: length)
        }
        self.offset += length
        return result
    }
    
    func readInt8() -> Int8 {
        var result: Int8 = 0
        self.read(&result, length: 1)
        return result
    }

    func readInt32() -> Int32 {
        var result: Int32 = 0
        self.read(&result, length: 4)
        return result
    }

    func readFloat() -> Float {
        var result: Float32 = 0
        self.read(&result, length: 4)
        return result
    }

    func skip(_ length: Int) {
        self.offset += length
    }
    
    func reset() {
        self.offset = 0
    }
}
