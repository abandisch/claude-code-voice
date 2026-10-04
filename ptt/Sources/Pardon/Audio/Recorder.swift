import AVFoundation
import Foundation

// MARK: - Audio capture

final class Recorder {
    let engine = AVAudioEngine()
    private let lock = NSLock()
    private var samples: [Int16] = []
    private var running = false
    private let outFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: Double(sampleRate), channels: 1, interleaved: true)!
    private var levelHandler: ((Double) -> Void)?
    // Called on the main thread with each buffer's voiceLevel; nil skips the measurement.
    var onLevel: ((Double) -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return levelHandler }
        set { lock.lock(); levelHandler = newValue; lock.unlock() }
    }

    func prepare() {
        _ = engine.inputNode
        engine.prepare()
    }

    func start() -> Bool {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0,
              let converter = AVAudioConverter(from: format, to: outFormat) else { return false }
        lock.lock(); samples = []; lock.unlock()
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.append(buffer, converter)
        }
        do { try engine.start() } catch { input.removeTap(onBus: 0); return false }
        running = true
        return true
    }

    private func append(_ buffer: AVAudioPCMBuffer, _ converter: AVAudioConverter) {
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * outFormat.sampleRate / buffer.format.sampleRate) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: capacity) else { return }
        var fed = false
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, inputStatus in
            if fed { inputStatus.pointee = .noDataNow; return nil }
            fed = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, let channel = out.int16ChannelData else { return }
        let converted = UnsafeBufferPointer(start: channel[0], count: Int(out.frameLength))
        lock.lock()
        samples.append(contentsOf: converted)
        let onLevel = levelHandler
        lock.unlock()
        if let onLevel = onLevel {
            let level = voiceLevel(converted)
            DispatchQueue.main.async { onLevel(level) }
        }
    }

    func stop() -> [Int16] {
        if running {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            running = false
            engine.prepare()
        }
        lock.lock(); defer { samples = []; lock.unlock() }
        return samples
    }
}
