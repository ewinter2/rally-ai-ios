import SwiftUI

struct TrackingView: View {
    @EnvironmentObject private var vm: TrackingViewModel
    @StateObject private var voice = VoiceRecognitionManager()

    @State private var isComposerVisible = false
    @State private var draftCommand = ""
    @State private var isPulsing = false
    @FocusState private var isCommandFieldFocused: Bool

    private var commandsForCurrentSet: [CommandInput] {
        vm.commandQueue
            .filter { $0.setNumber == vm.currentSetNumber }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 14) {
                        scoreHeader

                        if commandsForCurrentSet.isEmpty {
                            emptyState
                        } else {
                            ForEach(commandsForCurrentSet) { command in
                                commandCard(command)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 120)
                }

                micButton
                    .padding(.bottom, 20)
            }
            .navigationTitle("Tracking")
            .safeAreaInset(edge: .bottom) {
                Group {
                    if isComposerVisible {
                        composerBar
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isComposerVisible)
            }
        }
        // Keep draftCommand in sync with live transcription
        .onChange(of: voice.transcribedText) { _, newText in
            draftCommand = newText
        }
        // Start/stop the pulsing ring animation with recording state
        .onChange(of: voice.isRecording) { _, recording in
            if recording {
                isPulsing = true
            } else {
                isPulsing = false
            }
        }
        .onAppear {
            // Wire auto-submit: fires after 1.5 s of silence during voice recording
            voice.onAutoSubmit = { text in
                Task {
                    vm.inputText = VoiceRecognitionManager.normalizeNumberWords(text)
                    await vm.sendTextCommand()
                    draftCommand = ""
                    isComposerVisible = false
                }
            }
        }
    }

    // MARK: - Mic Button Action

    private func handleMicTap() {
        // If already recording: stop (keep text so coach can review/edit before sending)
        if voice.isRecording {
            voice.stopRecording()
            isCommandFieldFocused = true
            return
        }

        switch voice.permissionStatus {
        case .authorized:
            isComposerVisible = true
            try? voice.startRecording()

        case .denied:
            // No voice access — fall back to keyboard composer
            isComposerVisible = true
            isCommandFieldFocused = true

        case .unknown:
            // First time — request permissions then start if granted
            Task {
                await voice.requestPermissions()
                if voice.permissionStatus == .authorized {
                    isComposerVisible = true
                    try? voice.startRecording()
                } else {
                    isComposerVisible = true
                    isCommandFieldFocused = true
                }
            }
        }
    }

    // MARK: - Score Header

    private var scoreHeader: some View {
        HStack(alignment: .center, spacing: 16) {
            scoreBox(label: ourTeamLabel, value: vm.score.us, team: .us)

            VStack(spacing: 4) {
                Text("Set \(vm.currentSetNumber)")
                    .font(.headline)
                Text("\(vm.setsWon.us) – \(vm.setsWon.them)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            scoreBox(label: opponentLabel, value: vm.score.them, team: .them)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var ourTeamLabel: String {
        let name = vm.activeMatch?.ourTeamName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Us" : name
    }

    private var opponentLabel: String {
        let name = vm.activeMatch?.opponentName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Them" : name
    }

    private func scoreBox(label: String, value: Int, team: TeamSide) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("\(value)")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
                .animation(.spring(response: 0.3, dampingFraction: 0.75), value: value)
        }
        .frame(width: 96, height: 90)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .highPriorityGesture(
            DragGesture(minimumDistance: 18)
                .onEnded { drag in
                    let vertical   = drag.translation.height
                    let horizontal = drag.translation.width
                    guard abs(vertical) > abs(horizontal) else { return }
                    if vertical <= -24 {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            vm.adjustScore(team: team, delta: 1)
                        }
                    } else if vertical >= 24 {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            vm.adjustScore(team: team, delta: -1)
                        }
                    }
                }
        )
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "mic.circle")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text("No commands yet")
                .font(.headline)
            Text("Tap the mic button to speak or type a command.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Command Card

    private func commandCard(_ command: CommandInput) -> some View {
        let style = cardStyle(for: command)

        return HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(style.accentColor)
                .frame(width: 4)
                .padding(.vertical, 6)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    Text(command.rawText)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    Spacer(minLength: 12)

                    statusIcon(for: command)
                }

                if let message = statusMessage(for: command) {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(style.subtitleColor)
                }

                HStack(spacing: 14) {
                    Button {
                        draftCommand = command.rawText
                        isComposerVisible = true
                        isCommandFieldFocused = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.plain)

                    Button {
                        vm.removeCommand(id: command.id)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                }
                .foregroundStyle(.secondary)
                .font(.callout.weight(.medium))
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(style.background)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Mic Button

    private var micButton: some View {
        let isRecording = voice.isRecording

        return Button {
            handleMicTap()
        } label: {
            ZStack {
                // Expanding ripple ring — only while recording
                if isRecording {
                    Circle()
                        .stroke(Color.red.opacity(0.35), lineWidth: 2.5)
                        .scaleEffect(isPulsing ? 1.55 : 1.0)
                        .opacity(isPulsing ? 0 : 1)
                        .animation(
                            .easeOut(duration: 1.1).repeatForever(autoreverses: false),
                            value: isPulsing
                        )
                        .frame(width: 78, height: 78)
                }

                // Button face
                if isRecording {
                    Circle()
                        .fill(Color.red)
                        .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 1))
                } else {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(Circle().fill(Color.blue.opacity(0.34)))
                        .overlay(Circle().stroke(Color.white.opacity(0.62), lineWidth: 1))
                        .overlay(
                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [Color.white.opacity(0.22), Color.clear],
                                        center: .topLeading,
                                        startRadius: 16,
                                        endRadius: 54
                                    )
                                )
                        )
                }

                Image(systemName: isRecording ? "waveform" : "mic.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.14), radius: 1.6, x: 0, y: 1)
                    .animation(.spring(response: 0.25), value: isRecording)
            }
            .frame(width: 78, height: 78)
            .shadow(
                color: isRecording ? Color.red.opacity(0.35) : Color.blue.opacity(0.25),
                radius: 12, x: 0, y: 6
            )
            .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 3)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isRecording)
        }
        .disabled(vm.isLoading)
    }

    // MARK: - Composer Bar

    private var composerBar: some View {
        VStack(spacing: 0) {
            // Recording status strip
            if voice.isRecording {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 7, height: 7)
                        .opacity(isPulsing ? 0.25 : 1.0)
                        .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: isPulsing)

                    Text("Listening…")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)

                    Spacer()

                    Button("Cancel") {
                        voice.cancelRecording()
                        draftCommand = ""
                        isComposerVisible = false
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 4)
            }

            HStack(spacing: 10) {
                TextField(
                    voice.isRecording ? "Speak your command…" : "Type a command",
                    text: $draftCommand
                )
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($isCommandFieldFocused)
                // Field is read-only during recording; tap Stop to edit manually
                .disabled(voice.isRecording)

                if voice.isRecording {
                    // Stop recording — keeps transcribed text for manual review/edit
                    Button {
                        voice.stopRecording()
                        isCommandFieldFocused = true
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button("Send") {
                        submitCommand()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(vm.isLoading || draftCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Submit

    private func submitCommand() {
        let raw = draftCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        Task {
            vm.inputText = VoiceRecognitionManager.normalizeNumberWords(raw)
            await vm.sendTextCommand()
            draftCommand = ""
            isComposerVisible = false
            isCommandFieldFocused = false
        }
    }

    // MARK: - Status Helpers

    private func statusMessage(for command: CommandInput) -> String? {
        switch command.status {
        case .failed:      return command.errorMessage ?? "Could not interpret this command"
        case .needsReview: return "Could not interpret this command"
        case .parsing:     return "Parsing…"
        default:           return nil
        }
    }

    private func statusIcon(for command: CommandInput) -> some View {
        Group {
            switch command.status {
            case .committed:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .failed:
                Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
            case .needsReview:
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
            case .parsing:
                ProgressView()
            default:
                Image(systemName: "clock.fill").foregroundStyle(.secondary)
            }
        }
        .font(.title2)
    }

    private func cardStyle(for command: CommandInput) -> (background: Color, accentColor: Color, subtitleColor: Color) {
        switch command.status {
        case .committed:   return (Color.green.opacity(0.1),  .green,  .green)
        case .failed:      return (Color.red.opacity(0.08),   .red,    .red)
        case .needsReview: return (Color.orange.opacity(0.1), .orange, .orange)
        default:           return (Color(.secondarySystemGroupedBackground), Color(.separator), .secondary)
        }
    }
}

#Preview {
    TrackingView()
        .environmentObject(TrackingViewModel())
}
