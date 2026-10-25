import SwiftUI

/// Scene 3, "Readiness": the readiness ring climbs (the product's `ReadinessRing` and `CLMotion.fill`) while the
/// topic bars fill, then the weak spot gets its tag.
struct ReadinessScene: View {
    let active: Bool
    /// The app's clock, so the demo exam is always 23 days out on a real weekday.
    let now: Date

    @State private var ring = 0.38
    @State private var bars: [Double] = [0.08, 0.08, 0.08]
    @State private var weak = false

    static let topics: [(name: String, value: Double)] = [("Cell cycle", 0.92), ("Meiosis", 0.71), ("Genetics", 0.42)]
    static let start = 0.38
    static let end = 0.82

    var body: some View {
        GeometryReader { geo in
            let ringSize = max(96, min(148, geo.size.height - 212))
            VStack(spacing: 12) {
                Spacer(minLength: 0)
                ReadinessRing(value: ring, size: ringSize, lineWidth: ringSize * 0.095, caption: "ready")
                VStack(spacing: 2) {
                    Text("Bio 101 Midterm").clFont(.headline).foregroundStyle(CLColor.ink)
                    Text(dateLine).clFont(.subheadline).foregroundStyle(CLColor.ink2)
                }
                Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                    ForEach(Self.topics.indices, id: \.self) { i in
                        GridRow {
                            Text(Self.topics[i].name)
                                .clFont(.footnoteEmphasis)
                                .foregroundStyle(CLColor.ink)
                                .lineLimit(1)
                                .gridColumnAlignment(.leading)
                            CLBar(value: bars[i], color: CLColor.readiness(Self.topics[i].value), height: 8)
                            trailing(i)
                                .frame(width: 58, alignment: .trailing)
                        }
                    }
                }
                .padding(.top, 4)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .sceneLifecycle(active: active, reset: reset, settle: settle, script: play)
    }

    private var dateLine: String {
        let exam = Calendar.current.date(byAdding: .day, value: 23, to: now) ?? now
        return "\(exam.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) · 23 days to go"
    }

    @ViewBuilder
    private func trailing(_ i: Int) -> some View {
        if i == Self.topics.count - 1 {
            CLPill(text: "Weak", tone: .rose)
                .scaleEffect(weak ? 1 : 0.6)
                .opacity(weak ? 1 : 0)
        } else {
            Text("\(Int((Self.topics[i].value * 100).rounded()))%")
                .clFont(.number(14, .bold))
                .foregroundStyle(CLColor.ink)
        }
    }

    // MARK: Script

    private func reset() {
        ring = Self.start; bars = [0.08, 0.08, 0.08]; weak = false
    }

    private func settle() {
        ring = Self.end; bars = Self.topics.map(\.value); weak = true
    }

    private func play() async throws {
        try await nap(500)
        withAnimation(CLMotion.fill) { ring = Self.end }
        for i in Self.topics.indices {
            bars[i] = Self.topics[i].value // CLBar animates itself with CLMotion.fill
            try await nap(260)
        }
        try await nap(900)
        withAnimation(CLMotion.pop) { weak = true }
        try await nap(2600)
    }
}
