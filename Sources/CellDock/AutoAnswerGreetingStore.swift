import AVFoundation
import Combine
import Foundation

enum AutoAnswerGreetingSource: String, CaseIterable, Identifiable {
    case none
    case text
    case recording

    var id: Self { self }

    var title: String {
        switch self {
        case .none: return L10n.tr("不播放")
        case .text: return L10n.tr("文字播报")
        case .recording: return L10n.tr("录音")
        }
    }
}

@MainActor
final class AutoAnswerGreetingStore: NSObject, ObservableObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    static let shared = AutoAnswerGreetingStore()

    @Published private(set) var source: AutoAnswerGreetingSource
    @Published private(set) var text: String
    @Published private(set) var recordingDisplayName: String?
    @Published private(set) var isPreviewing = false
    @Published private(set) var isRecording = false

    private let defaults = UserDefaults.standard
    private let fileManager = FileManager.default
    private var previewPlayer: AVAudioPlayer?
    private var previewSynthesizer: AVSpeechSynthesizer?
    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?

    private static let sourceKey = "AutoAnswerGreetingSource.v1"
    private static let textKey = "AutoAnswerGreetingText.v1"
    private static let recordingNameKey = "AutoAnswerGreetingRecordingName.v1"
    private static let recordingFileKey = "AutoAnswerGreetingFile.v1"
    static let maximumTextLength = 200

    private override init() {
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: Self.sourceKey),
           let stored = AutoAnswerGreetingSource(rawValue: raw) {
            source = stored
        } else {
            source = .none
        }
        text = defaults.string(forKey: Self.textKey) ?? ""
        recordingDisplayName = defaults.string(forKey: Self.recordingNameKey)
        super.init()
        if recordingFileURL() == nil {
            recordingDisplayName = nil
        }
    }

    func setSource(_ source: AutoAnswerGreetingSource) {
        stopPreview()
        if isRecording { stopRecordingAndDiscard() }
        guard self.source != source else { return }
        self.source = source
        defaults.set(source.rawValue, forKey: Self.sourceKey)
    }

    func setText(_ text: String) {
        let clipped = String(text.prefix(Self.maximumTextLength))
        guard self.text != clipped else { return }
        self.text = clipped
        defaults.set(clipped, forKey: Self.textKey)
    }

    func installRecording(from sourceURL: URL) throws {
        stopPreview()
        if isRecording { stopRecordingAndDiscard() }
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessed { sourceURL.stopAccessingSecurityScopedResource() }
        }
        guard let player = try? AVAudioPlayer(contentsOf: sourceURL),
              player.duration.isFinite,
              player.duration > 0 else {
            throw AutoAnswerGreetingError.invalidAudio
        }
        if player.duration > CallUplinkPCM.maximumDuration {
            throw AutoAnswerGreetingError.tooLong
        }
        try replaceRecordingFile(from: sourceURL, displayName: sourceURL.lastPathComponent)
    }

    func clearRecording() {
        stopPreview()
        if isRecording { stopRecordingAndDiscard() }
        if let url = recordingFileURL() {
            try? fileManager.removeItem(at: url)
        }
        recordingDisplayName = nil
        defaults.removeObject(forKey: Self.recordingNameKey)
        defaults.removeObject(forKey: Self.recordingFileKey)
    }

    func startRecording() throws {
        stopPreview()
        if isRecording { stopRecordingAndDiscard() }
        let url = directoryURL.appendingPathComponent("greeting-capture.m4a")
        try? fileManager.removeItem(at: url)
        let recorder = try AVAudioRecorder(
            url: url,
            settings: [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 22_050,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
        )
        guard recorder.prepareToRecord(), recorder.record() else {
            throw AutoAnswerGreetingError.recordingFailed
        }
        self.recorder = recorder
        recordingURL = url
        isRecording = true
    }

    func stopRecording() throws {
        guard isRecording, let recorder, let url = recordingURL else { return }
        recorder.stop()
        self.recorder = nil
        isRecording = false
        recordingURL = nil
        do {
            try replaceRecordingFile(from: url, displayName: L10n.tr("已录制应答"))
        } catch {
            try? fileManager.removeItem(at: url)
            throw error
        }
        try? fileManager.removeItem(at: url)
        source = .recording
        defaults.set(AutoAnswerGreetingSource.recording.rawValue, forKey: Self.sourceKey)
    }

    func togglePreview() throws {
        if isPreviewing {
            stopPreview()
            return
        }
        switch source {
        case .none:
            return
        case .text:
            let spoken = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !spoken.isEmpty else { return }
            let synthesizer = AVSpeechSynthesizer()
            synthesizer.delegate = self
            let utterance = AVSpeechUtterance(string: spoken)
            utterance.voice = AVSpeechSynthesisVoice(
                language: AppLanguage.storedPreference.rawValue
            )
            previewSynthesizer = synthesizer
            isPreviewing = true
            synthesizer.speak(utterance)
        case .recording:
            guard let url = recordingFileURL(),
                  let player = try? AVAudioPlayer(contentsOf: url) else {
                throw AutoAnswerGreetingError.invalidAudio
            }
            player.delegate = self
            player.prepareToPlay()
            previewPlayer = player
            isPreviewing = true
            player.play()
        }
    }

    func stopPreview() {
        previewSynthesizer?.delegate = nil
        previewSynthesizer?.stopSpeaking(at: .immediate)
        previewSynthesizer = nil
        previewPlayer?.delegate = nil
        previewPlayer?.stop()
        previewPlayer = nil
        isPreviewing = false
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            guard synthesizer === previewSynthesizer else { return }
            stopPreview()
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(
        _ player: AVAudioPlayer,
        successfully flag: Bool
    ) {
        Task { @MainActor in
            guard player === previewPlayer else { return }
            stopPreview()
        }
    }

    func renderUplinkPCM() async throws -> Data {
        switch source {
        case .none:
            return Data()
        case .text:
            let spoken = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !spoken.isEmpty else { return Data() }
            return try await renderTextPCM(spoken)
        case .recording:
            guard let url = recordingFileURL() else { return Data() }
            return try renderFilePCM(url)
        }
    }

    private func renderTextPCM(_ text: String) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let synthesizer = AVSpeechSynthesizer()
            let utterance = AVSpeechUtterance(string: text)
            let language = AppLanguage.storedPreference.rawValue
            utterance.voice = AVSpeechSynthesisVoice.speechVoices().first {
                $0.language.hasPrefix(String(language.prefix(2))) && $0.quality == .default
            } ?? AVSpeechSynthesisVoice(language: language)
            let state = TTSRenderState(synthesizer: synthesizer, continuation: continuation)
            synthesizer.write(utterance) { buffer in
                state.append(buffer)
            }
        }
    }

    private func renderFilePCM(_ url: URL) throws -> Data {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let capacity = AVAudioFrameCount(min(
            file.length,
            AVAudioFramePosition(format.sampleRate * CallUplinkPCM.maximumDuration)
        ))
        guard capacity > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            throw AutoAnswerGreetingError.invalidAudio
        }
        try file.read(into: buffer)
        let samples = floatSamples(from: buffer)
        let pcm = CallUplinkPCM.pcm16LE(samples: samples, sampleRate: format.sampleRate)
        guard !pcm.isEmpty else { throw AutoAnswerGreetingError.invalidAudio }
        return pcm
    }

    private func replaceRecordingFile(from sourceURL: URL, displayName: String) throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let ext = sourceURL.pathExtension.isEmpty ? "m4a" : sourceURL.pathExtension
        let fileName = "greeting.\(ext)"
        let destination = directoryURL.appendingPathComponent(fileName)
        if let existing = recordingFileURL(), existing != destination {
            try? fileManager.removeItem(at: existing)
        }
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: sourceURL, to: destination)
        recordingDisplayName = displayName
        defaults.set(displayName, forKey: Self.recordingNameKey)
        defaults.set(fileName, forKey: Self.recordingFileKey)
    }

    private func stopRecordingAndDiscard() {
        recorder?.stop()
        recorder = nil
        isRecording = false
        if let url = recordingURL {
            try? fileManager.removeItem(at: url)
        }
        recordingURL = nil
    }

    private func recordingFileURL() -> URL? {
        let fileName = defaults.string(forKey: Self.recordingFileKey) ?? "greeting.m4a"
        let url = directoryURL.appendingPathComponent(fileName)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    private var directoryURL: URL {
        AppDataDirectory.userApplicationSupport()
            .appendingPathComponent("Greetings", isDirectory: true)
    }
}

enum AutoAnswerGreetingError: LocalizedError {
    case invalidAudio
    case tooLong
    case recordingFailed

    var errorDescription: String? {
        switch self {
        case .invalidAudio:
            return L10n.tr("无法读取该音频文件，请选择 macOS 支持的音频格式。")
        case .tooLong:
            return L10n.tr("应答录音最长 30 秒。")
        case .recordingFailed:
            return L10n.tr("无法开始录制应答语音。")
        }
    }
}

private final class TTSRenderState: @unchecked Sendable {
    private let synthesizer: AVSpeechSynthesizer
    private let lock = NSLock()
    private var samples: [Float] = []
    private var sampleRate = 0.0
    private var finished = false
    private let continuation: CheckedContinuation<Data, Error>

    init(
        synthesizer: AVSpeechSynthesizer,
        continuation: CheckedContinuation<Data, Error>
    ) {
        self.synthesizer = synthesizer
        self.continuation = continuation
        _ = self.synthesizer
    }

    func append(_ buffer: AVAudioBuffer) {
        lock.lock()
        defer { lock.unlock() }
        if finished { return }
        guard let pcm = buffer as? AVAudioPCMBuffer, pcm.frameLength > 0 else {
            finished = true
            let data = CallUplinkPCM.pcm16LE(samples: samples, sampleRate: sampleRate)
            continuation.resume(returning: data)
            return
        }
        if sampleRate == 0 {
            sampleRate = pcm.format.sampleRate
        }
        samples.append(contentsOf: floatSamples(from: pcm))
    }
}

private func floatSamples(from buffer: AVAudioPCMBuffer) -> [Float] {
    let frames = Int(buffer.frameLength)
    let channels = Int(buffer.format.channelCount)
    guard frames > 0, channels > 0 else { return [] }
    if let floats = buffer.floatChannelData {
        var mono = [Float](repeating: 0, count: frames)
        for channel in 0 ..< channels {
            let source = floats[channel]
            for frame in 0 ..< frames {
                mono[frame] += source[frame] / Float(channels)
            }
        }
        return mono
    }
    if let ints = buffer.int16ChannelData {
        var mono = [Float](repeating: 0, count: frames)
        let scale = 1 / Float(Int16.max)
        for channel in 0 ..< channels {
            let source = ints[channel]
            for frame in 0 ..< frames {
                mono[frame] += Float(source[frame]) * scale / Float(channels)
            }
        }
        return mono
    }
    return []
}
