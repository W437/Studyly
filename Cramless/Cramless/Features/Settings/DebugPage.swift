#if DEBUG
import SwiftUI

/// Settings ▸ Debug (DEBUG builds only): reopen onboarding at any page without wiping data, open any harness route,
/// seed the demo world, and see this run's configuration.
struct DebugPage: View {
    @Environment(AppModel.self) private var app
    @State private var page = 1

    private static let routes: [(name: String, arg: String?)] = [
        ("today", nil), ("library", nil), ("ask", nil), ("progress", nil), ("exam", nil), ("course", nil), ("source", nil),
        ("sourcePage", nil), ("lectureNotes", nil), ("confusion", nil), ("streak", nil), ("chat", nil), ("squad", nil),
        ("session", nil), ("session", "fix"), ("session", "examEve"), ("scanner", nil), ("capture", nil),
        ("captureFlow", nil), ("paste", nil), ("importDeck", nil), ("newCourse", nil), ("newExam", nil), ("editExam", nil),
        ("logGrade", nil), ("editItem", nil), ("newItem", nil), ("explain", nil), ("makeCards", nil), ("paywall", nil),
        ("paywall", "onboarding"), ("examPass", nil), ("consent", nil), ("consent", "photos"), ("squadRedeem", "CAP-7Q4K"),
        ("record", nil), ("todayWhy", nil), ("skyList", nil), ("quests", nil), ("lastLook", nil),
    ]

    var body: some View {
        SettingsScroll(title: "Debug") {
            CLSectionHeader(title: "Onboarding")
            VStack(alignment: .leading, spacing: 12) {
                Stepper(value: $page, in: 0...(OnboardingMachine.sequence.count - 2)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Page \(page)").clFont(.bodyEmphasis).foregroundStyle(CLColor.ink)
                        Text(Self.pageName(page)).clFont(.footnote).foregroundStyle(CLColor.ink2)
                    }
                }
                Button("Open onboarding here") {
                    app.router.present(.onboarding(page: page))
                }
                .buttonStyle(.cl(.dark, size: .medium))
                Text("Your data stays. Finishing onboarding brings you back here.")
                    .clFont(.footnote).foregroundStyle(CLColor.ink2)
            }
            .clCard()

            SettingsGroup(title: "Feel") {
                NavigationLink(value: Route.settingsPage(.feelLab)) {
                    CLRow(icon: "waveform", tint: .capy, title: "Feel lab",
                          subtitle: "Every sound and haptic, on each palette")
                }
                .buttonStyle(.pressable)
            }

            SettingsGroup(title: "Harness routes", footer: "The same screens CRAMLESS_ROUTE opens (App/TestHarness.swift).") {
                ForEach(Array(Self.routes.enumerated()), id: \.offset) { _, route in
                    Button {
                        TestHarness.apply(route: route.name, arg: route.arg, app: app)
                    } label: {
                        HStack {
                            Text(route.arg.map { "\(route.name):\($0)" } ?? route.name)
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(CLColor.ink)
                            Spacer()
                            Image(systemName: "arrow.up.forward.app").foregroundStyle(CLColor.ink4)
                        }
                        .padding(.horizontal, 16)
                        .frame(minHeight: CLMetrics.minHitTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressable)
                }
            }

            SettingsGroup(title: "Demo data", footer: "The demo world only seeds an empty library.") {
                SettingsActionRow(icon: "leaf", tint: .mint, title: "Seed the demo world",
                                  subtitle: app.courses.isEmpty ? "Maya's four courses, exams and history" : "The library isn't empty") {
                    SampleData.seed(into: app)
                    app.router.toast("Demo world seeded", systemImage: "leaf.fill")
                }
                .disabled(!app.courses.isEmpty)
                SettingsActionRow(icon: "bubble.left.and.bubble.right", tint: .sky, title: "Add the worked chat",
                                  subtitle: "Mitosis vs meiosis, with a table and a quick check") {
                    if AskDemo.conversation(app: app) != nil { app.router.toast("Chat added to Ask", systemImage: "bubble.left.fill") }
                }
            }

            SettingsGroup(title: "This run") {
                Text(app.config.startupLine)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(CLColor.ink2)
                    .padding(16)
                    .textSelection(.enabled)
            }
        }
    }

    static func pageName(_ index: Int) -> String {
        let steps = OnboardingMachine.sequence
        guard steps.indices.contains(index) else { return "" }
        switch steps[index] {
        case .welcome: return "Welcome"
        case .firstSet: return "First set"
        case .firstSession: return "First session"
        case .examDate: return "Exam date"
        case .plan: return "Plan"
        case .paywall: return "Paywall"
        case .done: return "Done"
        }
    }
}
#endif
