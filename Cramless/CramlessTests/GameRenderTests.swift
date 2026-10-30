import SwiftUI
import UIKit
import XCTest
@testable import Cramless

/// Draws the game loop's pictures to PNGs in docs/shots/game/ (light and dark), to be looked at: the flame in each stage and
/// size, every badge as a medal (earned, tilted, and still to earn), the six skies, and the quests card. There is nothing to
/// compare them to: the test only makes sure each one draws.
@MainActor
final class GameRenderTests: XCTestCase {
    static let outputFolder = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "docs/shots/game", directoryHint: .isDirectory)

    override func setUp() async throws {
        try FileManager.default.createDirectory(at: Self.outputFolder, withIntermediateDirectories: true)
    }

    @discardableResult
    private func render<V: View>(_ view: V, _ name: String, _ scheme: ColorScheme, scale: CGFloat = 2) throws -> UIImage {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, scheme))
        renderer.scale = scale
        let image = try XCTUnwrap(renderer.uiImage, name)
        let data = try XCTUnwrap(image.pngData(), name)
        try data.write(to: Self.outputFolder.appending(path: "\(name)-\(scheme == .dark ? "dark" : "light").png"))
        return image
    }

    private func background(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color(hex: 0x0B1220) : Color(hex: 0xF1F5FA) }

    func testTheFlameInEveryStage() throws {
        for scheme in [ColorScheme.light, .dark] {
            let sheet = VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .bottom, spacing: 22) {
                    ForEach(StreakStage.allCases, id: \.self) { stage in
                        VStack(spacing: 6) {
                            StreakFlame(stage: stage, size: 110)
                            Text(String(describing: stage)).font(.caption).foregroundStyle(CLColor.ink2)
                        }
                    }
                }
                HStack(alignment: .center, spacing: 26) {
                    ForEach([15.0, 22.0, 30.0, 44.0], id: \.self) { size in
                        HStack(spacing: 10) {
                            ForEach(StreakStage.allCases.dropFirst(), id: \.self) { stage in
                                StreakFlame(stage: stage, size: size)
                            }
                        }
                    }
                }
                HStack(spacing: 14) {
                    Text("Not lit").font(.caption).foregroundStyle(CLColor.ink2)
                    ForEach(StreakStage.allCases, id: \.self) { stage in
                        StreakFlame(stage: stage, size: 44, lit: false)
                    }
                }
            }
            .padding(20)
            .background(background(scheme))
            let image = try render(sheet, "flames", scheme)
            XCTAssertGreaterThan(image.size.width, 300)
        }
    }

    func testEveryBadgeAsAMedal() throws {
        for scheme in [ColorScheme.light, .dark] {
            let columns = Array(repeating: GridItem(.fixed(104), spacing: 14), count: 5)
            let sheet = VStack(alignment: .leading, spacing: 14) {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(Badge.allCases) { BadgeMedal(badge: $0, size: 96) }
                }
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(Badge.allCases) { BadgeMedal(badge: $0, size: 96, tilt: CGPoint(x: 0.8, y: -0.5)) }
                }
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(Badge.allCases) { BadgeMedal(badge: $0, earned: false, size: 96) }
                }
            }
            .padding(20)
            .background(background(scheme))
            try render(sheet, "medals", scheme)
        }
    }

    func testTheBigMedalAndItsSheetContent() throws {
        for scheme in [ColorScheme.light, .dark] {
            let medals = HStack(spacing: 20) {
                BadgeMedal(badge: .streak30, size: 200)
                BadgeMedal(badge: .saves10, size: 200, tilt: CGPoint(x: -0.7, y: 0.6))
                BadgeMedal(badge: .streak365, size: 200, tilt: CGPoint(x: 0.9, y: 0.2))
            }
            .padding(24)
            .background(background(scheme))
            try render(medals, "medals-large", scheme)
        }
    }

    func testTheSixSkies() throws {
        for scheme in [ColorScheme.light, .dark] {
            let sheet = HStack(spacing: 14) {
                ForEach(SkyTheme.allCases) { theme in
                    VStack(spacing: 6) {
                        SkySwatch(theme: theme, width: 110, height: 150)
                        Text(String(localized: theme.title)).font(.caption).foregroundStyle(CLColor.ink2)
                    }
                }
                SkySwatch(theme: .aurora, width: 110, height: 150, locked: true)
            }
            .padding(20)
            .background(background(scheme))
            try render(sheet, "skies", scheme)
        }
    }

    func testTheQuestsCardAndABadgeRowAtTheLargestTextSize() throws {
        let rows = [QuestRow(kind: .finishSession, progress: QuestProgress(done: 1, goal: 1), isDone: true, subject: nil),
                    QuestRow(kind: .rescueFading, progress: QuestProgress(done: 2, goal: 3), isDone: false, subject: nil),
                    QuestRow(kind: .examTopic, progress: QuestProgress(done: 0, goal: 5), isDone: false, subject: "Organic Chemistry II")]
        let quests = QuestsToday(rows: rows, week: 7, weekGoal: 12, nextSky: .dusk, weekLit: false)
        for scheme in [ColorScheme.light, .dark] {
            let sheet = VStack(spacing: 16) {
                TodayQuestsCard(quests: quests)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Badges").font(.title2.bold())
                    BadgeCell(status: BadgeStatus(badge: .streak30, progress: BadgeProgress(value: 12, target: 30), earnedAt: nil),
                              calendar: .current)
                    BadgeCell(status: BadgeStatus(badge: .firstSession, progress: BadgeProgress(value: 1, target: 1),
                                                  earnedAt: Date(timeIntervalSince1970: 1_800_000_000)), calendar: .current)
                }
                .clCard()
            }
            .environment(\.dynamicTypeSize, .accessibility3)
            .frame(width: 370)
            .padding(16)
            .background(background(scheme))
            try render(sheet, "quests-ax", scheme)
        }
    }

    func testTheQuestsCardInThreeStates() throws {
        func quests(_ done: Int, week: Int) -> QuestsToday {
            let kinds: [QuestKind] = [.finishSession, .rescueFading, .ownWords]
            let rows = kinds.enumerated().map { index, kind in
                QuestRow(kind: kind, progress: index < done ? QuestProgress(done: kind.goal, goal: kind.goal)
                            : QuestProgress(done: min(1, kind.goal - 1), goal: kind.goal),
                         isDone: index < done, subject: nil)
            }
            return QuestsToday(rows: rows, week: week, weekGoal: 12, nextSky: .dusk, weekLit: false)
        }
        var lit = quests(3, week: 12)
        lit.weekLit = true
        lit.nextSky = nil
        for scheme in [ColorScheme.light, .dark] {
            let sheet = VStack(spacing: 16) {
                TodayQuestsCard(quests: quests(0, week: 0))
                TodayQuestsCard(quests: quests(1, week: 5))
                TodayQuestsCard(quests: quests(3, week: 9))
                TodayQuestsCard(quests: lit)
            }
            .frame(width: 370)
            .padding(16)
            .background(background(scheme))
            try render(sheet, "quests", scheme)
        }
    }
}
