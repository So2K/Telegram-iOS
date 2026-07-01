import Foundation

private let maxAudioWaveformSamples = 4096

private func getBits(data: UnsafeRawPointer, length: Int, bitOffset: Int, numBits: Int) -> Int32 {
    guard length > 0, bitOffset >= 0, numBits > 0, numBits < 31 else {
        return 0
    }

    let normalizedNumBits = (1 << numBits) - 1
    let byteOffset = bitOffset / 8
    guard byteOffset < length else {
        return 0
    }

    let normalizedData = data.advanced(by: byteOffset)
    let normalizedBitOffset = bitOffset % 8

    var value: Int32 = 0
    let remaining = length - byteOffset
    if remaining < 4 {
        withUnsafeMutableBytes(of: &value, { (bytes: UnsafeMutableRawBufferPointer) -> Void in
            if let baseAddress = bytes.baseAddress {
                memcpy(baseAddress, normalizedData, remaining)
            }
        })
    } else {
        value = normalizedData.assumingMemoryBound(to: Int32.self).pointee
    }
    return (value >> Int32(normalizedBitOffset)) & Int32(normalizedNumBits)
}

private func setBits(data: UnsafeMutableRawPointer, bitOffset: Int, numBits: Int, value: Int32) {
    guard bitOffset >= 0, numBits > 0, numBits < 31 else {
        return
    }

    let normalizedData = data.advanced(by: bitOffset / 8)
    let normalizedBitOffset = bitOffset % 8
    
    normalizedData.assumingMemoryBound(to: Int32.self).pointee |= value << Int32(normalizedBitOffset)
}

public final class AudioWaveform: Equatable {
    public let samples: Data
    public let peak: Int32
    
    public init(samples: Data, peak: Int32) {
        self.samples = samples
        self.peak = peak
    }
    
    public convenience init(bitstream: Data, bitsPerSample: Int) {
        guard bitsPerSample > 0, bitsPerSample < 31, !bitstream.isEmpty else {
            self.init(samples: Data(), peak: 1)
            return
        }

        let numSamples = min(maxAudioWaveformSamples, Int(Float(bitstream.count * 8) / Float(bitsPerSample)))
        var result = Data()
        result.count = numSamples * 2
        let peak = Int32((1 << bitsPerSample) - 1)
        
        bitstream.withUnsafeBytes { bytes -> Void in
            guard let bitstreamBaseAddress = bytes.baseAddress else {
                return
            }

            result.withUnsafeMutableBytes { samples -> Void in
                guard let samplesBaseAddress = samples.baseAddress else {
                    return
                }

                let norm = Int64(peak)
                let samples = samplesBaseAddress.assumingMemoryBound(to: Int16.self)
                for i in 0 ..< numSamples {
                    let sample = Int64(getBits(data: bitstreamBaseAddress, length: bitstream.count, bitOffset: i * bitsPerSample, numBits: bitsPerSample)) * norm / norm
                    samples[i] = Int16(max(Int64(Int16.min), min(Int64(Int16.max), sample)))
                }
            }
        }
        
        self.init(samples: result, peak: peak)
    }
    
    public func makeBitstream() -> Data {
        let numSamples = min(maxAudioWaveformSamples, self.samples.count / 2)
        if numSamples == 0 {
            return Data()
        }

        let bitstreamLength = (numSamples * 5) / 8 + (((numSamples * 5) % 8) == 0 ? 0 : 1)
        var result = Data()
        result.count = bitstreamLength + 4
        
        let maxSample: Int32 = max(1, self.peak)
        
        self.samples.withUnsafeBytes { rawSamples -> Void in
            guard let rawSamplesBaseAddress = rawSamples.baseAddress else {
                return
            }
            let samples = rawSamplesBaseAddress.assumingMemoryBound(to: Int16.self)
            
            result.withUnsafeMutableBytes { rawBytes -> Void in
                guard let rawBytesBaseAddress = rawBytes.baseAddress else {
                    return
                }
                let bytes = rawBytesBaseAddress.assumingMemoryBound(to: Int16.self)

                for i in 0 ..< numSamples {
                    let value: Int32 = min(Int32(31), abs(Int32(samples[i])) * 31 / maxSample)
                    if i == 99 {
                        assert(true)
                    }
                    setBits(data: bytes, bitOffset: i * 5, numBits: 5, value: value & Int32(31))
                }
            }
        }
        
        result.count = bitstreamLength
        
        return result
    }
    
    public func subwaveform(from start: Double, to end: Double) -> AudioWaveform {
        let normalizedStart = max(0.0, min(1.0, start))
        let normalizedEnd = max(normalizedStart, min(1.0, end))
        
        let numSamples = self.samples.count / 2
        let startIndex = Int(Double(numSamples) * normalizedStart) * 2
        let endIndex = Int(Double(numSamples) * normalizedEnd) * 2
        
        let rangeLength = endIndex - startIndex
        let subData: Data
        
        if rangeLength > 0 {
            subData = self.samples.subdata(in: startIndex..<endIndex)
        } else {
            subData = Data()
        }
        
        return AudioWaveform(samples: subData, peak: self.peak)
    }
    
    public static func ==(lhs: AudioWaveform, rhs: AudioWaveform) -> Bool {
        return lhs.peak == rhs.peak && lhs.samples == rhs.samples
    }
}
