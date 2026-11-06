import SwiftUI

/// How you remember, in the sky's own terms: the reviews coming due and the brightest topics. Counts only: each exam's readiness is the
/// one percentage. It heads the sky's list, and opens as a fitted sheet from the sky itself.
struct SkyMemoryPanel: View {
    let scene: SkyScene
    let due: [DueForecastDay]
    let calendar: Calendar

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                CLEyebrow(text: "Reviews due, next 7 days")
                    .padding(.bottom, 6)
                    .accessibilityAddTraits(.isHeader)
                DueForecastChart(days: due, calendar: calendar)
                Text("Questions come back right before you'd forget them.")
                    .clFont(.footnote)
                    .foregroundStyle(CLColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }
            .clCard()
            let brightest = scene.brightest(count: 3)
            if !brightest.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    CLEyebrow(text: "Brightest").accessibilityAddTraits(.isHeader)
                    ForEach(brightest) { topic in
                        HStack(spacing: 12) {
                            if let glyph = scene.glyph(of: topic.index) { SkyGlyphView(glyph: glyph, size: 40) }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: topic.name).clFont(.subheadlineEmphasis).foregroundStyle(CLColor.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(verbatim: SkyCopy.detail(topic.index, in: scene)).clFont(.footnote).foregroundStyle(CLColor.ink2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .clCard()
            }
        }
    }
}

/// The panel as a sheet, over the sky.
struct SkyMemorySheet: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        TodayFittedSheet {
            SkyMemoryPanel(scene: app.skyScene(aspect: 1), due: app.dueForecast(days: 7), calendar: app.calendar)
                .padding(.horizontal, CLSpace.gutter)
                .padding(.top, 24)
                .padding(.bottom, 16)
        }
    }
}
