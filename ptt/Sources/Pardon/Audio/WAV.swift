import Foundation

let sampleRate = 16_000

func wavData(samples: [Int16], sampleRate: Int) -> Data {
    let dataBytes = samples.count * 2
    var d = Data(capacity: 44 + dataBytes)
    func u32(_ v: Int) { withUnsafeBytes(of: UInt32(v).littleEndian) { d.append(contentsOf: $0) } }
    func u16(_ v: Int) { withUnsafeBytes(of: UInt16(v).littleEndian) { d.append(contentsOf: $0) } }
    d.append(contentsOf: Array("RIFF".utf8)); u32(36 + dataBytes); d.append(contentsOf: Array("WAVE".utf8))
    d.append(contentsOf: Array("fmt ".utf8)); u32(16)
    u16(1); u16(1); u32(sampleRate); u32(sampleRate * 2); u16(2); u16(16)
    d.append(contentsOf: Array("data".utf8)); u32(dataBytes)
    samples.withUnsafeBufferPointer { buf in
        for s in buf { withUnsafeBytes(of: s.littleEndian) { d.append(contentsOf: $0) } }
    }
    return d
}
