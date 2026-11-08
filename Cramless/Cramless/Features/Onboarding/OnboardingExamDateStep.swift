import SwiftUI

/// "When's your Bio 101 exam?": asked after the first session, named after the course the first page went to. A month of days
/// (today a ring, nothing picked until a tap) and "No exam yet"; either way Continue moves on. A day makes the course's exam
/// (`AppModel.setOnboardingExam`); "No exam yet" makes none, and the plan shows its no-exam state.
///
/// DEBUG hook: `CRAMLESS_ONB_DATE=<days>|none` picks the day that many days from today (or "No exam yet"), as a tap would.
struct OnboardingExamDateStep: View {
    let courseID: UUID?
    let onDone: () -> Void

    @Environment(AppModel.self) private var app
    @State private var day: Date?
    @State private var noExam = false

    private var answered: Bool { day != nil || noExam }

    var body: some View {
        let today = app.calendar.startOfDay(for: app.now)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(QuizContent.examQuestion(courseName: app.onboardingCourse(courseID)?.name))
                    .clFont(.brandTitle(30))
                    .foregroundStyle(CLColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text("Capling plans backwards from that date.")
                    .clFont(.body)
                    .foregroundStyle(CLColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
                VStack(spacing: 12) {
                    calendarCard(today: today)
                    QuizOptionRow(symbol: "calendar.badge.minus", title: "No exam yet",
                                  detail: "You can add it later", selected: noExam) {
                        noExam = true
                        withAnimation(CLMotion.snap) { day = nil }
                    }
                }
                .padding(.top, 20)
            }
            .padding(.horizontal, CLSpace.gutter)
            .padding(.top, 8)
            .padding(.bottom, 16)
            .frame(maxWidth: CLMetrics.readableWidth)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
        .background(CLColor.background.ignoresSafeArea())
        .safeAreaBar(edge: .bottom) {
            Button("Continue", action: next)
                .buttonStyle(.cl(.primary))
                .disabled(!answered)
                .padding(.horizontal, CLSpace.gutter)
                .padding(.top, 10)
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        #if DEBUG
        .onAppear(perform: applyDebugHook)
        #endif
    }

    private func calendarCard(today: Date) -> some View {
        let last = app.calendar.date(byAdding: .year, value: 1, to: today) ?? today
        return VStack(alignment: .leading, spacing: 6) {
            ExamDayCalendar(selection: Binding(get: { day }, set: { picked in
                CLHaptics.select()
                noExam = false
                withAnimation(CLMotion.snap) { day = picked }
            }), today: today, last: last, calendar: app.calendar)
            Group {
                if let day {
                    Label(QuizContent.examSummary(day, now: app.now, calendar: app.calendar), systemImage: "calendar")
                        .clFont(.subheadlineEmphasis)
                        .foregroundStyle(CLColor.tangerineInk)
                } else {
                    Text("Tap your exam day")
                        .clFont(.footnoteEmphasis)
                        .foregroundStyle(CLColor.ink3)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
            .frame(minHeight: 24)
            .accessibilityAddTraits(.updatesFrequently)
        }
        .padding(10)
        .background(CLColor.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(day != nil ? CLColor.tangerine : .clear, lineWidth: 2))
        .shadow(color: CLColor.night.opacity(0.05), radius: 1, y: 1)
        .shadow(color: CLColor.night.opacity(0.06), radius: 12, y: 8)
        .animation(CLMotion.snap, value: day != nil)
    }

    private func next() {
        guard answered else { return }
        CLHaptics.tap()
        app.setOnboardingExam(day: noExam ? nil : day, courseID: courseID)
        onDone()
    }

    #if DEBUG
    private func applyDebugHook() {
        guard let raw = TestHarness.once("CRAMLESS_ONB_DATE") else { return }
        if raw == "none" {
            noExam = true
        } else if let days = Int(raw) {
            day = app.calendar.startOfDay(for: app.calendar.adding(days: days, to: app.now))
        }
    }
    #endif
}

/// A month of days to pick the exam's from. Today is a ring (so an untouched calendar never looks answered), the picked day a
/// filled circle, days before today and after `last` dimmed and not tappable. The arrows step a month.
struct ExamDayCalendar: View {
    @Binding var selection: Date?
    /// The start of today, and of the last day that can be picked.
    let today: Date
    let last: Date
    let calendar: Calendar

    @State private var month: Date?

    private var shownMonth: Date { month ?? startOfMonth(selection ?? today) }

    var body: some View {
        let first = shownMonth
        VStack(spacing: 8) {
            header(first)
            weekdays
            grid(first)
        }
        // Seven columns don't grow past this; the numbers stay readable in their 44-point cells.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private func header(_ first: Date) -> some View {
        let canGoBack = first > startOfMonth(today)
        let canGoOn = (calendar.date(byAdding: .month, value: 1, to: first) ?? first) <= last
        return HStack(spacing: 4) {
            Text(first.formatted(.dateTime.month(.wide).year()))
                .clFont(.headline)
                .foregroundStyle(CLColor.ink)
                .contentTransition(.opacity)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            monthButton("chevron.left", label: "Previous month", enabled: canGoBack) { step(-1) }
            monthButton("chevron.right", label: "Next month", enabled: canGoOn) { step(1) }
        }
        .padding(.leading, 8)
    }

    private func monthButton(_ symbol: String, label: LocalizedStringResource, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            CLHaptics.tap()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(enabled ? CLColor.tangerineInk : CLColor.ink4)
                .frame(width: CLMetrics.minHitTarget, height: CLMetrics.minHitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(Text(label))
    }

    private var weekdays: some View {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let order = (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 }
        return HStack(spacing: 0) {
            ForEach(order, id: \.self) { index in
                Text(symbols[index].uppercased())
                    .clFont(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(CLColor.ink3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    private func grid(_ first: Date) -> some View {
        let count = calendar.range(of: .day, in: .month, for: first)?.count ?? 30
        let lead = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        let cells: [Date?] = Array(repeating: nil, count: lead)
            + (0..<count).map { calendar.date(byAdding: .day, value: $0, to: first) }
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
        return LazyVGrid(columns: columns, spacing: 2) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, date in
                if let date {
                    dayCell(date)
                } else {
                    Color.clear.frame(height: CLMetrics.minHitTarget)
                }
            }
        }
        .id(first)
    }

    private func dayCell(_ date: Date) -> some View {
        let isToday = calendar.isDate(date, inSameDayAs: today)
        let picked = selection.map { calendar.isDate($0, inSameDayAs: date) } ?? false
        let open = date >= today && date <= last
        return Button {
            selection = date
        } label: {
            Text("\(calendar.component(.day, from: date))")
                .clFont(picked || isToday ? .bodyEmphasis : .body)
                .monospacedDigit()
                .foregroundStyle(picked ? CLColor.onFill : open ? CLColor.ink : CLColor.ink4)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(width: 40, height: 40)
                .background {
                    if picked {
                        Circle().fill(CLColor.tangerine)
                    } else if isToday {
                        Circle().strokeBorder(CLColor.tangerine, lineWidth: 2)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: CLMetrics.minHitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!open)
        .accessibilityLabel(Text(date.formatted(.dateTime.weekday(.wide).month(.wide).day())))
        .accessibilityValue(isToday ? Text("Today") : Text(verbatim: ""))
        .accessibilityAddTraits(picked ? [.isButton, .isSelected] : .isButton)
    }

    private func step(_ months: Int) {
        guard let next = calendar.date(byAdding: .month, value: months, to: shownMonth) else { return }
        withAnimation(CLMotion.fade) { month = next }
    }

    private func startOfMonth(_ date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }
}

/// A tappable answer card: an icon on a soft tile, the answer, and a check that fills when picked.
struct QuizOptionRow: View {
    let symbol: String
    let title: LocalizedStringResource
    var detail: LocalizedStringResource?
    let selected: Bool
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Button {
            CLHaptics.select()
            action()
        } label: {
            // Centred normally; at accessibility sizes a row is several lines tall, so the icon and the check
            // stay with the first line.
            HStack(alignment: typeSize.isAccessibilitySize ? .top : .center, spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(CLColor.skyInk)
                    .frame(width: 40, height: 40)
                    .background(CLColor.skySoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .clFont(.bodyEmphasis)
                        .foregroundStyle(CLColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail {
                        Text(detail)
                            .clFont(.subheadline)
                            .foregroundStyle(CLColor.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                check
            }
            .padding(16)
            .background(CLColor.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(selected ? CLColor.tangerine : .clear, lineWidth: 2))
            .shadow(color: CLColor.night.opacity(0.05), radius: 1, y: 1)
            .shadow(color: CLColor.night.opacity(0.06), radius: 12, y: 8)
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.pressable)
        .animation(CLMotion.snap, value: selected)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private var check: some View {
        ZStack {
            Circle().strokeBorder(CLColor.surface3, lineWidth: 2).opacity(selected ? 0 : 1)
            Circle().fill(CLColor.tangerine).opacity(selected ? 1 : 0)
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(CLColor.onFill)
                .scaleEffect(selected ? 1 : 0.4)
                .opacity(selected ? 1 : 0)
        }
        .frame(width: 26, height: 26)
        .animation(CLMotion.pop, value: selected)
        .accessibilityHidden(true)
    }
}
