import SwiftUI

/// The card of an imported deck that one of Cap's answers rests on. A deck has cards, not pages, so a citation to one opens
/// here: the card's place in its deck, and the card, front and back. Found again from the quote, so a card that was deleted or
/// changed since the answer says so instead of pointing nowhere.
struct DeckCardView: View {
    let sourceID: UUID
    let quote: String
    /// The citation's label ("Deck: X · card 7"): it numbers the card, which tells two cards with the same words apart.
    var label: String?

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let _ = app.revision
        Group {
            if let found = app.deckCard(quoting: quote, in: sourceID, label: label) {
                content(source: found.source, number: found.number, card: found.card)
            } else {
                ContentUnavailableView("This card isn't here anymore", systemImage: "rectangle.stack",
                                       description: Text("Its deck was deleted or changed."))
            }
        }
        .clScreenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Over the Ask tab it is a sheet of its own; pushed inside another sheet, the back button is enough.
            if case .deckCard = app.router.sheet {
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
    }

    private func content(source: Source, number: Int, card: TutorCard) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(verbatim: TutorMaterial.deckLabel(title: source.title, number: number))
                    .clFont(.footnoteEmphasis)
                    .foregroundStyle(CLColor.ink3)
                    .accessibilityAddTraits(.isHeader)
                side("Front", card.front)
                side("Back", card.back)
                if !card.note.clTrimmed.isEmpty { side("Note", card.note) }
            }
            .padding(.horizontal, CLSpace.gutter)
            .padding(.vertical, 16)
        }
        .navigationTitle(source.title)
    }

    private func side(_ title: LocalizedStringResource, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).clFont(.eyebrow).foregroundStyle(CLColor.ink3)
            Text(verbatim: text)
                .clFont(.body)
                .foregroundStyle(CLColor.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .clCard(padding: 16)
        .accessibilityElement(children: .combine)
    }
}
