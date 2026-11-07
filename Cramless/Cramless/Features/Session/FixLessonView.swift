import SwiftUI

/// What a mix-up's fix opens on, wherever it was tapped: Cap writing its lesson (Cloud AI, when it's allowed), then the lesson, then the questions.
///
/// DEBUG: `CRAMLESS_FIX_LESSON=writing` holds it on "Cap is writing it".
struct FixLessonView: View {
    enum Step: Equatable {
        case writing
        case lesson(String)
    }

    let step: Step
    /// The mix-up's name.
    let title: String
    let questions: Int
    var onStart: () -> Void
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(CLColor.ink2)
                        .frame(width: CLMetrics.minHitTarget, height: CLMetrics.minHitTarget)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(Text("Close"))
                Spacer()
            }
            .padding(.horizontal, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    CapFace(size: 56)
                    if title != ConfusionCandidate.unnamed, !title.isEmpty {
                        Text(verbatim: title)
                            .clFont(.title2)
                            .foregroundStyle(CLColor.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    switch step {
                    case .writing:
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Cap is writing it")
                                .clFont(.body)
                                .foregroundStyle(CLColor.ink2)
                        }
                        .accessibilityElement(children: .combine)
                    case .lesson(let lesson):
                        Text(verbatim: lesson)
                            .clFont(.body)
                            .foregroundStyle(CLColor.ink)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, CLSpace.gutter)
                .padding(.top, 8)
            }
            if case .lesson = step {
                VStack(spacing: 0) {
                    Rectangle().fill(CLColor.hairline).frame(height: 0.5)
                    Button(questions == 1 ? "Try it again" : "Try the questions", action: onStart)
                        .buttonStyle(.cl(.primary))
                        .padding(.horizontal, CLSpace.gutter)
                        .padding(.vertical, 12)
                }
            }
        }
    }
}
