import SwiftUI

/// After the exam: the grade the person got, then how it compares with what Capling projected. Saving it
/// (`AppModel.logGrade`) is what lets later projections calibrate. The field starts empty (a logged grade must be
/// the person's own number, never the projection nudged into place); a grade logged before shows for changing.
///
/// Harness: `CRAMLESS_SCENARIO=past` first moves the exam three days back; `CRAMLESS_GRADE=<percent>` logs that grade
/// on appear and shows the result.
struct LogGradeView: View {
    let examID: UUID

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var percent: Int?
    @State private var loaded = false
    @State private var saved: Saved?
    @FocusState private var fieldFocused: Bool

    /// What the result shows, fixed at the moment of saving.
    private struct Saved: Equatable {
        var projected: Double
        var got: Double
        var calibratedNow: Bool
    }

    var body: some View {
        let exam = app.exam(examID)
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if let saved {
                        result(saved, title: exam?.title ?? "the exam")
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    } else if let exam, exam.deletedAt == nil {
                        entry(exam)
                    } else {
                        Text("This exam was deleted.").clFont(.body).foregroundStyle(CLColor.ink2)
                    }
                }
                .padding(.horizontal, CLSpace.gutter)
                .padding(.vertical, 12)
                .frame(maxWidth: CLMetrics.readableWidth)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .clScreenBackground()
            .navigationTitle(saved == nil ? "Log your grade" : "Logged")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if saved == nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", role: .cancel) { dismiss() }
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(CLColor.background)
        .onAppear {
            guard !loaded, let exam else { return }
            loaded = true
            if let score = exam.resultScore { percent = Int((score * 100).rounded()) }
        }
        #if DEBUG
        .task {
            app.applyHarnessScenarioOnce(examID: examID)
            if let grade = TestHarness.once("CRAMLESS_GRADE").flatMap(Int.init), let exam = app.exam(examID) {
                percent = grade
                save(exam)
            }
        }
        #endif
    }

    private func entry(_ exam: Exam) -> some View {
        VStack(spacing: 18) {
            VStack(spacing: 4) {
                Text("How did it go?")
                    .clFont(.title2)
                    .foregroundStyle(CLColor.ink)
                Text("\(exam.title) · \(CLFormat.day(exam.date, calendar: app.calendar))")
                    .clFont(.subheadline)
                    .foregroundStyle(CLColor.ink2)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 8)

            VStack(spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    TextField("––", value: $percent, format: .number)
                        .keyboardType(.numberPad)
                        .focused($fieldFocused)
                        .font(.system(size: 64, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .fixedSize()
                        .foregroundStyle(CLColor.ink)
                        .accessibilityLabel(Text("Your grade, in percent"))
                        .onChange(of: percent) { _, value in
                            guard let value else { return }
                            let clamped = min(100, max(0, value))
                            if clamped != value { percent = clamped }
                        }
                    Text("%")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(CLColor.ink2)
                        .accessibilityHidden(true)
                }
                if let percent {
                    CLPill(text: .verbatim(GradeModel.letter(Double(percent) / 100)), tone: .neutral)
                        .accessibilityLabel(Text("Letter grade \(GradeModel.letter(Double(percent) / 100))"))
                } else {
                    Text("Type it, or slide").clFont(.footnoteEmphasis).foregroundStyle(CLColor.ink3)
                }
                Slider(value: Binding(get: { Double(percent ?? 75) }, set: { percent = Int($0.rounded()) }), in: 0...100, step: 1) {
                    Text("Your grade")
                }
                .tint(percent == nil ? CLColor.ink4 : CLColor.tangerine)
                .accessibilityValue(Text(percent.map { "\($0) percent" } ?? "Not set"))
                .padding(.horizontal, 4)
            }
            .clCard(padding: 20)

            Button("Save grade") { save(exam) }
                .buttonStyle(.cl(.primary))
                .disabled(percent == nil)

            Text("Capling compares it with what it projected, so later projections fit how you do.")
                .clFont(.footnote)
                .foregroundStyle(CLColor.ink2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func result(_ saved: Saved, title: String) -> some View {
        let lines = ExamPresentation.gradeComparison(projected: saved.projected, got: saved.got, calibratedNow: saved.calibratedNow)
        let beat = saved.got >= saved.projected - 0.005
        return VStack(spacing: 16) {
            CapView(pose: beat ? .celebrate : .study, size: 130)
                .padding(.top, 8)
            Text(CLFormat.percent(saved.got))
                .font(.system(size: 56, weight: .heavy, design: .rounded))
                .foregroundStyle(CLColor.ink)
                .accessibilityLabel(Text("You got \(CLFormat.percent(saved.got))"))
            Text(lines.headline)
                .clFont(.headline)
                .foregroundStyle(CLColor.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            GradeBars(projected: saved.projected, got: saved.got)
                .clCard(padding: 18)
            Text(lines.note)
                .clFont(.subheadline)
                .foregroundStyle(CLColor.ink2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Done") { dismiss() }
                .buttonStyle(.cl(.primary))
                .padding(.top, 4)
        }
    }

    private func save(_ exam: Exam) {
        guard let percent else { return }
        fieldFocused = false
        let got = Double(min(100, max(0, percent))) / 100
        let projected = app.projectedGrade(for: exam).percent
        app.logGrade(examID: exam.id, score: got)
        let calibratedNow = app.calibratingExamCount >= 2
        CLHaptics.success()
        withAnimation(CLMotion.settle) {
            saved = Saved(projected: projected, got: got, calibratedNow: calibratedNow)
        }
    }
}
