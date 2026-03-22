// FineTune/Views/Components/MuteButton.swift
import SwiftUI

enum SpeakerVolumeIcon {
    static func symbolName(levelFraction: Double, isMuted: Bool = false, filled: Bool = true) -> String {
        if isMuted {
            return filled ? "speaker.slash.fill" : "speaker.slash"
        }

        let level = max(0.0, min(1.0, levelFraction))
        let suffix = filled ? ".fill" : ""

        if level <= 1.0 / 3.0 {
            return "speaker.wave.1\(suffix)"
        } else if level <= 2.0 / 3.0 {
            return "speaker.wave.2\(suffix)"
        } else {
            return "speaker.wave.3\(suffix)"
        }
    }

    static func layoutReferenceSymbol(filled: Bool = true) -> String {
        filled ? "speaker.wave.3.fill" : "speaker.wave.3"
    }
}

/// A mute button with pulse animation on toggle
/// Shows speaker.wave when unmuted, speaker.slash when muted
struct MuteButton: View {
    let isMuted: Bool
    let levelFraction: Double
    let action: () -> Void

    init(isMuted: Bool, levelFraction: Double = 1.0, action: @escaping () -> Void) {
        self.isMuted = isMuted
        self.levelFraction = levelFraction
        self.action = action
    }

    var body: some View {
        BaseMuteButton(
            isMuted: isMuted,
            mutedIcon: "speaker.slash.fill",
            unmutedIcon: SpeakerVolumeIcon.symbolName(levelFraction: levelFraction),
            layoutReferenceIcon: SpeakerVolumeIcon.layoutReferenceSymbol(),
            mutedHelp: "Unmute",
            unmutedHelp: "Mute",
            action: action
        )
    }
}

/// A mute button for input devices (microphones)
/// Shows mic when unmuted, mic.slash when muted
struct InputMuteButton: View {
    let isMuted: Bool
    let action: () -> Void

    var body: some View {
        BaseMuteButton(
            isMuted: isMuted,
            mutedIcon: "mic.slash.fill",
            unmutedIcon: "mic.fill",
            layoutReferenceIcon: "mic.fill",
            mutedHelp: "Unmute microphone",
            unmutedHelp: "Mute microphone",
            action: action
        )
    }
}

// MARK: - Base Implementation

/// Shared mute button implementation with configurable icons
private struct BaseMuteButton: View {
    let isMuted: Bool
    let mutedIcon: String
    let unmutedIcon: String
    let layoutReferenceIcon: String
    let mutedHelp: String
    let unmutedHelp: String
    let action: () -> Void

    @State private var isPulsing = false
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .leading) {
                Image(systemName: layoutReferenceIcon)
                    .opacity(0)
                Image(systemName: currentIcon)
                    .contentTransition(.symbolEffect(.replace))
            }
            .font(.system(size: 14))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(buttonColor)
            .fixedSize()
            .padding(.horizontal, 4)
            .scaleEffect(isPulsing ? 1.1 : 1.0)
            .frame(
                minWidth: DesignTokens.Dimensions.minTouchTarget,
                minHeight: DesignTokens.Dimensions.minTouchTarget,
                alignment: .leading
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(MuteButtonPressStyle())
        .onHover { hovering in
            isHovered = hovering
        }
        .help(isMuted ? mutedHelp : unmutedHelp)
        .animation(.spring(response: 0.25, dampingFraction: 0.5), value: isPulsing)
        .animation(DesignTokens.Animation.hover, value: isHovered)
        .animation(.easeInOut(duration: 0.18), value: unmutedIcon)
        .onChange(of: isMuted) { _, _ in
            isPulsing = true
            Task {
                try? await Task.sleep(for: .seconds(0.25))
                isPulsing = false
            }
        }
    }

    private var currentIcon: String {
        isMuted ? mutedIcon : unmutedIcon
    }

    private var buttonColor: Color {
        if isMuted {
            return DesignTokens.Colors.mutedIndicator
        } else if isHovered {
            return DesignTokens.Colors.interactiveHover
        } else {
            return DesignTokens.Colors.interactiveDefault
        }
    }
}

/// Internal button style for press feedback
private struct MuteButtonPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Previews

#Preview("Mute Button States") {
    ComponentPreviewContainer {
        HStack(spacing: DesignTokens.Spacing.lg) {
            VStack {
                MuteButton(isMuted: false) {}
                Text("Unmuted")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack {
                MuteButton(isMuted: true) {}
                Text("Muted")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview("Input Mute Button States") {
    ComponentPreviewContainer {
        HStack(spacing: DesignTokens.Spacing.lg) {
            VStack {
                InputMuteButton(isMuted: false) {}
                Text("Unmuted")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack {
                InputMuteButton(isMuted: true) {}
                Text("Muted")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview("Mute Button Interactive") {
    struct InteractivePreview: View {
        @State private var isMuted = false

        var body: some View {
            ComponentPreviewContainer {
                VStack(spacing: DesignTokens.Spacing.md) {
                    MuteButton(isMuted: isMuted) {
                        isMuted.toggle()
                    }

                    Text(isMuted ? "Muted" : "Playing")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
    return InteractivePreview()
}
