import Foundation

enum CallUplinkPCM {
    static let sampleRate = 8_000.0
    static let maximumDuration: TimeInterval = 30

    static func pcm16LE(samples: [Float], sampleRate: Double) -> Data {
        guard sampleRate > 0, samples.count >= 2 else { return Data() }
        let source: [Float]
        if sampleRate > Self.sampleRate {
            var conditioner = VoiceCaptureConditioner()
            source = conditioner.process(samples, sampleRate: sampleRate)
        } else {
            source = samples
        }
        let step = sampleRate / Self.sampleRate
        var pcm = Data()
        pcm.reserveCapacity(Int(Double(source.count) / step) * 2 + 4)
        var position = 0.0
        while position + 1 < Double(source.count) {
            let lower = Int(position)
            let fraction = Float(position - Double(lower))
            let value = source[lower] * (1 - fraction) + source[lower + 1] * fraction
            let scaled = Int16(max(-1, min(1, value)) * Float(Int16.max))
            var littleEndian = scaled.littleEndian
            withUnsafeBytes(of: &littleEndian) { pcm.append(contentsOf: $0) }
            position += step
        }
        let maximumBytes = Int(Self.sampleRate * Self.maximumDuration) * MemoryLayout<Int16>.size
        if pcm.count > maximumBytes {
            pcm = Data(pcm.prefix(maximumBytes))
        }
        return pcm
    }
}
