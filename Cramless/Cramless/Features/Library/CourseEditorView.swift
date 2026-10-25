import SwiftUI

/// New course or edit one: its name, colour and symbol, and Delete.
struct CourseEditorView: View {
    let courseID: UUID?

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var color: CourseColor = .sky
    @State private var symbol = CourseEditorView.symbols[0]
    @State private var loaded = false
    @State private var confirmDelete = false
    @FocusState private var nameFocused: Bool

    /// Curated subject symbols.
    static let symbols = [
        "book.closed", "leaf", "flask", "atom", "brain.head.profile", "character.bubble",
        "function", "x.squareroot", "chart.line.uptrend.xyaxis", "globe.americas", "building.columns", "scalemass",
        "stethoscope", "heart.text.square", "music.note", "paintpalette", "theatermasks", "laptopcomputer",
        "cpu", "gearshape.2", "pencil.and.ruler", "dollarsign.circle", "map", "graduationcap",
    ]

    var body: some View {
        let course = app.course(courseID)
        let counts = course.map { LibraryCourseModel(course: $0, app: app) }
        NavigationStack {
            Form {
                Section {
                    preview
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }

                Section("Name") {
                    TextField("Bio 101", text: $name)
                        .clFont(.body)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .focused($nameFocused)
                        .onSubmit(save)
                }
                .listRowBackground(CLColor.surface)

                Section("Colour") {
                    ColorRow(selection: $color)
                }
                .listRowBackground(CLColor.surface)

                Section("Symbol") {
                    SymbolGrid(symbols: Self.symbols, selection: $symbol, tint: color)
                }
                .listRowBackground(CLColor.surface)

                if let counts {
                    Section {
                        Button("Delete course", role: .destructive) { confirmDelete = true }
                            .frame(maxWidth: .infinity)
                    } footer: {
                        Text("Its \(LibraryFormat.courseCounts(sources: counts.sources, questions: counts.questions)) and its exams go too.")
                    }
                    .listRowBackground(CLColor.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .clScreenBackground()
            .navigationTitle(courseID == nil ? "New course" : "Edit course")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(courseID == nil ? "Add" : "Save", action: save)
                        .disabled(name.clTrimmed.isEmpty)
                }
            }
            .alert("Delete \(course?.name ?? "course")?", isPresented: $confirmDelete) {
                Button("Delete course", role: .destructive) {
                    if let id = courseID {
                        dismiss()
                        if case .course(id)? = app.router.paths[app.router.tab]?.last { app.router.pop() }
                        app.deleteCourse(id)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This can't be undone.")
            }
        }
        .presentationDetents([.large])
        .presentationBackground(CLColor.background)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let course {
                name = course.name
                color = course.color
                symbol = course.symbol
            } else {
                // A colour the person doesn't use yet.
                let used = Set(app.courses.map(\.color))
                color = CourseColor.allCases.first { !used.contains($0) } ?? .sky
                // Straight to the name (not in headless screenshot runs, where the keyboard would hide the form).
                nameFocused = !app.config.isHarness
            }
        }
    }

    private var preview: some View {
        VStack(spacing: 10) {
            CLIconBadge(systemImage: symbol, tint: color, size: 72)
                .animation(CLMotion.pop, value: symbol)
                .animation(CLMotion.snap, value: color)
            Text(name.clTrimmed.isEmpty ? "Course name" : name.clTrimmed)
                .clFont(.title3)
                .foregroundStyle(name.clTrimmed.isEmpty ? CLColor.ink4 : CLColor.ink)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .accessibilityHidden(true)
    }

    private func save() {
        guard !name.clTrimmed.isEmpty else { return }
        if let courseID {
            app.updateCourse(courseID, name: name, color: color, symbol: symbol)
            CLHaptics.land()
            dismiss()
        } else if let course = app.createCourse(name: name, color: color, symbol: symbol) {
            CLHaptics.land()
            dismiss()
            app.router.toast("Added \(course.name)")
        }
    }
}

/// The six course colours as swatches.
private struct ColorRow: View {
    @Binding var selection: CourseColor

    var body: some View {
        HStack(spacing: 0) {
            ForEach(CourseColor.allCases, id: \.self) { color in
                Button {
                    CLHaptics.select()
                    withAnimation(CLMotion.snap) { selection = color }
                } label: {
                    ZStack {
                        Circle().fill(color.fill).frame(width: 34, height: 34)
                        if selection == color {
                            Circle().strokeBorder(CLColor.ink, lineWidth: 2.5).frame(width: 42, height: 42)
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .heavy))
                                .foregroundStyle(CLColor.onFill)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: CLMetrics.minHitTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(color.spokenName))
                .accessibilityAddTraits(selection == color ? [.isSelected] : [])
            }
        }
        .padding(.vertical, 4)
    }
}

/// A grid of subject symbols.
private struct SymbolGrid: View {
    let symbols: [String]
    @Binding var selection: String
    let tint: CourseColor
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: typeSize.isAccessibilitySize ? 4 : 6)
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(symbols, id: \.self) { symbol in
                Button {
                    CLHaptics.select()
                    withAnimation(CLMotion.snap) { selection = symbol }
                } label: {
                    Image(systemName: symbol)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(selection == symbol ? tint.ink : CLColor.ink2)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(selection == symbol ? tint.soft : CLColor.surface2,
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            if selection == symbol {
                                RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(tint.ink, lineWidth: 2)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(symbol.replacingOccurrences(of: ".", with: " ")))
                .accessibilityAddTraits(selection == symbol ? [.isSelected] : [])
            }
        }
        .padding(.vertical, 6)
    }
}

extension CourseColor {
    /// The colour's name, for VoiceOver.
    var spokenName: String {
        switch self {
        case .sky: "Sky blue"
        case .tangerine: "Tangerine"
        case .mint: "Mint"
        case .sun: "Sun yellow"
        case .rose: "Rose"
        case .capy: "Capy brown"
        }
    }
}
