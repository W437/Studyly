import SwiftUI

/// Your memory sky, full screen: every star an item you've studied, every constellation a topic. Tap a constellation
/// for how it's doing and to practice it; "Sky as a list" is the same thing for VoiceOver, for large text, and for
/// anyone who'd rather read it.
///
/// Opened from "Why these?" ("Study something else", the route `skyList`), the page is a list titled "Study something else" that
/// starts with the courses and their Practice buttons, with the sky's summary under them; the sky is a tap away.
///
/// DEBUG hooks, read once (`SkyDebug`): `CRAMLESS_SKY=still|relight|flare|age:<days>|lapse:<days>|focus:<n>|tour|list|fill:<n>`,
/// comma-separated; the route is `CRAMLESS_ROUTE=sky`.
struct SkyScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.clReduceMotion) private var reduceMotion
    @Environment(\.skyTheme) private var skyTheme

    @State private var scene: SkyScene?
    @State private var sceneID = 0
    @State private var focus: Int?
    @State private var asList: Bool?
    /// Opened to pick something else to study: the list leads with the courses, under that title.
    private let choosing: Bool
    @State private var relight: SkyRelight = .none
    @State private var size = CGSize.zero
    #if DEBUG
    @State private var debug = SkyDebug.read()
    @State private var date: Date?
    #endif

    private struct ReloadKey: Equatable {
        var revision: Int
        var aspect: Int
    }

    private var listMode: Bool { asList ?? typeSize.isAccessibilitySize }

    /// `startsAsList`: open as the list that leads with the courses (Today's "Study something else"), with the sky a tap away.
    init(startsAsList: Bool = false) {
        _asList = State(initialValue: startsAsList ? true : nil)
        choosing = startsAsList
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if listMode {
                    CLColor.background.ignoresSafeArea()
                    if let scene {
                        SkyListView(scene: scene, due: app.dueForecast(days: 7), calendar: app.calendar, coursesFirst: choosing,
                                    onRelight: start, onOpenCourse: openCourse)
                    }
                } else {
                    sky(geo)
                }
            }
            .onChange(of: geo.size, initial: true) { _, new in size = new }
        }
        .navigationTitle(listMode && choosing ? Text("Study something else") : Text("Memory sky"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(listMode ? .automatic : .hidden, for: .tabBar)
        .toolbarBackground(listMode ? .automatic : .hidden, for: .navigationBar)
        .toolbarColorScheme(listMode ? nil : .dark, for: .navigationBar)
        .preferredColorScheme(listMode ? nil : .dark)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation(CLMotion.settle) { asList = !listMode; focus = nil }
                } label: {
                    Image(systemName: listMode ? "sparkles" : "list.bullet")
                }
                .accessibilityLabel(listMode ? Text("Show the sky") : Text("Sky as a list"))
            }
        }
        .task(id: ReloadKey(revision: app.revision, aspect: Int((size.height / max(size.width, 1)) * 20))) { await reload() }
        #if DEBUG
        .task { await runHooks() }
        #endif
    }

    // MARK: The sky

    @ViewBuilder
    private func sky(_ geo: GeometryProxy) -> some View {
        // Room for the pill and "How you remember" under the navigation bar.
        let top = geo.safeAreaInsets.top + 98
        let bottom = geo.safeAreaInsets.bottom + (focus == nil ? 64 : 262)
        ZStack {
            if let scene {
                MemorySkyView(scene: scene, sceneID: sceneID, focus: $focus, relight: relight, interactive: true,
                              animates: animates, insetTop: top, insetBottom: bottom, safeArea: geo.safeAreaInsets, onRelight: relightConstellation,
                              onPlayed: { relight = .none })
                    .ignoresSafeArea()
                if scene.isEmpty {
                    SkyEmpty().padding(.horizontal, CLSpace.gutter)
                } else {
                    VStack(spacing: 0) {
                        SkyHeader(scene: scene).padding(.top, 8)
                        Button {
                            CLHaptics.tap()
                            app.router.present(.skyMemory)
                        } label: {
                            HStack(spacing: 3) {
                                Text("How you remember")
                                Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
                            }
                            .clFont(.footnoteEmphasis)
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.horizontal, 14)
                            .frame(minHeight: 36)
                            .glassEffect(.regular.interactive(), in: .capsule)
                            .environment(\.colorScheme, .dark)
                            .frame(minHeight: CLMetrics.minHitTarget)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Spacer(minLength: 0)
                        if let i = focus, scene.layout.constellations.indices.contains(i) {
                            SkyFocusCard(scene: scene, index: i, onRelight: { relightConstellation(i) },
                                         onTeach: teachAction(scene.layout.constellations[i]),
                                         onOpenCourse: { openCourse(scene.layout.constellations[i].courseID) },
                                         onClose: { withAnimation(CLMotion.settle) { focus = nil } })
                                .padding(.horizontal, CLSpace.gutter)
                                .padding(.bottom, 12)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        } else {
                            SkyLegend().padding(.bottom, 14)
                                .transition(.opacity)
                        }
                    }
                    .animation(CLMotion.settle, value: focus)
                }
            } else {
                Color.clear
            }
        }
        .background(skyTheme.palette.top.ignoresSafeArea())
    }

    private var animates: Bool {
        #if DEBUG
        return !debug.still
        #else
        return true
        #endif
    }

    // MARK: Loading

    private func reload() async {
        guard size.width > 1 else { return }
        #if DEBUG
        if let n = debug.fill, scene == nil { app.debugFillSky(n) }
        #endif
        var next = app.skyScene(aspect: Double(size.height / size.width), at: dateOverride)
        #if DEBUG
        if let demo = debug.demoRelight, scene == nil {
            let (changed, relit) = SkyDemo.relit(next, count: demo)
            next = changed
            relight = relit
        }
        #endif
        if relight.isEmpty { relight = app.takeSkyRelight() }
        scene = next
        sceneID &+= 1
        if let i = focus, !next.layout.constellations.indices.contains(i) { focus = nil }
    }

    private var dateOverride: Date? {
        #if DEBUG
        return date
        #else
        return nil
        #endif
    }

    // MARK: Actions

    /// Teach Cap, for a topic's constellation with enough stars to explain (a course's loose stars have no topic to teach).
    private func teachAction(_ constellation: SkyLayout.Constellation) -> (() -> Void)? {
        guard let topicID = constellation.topicID, constellation.stars.count >= TeachPlanner.minIdeas else { return nil }
        return {
            CLHaptics.tap()
            app.router.present(.teach(topicID: topicID))
        }
    }

    private func relightConstellation(_ index: Int) {
        guard let scene, scene.layout.constellations.indices.contains(index) else { return }
        start(scene.layout.constellations[index])
    }

    private func start(_ constellation: SkyLayout.Constellation) {
        guard let scene else { return }
        CLHaptics.tap()
        app.router.present(.session(app.relightRequest(constellation, in: scene)))
    }

    private func openCourse(_ id: UUID) {
        app.router.push(.course(id))
    }

    #if DEBUG
    /// The launch hooks: a still frame, a demo relight, the flare on a loop, the sky some days on, a time-lapse of
    /// forgetting, a focused constellation, the list.
    private func runHooks() async {
        if debug.list { asList = true }
        if debug.memory {
            try? await nap(700)
            app.router.present(.skyMemory)
        }
        if let age = debug.age { date = app.now.addingTimeInterval(age * 86_400) }
        if let n = debug.focus {
            for _ in 0..<40 where scene == nil { try? await nap(100) }
            if let scene, scene.layout.constellations.indices.contains(n) { focus = n }
        }
        if debug.tour {
            for _ in 0..<40 where scene == nil { try? await nap(100) }
            try? await nap(1500)
            guard let current = scene else { return }
            // The three constellations with the most dim stars, one after another, then back to the whole sky.
            let order = current.layout.constellations.indices.sorted {
                current.light.dimCount(current.layout.constellations[$0]) > current.light.dimCount(current.layout.constellations[$1])
            }.prefix(3)
            for i in order {
                focus = i
                try? await nap(2800)
            }
            focus = nil
        }
        if let days = debug.lapse {
            for _ in 0..<40 where scene == nil { try? await nap(100) }
            try? await nap(900)
            let steps = 96
            for step in 0...steps {
                date = app.now.addingTimeInterval(days * 86_400 * Double(step) / Double(steps))
                await reload()
                try? await nap(90)
            }
        }
        if debug.flare {
            for _ in 0..<40 where scene == nil { try? await nap(100) }
            var turn = 0
            while !Task.isCancelled, let current = scene {
                try? await nap(1800)
                // Lit again and again: the stars of the focused constellation, else a few near the middle of the sky.
                let pool: [Int]
                if let f = focus, current.layout.constellations.indices.contains(f) {
                    pool = current.layout.constellations[f].stars.filter { !current.light.hollow[$0] }
                } else {
                    pool = Array(current.layout.stars.indices.sorted {
                        let a = current.layout.stars[$0].point, b = current.layout.stars[$1].point
                        let cx = current.layout.width / 2, cy = current.layout.height / 2
                        return hypot(a.x - cx, a.y - cy) < hypot(b.x - cx, b.y - cy)
                    }.prefix(3))
                }
                guard !pool.isEmpty else { return }
                let id = current.layout.stars[pool[(turn * 3) % pool.count]].id
                relight = SkyRelight(relit: [id], lit: [], saved: [id], from: [id: 0.1])
                sceneID &+= 1
                turn += 1
            }
        }
    }
    #endif
}

// MARK: - Pieces

/// "142 stars · 31 dim · 15 not yet lit", in a glass pill under the navigation bar.
private struct SkyHeader: View {
    let scene: SkyScene

    var body: some View {
        let parts = [String(localized: SkyCopy.stars(scene.starCount)), String(localized: SkyCopy.dim(scene.dimCount)),
                     scene.hollowCount > 0 ? String(localized: SkyCopy.notYetLit(scene.hollowCount)) : nil].compactMap { $0 }
        Text(parts.joined(separator: " · "))
            .clFont(.footnoteEmphasis)
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 16)
            .frame(minHeight: CLMetrics.minHitTarget)
            .glassEffect(.regular, in: .capsule)
            .environment(\.colorScheme, .dark)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(SkyCopy.summary(scene))
    }
}

/// What a bright star, a dim one and a hollow ring mean, each with its own shape as well as its brightness.
private struct SkyLegend: View {
    var body: some View {
        HStack(spacing: 18) {
            item(Circle().fill(.white).frame(width: 9, height: 9), "Bright")
            item(Circle().fill(.white.opacity(0.35)).frame(width: 6, height: 6), "Dim")
            item(Circle().strokeBorder(.white.opacity(0.7), lineWidth: 1).frame(width: 9, height: 9), "Not yet lit")
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 36)
        .glassEffect(.regular, in: .capsule)
        .environment(\.colorScheme, .dark)
        .accessibilityHidden(true)
    }

    private func item<S: View>(_ mark: S, _ label: LocalizedStringResource) -> some View {
        HStack(spacing: 6) {
            mark.frame(width: 12, height: 12)
            Text(label).clFont(.caption).foregroundStyle(.white.opacity(0.85))
        }
    }
}

/// The three kinds of star in a constellation, as a bar: bright, dim, not yet lit.
private struct SkyMeter: View {
    let bright: Int
    let dim: Int
    let hollow: Int

    var body: some View {
        GeometryReader { geo in
            let total = max(1, bright + dim + hollow)
            let w = geo.size.width - 4
            HStack(spacing: 2) {
                if bright > 0 { Capsule().fill(.white).frame(width: w * Double(bright) / Double(total)) }
                if dim > 0 { Capsule().fill(.white.opacity(0.32)).frame(width: w * Double(dim) / Double(total)) }
                if hollow > 0 {
                    Capsule().strokeBorder(.white.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                        .frame(width: w * Double(hollow) / Double(total))
                }
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}

/// A tapped constellation: its name, how it's doing, and the way to practice it.
private struct SkyFocusCard: View {
    let scene: SkyScene
    let index: Int
    var onRelight: () -> Void
    /// Teach Cap: a topic with enough questions to explain. Nil: not offered.
    var onTeach: (() -> Void)? = nil
    var onOpenCourse: () -> Void
    var onClose: () -> Void

    var body: some View {
        let c = scene.layout.constellations[index]
        let light = scene.light
        let bright = light.brightCount(c), dim = light.dimCount(c)
        let hollow = c.stars.filter { light.hollow[$0] }.count
        let minutes = scene.minutesToRelight(index)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: c.name).clFont(.title3).foregroundStyle(.white)
                        .accessibilityAddTraits(.isHeader)
                    if !scene.courseName(of: c).isEmpty, scene.courseName(of: c) != c.name {
                        Text(verbatim: scene.courseName(of: c)).clFont(.footnote).foregroundStyle(.white.opacity(0.7))
                    }
                }
                Spacer(minLength: 8)
                SkyCloseButton(action: onClose)
            }
            SkyMeter(bright: bright, dim: dim, hollow: hollow)
            Text(verbatim: SkyCopy.detail(index, in: scene))
                .clFont(.footnote).foregroundStyle(.white.opacity(0.85))
            Button(action: onRelight) {
                Text(SkyCopy.practice(c.name, minutes: minutes))
                    .lineLimit(2).multilineTextAlignment(.center)
            }
            .buttonStyle(.cl(.primary))
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { secondary }
                VStack(spacing: 8) { secondary }
            }
        }
        .padding(18)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: CLRadius.card, style: .continuous))
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var secondary: some View {
        if let onTeach {
            Button(action: onTeach) { Text(TeachCopy.title).lineLimit(1) }
                .buttonStyle(.cl(.white, size: .medium))
        }
        Button(action: onOpenCourse) { Text("Open course").lineLimit(1) }
            .buttonStyle(.cl(.white, size: .medium))
    }
}

/// The focus card's close button: a quiet glass circle, 44 pt to tap.
private struct SkyCloseButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 32, height: 32)
                .background(.white.opacity(0.14), in: Circle())
                .frame(width: CLMetrics.minHitTarget, height: CLMetrics.minHitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Close"))
    }
}

/// Nothing studied yet: Cap at his telescope, and a way to add material.
private struct SkyEmpty: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: 14) {
            CapView(pose: .stargaze, size: 190, idle: .breathe)
            Text("Your sky is waiting")
                .clFont(.title2).foregroundStyle(.white).multilineTextAlignment(.center)
            Text("Add class material, and every question you study becomes a star.")
                .clFont(.callout).foregroundStyle(.white.opacity(0.8)).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Add material") { app.router.present(.capture(courseID: nil)) }
                .buttonStyle(.cl(.primary, fullWidth: false))
                .padding(.top, 6)
        }
        .frame(maxWidth: 420)
    }
}

// MARK: - As a list

/// The sky as rows: each course, and under it each constellation with how many of its stars are bright and a way to
/// practice it. What VoiceOver gets by default, and anyone at large text sizes (where each row stacks).
///
/// `coursesFirst` ("Study something else"): the courses lead, so the first Practice is on the first screen (above the tab bar on an SE),
/// and the sky's summary and its panel follow them.
struct SkyListView: View {
    let scene: SkyScene
    /// The panel with the summary: what's coming up to review.
    let due: [DueForecastDay]
    let calendar: Calendar
    var coursesFirst = false
    var onRelight: (SkyLayout.Constellation) -> Void
    var onOpenCourse: (UUID) -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    private struct Group: Identifiable {
        var id: UUID
        var name: String
        var color: CourseColor
        var constellations: [(index: Int, c: SkyLayout.Constellation)]
    }

    private var groups: [Group] {
        var order: [UUID] = []
        var byCourse: [UUID: [(Int, SkyLayout.Constellation)]] = [:]
        for (i, c) in scene.layout.constellations.enumerated() {
            if byCourse[c.courseID] == nil { order.append(c.courseID) }
            byCourse[c.courseID, default: []].append((i, c))
        }
        return order.map { id in
            let list = byCourse[id] ?? []
            return Group(id: id, name: scene.courseNames[id] ?? "", color: scene.courseColors[id] ?? .sky,
                         constellations: list.map { (index: $0.0, c: $0.1) })
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if coursesFirst {
                    courses
                    summary.padding(.top, 30)
                } else {
                    summary.padding(.top, 8)
                    courses
                }
            }
            .padding(.horizontal, CLSpace.gutter)
            .padding(.bottom, 40)
        }
    }

    /// The sky in a sentence, and what's coming up to review.
    private var summary: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(SkyCopy.summary(scene))
                .clFont(.callout).foregroundStyle(CLColor.ink2)
            if !scene.isEmpty { SkyMemoryPanel(scene: scene, due: due, calendar: calendar) }
        }
    }

    /// Each course, and its topics with Practice.
    @ViewBuilder private var courses: some View {
        ForEach(Array(groups.enumerated()), id: \.element.id) { position, group in
            header(group, first: position == 0)
            CLList {
                ForEach(group.constellations, id: \.c.id) { entry in
                    SkyListRow(scene: scene, index: entry.index, constellation: entry.c, color: group.color, onRelight: onRelight)
                }
            }
        }
    }

    /// The course's name, with "Open course" beside it (below it at large text sizes). The first one at the head of the page sits
    /// close under the title.
    private func header(_ group: Group, first: Bool = false) -> some View {
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
        return layout {
            Text(verbatim: group.name).clFont(.title3).foregroundStyle(CLColor.ink)
                .accessibilityAddTraits(.isHeader)
            if !stacked { Spacer() }
            Button("Open course") { onOpenCourse(group.id) }
                .clFont(.subheadlineEmphasis)
                .foregroundStyle(CLColor.skyInk)
                .buttonStyle(.plain)
                .frame(minHeight: CLMetrics.minHitTarget, alignment: .leading)
        }
        .padding(.top, coursesFirst && first ? 4 : 26)
        .padding(.bottom, 10)
        .padding(.horizontal, 2)
    }
}

/// One constellation as a row: its name, how it is doing, and the button. At the accessibility text sizes the button
/// moves under the words and spans the row, so nothing is squeezed.
private struct SkyListRow: View {
    let scene: SkyScene
    let index: Int
    let constellation: SkyLayout.Constellation
    let color: CourseColor
    var onRelight: (SkyLayout.Constellation) -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let c = constellation
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
        let minutes = scene.minutesToRelight(index)
        layout {
            if !stacked { CLIconBadge(systemImage: c.topicID == nil ? "circle.dotted" : "sparkles", tint: color) }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: c.name).clFont(.bodyEmphasis).foregroundStyle(CLColor.ink)
                Text(verbatim: SkyCopy.detail(index, in: scene)).clFont(.footnote).foregroundStyle(CLColor.ink2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button { onRelight(c) } label: {
                Text("Practice")
            }
            .buttonStyle(.cl(.soft, size: .small, fullWidth: stacked))
            .accessibilityLabel(Text(SkyCopy.practice(c.name, minutes: minutes)))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: CLMetrics.rowMinHeight, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(SkyCopy.label(index, in: scene))
        .accessibilityAction(named: Text("Practice")) { onRelight(c) }
    }
}

// MARK: - DEBUG

#if DEBUG
/// `CRAMLESS_SKY`, comma-separated:
/// - `still`: no twinkle and no glide, for a screenshot.
/// - `relight[:n]`: plays a relight of n (default 12) stars of the topics with the most dim ones, as if a session had
///   just ended.
/// - `flare`: lights one star again and again, with the save's ring and sparkle, to film the flare.
/// - `age:<days>`: the sky that many days on, if nothing were studied.
/// - `lapse:<days>`: the same, as a time-lapse over about ten seconds.
/// - `focus:<n>`: focuses the nth constellation.
/// - `tour`: focuses the three constellations with the most dim stars, one after another, then the whole sky.
/// - `list`: starts as a list, with the panel of what's coming due and the brightest topics at its head.
/// - `memory`: opens that panel as a sheet over the sky.
/// - `fill:<n>`: adds n more studied items to the demo world first, for a fuller sky.
struct SkyDebug {
    var still = false
    var demoRelight: Int?
    var flare = false
    var age: Double?
    var lapse: Double?
    var focus: Int?
    var tour = false
    var list = false
    var memory = false
    var fill: Int?

    @MainActor static func read() -> SkyDebug {
        var out = SkyDebug()
        guard let raw = TestHarness.value("CRAMLESS_SKY") else { return out }
        for part in raw.split(separator: ",").map(String.init) {
            let pair = part.split(separator: ":", maxSplits: 1).map(String.init)
            let arg = pair.count > 1 ? pair[1] : nil
            switch pair[0] {
            case "still": out.still = true
            case "relight": out.demoRelight = arg.flatMap(Int.init) ?? 12
            case "flare": out.flare = true
            case "age": out.age = arg.flatMap(Double.init)
            case "lapse": out.lapse = arg.flatMap(Double.init)
            case "focus": out.focus = arg.flatMap(Int.init) ?? 0
            case "tour": out.tour = true
            case "list": out.list = true
            case "memory": out.memory = true
            case "fill": out.fill = arg.flatMap(Int.init) ?? 200
            default: break
            }
        }
        return out
    }
}

/// A made-up session for the films: a topic or two practiced, the stars that had faded or never been lit answered right.
enum SkyDemo {
    static func relit(_ scene: SkyScene, count: Int) -> (SkyScene, SkyRelight) {
        var scene = scene
        // The constellations with the most to light, in turn, each one's dimmest stars first.
        func toLight(_ c: SkyLayout.Constellation) -> [Int] {
            c.stars.filter { scene.light.isDim($0) || scene.light.hollow[$0] }.sorted {
                (scene.light.hollow[$0] ? 2 : 0, scene.light.brightness[$0]) < (scene.light.hollow[$1] ? 2 : 0, scene.light.brightness[$1])
            }
        }
        let order = scene.layout.constellations.sorted { toLight($0).count > toLight($1).count }
        var chosen: [Int] = []
        for c in order where chosen.count < count { chosen += toLight(c) }
        var relight = SkyRelight()
        for (k, i) in chosen.prefix(count).enumerated() {
            let id = scene.layout.stars[i].id
            let hollow = scene.light.hollow[i]
            relight.relit.insert(id)
            relight.from[id] = hollow ? 0 : scene.light.brightness[i]
            if hollow { relight.lit.insert(id) } else if k % 3 == 0 { relight.saved.insert(id) }
            scene.light.recall[i] = 0.99
            scene.light.brightness[i] = 1
            scene.light.hollow[i] = false
            scene.light.flicker[i] = 0.1
        }
        return (scene, relight)
    }
}
#endif
