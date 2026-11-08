import SwiftUI

/// The first screen: Cap on the shore of a night sky with a small constellation to light, the wordmark, the promise, and two ways in.
/// Touching a star (or waiting while Cap does) lights Cap's cap in the sky, which says the app's idea before a word is read: a
/// memory is a star, and a little every day keeps it lit. Nothing waits for the gesture: the buttons are there from the start.
struct WelcomeView: View {
    @Environment(OnboardingCoordinator.self) private var onboarding
    @Environment(\.clReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase
    @State private var arrived = false
    @State private var stage = WelcomeStage()

    /// The welcome is what the person is looking at: not covered by the first set (a navigation push keeps it alive under the steps),
    /// not behind the "I already have an account" sheet, and the app is in the foreground. Cap says and lights nothing otherwise, and
    /// no note plays over another screen.
    private var isFront: Bool {
        onboarding.step == .welcome && !onboarding.showsWelcomeBack && scenePhase == .active
    }

    /// The colour under the lake, so the words below the sky stand on the same ground.
    static let floor = Color(hex: 0x080E22)

    var body: some View {
        GeometryReader { geo in
            let compact = typeSize.isAccessibilitySize
            let top = geo.safeAreaInsets.top
            let screen = geo.size.height + top + geo.safeAreaInsets.bottom
            // Most of the screen's height goes to the sky on a tall phone (a bit over half); a short one has little to spare, so it gets
            // what the words below leave (about 250 points) when that is more.
            let small = screen < 740
            let band = compact ? 230 : max(min(520, max(330, screen * 0.52)), min(screen - top - geo.safeAreaInsets.bottom - 250, 400))
            let geometry = HeroWorldGeometry(width: geo.size.width, height: top + band, topInset: top, compact: compact)
            ScrollView {
                VStack(spacing: 0) {
                    WelcomeWorld(stage: stage, geometry: geometry, capSize: compact ? 110 : min(214, max(140, geo.size.width * (small ? 0.42 : 0.52))), isFront: isFront)
                        .frame(height: geometry.height)
                        // Where the lake ends, the page's floor begins.
                        .overlay(alignment: .bottom) {
                            LinearGradient(colors: [Self.floor.opacity(0), Self.floor], startPoint: .top, endPoint: .bottom)
                                .frame(height: 26)
                                .allowsHitTesting(false)
                        }
                        .opacity(arrived ? 1 : 0)
                    words
                }
                .frame(minHeight: screen, alignment: .top)
            }
            .scrollBounceBehavior(.basedOnSize)
            .ignoresSafeArea(edges: .top)
        }
        .background(Self.floor.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .task {
            guard !arrived else { return }
            if reduceMotion { arrived = true } else { withAnimation(CLMotion.settle.delay(0.1)) { arrived = true } }
        }
        .task(id: isFront) { if isFront { await stage.run() } }
        .task {
            // The first sound of a launch renders its samples and starts the audio engine, and the first haptic starts its own: do it here, while
            // nothing but a fade is on screen, and not at the first touch. (A debug build held the main thread 163 ms for the first note.)
            try? await Task.sleep(for: .milliseconds(250))
            await CLFeel.prepare(cues: WelcomeStage.cues)
        }
    }

    private var words: some View {
        let lit = stage.celebrated
        return VStack(alignment: .leading, spacing: 0) {
            CaplingWordmark(size: 54, color: .white, starLit: lit)
                .accessibilityAddTraits(.isHeader)
            Text("A little every day.\nReady on exam day.")
                .clFont(.title3)
                .foregroundStyle(Color.white.opacity(lit ? 0.96 : 0.82))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
                .animation(CLMotion.fade, value: lit)
            Button("Get started") {
                CLHaptics.tap()
                onboarding.advance()
            }
            .buttonStyle(.cl(.primary))
            // Once, when the cap is lit: a small breath, as if it were pleased.
            .keyframeAnimator(initialValue: 1.0, trigger: lit) { content, scale in content.scaleEffect(scale) } keyframes: { _ in
                SpringKeyframe(1.04, duration: 0.22)
                SpringKeyframe(1.0, duration: 0.4)
            }
            .padding(.top, 22)
            Button("I already have an account") { onboarding.showsWelcomeBack = true }
                .buttonStyle(.cl(.ghost))
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 6)
        .padding(.bottom, 12)
        .opacity(arrived ? 1 : 0)
        .offset(y: arrived || reduceMotion ? 0 : 14)
        .animation(CLMotion.settle.delay(0.35), value: arrived)
    }
}
