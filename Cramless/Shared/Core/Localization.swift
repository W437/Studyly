import Foundation

// Copy lives in String Catalogs (Cramless/Resources/Localizable.xcstrings, CramlessWidgets/Localizable.xcstrings;
// scripts/sync_strings.sh fills them after each build). Components take `LocalizedStringResource`, so a literal
// passed to one is localizable: `CLRow(title: "Accessibility")`. Text that must not be translated goes through
// `.verbatim(_:)`.

extension LocalizedStringResource {
    /// Text shown exactly as it is: the person's own words (a course name, an answer), AI text, or a line already
    /// built from localized copy. (One catalog entry, "%@", never translated.)
    static func verbatim(_ text: String) -> LocalizedStringResource {
        "\(text)"
    }
}
