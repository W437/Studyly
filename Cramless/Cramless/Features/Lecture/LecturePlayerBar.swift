import SwiftUI

/// Hearing the lecture: pinned under the notes when its audio is on this iPhone. Its own view, so the clock's ticks redraw only this bar.
/// A moment cued from a question or a citation waits on "Play from 12:36"; once playing, the big button is Play and Pause.
struct LecturePlayerBar: View {
    let player: LecturePlayer

    /// Where a finger has the slider; the clock doesn't move it meanwhile.
    @State private var scrubbing: Double?
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let duration = max(player.track?.duration ?? 0, 1)
        let shown = min(scrubbing ?? player.position, duration)
        VStack(spacing: 4) {
            if player.refusedForRecording {
                Label("Playback is off while a lecture is recording.", systemImage: "mic.fill")
                    .clFont(.footnote)
                    .foregroundStyle(CLColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 4)
            }
            Slider(value: Binding(get: { shown }, set: { scrubbing = $0 }), in: 0...duration) { editing in
                guard !editing, let target = scrubbing else { return }
                player.seek(to: target)
                scrubbing = nil
            }
            .tint(CLColor.skyInk)
            .accessibilityLabel(Text("Where you are in the lecture"))
            .accessibilityValue(Text(CLFormat.timestamp(shown)))
            if typeSize.isAccessibilitySize {
                HStack {
                    times(elapsed: shown, duration: duration)
                }
                controls.frame(maxWidth: .infinity)
            } else {
                ZStack {
                    HStack { times(elapsed: shown, duration: duration) }
                    controls
                }
            }
        }
        .padding(.horizontal, CLSpace.gutter)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .frame(maxWidth: CLMetrics.readableWidth)
        .frame(maxWidth: .infinity)
        .background(alignment: .top) {
            CLColor.background
                .overlay(alignment: .top) { Rectangle().fill(CLColor.hairline).frame(height: 0.5) }
                .ignoresSafeArea(edges: .bottom)
        }
    }

    @ViewBuilder
    private func times(elapsed: Double, duration: Double) -> some View {
        Text(CLFormat.timestamp(elapsed))
            .clFont(.number(13, .semibold))
            .foregroundStyle(CLColor.ink2)
            .accessibilityHidden(true)
        Spacer(minLength: 8)
        Text("-\(CLFormat.timestamp(duration - elapsed))")
            .clFont(.number(13, .semibold))
            .foregroundStyle(CLColor.ink3)
            .accessibilityHidden(true)
    }

    private var controls: some View {
        HStack(spacing: 10) {
            CLIconButton(systemImage: "gobackward.15", label: "Back 15 seconds") {
                CLHaptics.select()
                player.back15()
            }
            playButton
            Button {
                CLHaptics.select()
                player.cycleSpeed()
            } label: {
                Text(player.speed.label)
                    .clFont(.number(13, .bold))
                    .foregroundStyle(CLColor.ink)
                    .frame(minWidth: 34, minHeight: 34)
                    .background(CLColor.surface3, in: Capsule())
                    .frame(minWidth: CLMetrics.minHitTarget, minHeight: CLMetrics.minHitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Speed"))
            .accessibilityValue(Text(player.speed.label))
        }
    }

    @ViewBuilder private var playButton: some View {
        if player.isCued && !player.isPlaying {
            Button("Play from \(CLFormat.timestamp(player.position))") {
                CLHaptics.tap()
                player.resume()
            }
            .buttonStyle(.cl(.primary, size: .small, fullWidth: false))
        } else {
            Button {
                CLHaptics.tap()
                player.togglePlay()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(CLColor.onFill)
                    .frame(width: 48, height: 48)
                    .background(CLColor.sky, in: Circle())
                    .contentShape(Circle())
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.pressable)
            .accessibilityLabel(player.isPlaying ? Text("Pause") : Text("Play"))
        }
    }
}
