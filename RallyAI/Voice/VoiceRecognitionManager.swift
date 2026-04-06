import Combine
import Speech
import AVFoundation

/// Manages live speech recognition for voice command input.
/// Transcribes audio in real-time and fires `onAutoSubmit` after 1.5 s of silence.
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

    // MARK: - Callbacks

    /// Called automatically after 1.5 s of silence with the final transcribed text.
    var onAutoSubmit: ((String) -> Void)?

    // MARK: - Private

    private let speechRecognizer    = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest  : SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask     : SFSpeechRecognitionTask?
    private let audioEngine         = AVAudioEngine()
    private var silenceTimer        : Timer?
    private var tapInstalled        = false

    // MARK: - Init

    init() {
        refreshPermissionStatus()
    }

    // MARK: - Permissions

    func refreshPermissionStatus() {
        let speech = SFSpeechRecognizer.authorizationStatus()
        let mic    = AVAudioSession.sharedInstance().recordPermission

        switch (speech, mic) {
        case (.authorized, .granted):
            permissionStatus = .authorized
        case (.denied, _), (.restricted, _), (_, .denied):
            permissionStatus = .denied
        default:
            permissionStatus = .unknown
        }
    }

    /// Requests both microphone and speech recognition permissions sequentially.
    func requestPermissions() async {
        let speechStatus = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }

        let micGranted = await withCheckedContinuation { cont in
            AVAudioSession.sharedInstance().requestRecordPermission { cont.resume(returning: $0) }
        }

        permissionStatus = (speechStatus == .authorized && micGranted) ? .authorized : .denied
    }

    // MARK: - Recording

    /// Starts live recognition. Throws if the audio session or engine can't start.
    func startRecording() throws {
        guard !audioEngine.isRunning else { return }
        guard speechRecognizer?.isAvailable == true else { return }

        transcribedText = ""

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
                Task { @MainActor [weak self] in
                    guard let self, self.isRecording else { return }
                    self.transcribedText = text
                    self.scheduleAutoSubmit()
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

    /// Stops recording cleanly. Transcribed text is preserved for manual review.
    func stopRecording() {
        cancelSilenceTimer()

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

    // MARK: - Auto Submit

    private func scheduleAutoSubmit() {
        cancelSilenceTimer()
        guard !transcribedText.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        silenceTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self, self.isRecording else { return }
                let text = self.transcribedText
                self.stopRecording()
                self.onAutoSubmit?(text)
            }
        }
    }

    private func cancelSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = nil
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
