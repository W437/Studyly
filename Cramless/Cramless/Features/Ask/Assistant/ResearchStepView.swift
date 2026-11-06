import SwiftUI

/// Cap researching on the web, on trusted study sites only, shown as it happens:
///  1. the search types itself into a search bar, in plain words;
///  2. the pages it found pop up as the sites' tiles, one after another;
///  3. a ring of light passes over the tiles while it reads;
///  4. the summary writes itself, with the key words in bold;
///  5. the pages the summary rests on appear as links to open, so every claim can be followed.
/// Then the student saves it as a note, or doesn't. (Pro only; never for an account under 18.)
struct ResearchStepView: View {
    let step: AssistantStep
    let result: ResearchResult
    let actions: AssistantStepActions
    var animated = false
    /// The save button's words.
    var saveTitle: String

    @Environment(\.clReduceMotion) private var reduceMotion
    @State private var tilesShown: Int
    @State private var expanded = false

    init(step: AssistantStep, result: ResearchResult, actions: AssistantStepActions, animated: Bool, saveTitle: String? = nil) {
        self.step = step
        self.result = result
        self.actions = actions
        self.animated = animated
        self.saveTitle = saveTitle ?? String(localized: "Save as note")
        _tilesShown = State(initialValue: animated ? 0 : min(8, result.sources.count))
    }

    private var working: Bool { step.status == .working }
    private var tiles: [WebSource] { Array(result.sources.prefix(8)) }

    var body: some View {
        StepCard(step: step, actions: actions, addTitle: saveTitle, subtitle: "From trusted study sites") {
            VStack(alignment: .leading, spacing: 12) {
                if working || !result.queries.isEmpty { searchBar }
                if !result.sources.isEmpty { sources }
                if !result.text.isEmpty { summary }
                if !result.cited.isEmpty { cited }
            }
            .animation(animated ? CLMotion.settle : nil, value: result.cited.count)
        }
        .task(id: tiles.count) {
            guard animated else { return }
            while tilesShown < min(tiles.count, 8) {
                try? await nap(95)
                if Task.isCancelled { return }
                tilesShown += 1
                if tilesShown <= 6 { CLFeel.play(.cardOut(tilesShown - 1)) }
            }
        }
        .onChange(of: step.status) { old, new in
            if animated, new == .applied, old != .applied { CLFeel.play(.saved) }
        }
    }

    // MARK: 1. The search

    private var searchBar: some View {
        let searching = working && (result.phase == .starting || result.phase == .searching)
        return HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(CLColor.skyInk)
                .symbolEffect(.pulse, isActive: searching && !reduceMotion)
            Group {
                if let query = result.queries.last {
                    if animated && working { TypewriterText(text: query) } else { Text(verbatim: query) }
                } else {
                    Text("Searching…").foregroundStyle(CLColor.ink3)
                }
            }
            .clFont(.subheadline)
            .foregroundStyle(CLColor.ink)
            .lineLimit(1)
            Spacer(minLength: 0)
            if searching { WorkingDots(tint: CLColor.skyInk) }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .background(CLColor.surface2, in: Capsule())
        .overlay(Capsule().strokeBorder(searching ? CLColor.sky.opacity(0.7) : CLColor.hairline, lineWidth: searching ? 1.5 : 0.5))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Search: \(result.queries.last ?? "starting")"))
    }

    // MARK: 2 and 3. The pages found, and read

    private var sources: some View {
        let reading = working && (result.phase == .reading || result.phase == .writing)
        return VStack(alignment: .leading, spacing: 8) {
            Text(working ? "Found \(CLFormat.count(result.sources.count, "page"))" : "Read \(CLFormat.count(result.sources.count, "page"))")
                .clFont(.caption)
                .foregroundStyle(CLColor.ink3)
            TimelineView(.animation(minimumInterval: 1 / 15, paused: !reading || reduceMotion)) { timeline in
                let active = reading && !reduceMotion && !tiles.isEmpty
                    ? Int(timeline.date.timeIntervalSinceReferenceDate * 3.2) % tiles.count : -1
                CLFlow(spacing: 10, lineSpacing: 10) {
                    ForEach(Array(tiles.enumerated()), id: \.offset) { i, source in
                        if i < tilesShown {
                            VStack(spacing: 4) {
                                WebSourceTile(domain: source.domain, size: 42)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .strokeBorder(CLColor.sky, lineWidth: 2.5)
                                            .opacity(active == i ? 1 : 0)
                                            .scaleEffect(active == i ? 1.12 : 1)
                                    }
                                    .shadow(color: active == i ? CLColor.sky.opacity(0.8) : .clear, radius: 8)
                                Text(verbatim: WebSourceBrand.brand(for: source.domain).name)
                                    .clFont(.caption)
                                    .foregroundStyle(CLColor.ink3)
                                    .lineLimit(1)
                                    .frame(width: 58)
                            }
                            .transition(.scale(scale: 0.3).combined(with: .opacity))
                            .animation(CLMotion.snap, value: active)
                        }
                    }
                    if result.sources.count > 8 {
                        Text("+\(result.sources.count - 8)").clFont(.footnoteEmphasis).foregroundStyle(CLColor.ink3)
                            .frame(width: 42, height: 42)
                    }
                }
            }
            .animation(CLMotion.pop, value: tilesShown)
        }
    }

    // MARK: 4. The summary

    private var summary: some View {
        VStack(alignment: .leading, spacing: 8) {
            CapMarkdownView(text: result.text, streaming: working && result.phase == .writing)
                .frame(maxHeight: expanded || working ? nil : 190, alignment: .top)
                .clipped()
                .mask {
                    if expanded || working || result.text.count < 520 {
                        Rectangle()
                    } else {
                        LinearGradient(stops: [.init(color: .black, location: 0.72), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom)
                    }
                }
            if !working, result.text.count >= 520 {
                Button(expanded ? "Show less" : "Read it all") { withAnimation(CLMotion.settle) { expanded.toggle() } }
                    .clFont(.footnoteEmphasis)
                    .foregroundStyle(CLColor.skyInk)
                    .buttonStyle(.plain)
                    .frame(minHeight: CLMetrics.minHitTarget, alignment: .leading)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CLColor.surface2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: 5. Where it comes from

    private var cited: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("It rests on").clFont(.caption).foregroundStyle(CLColor.ink3)
            ForEach(Array(result.cited.prefix(4).enumerated()), id: \.element.url) { _, source in
                WebSourceChip(source: source, cited: true)
                    .transition(.scale(scale: 0.8, anchor: .leading).combined(with: .opacity))
            }
        }
    }
}
