import SwiftUI

/// "Your questions cover 17% of your material." with the way to add questions for the rest: under the exam's ring, and at the top
/// of a source in the Library. Amber (the app's sun) when the questions cover less than half, and never an alarm: a plain
/// sentence, the source that holds most of what is left, and one button.
struct CoverageNoteCard: View {
    let sentence: String
    /// The source that holds most of what is left: "Palsgraf: 18%".
    var detail: String? = nil
    /// Less than half is covered.
    var isThin = false
    var offersMore = true
    var centered = true
    var onAdd: () -> Void

    var body: some View {
        VStack(alignment: centered ? .center : .leading, spacing: 8) {
            Text(sentence)
                .clFont(.subheadlineEmphasis)
                .foregroundStyle(isThin ? CLColor.sunInk : CLColor.ink)
                .multilineTextAlignment(centered ? .center : .leading)
                .fixedSize(horizontal: false, vertical: true)
            if let detail {
                Text(detail)
                    .clFont(.footnote)
                    .foregroundStyle(isThin ? CLColor.sunInk : CLColor.ink2)
                    .multilineTextAlignment(centered ? .center : .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if offersMore {
                Button {
                    CLHaptics.tap()
                    onAdd()
                } label: {
                    Text("Add questions for the rest")
                }
                .buttonStyle(.cl(.soft, size: .medium, fullWidth: false))
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
        .background(isThin ? CLColor.sunSoft : CLColor.surface2, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}
