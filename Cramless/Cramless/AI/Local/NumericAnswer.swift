import Foundation

/// A calculation's answer is a quantity: "0.50 (50%, dimensionless)", "500 J per cycle", "−2 J/K", "0.300 M". Its key ideas describe the
/// method ("Use η = 1 − Tc/TH"), which a correct final number never states, so grading it by key ideas marks a right answer wrong
/// (measured in the 14-day tests: 49 of 274 right answers in two students' runs, by this iPhone's model and by Cloud AI alike).
///
/// When the model answer is only a quantity, the person's answer is right if it states the same quantity: in any of its forms (0.5 or
/// 50%), with a unit that doesn't contradict it, and with the same sign. It never says an answer is wrong: a number that doesn't match
/// goes to the grader that would have seen it anyway (it may be the right number in another form: "half", "5×10⁻¹").
enum NumericAnswer {

    /// A number as written: every value it could stand for (a percent is both itself and its fraction) and the known unit beside it.
    struct Quantity: Equatable {
        var values: [Double]
        var unit: String?
    }

    /// The person's answer states the model answer's quantity.
    static func agrees(modelAnswer: String, typed: String) -> Bool {
        guard let model = quantity(ofModelAnswer: modelAnswer) else { return false }
        let found = numbers(in: typed)
        guard !found.isEmpty else { return false }
        // A long answer may work towards its number, so only the last one counts; a short answer is read whole.
        let words = typed.split(whereSeparator: \.isWhitespace).count
        let candidates = words > longAnswerWords ? [found[found.count - 1]] : found
        return candidates.contains { matches(model, $0) }
    }

    /// More words than this and only the last number in the answer is compared.
    static let longAnswerWords = 12

    // MARK: The model answer

    /// Words a model answer may carry beside its number and unit.
    private static let fillers: Set<String> = [
        "per", "cycle", "each", "dimensionless", "approximately", "about", "roughly", "approx", "total", "percent", "degrees", "exactly", "only",
    ]

    /// Units compared when both sides name one ("500 kJ" is not "500 J"). Case matters (M is molar, m is metres).
    private static let units: Set<String> = [
        "J", "kJ", "MJ", "cal", "kcal", "K", "C", "°C", "F", "°F", "W", "kW", "MW", "N", "kN", "Pa", "kPa", "MPa", "atm", "bar", "mmHg",
        "m", "cm", "mm", "km", "nm", "μm", "µm", "s", "ms", "min", "h", "hr", "kg", "g", "mg", "μg", "µg", "mol", "mmol", "L", "mL",
        "M", "mM", "V", "mV", "A", "mA", "Hz", "kHz", "MHz", "eV", "keV", "J/K", "J/mol", "m/s", "m/s²", "mol/L", "g/mol", "g/L",
        "kg/m³", "mg/dL", "mmol/L", "bpm", "units", "unit", "kJ/K", "kJ/mol", "kJ/kg", "J/kg", "J/g", "J/(mol·K)", "J/(kg·K)", "cal/g",
        "W/m²", "N·m", "kg·m/s", "km/h", "mph",
    ]

    /// The same unit written two ways.
    private static let sameUnit: [String: String] = ["mol/L": "M", "mmol/L": "mM", "µm": "μm", "µg": "μg", "hr": "h"]

    private static func canonical(_ unit: String) -> String { sameUnit[unit] ?? unit }

    /// Symbols that make a number a relation or a formula rather than a quantity ("dS > 0", "W(1, 4) = 4").
    private static let relations = Set("<>=≤≥≠≡")

    /// The model answer's quantity, when the answer is nothing but one quantity.
    static func quantity(ofModelAnswer text: String) -> Quantity? {
        guard !text.contains(where: { relations.contains($0) }) else { return nil }
        var groups: [[Double]] = []
        var unit: String?
        let tokens = rawTokens(text)
        guard !tokens.isEmpty, tokens.count <= 8 else { return nil }
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            if let number = number(from: token, previous: index > 0 ? tokens[index - 1] : nil, next: index + 1 < tokens.count ? tokens[index + 1] : nil) {
                groups.append(number.values)
                if let u = number.unit { unit = unit ?? u }
            } else if units.contains(token) {
                unit = unit ?? token
            } else if fillers.contains(token.lowercased()) || isSign(token) {
                // beside the number
            } else {
                return nil
            }
            index += 1
        }
        let merged = mergeOverlapping(groups)
        guard merged.count == 1 else { return nil }
        return Quantity(values: merged[0], unit: unit)
    }

    // MARK: The person's answer

    /// Every number in a text, in order.
    static func numbers(in text: String) -> [Quantity] {
        let tokens = rawTokens(text)
        var found: [Quantity] = []
        for (i, token) in tokens.enumerated() {
            if let q = number(from: token, previous: i > 0 ? tokens[i - 1] : nil, next: i + 1 < tokens.count ? tokens[i + 1] : nil) {
                found.append(q)
            }
        }
        return found
    }

    private static func matches(_ model: Quantity, _ typed: Quantity) -> Bool {
        if let a = model.unit, let b = typed.unit, canonical(a) != canonical(b) { return false }
        return model.values.contains { m in typed.values.contains { close(m, $0) } }
    }

    // MARK: Reading numbers

    /// Whitespace-separated pieces with the punctuation around them taken off. A minus sign is kept with its number.
    private static func rawTokens(_ text: String) -> [String] {
        let edge = CharacterSet(charactersIn: "()[]{}\"'“”‘’.,;:!?~≈")
        return text.split(whereSeparator: \.isWhitespace).compactMap { piece in
            let trimmed = String(piece).trimmingCharacters(in: edge)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    private static func isSign(_ token: String) -> Bool { ["minus", "negative", "plus", "positive"].contains(token.lowercased()) }

    private static let minus: Set<Character> = ["-", "−", "–", "‒"]

    /// A token that is a number (with its sign, thousands separators, a percent sign, a fraction or an exponent), and a unit glued to it
    /// ("500J") or in the next token ("500 J"). `previous` supplies the sign of "minus 2".
    private static func number(from token: String, previous: String?, next: String?) -> Quantity? {
        var body = Substring(token)
        var negative = false
        if let first = body.first, minus.contains(first) || first == "+" {
            negative = minus.contains(first)
            body = body.dropFirst()
        } else if let previous, ["minus", "negative"].contains(previous.lowercased()) {
            negative = true
        }
        guard let first = body.first, first.isNumber || first == "." || first == "," else { return nil }

        // Split the number from what follows it: "50%", "500J", "0.3M".
        var end = body.startIndex
        var sawDigit = false
        while end < body.endIndex {
            let c = body[end]
            if c.isASCII, c.isNumber { sawDigit = true; end = body.index(after: end); continue }
            if c == "." || c == "," || c == "/" { end = body.index(after: end); continue }
            if (c == "e" || c == "E"), sawDigit, body.index(after: end) < body.endIndex {
                let rest = body[body.index(after: end)...]
                let digits = rest.drop { $0 == "+" || $0 == "-" || $0 == "−" }
                if let d = digits.first, d.isASCII, d.isNumber { end = body.index(after: end); continue }
            }
            if (c == "+" || c == "-" || c == "−"), end > body.startIndex, "eE".contains(body[body.index(before: end)]) { end = body.index(after: end); continue }
            break
        }
        guard sawDigit else { return nil }
        var numeric = String(body[body.startIndex..<end])
        while let l = numeric.last, l == "." || l == "," || l == "/" { numeric.removeLast() }
        let suffix = String(body[end...])

        guard var value = parse(numeric.replacingOccurrences(of: "−", with: "-")) else { return nil }
        if negative { value = -value }

        var values = [value]
        var unit: String?
        if suffix == "%" {
            values = [value / 100, value]
        } else if !suffix.isEmpty {
            // A glued suffix must be a unit; "2nd", "3rd", "CO2"-like pieces are not quantities.
            guard units.contains(suffix) else { return nil }
            unit = suffix
        } else if let next {
            if units.contains(next) { unit = next }
            else if next.lowercased() == "percent" || next.lowercased() == "%" { values = [value / 100, value] }
        }
        return Quantity(values: values, unit: unit)
    }

    /// "1,200" → 1200, "0,5" → 0.5, "1/2" → 0.5, "1.5e3" → 1500.
    private static func parse(_ text: String) -> Double? {
        var s = text
        if s.contains("/") {
            let parts = s.split(separator: "/", omittingEmptySubsequences: false)
            guard parts.count == 2, let a = parse(String(parts[0])), let b = parse(String(parts[1])), b != 0 else { return nil }
            return a / b
        }
        if s.contains(",") {
            let parts = s.split(separator: ",", omittingEmptySubsequences: false)
            let thousands = parts.count > 1 && parts.dropFirst().allSatisfy { $0.count == 3 && $0.allSatisfy(\.isNumber) }
                && (1...3).contains(parts[0].count)
            if thousands { s = parts.joined() }
            else if parts.count == 2, !s.contains(".") { s = parts.joined(separator: ".") }   // a decimal comma
            else { return nil }
        }
        return Double(s)
    }

    // MARK: Comparing

    private static func close(_ a: Double, _ b: Double) -> Bool {
        abs(a - b) <= max(1e-9, 1e-3 * max(abs(a), abs(b)))
    }

    /// Groups of values that share a value are one quantity written twice ("0.50" and "50%").
    private static func mergeOverlapping(_ groups: [[Double]]) -> [[Double]] {
        var merged: [[Double]] = []
        for group in groups {
            if let at = merged.firstIndex(where: { existing in existing.contains { e in group.contains { close(e, $0) } } }) {
                merged[at] += group
            } else {
                merged.append(group)
            }
        }
        return merged
    }
}
