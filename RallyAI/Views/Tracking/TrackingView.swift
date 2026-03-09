import SwiftUI

struct TrackingView: View {
    @EnvironmentObject private var vm: TrackingViewModel
    @State private var isComposerVisible = false
    @State private var draftCommand = ""
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
                if isComposerVisible {
                    composerBar
                }
            }
        }
    }

    private var scoreHeader: some View {
        HStack(alignment: .center, spacing: 20) {
            scoreBox(label: "Us", value: vm.score.us, team: .us)

            Text("Set \(vm.currentSetNumber)")
                .font(.headline)
                .frame(maxWidth: .infinity)

            scoreBox(label: "Them", value: vm.score.them, team: .them)
        }
    }

    private func scoreBox(label: String, value: Int, team: TeamSide) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.subheadline)
            Text("\(value)")
                .font(.system(size: 38, weight: .medium, design: .rounded))
        }
        .frame(width: 84, height: 84)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .highPriorityGesture(
            DragGesture(minimumDistance: 18)
                .onEnded { drag in
                    let vertical = drag.translation.height
                    let horizontal = drag.translation.width

                    guard abs(vertical) > abs(horizontal) else { return }

                    if vertical <= -24 {
                        vm.adjustScore(team: team, delta: 1)
                    } else if vertical >= 24 {
                        vm.adjustScore(team: team, delta: -1)
                    }
                }
        )
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No commands yet")
                .font(.headline)
            Text("Tap the mic button to type a command.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func commandCard(_ command: CommandInput) -> some View {
        let style = style(for: command)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(command.rawText)
                    .font(.title3.weight(.medium))
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
            .foregroundStyle(.primary)
            .font(.headline)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(style.background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var micButton: some View {
        Button {
            isComposerVisible = true
            isCommandFieldFocused = true
        } label: {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Circle()
                            .fill(Color.blue.opacity(0.34))
                    )
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.62), lineWidth: 1)
                    )
                    .overlay(
                        Circle()
                            .stroke(Color.blue.opacity(0.32), lineWidth: 2)
                            .blur(radius: 1)
                    )
                    .overlay(
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        Color.white.opacity(0.22),
                                        Color.clear
                                    ],
                                    center: .topLeading,
                                    startRadius: 16,
                                    endRadius: 54
                                )
                            )
                    )

                Image(systemName: "mic.fill")
                    .font(.system(size: 33, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.14), radius: 1.6, x: 0, y: 1)
            }
            .frame(width: 78, height: 78)
            .shadow(color: Color.blue.opacity(0.25), radius: 12, x: 0, y: 6)
            .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 3)
        }
        .disabled(vm.isLoading)
    }

    private var composerBar: some View {
        HStack(spacing: 10) {
            TextField("Type a command", text: $draftCommand)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($isCommandFieldFocused)

            Button("Send") {
                Task {
                    vm.inputText = draftCommand
                    await vm.sendTextCommand()
                    draftCommand = ""
                    isComposerVisible = false
                    isCommandFieldFocused = false
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(vm.isLoading || draftCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
    }

    private func statusMessage(for command: CommandInput) -> String? {
        switch command.status {
        case .failed:
            return command.errorMessage ?? "Could not interpret this command"
        case .needsReview:
            return "Could not interpret this command"
        /*case .committed:
            if let parsed = command.parsedEvent {
                return "Mapped to \(parsed.event)"
            }
            return nil*/
        case .parsing:
            return "Parsing..."
        default:
            return nil
        }
    }

    private func statusIcon(for command: CommandInput) -> some View {
        Group {
            switch command.status {
            case .committed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
            case .needsReview:
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
            case .parsing:
                ProgressView()
            default:
                Image(systemName: "clock.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.title2)
    }

    private func style(for command: CommandInput) -> (background: Color, subtitleColor: Color) {
        switch command.status {
        case .committed:
            return (Color.green.opacity(0.28), .green)
        case .failed:
            return (Color.red.opacity(0.24), .red)
        case .needsReview:
            return (Color.orange.opacity(0.24), .orange)
        default:
            return (Color(.secondarySystemGroupedBackground), .secondary)
        }
    }
}

#Preview {
    TrackingView()
        .environmentObject(TrackingViewModel())
}
