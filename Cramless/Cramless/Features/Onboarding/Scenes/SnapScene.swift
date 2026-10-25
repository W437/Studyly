import SwiftUI

/// Scene 1, "Snap a page": the scanner's brackets lock onto a textbook page, a scan sweeps down it, the key
/// lines get highlighted, and three cards pop out (a flashcard, a multiple choice question, an own-words question),
/// each with its page chip.
struct SnapScene: View {
    let active: Bool

    @Environment(\.colorScheme) private var scheme
    @State private var locked = false
    @State private var scanning = false
    @State private var scan: CGFloat = 0
    @State private var marked = 0
    @State private var cards = 0

    /// What the page made: a flashcard first (it is what people come for), then two other kinds, each with its own icon.
    static let questions: [(kind: ItemKind, text: String)] = [
        (.flashcard, "What does mitosis make?"), (.mcq, "Which phase comes first?"), (.recall, "Why do cells divide?"),
    ]
    /// Line widths above and below the row of cells; the highlighter marks three of them, in reading order.
    private static let topLines: [CGFloat] = [0.94, 0.86, 0.9]
    private static let bottomLines: [CGFloat] = [0.88, 0.7, 0.92, 0.64, 0.8]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack(alignment: .top) {
                paper(width: w * 0.64, height: h * 0.6)
                    .overlay { brackets }
                    .rotationEffect(.degrees(-2))
                    .padding(.top, h * 0.075)
                // The cards stack over the foot of the page and hide the lower brackets, as in the scanner.
                VStack(spacing: 5) {
                    ForEach(Self.questions.indices, id: \.self) { i in
                        card(i).frame(width: w * 0.84)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 10)
            }
            .frame(width: w, height: h)
        }
        .sceneLifecycle(active: active, reset: reset, settle: settle, script: play)
    }

    // MARK: Parts

    private func paper(width: CGFloat, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            PaperLine(fraction: 0.62, height: 11, color: PaperInk.heading)
                .padding(.bottom, 4)
            ForEach(Self.topLines.indices, id: \.self) { i in
                PaperLine(fraction: Self.topLines[i], marked: i == 1 && marked >= 1)
            }
            HStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { _ in
                    Circle()
                        .fill(PaperInk.cellFill)
                        .overlay(Circle().strokeBorder(PaperInk.cellStroke, lineWidth: 2))
                        .aspectRatio(1, contentMode: .fit)
                }
            }
            .padding(.vertical, 4)
            ForEach(Self.bottomLines.indices, id: \.self) { i in
                PaperLine(fraction: Self.bottomLines[i], marked: (i == 2 && marked >= 2) || (i == 3 && marked >= 3))
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 16)
        .frame(width: width, height: height, alignment: .top)
        .background(CLColor.paper)
        .overlay(alignment: .top) {
            LinearGradient(colors: [CLColor.sky.opacity(0), CLColor.sky.opacity(0.45)], startPoint: .top, endPoint: .bottom)
                .frame(height: 40)
                .overlay(alignment: .bottom) { Rectangle().fill(CLColor.sky).frame(height: 2) }
                .offset(y: -40 + scan * (height + 40))
                .opacity(scanning ? 1 : 0)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: CLColor.night.opacity(0.16), radius: 14, y: 10)
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(CLColor.night.opacity(0.08), lineWidth: 0.5))
    }

    private var brackets: some View {
        let out: CGFloat = locked ? 10 : 24
        return ZStack {
            corner(.topLeading).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .offset(x: -out, y: -out)
            corner(.topTrailing).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .offset(x: out, y: -out)
            // The lower pair tucks away behind the questions as they land.
            Group {
                corner(.bottomLeading).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .offset(x: -out, y: out)
                corner(.bottomTrailing).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .offset(x: out, y: out)
            }
            .opacity(cards > 0 ? 0 : 1)
        }
        .opacity(locked ? 1 : 0)
    }

    private func corner(_ c: BracketCorner.Corner) -> some View {
        BracketCorner(corner: c)
            .stroke(CLColor.skyInk, style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
            .frame(width: 26, height: 26)
    }

    private func card(_ i: Int) -> some View {
        let on = cards > i
        return HStack(spacing: 8) {
            Image(systemName: Self.questions[i].kind.studySymbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CLColor.ink3)
                .frame(width: 16)
            Text(Self.questions[i].text)
                .clFont(.footnoteEmphasis)
                .foregroundStyle(CLColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 4)
            CLSourceChip(label: "p. 87")
        }
        .padding(.leading, 13)
        .padding(.trailing, 8)
        .padding(.vertical, 6)
        .background(scheme == .dark ? CLColor.surface2 : CLColor.surface,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(CLColor.hairline, lineWidth: 0.5))
        .shadow(color: CLColor.night.opacity(scheme == .dark ? 0.4 : 0.16), radius: 12, y: 8)
        .opacity(on ? 1 : 0)
        .scaleEffect(on ? 1 : 0.9)
        .offset(y: on ? 0 : 30)
    }

    // MARK: Script

    private func reset() {
        locked = false; scanning = false; scan = 0; marked = 0; cards = 0
    }

    private func settle() {
        locked = true; scanning = false; scan = 1; marked = 3; cards = 3
    }

    private func play() async throws {
        try await nap(450)
        withAnimation(CLMotion.calm) { locked = true }
        try await nap(650)
        withAnimation(CLMotion.fade) { scanning = true }
        withAnimation(CLMotion.fill) { scan = 1 }
        try await nap(1150)
        withAnimation(CLMotion.fade) { scanning = false }
        for i in 1...3 {
            withAnimation(CLMotion.calm) { marked = i }
            try await nap(240)
        }
        try await nap(250)
        for i in 1...3 {
            withAnimation(CLMotion.pop) { cards = i }
            try await nap(170)
        }
        try await nap(2400)
    }
}
