import Combine
import Speech
import AVFoundation

/// Manages live speech recognition for voice command input.
/// Transcribes audio in real-time. Start/stop is controlled externally (e.g. press-and-hold).
@MainActor
final class VoiceRecognitionManager: ObservableObject {

    // MARK: - Published State

    enum PermissionStatus {
        case unknown    // not yet asked
        case authorized // mic + speech both granted
        case denied     // one or both denied — fall back to keyboard
    }

    @Published var isRecording      = false
    @Published var transcribedText  = ""
    @Published var permissionStatus: PermissionStatus = .unknown
    /// Average per-segment confidence from the most recent recognition (0–1).
    /// `nil` means no confidence info was reported by the recognizer.
    @Published var lastAverageConfidence: Float? = nil

    // MARK: - Private

    private let speechRecognizer    = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest  : SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask     : SFSpeechRecognitionTask?
    private let audioEngine         = AVAudioEngine()
    private var tapInstalled        = false

    // MARK: - Init

    init() {
        refreshPermissionStatus()
    }

    // MARK: - Permissions

    func refreshPermissionStatus() {
        let speech = SFSpeechRecognizer.authorizationStatus()

        var micGranted: Bool
        if #available(iOS 17.0, *) {
            micGranted = (AVAudioApplication.shared.recordPermission == .granted)
        } else {
            micGranted = (AVAudioSession.sharedInstance().recordPermission == .granted)
        }

        switch (speech, micGranted) {
        case (.authorized, true):
            permissionStatus = .authorized
        case (.denied, _), (.restricted, _), (_, false):
            permissionStatus = .denied
        default:
            permissionStatus = .unknown
        }
    }

    /// Requests both microphone and speech recognition permissions sequentially.
    func requestPermissions() async {
        let speechStatus = await withCheckedContinuation { (cont: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status)
            }
        }

        let micGranted: Bool = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { granted in
                    cont.resume(returning: granted)
                }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    cont.resume(returning: granted)
                }
            }
        }

        permissionStatus = (speechStatus == .authorized && micGranted) ? .authorized : .denied
    }

    // MARK: - Recording

    /// Starts live recognition. Throws if the audio session or engine can't start.
    func startRecording() throws {
        guard !audioEngine.isRunning else { return }
        guard speechRecognizer?.isAvailable == true else { return }

        transcribedText = ""
        lastAverageConfidence = nil

        // Configure audio session for recording
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        // Build recognition request
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Prefer on-device recognition for offline + privacy (iOS 16+)
        if #available(iOS 16, *) {
            request.requiresOnDeviceRecognition = speechRecognizer?.supportsOnDeviceRecognition ?? false
        }
        recognitionRequest = request

        // Start recognition task
        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let text = result.bestTranscription.formattedString
                let avg  = Self.averageConfidence(of: result.bestTranscription.segments.map { $0.confidence })
                Task { @MainActor [weak self] in
                    guard let self, self.isRecording else { return }
                    self.transcribedText = text
                    self.lastAverageConfidence = avg
                }
            }

            // Recognition ended (error or final result)
            if error != nil || result?.isFinal == true {
                Task { @MainActor [weak self] in
                    self?.stopRecording()
                }
            }
        }

        // Tap the microphone input
        let inputNode = audioEngine.inputNode
        let format    = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
        tapInstalled = true

        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true
    }

    /// Stops recording cleanly. Transcribed text is preserved so the caller can submit it.
    func stopRecording() {
        if audioEngine.isRunning { audioEngine.stop() }
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }

        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        isRecording = false
    }

    /// Stops recording and clears any partial transcription (e.g. user cancels).
    func cancelRecording() {
        stopRecording()
        transcribedText = ""
    }

    // MARK: - Confidence

    /// Averages per-segment confidence values, ignoring zeros (which mean "no info").
    /// Returns `nil` if no segment reported a usable confidence — callers should treat
    /// that as "submit anyway" rather than penalising the user.
    static func averageConfidence(of values: [Float]) -> Float? {
        let nonZero = values.filter { $0 > 0 }
        guard !nonZero.isEmpty else { return nil }
        return nonZero.reduce(0, +) / Float(nonZero.count)
    }

    // MARK: - Number Word Normalisation

    /// Converts English number words (zero – ninety-nine) to digit strings.
    ///
    /// Handles:
    /// - Simple words:   "one" → "1", "fifteen" → "15"
    /// - Round tens:     "thirty" → "30", "eighty" → "80"
    /// - Compounds:      "twenty-one" / "twenty one" → "21"
    ///
    /// Uses `\b` word-boundary matching so substrings like "bone" are never touched.
    static func normalizeNumberWords(_ input: String) -> String {
        let ones = [
            "zero", "one", "two", "three", "four", "five", "six", "seven",
            "eight", "nine", "ten", "eleven", "twelve", "thirteen", "fourteen",
            "fifteen", "sixteen", "seventeen", "eighteen", "nineteen"
        ]
        let tens = [
            "", "", "twenty", "thirty", "forty", "fifty",
            "sixty", "seventy", "eighty", "ninety"
        ]

        var text = input.lowercased()

        // 1. Compound numbers first so "twenty one" → "21" before
        //    "one" could become "1" on its own.
        for t in 2...9 {
            for o in 1...9 {
                let value = t * 10 + o
                // Hyphenated: "twenty-one"
                text = text.replacingOccurrences(
                    of: "\\b\(tens[t])-\(ones[o])\\b",
                    with: "\(value)",
                    options: .regularExpression
                )
                // Space-separated: "twenty one"
                text = text.replacingOccurrences(
                    of: "\\b\(tens[t]) \(ones[o])\\b",
                    with: "\(value)",
                    options: .regularExpression
                )
            }
        }

        // 2. Round tens: "twenty" → "20", "ninety" → "90", etc.
        for t in 2...9 {
            text = text.replacingOccurrences(
                of: "\\b\(tens[t])\\b",
                with: "\(t * 10)",
                options: .regularExpression
            )
        }

        // 3. Zero through nineteen
        for (i, word) in ones.enumerated() {
            text = text.replacingOccurrences(
                of: "\\b\(word)\\b",
                with: "\(i)",
                options: .regularExpression
            )
        }

        return text
    }
}
