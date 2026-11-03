import XCTest
@testable import Cramless

/// The offline rules write questions for English only. For a page in another language the result says so in plain
/// words, says what would write questions for it, and carries the consent offer when consent is what is missing: never
/// an empty set with no reason. Spanish, Hebrew and Arabic samples, as Wikipedia writes them.
@MainActor
final class OfflineLanguageTests: CaptureTestCase {

    private let spanish = [
        "La mitosis es el proceso por el cual una célula se divide en dos células hijas idénticas.",
        "Citocinesis: la división del citoplasma que sigue a la mitosis.",
        "Durante la mitosis el material genético se copia y se reparte por igual entre los dos núcleos nuevos.",
    ]
    private let hebrew = [
        "מלחמת העצמאות הישראלית פרצה ב-30 בנובמבר 1947.",
        "בבוקר היום שלאחר קבלת תוכנית החלוקה בעצרת האו\"ם, פתחו ערביי ארץ ישראל בהתקפות כנגד היישוב היהודי בארץ ישראל כדי למנוע את יישומה.",
        "בכך נפתח השלב הראשון של המלחמה, המכונה לעיתים בשם מלחמת האזרח.",
    ]
    private let arabic = [
        "الثورة الفرنسية هي فترة مؤثرة من الاضطرابات الاجتماعية والسياسية في فرنسا عرفت عدة مراحل استمرت من 1789 حتى 1799.",
        "وكانت لها تأثيرات عميقة على أوروبا والعالم الغربي عموما، انتهت بسيطرة البورجوازية خلال التحالف مع نابليون.",
        "ثم انتهت بتصدير الأزمة من خلال الاستعمار بالتوسع اللاحق للإمبراطورية الفرنسية.",
    ]

    private var samples: [(code: String, lines: [String])] { [("es", spanish), ("he", hebrew), ("ar", arabic)] }

    private func input(_ lines: [String]) -> GenerationInput {
        GenerationInput(course: "History", sourceTitle: "Apuntes", level: "college",
                        pages: [PageText(index: 0, label: "1", lines: lines.enumerated().map { TextLine(id: "p0.l\($0.offset)", text: $0.element, box: nil) })])
    }

    private let english = "The offline rules only write questions for English pages"

    // MARK: The generator

    func testTheLanguagesAreKnownAndOnlyTermCardsComeOut() {
        for (code, lines) in samples {
            let r = LocalGenerator.generate(pages: input(lines).pages, sourceTitle: "T")
            XCTAssertEqual(r.language, code)
            XCTAssertEqual(r.quality, .unsupportedLanguage, code)
            XCTAssertTrue(r.items.allSatisfy { $0.kind == .flashcard }, code)
        }
        XCTAssertEqual(LocalGenerator.generate(pages: input(spanish).pages, sourceTitle: "T").items.map(\.prompt), ["Citocinesis"])
        XCTAssertTrue(LocalGenerator.generate(pages: input(hebrew).pages, sourceTitle: "T").items.isEmpty)
        XCTAssertTrue(LocalGenerator.generate(pages: input(arabic).pages, sourceTitle: "T").items.isEmpty)
    }

    // MARK: Cloud AI could write them, but isn't allowed yet

    func testWithConsentMissingTheNoteSaysWhatWouldWorkAndTheOutcomeCarriesTheOffer() async throws {
        for (code, lines) in samples {
            let app = AITestSupport.makeApp(mode: .relay, consent: false)
            let relay = RecordingTransport()
            app.ai.transportOverride = relay
            let outcome = await app.ai.generateSet(input(lines))

            XCTAssertTrue(relay.calls.isEmpty, "nothing leaves the iPhone before consent: \(code)")
            XCTAssertEqual(outcome.origin, .rules, code)
            XCTAssertEqual(outcome.suggestion, .allowCloud(feature: AIJob.generate.feature), code)
            let note = try XCTUnwrap(outcome.note, code)
            XCTAssertTrue(note.hasPrefix("This page doesn't look like English, and \(english.lowercasedFirst)"), note)
            XCTAssertTrue(note.hasSuffix(" Cloud AI can write questions for it."), note)
            if code == "es" {
                XCTAssertEqual(outcome.items.map(\.prompt), ["Citocinesis"])
                XCTAssertTrue(note.contains("so these are just the term cards on it."), note)
            } else {
                XCTAssertTrue(outcome.items.isEmpty, code)
                XCTAssertFalse(note.contains("term cards"), "there are none to talk about: \(note)")
            }
        }
    }

    func testWhenAllowedTheCloudWritesThemInstead() async {
        for (_, lines) in samples {
            let app = AITestSupport.makeApp(mode: .mock)
            let outcome = await app.ai.generateSet(input(lines))
            // The mock relay answers from its canned page, whose lines aren't these: what matters is that it is asked.
            XCTAssertTrue(outcome.origin == .cloud || outcome.fellBack, "the cloud is tried first for any language")
        }
    }

    // MARK: Cloud AI can't be asked

    func testABuildWithoutARelayDoesNotPromiseCloudAI() async throws {
        let app = AITestSupport.makeApp(mode: .local)
        let outcome = await app.ai.generateSet(input(hebrew))
        XCTAssertNil(outcome.suggestion)
        XCTAssertEqual(outcome.note, "This page doesn't look like English, and the offline rules only write questions for English pages.")
    }

    func testAChildIsNeverOffered() async {
        let app = AITestSupport.makeApp(mode: .relay, consent: true, age: .under13)
        app.ai.transportOverride = RecordingTransport()
        let outcome = await app.ai.generateSet(input(arabic))
        XCTAssertNil(outcome.suggestion)
        XCTAssertEqual(outcome.note, "This page doesn't look like English, and the offline rules only write questions for English pages.")
    }

    func testWhenTheFreeScansAreUsedUpTheNoteSaysSo() async throws {
        let app = AITestSupport.makeApp(mode: .relay, consent: true)
        app.ai.transportOverride = RecordingTransport()
        app.ai.setServerQuota(QuotaStatus(plan: .free, meters: [QuotaMeter(key: .scans, used: 3, limit: 3, period: .week)]))
        let outcome = await app.ai.generateSet(input(hebrew))
        XCTAssertEqual(outcome.limitReached, .scans)
        guard case .upgrade(.scans, _)? = outcome.suggestion else { return XCTFail("\(String(describing: outcome.suggestion))") }
        XCTAssertEqual(outcome.note, "This page doesn't look like English, and the offline rules only write questions for English pages. "
                       + "This week's free AI scans are used up. Cloud AI can write questions for it once they reset, or with Capling Pro.")
    }

    func testWhenCloudAICouldNotBeReachedTheNoteSaysSo() async {
        let app = AITestSupport.makeApp(mode: .relay, consent: true)
        let relay = RecordingTransport()
        relay.failures["generate"] = .offline
        app.ai.transportOverride = relay
        let outcome = await app.ai.generateSet(input(spanish))
        XCTAssertEqual(outcome.origin, .rules)
        XCTAssertTrue(outcome.fellBack)
        XCTAssertEqual(outcome.note, "This page doesn't look like English, and the offline rules only write questions for English pages, "
                       + "so these are just the term cards on it. Cloud AI couldn't be reached. Try again later.")
    }

    func testWhenCloudAIIsGettingReadyTheNoteSaysSo() async {
        let app = AITestSupport.makeApp(mode: .relay, consent: true)
        let relay = ScriptedRelay()
        relay.onGenerate = { _, _ in throw RelayError.accountPending }
        app.ai.transportOverride = relay
        let outcome = await app.ai.generateSet(input(arabic))
        XCTAssertTrue(outcome.items.isEmpty)
        XCTAssertEqual(outcome.note, "This page doesn't look like English, and the offline rules only write questions for English pages. "
                       + "Cloud AI is getting ready. Try again later.")
    }

    // MARK: Which language a page is in

    /// Paragraphs of one article each, as the recogniser meets them in a book: it reads each at 0.99 or more.
    static let polishParagraph = "Mitoza jest procesem podziału komórki, w którym z jednej komórki macierzystej powstają dwie identyczne komórki "
        + "potomne. Dzięki niej organizm rośnie i odnawia uszkodzone tkanki."
    private static let germanParagraph = "Die Mitose ist ein Vorgang der Zellteilung, bei dem aus einer Zelle zwei erbgleiche Tochterzellen entstehen. "
        + "Sie sorgt für das Wachstum und für die Erneuerung von Geweben."
    private static let spanishParagraph = "La mitosis es el proceso por el cual una célula eucariota se divide en dos células hijas idénticas. "
        + "Permite el crecimiento y la reparación de los tejidos dañados."
    private static let frenchParagraph = "La mitose est le processus par lequel une cellule eucaryote se divise en deux cellules filles génétiquement "
        + "identiques. Elle permet la croissance des organismes."
    private static let hebrewParagraph = "מיטוזה היא חלוקת תא שבה נוצרים שני תאים זהים. התהליך מאפשר לגוף לגדול ולתקן רקמות פגועות."
    private static let arabicParagraph = "الانقسام الفتيلي هو عملية تنقسم فيها الخلية إلى خليتين متطابقتين. تسمح هذه العملية للجسم بالنمو وإصلاح الأنسجة التالفة."
    private static let englishParagraph = "Mitosis is the process by which a single eukaryotic cell divides to produce two identical daughter cells. "
        + "It allows the body to grow and to repair damaged tissue."
    private static let englishWithSymbols = "Solve for x: 2x + 3 = 11, so 2x = 8 and x = 4. Check: 2(4) + 3 = 11, which is correct. "
        + "Then substitute x = 4 into y = x^2 - 3x + 1 to get y = 5."

    func testAnEquationSheetIsNotGuessedToBeInARareLanguage() {
        // The worksheet that Cloud AI wrote up in Polish: 129 letters, and the recogniser put Polish at 0.63, Turkish at 0.11, Danish and German
        // at 0.07. Not sure enough, so the page's language is the course's other sources', else the device's, else English.
        let sheet = GenerationPartsTests.equations
        XCTAssertGreaterThanOrEqual(sheet.unicodeScalars.filter { $0.properties.isAlphabetic }.count, LocalGenerator.minimumLanguageLetters)
        XCTAssertNil(LocalGenerator.confidentLanguage(sheet))
        XCTAssertNil(OnDeviceLanguageGate.dominantLanguage(sheet))
        XCTAssertNotEqual(LocalGenerator.dominantLanguage(sheet, deviceLanguage: "en"), "pl")
        XCTAssertEqual(LocalGenerator.dominantLanguage(sheet, deviceLanguage: "en"), "en")
        XCTAssertEqual(LocalGenerator.dominantLanguage(sheet, courseLanguage: "es", deviceLanguage: "en"), "es", "the course's other sources come first")
        XCTAssertEqual(LocalGenerator.dominantLanguage(sheet, deviceLanguage: "de"), "de", "then the device's")
        XCTAssertEqual(LocalGenerator.dominantLanguage(sheet), LocalGenerator.deviceLanguage())

        // This iPhone's model is not kept from it as "not English"; and the offline rules read it as the language it falls back to.
        XCTAssertEqual(OnDeviceLanguageGate.verdict(for: sheet, supportsLocale: { _ in true }), .supported)
        let page = PageText(index: 0, label: "1", lines: [TextLine(id: "p0.l0", text: sheet, box: nil)])
        XCTAssertEqual(LocalGenerator.generate(pages: [page], sourceTitle: "Worksheet").language, LocalGenerator.deviceLanguage())
        XCTAssertEqual(LocalGenerator.generate(pages: [page], sourceTitle: "Worksheet", courseLanguage: "en").language, "en")
    }

    func testARealParagraphIsStillRecognisedInEveryLanguageWhateverTheFallbackIs() {
        let paragraphs: [(String, String)] = [("pl", Self.polishParagraph), ("de", Self.germanParagraph), ("es", Self.spanishParagraph),
                                              ("fr", Self.frenchParagraph), ("he", Self.hebrewParagraph), ("ar", Self.arabicParagraph),
                                              ("en", Self.englishParagraph)]
        for (code, text) in paragraphs {
            XCTAssertEqual(LocalGenerator.confidentLanguage(text), code, code)
            XCTAssertEqual(LocalGenerator.dominantLanguage(text, courseLanguage: "ja", deviceLanguage: "ko"), code, "\(code): not the fallback")
        }
        // English with a good many symbols in it is still English, not a language guessed from them.
        XCTAssertEqual(LocalGenerator.dominantLanguage(Self.englishWithSymbols, courseLanguage: "pl", deviceLanguage: "pl"), "en")
        XCTAssertEqual(LocalGenerator.dominantLanguage(Self.englishWithSymbols, deviceLanguage: "en"), "en")
        // The gate still keeps a foreign page from this iPhone's English model.
        XCTAssertEqual(OnDeviceLanguageGate.verdict(for: Self.polishParagraph, supportsLocale: { _ in true }), .notEnglish("pl"))
        XCTAssertEqual(OnDeviceLanguageGate.verdict(for: Self.spanishParagraph, supportsLocale: { _ in true }), .notEnglish("es"))
        XCTAssertEqual(OnDeviceLanguageGate.verdict(for: Self.englishWithSymbols, supportsLocale: { _ in true }), .supported)
    }

    func testAFewWordsAreNotEnoughToGoOnAndFallBack() {
        // Ten words, 24 letters: "call Sam" once read as Polish, and short Spanish reads as Spanish only if there are enough letters.
        let ten = "no sé qué es lo que va a ser de mí"
        XCTAssertEqual(ten.split(separator: " ").count, 11)
        XCTAssertLessThan(ten.unicodeScalars.filter { $0.properties.isAlphabetic }.count, LocalGenerator.minimumLanguageLetters)
        XCTAssertNil(LocalGenerator.confidentLanguage(ten))
        XCTAssertEqual(LocalGenerator.dominantLanguage(ten, deviceLanguage: "en"), "en")
        XCTAssertEqual(LocalGenerator.dominantLanguage(ten, courseLanguage: "fr", deviceLanguage: "en"), "fr")
        XCTAssertEqual(LocalGenerator.dominantLanguage("call Sam", deviceLanguage: "en"), "en")
        XCTAssertEqual(LocalGenerator.dominantLanguage("", deviceLanguage: "es"), "es")
    }

    func testTheLanguageOfTheCoursesOtherSourcesAndTheDeviceFallBack() throws {
        XCTAssertEqual(LocalGenerator.commonLanguage(of: [Self.spanishParagraph, Self.englishParagraph, Self.spanishParagraph]), "es", "most of them")
        XCTAssertEqual(LocalGenerator.commonLanguage(of: [Self.germanParagraph, Self.frenchParagraph]), "de", "a tie goes to the first (the newest)")
        XCTAssertNil(LocalGenerator.commonLanguage(of: ["call Sam", GenerationPartsTests.equations]), "none of them is sure")
        XCTAssertNil(LocalGenerator.commonLanguage(of: []))
        // The device's language, when the app speaks it.
        XCTAssertEqual(LocalGenerator.deviceLanguage(locale: Locale(identifier: "es_MX"), known: ["en", "es"]), "es")
        XCTAssertEqual(LocalGenerator.deviceLanguage(locale: Locale(identifier: "es_MX"), known: ["en"]), "en", "not one the app knows")
        XCTAssertEqual(LocalGenerator.deviceLanguage(locale: Locale(identifier: "tlh"), known: ["en", "es"]), "en")
        XCTAssertEqual(LocalGenerator.deviceLanguage(locale: Locale(identifier: "de_DE"), known: []), "en")
    }

    func testTheCoursesOtherSourcesSetTheLanguageOfAnEquationSheet() throws {
        let app = try makeApp()
        let course = makeCourse(app, name: "Química")
        let notes = try app.createSource(fromText: Self.spanishParagraph + "\n\n" + Self.spanishParagraph, title: "Apuntes", course: course)
        _ = try app.createSource(fromText: Self.spanishParagraph, title: "Capítulo 2", course: course)
        let sheet = try app.createSource(fromText: GenerationPartsTests.equations, title: "Hoja", course: course)
        XCTAssertEqual(app.courseLanguage(of: course, excluding: sheet.id), "es")
        XCTAssertEqual(app.generationInput(for: sheet).courseLanguage, "es")
        XCTAssertEqual(app.generationInput(for: notes).courseLanguage, "es", "the sheet is no help, the other Spanish source is")
        XCTAssertNil(app.courseLanguage(of: nil, excluding: nil))

        // Nothing sure in the course: nothing to go on, and the device's language is the next stop.
        let lonely = makeCourse(app, name: "Chem")
        let alone = try app.createSource(fromText: GenerationPartsTests.equations, title: "Worksheet", course: lonely)
        XCTAssertNil(app.generationInput(for: alone).courseLanguage)
    }

    // MARK: What the person sees

    private func flowApp(consent: Bool) -> AppModel {
        let defaults = UserDefaults(suiteName: "offline-language-tests-\(UUID().uuidString)")!
        var environment = ["XCTestConfigurationFilePath": "offline-language-tests"]
        if !consent { environment["CRAMLESS_CONSENT"] = "0" }
        let config = AppConfig(supabaseURL: nil, supabaseAnonKey: nil, aiMode: .mock, isHarness: false, inMemoryStore: true,
                               seedDemoData: false, environment: environment)
        let app = AppModel(config: config, defaults: defaults)
        app.settings.cloudConsentVersion = consent ? AIConsent.currentVersion : 0
        app.ai.mockLatencyScale = 0
        app.ai.streamPause = .zero
        app.ai.probe = FixedOnDeviceProbe(.unavailable(.notChecked))
        return app
    }

    private func run(_ app: AppModel, body: String) async throws -> CaptureRun {
        let course = makeCourse(app)
        let run = CaptureRun(app: app, request: CaptureRequest(input: .text(title: "Apuntes", body: body), courseID: course.id))
        run.pace = 0
        run.start()
        let deadline = Date().addingTimeInterval(20)
        while run.phase == .running, Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertNotEqual(run.phase, .running, "the run didn't finish")
        return run
    }

    func testAnEmptyHebrewSetIsNeverSilentAndOffersCloudAI() async throws {
        let app = flowApp(consent: false)
        let run = try await run(app, body: hebrew.joined(separator: " "))
        guard case .failed(.noQuestions(let note?)) = run.phase else { return XCTFail("expected the no-questions screen, got \(run.phase)") }
        XCTAssertTrue(note.contains(english.lowercasedFirst), note)
        XCTAssertTrue(note.hasSuffix("Cloud AI can write questions for it."), note)
        XCTAssertEqual(run.noQuestionsSuggestion, .allowCloud(feature: AIJob.generate.feature))
    }

    func testANearlyEmptySpanishSetShowsTheNoteAndTheOfferOnTheReview() async throws {
        let app = flowApp(consent: false)
        let run = try await run(app, body: spanish.joined(separator: " "))
        guard case .review(let id) = run.phase else { return XCTFail("expected the review, got \(run.phase)") }
        let report = try XCTUnwrap(app.draftReport(sourceID: id))
        XCTAssertEqual(report.origin, .rules)
        XCTAssertTrue(report.note?.contains("just the term cards") == true, "\(report.note ?? "nil")")
        XCTAssertEqual(report.suggestion?.aiSuggestion, .allowCloud(feature: AIJob.generate.feature))
    }
}

private extension String {
    /// "The offline rules…" → "the offline rules…".
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
}
