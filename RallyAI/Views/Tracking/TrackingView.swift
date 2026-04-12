import SwiftUI

struct TrackingView: View {
    @EnvironmentObject private var vm: TrackingViewModel
    @StateObject private var voice = VoiceRecognitionManager()

    @State private var isComposerVisible = false
    @State private var draftCommand = ""
    @State private var isPulsing = false
    @State private var isHolding = false
    @FocusState private var isCommandFieldFocused: Bool

    /// Tracks the score at which the set-win banner was last dismissed.
    /// When the live score matches this, the auto-triggered banner stays hidden.
    @State private var setWinBannerDismissedScore: Score? = nil
    /// True when the coach manually tapped "End Set" mid-game (no win condition required).
    @State private var manualEndSetRequested = false
    /// Which set's command feed is currently displayed. Defaults to the live set.
    @State private var viewingSetNumber: Int = 1

    private var isViewingPastSet: Bool { viewingSetNumber < vm.currentSetNumber }

    private var viewingScore: Score {
        vm.gameState.scoreForSet(viewingSetNumber)
    }

    private var showSetWinBanner: Bool {
        guard !isViewingPastSet else { return false }
        if manualEndSetRequested { return true }
        guard vm.setWinningTeam != nil else { return false }
        return setWinBannerDismissedScore != vm.score
    }

    private var commandsForCurrentSet: [CommandInput] {
        vm.commandQueue
            .filter { $0.setNumber == viewingSetNumber }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Score header lives outside the ScrollView so swipe-to-adjust
                    // gestures never compete with scrolling
                    scoreHeader
                        .padding(.horizontal, 16)
                        .padding(.top, 12)

                    ScrollView {
                        VStack(spacing: 14) {
                            if voice.isRecording {
                                recordingCard
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            }

                            if vm.isActiveMatchCompleted {
                                completedMatchBanner
                            } else if showSetWinBanner {
                                setWinBanner
                                    .transition(.move(edge: .top).combined(with: .opacity))
                            }

                            if isViewingPastSet {
                                HStack(spacing: 6) {
                                    Image(systemName: "clock")
                                        .font(.caption2)
                                    Text("Viewing Set \(viewingSetNumber) — tap → to return to live")
                                        .font(.caption)
                                }
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 6)
                            }

                            if commandsForCurrentSet.isEmpty {
                                emptyState
                            } else {
                                ForEach(commandsForCurrentSet) { command in
                                    commandCard(command)
                                }
                            }
                        }
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showSetWinBanner)
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                        .padding(.bottom, 120)
                    }
                }

                if !vm.isActiveMatchCompleted {
                    micButton
                        .padding(.bottom, 20)
                }

            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: voice.isRecording)
            .navigationTitle("Tracking")
            .safeAreaInset(edge: .bottom) {
                Group {
                    if isComposerVisible && !vm.isActiveMatchCompleted {
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
            viewingSetNumber = vm.currentSetNumber
        }
        .onChange(of: vm.currentSetNumber) { _, newSetNumber in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                viewingSetNumber = newSetNumber
            }
        }
    }

    // MARK: - Hold-to-Record

    private func handleHoldBegan() {
        guard !isHolding else { return }
        isHolding = true

        switch voice.permissionStatus {
        case .authorized:
            // Recording card at top handles all visual feedback — no composer needed
            try? voice.startRecording()

        case .denied:
            // No voice access — fall back to keyboard composer
            isComposerVisible = true
            isCommandFieldFocused = true

        case .unknown:
            // First hold ever — request permissions then start
            Task {
                await voice.requestPermissions()
                if voice.permissionStatus == .authorized {
                    try? voice.startRecording()
                } else {
                    isComposerVisible = true
                    isCommandFieldFocused = true
                }
            }
        }
    }

    private func handleHoldEnded() {
        guard isHolding else { return }
        isHolding = false
        guard voice.isRecording else { return }

        voice.stopRecording()

        let text = voice.transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            isComposerVisible = false
            return
        }

        // Split into individual commands on commas or "and", submit each separately
        let commands = splitCommands(text)
        Task {
            for command in commands {
                vm.inputText = VoiceRecognitionManager.normalizeNumberWords(command)
                await vm.sendTextCommand()
            }
            draftCommand = ""
        }
    }

    /// Splits a transcript into individual commands on natural spoken boundaries.
    /// e.g. "7 ace, 4 kill" → ["7 ace", "4 kill"]
    ///      "7 ace and 4 kill" → ["7 ace", "4 kill"]
    private func splitCommands(_ text: String) -> [String] {
        text
            .components(separatedBy: ",")
            .flatMap { $0.components(separatedBy: " and ") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Score Header

    private var scoreHeader: some View {
        HStack(alignment: .center, spacing: 16) {
            scoreBox(label: ourTeamLabel, value: viewingScore.us, team: .us)

            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            viewingSetNumber -= 1
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .opacity(viewingSetNumber > 1 ? 1 : 0)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewingSetNumber <= 1)

                    Text("Set \(viewingSetNumber)")
                        .font(.headline)
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: viewingSetNumber)

                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            viewingSetNumber += 1
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .opacity(isViewingPastSet ? 1 : 0)
                    }
                    .buttonStyle(.plain)
                    .disabled(!isViewingPastSet)
                }

                Text("\(vm.setsWon.us) – \(vm.setsWon.them)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if !isViewingPastSet {
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            manualEndSetRequested = true
                        }
                    } label: {
                        Text("End Set")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color(.tertiarySystemGroupedBackground), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity)

            scoreBox(label: opponentLabel, value: viewingScore.them, team: .them)
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

    // MARK: - Completed Match Banner

    private var completedMatchBanner: some View {
        let setsWon = vm.setsWon
        let weWon = setsWon.us > setsWon.them
        let accentColor: Color = weWon ? .green : .red

        return HStack(spacing: 12) {
            Image(systemName: weWon ? "trophy.fill" : "flag.fill")
                .foregroundStyle(accentColor)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text("Match complete")
                    .font(.subheadline.weight(.semibold))
                Text("Final sets: \(setsWon.us) – \(setsWon.them) · Read only")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(accentColor.opacity(0.35), lineWidth: 1.5)
                )
        )
    }

    // MARK: - Set Win Banner

    private var setWinBanner: some View {
        let winningTeam = vm.setWinningTeam
        let isManual = winningTeam == nil
        let weWon = winningTeam == .us
        let accentColor: Color = isManual ? .orange : (weWon ? .green : .red)
        let ourName = vm.activeMatch?.ourTeamName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let theirName = vm.activeMatch?.opponentName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let teamName: String = weWon
            ? (ourName.isEmpty ? "Us" : ourName)
            : (theirName.isEmpty ? "Them" : theirName)
        let setsWon = vm.setsWon

        return VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: isManual ? "flag.checkered" : (weWon ? "trophy.fill" : "flag.fill"))
                    .foregroundStyle(accentColor)
                    .font(.title3.weight(.semibold))

                VStack(alignment: .leading, spacing: 2) {
                    Text(isManual ? "End of Set \(vm.currentSetNumber)?" : "\(teamName) wins Set \(vm.currentSetNumber)")
                        .font(.subheadline.weight(.semibold))
                    Text("Sets: \(setsWon.us) – \(setsWon.them)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            HStack(spacing: 10) {
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        vm.startNewSet()
                        setWinBannerDismissedScore = nil
                        manualEndSetRequested = false
                    }
                } label: {
                    Text("New Set")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Color.blue, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        vm.completeMatch()
                        manualEndSetRequested = false
                    }
                } label: {
                    Text("End Match")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        setWinBannerDismissedScore = vm.score
                        manualEndSetRequested = false
                    }
                } label: {
                    Text("Keep Going")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(accentColor.opacity(0.35), lineWidth: 1.5)
                )
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

        return VStack(spacing: 10) {
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
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.95, green: 0.25, blue: 0.25),
                                         Color(red: 0.75, green: 0.1, blue: 0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [Color.white.opacity(0.28), Color.clear],
                                        center: .topLeading,
                                        startRadius: 8,
                                        endRadius: 52
                                    )
                                )
                        )
                        .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 1))
                } else {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.45, green: 0.72, blue: 1.0),
                                         Color(red: 0.2, green: 0.52, blue: 1.0)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [Color.white.opacity(0.38), Color.clear],
                                        center: .topLeading,
                                        startRadius: 8,
                                        endRadius: 52
                                    )
                                )
                        )
                        .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 1))
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
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in handleHoldBegan() }
                    .onEnded   { _ in handleHoldEnded() }
            )
            .disabled(vm.isLoading)

            HStack(spacing: 14) {
                Text(isRecording ? "Release to send" : "Hold to record")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isRecording ? .red : .secondary)

                if !isRecording {
                    Button {
                        isComposerVisible = true
                        isCommandFieldFocused = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "keyboard")
                                .font(.caption)
                            Text("Type")
                                .font(.caption.weight(.medium))
                        }
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isRecording)
        }
    }

    // MARK: - Recording Card

    private var recordingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                    .opacity(isPulsing ? 0.25 : 1.0)
                    .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: isPulsing)

                Text("Recording…")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)

                Spacer()

                Button("Cancel") {
                    voice.cancelRecording()
                    isHolding = false
                    draftCommand = ""
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            }

            Text(draftCommand.isEmpty ? "Speak your command…" : draftCommand)
                .font(.title3.weight(.medium))
                .foregroundStyle(draftCommand.isEmpty ? .tertiary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(4)
                .animation(.default, value: draftCommand)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 6)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Composer Bar

    private var composerBar: some View {
        HStack(spacing: 10) {
            TextField("Type a command", text: $draftCommand)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($isCommandFieldFocused)

            Button("Send") {
                submitCommand()
            }
            .buttonStyle(.borderedProminent)
            .disabled(vm.isLoading || draftCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button {
                draftCommand = ""
                isComposerVisible = false
                isCommandFieldFocused = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
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
