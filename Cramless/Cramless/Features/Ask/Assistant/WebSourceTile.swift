import SwiftUI

/// How a website looks in a source chip: a coloured tile with its letter or a symbol, in the site's colours. Drawn here, not
/// fetched: asking a site for its icon would tell it what the student is researching. Sites the table doesn't know get a
/// tile in a calm colour from their name.
struct WebSourceBrand: Equatable {
    enum Glyph: Equatable {
        case letters(String, serif: Bool)
        case symbol(String)
    }

    var name: String
    var fill: Color
    var ink: Color
    var glyph: Glyph
    /// A white tile needs an outline to be seen on white.
    var outlined = false

    private static func make(_ name: String, _ hex: UInt32, _ glyph: Glyph, ink: Color = .white, outlined: Bool = false) -> WebSourceBrand {
        WebSourceBrand(name: name, fill: Color(hex: hex), ink: ink, glyph: glyph, outlined: outlined)
    }

    /// The known sites, by registrable domain (subdomains match too).
    private static let known: [(String, WebSourceBrand)] = [
        ("wikipedia.org", make("Wikipedia", 0xFFFFFF, .letters("W", serif: true), ink: .black, outlined: true)),
        ("wikibooks.org", make("Wikibooks", 0xFFFFFF, .letters("W", serif: true), ink: .black, outlined: true)),
        ("wikiversity.org", make("Wikiversity", 0xFFFFFF, .letters("W", serif: true), ink: .black, outlined: true)),
        ("britannica.com", make("Britannica", 0x15397A, .letters("B", serif: true))),
        ("khanacademy.org", make("Khan Academy", 0x14BF96, .symbol("leaf.fill"), ink: Color(hex: 0x0B1B33))),
        ("openstax.org", make("OpenStax", 0xF47B20, .symbol("book.closed.fill"), ink: Color(hex: 0x1D0E00))),
        ("libretexts.org", make("LibreTexts", 0x0B6FB4, .letters("L", serif: false))),
        ("ck12.org", make("CK-12", 0x1F9BD7, .letters("CK", serif: false))),
        ("mit.edu", make("MIT", 0xA31F34, .letters("MIT", serif: false))),
        ("stanford.edu", make("Stanford", 0x8C1515, .letters("S", serif: true))),
        ("harvard.edu", make("Harvard", 0xA51C30, .letters("H", serif: true))),
        ("yale.edu", make("Yale", 0x00356B, .letters("Y", serif: true))),
        ("princeton.edu", make("Princeton", 0xF58025, .letters("P", serif: true), ink: Color(hex: 0x1D0E00))),
        ("cornell.edu", make("Cornell", 0xB31B1B, .letters("C", serif: true))),
        ("berkeley.edu", make("UC Berkeley", 0x003262, .letters("B", serif: true))),
        ("ox.ac.uk", make("Oxford", 0x002147, .letters("O", serif: true))),
        ("cam.ac.uk", make("Cambridge", 0x4B7F68, .letters("C", serif: true))),
        ("nih.gov", make("NIH", 0x20558A, .letters("NIH", serif: false))),
        ("medlineplus.gov", make("MedlinePlus", 0x1B5F8C, .symbol("cross.case.fill"))),
        ("cdc.gov", make("CDC", 0x005EAA, .letters("CDC", serif: false))),
        ("who.int", make("WHO", 0x0093D5, .letters("WHO", serif: false))),
        ("nasa.gov", make("NASA", 0x0B3D91, .symbol("sparkles"))),
        ("noaa.gov", make("NOAA", 0x0085CA, .symbol("cloud.sun.fill"))),
        ("usgs.gov", make("USGS", 0x006F41, .letters("USGS", serif: false))),
        ("nist.gov", make("NIST", 0x1D3F6E, .letters("NIST", serif: false))),
        ("energy.gov", make("Energy.gov", 0x1F5A8A, .symbol("bolt.fill"))),
        ("epa.gov", make("EPA", 0x2E7D32, .symbol("leaf.fill"))),
        ("loc.gov", make("Library of Congress", 0x1D3557, .symbol("building.columns.fill"))),
        ("archives.gov", make("National Archives", 0x5B2C2C, .symbol("building.columns.fill"))),
        ("si.edu", make("Smithsonian", 0x1E5AA8, .letters("SI", serif: false))),
        ("nature.com", make("Nature", 0xC8102E, .letters("N", serif: true))),
        ("mayoclinic.org", make("Mayo Clinic", 0x0B2D5C, .letters("M", serif: false))),
        ("clevelandclinic.org", make("Cleveland Clinic", 0x0071BC, .letters("CC", serif: false))),
        ("law.cornell.edu", make("Legal Information Institute", 0xB31B1B, .symbol("scale.3d"))),
        ("worldbank.org", make("World Bank", 0x009FDA, .symbol("globe.europe.africa.fill"))),
        ("imf.org", make("IMF", 0x00539F, .letters("IMF", serif: false))),
        ("oecd.org", make("OECD", 0x0B3C5D, .letters("OECD", serif: false))),
        ("un.org", make("United Nations", 0x009EDB, .symbol("globe"))),
        ("investopedia.com", make("Investopedia", 0x0B5E2F, .letters("I", serif: true))),
        ("merriam-webster.com", make("Merriam-Webster", 0xC8102E, .letters("M", serif: true))),
        ("cambridge.org", make("Cambridge Dictionary", 0x4B7F68, .letters("C", serif: true))),
        ("mozilla.org", make("MDN", 0x0B1F3A, .letters("MDN", serif: false))),
        ("python.org", make("Python", 0x3776AB, .symbol("chevron.left.forwardslash.chevron.right"))),
        ("wolfram.com", make("Wolfram MathWorld", 0xDD1100, .symbol("function"))),
        ("gsu.edu", make("HyperPhysics", 0x0039A6, .letters("HP", serif: false))),
        ("chemguide.co.uk", make("Chemguide", 0x00796B, .symbol("flask.fill"))),
    ]

    private static let calm: [(UInt32, UInt32)] = [
        (0x7CC8FF, 0x0B1B33), (0x22C38E, 0x06241B), (0xFFCF3F, 0x2A2000), (0xFF9A4D, 0x2A1100), (0xB59CFF, 0x1A1033),
    ]

    /// The brand for a host such as "en.wikipedia.org" or "www.britannica.com".
    static func brand(for host: String) -> WebSourceBrand {
        let domain = host.lowercased().replacingOccurrences(of: "www.", with: "")
        if let hit = known.first(where: { domain == $0.0 || domain.hasSuffix("." + $0.0) }) { return hit.1 }
        let word = domain.split(separator: ".").dropLast().last.map(String.init) ?? domain
        let pick = calm[Int(AssistantDrafts.seed(word) % UInt64(calm.count))]
        return WebSourceBrand(name: domain, fill: Color(hex: pick.0), ink: Color(hex: pick.1),
                              glyph: .letters(String(word.prefix(1)).uppercased(), serif: false))
    }
}

/// The site's tile: its letter or symbol on its colour.
struct WebSourceTile: View {
    let domain: String
    var size: CGFloat = 36

    var body: some View {
        let brand = WebSourceBrand.brand(for: domain)
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).fill(brand.fill)
            if brand.outlined {
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).strokeBorder(CLColor.night.opacity(0.14), lineWidth: 1)
            }
            switch brand.glyph {
            case .letters(let text, let serif):
                Text(text)
                    .font(.system(size: size * (text.count > 2 ? 0.28 : text.count == 2 ? 0.36 : 0.5), weight: .heavy,
                                  design: serif ? .serif : .rounded))
                    .foregroundStyle(brand.ink)
                    .minimumScaleFactor(0.6)
            case .symbol(let name):
                Image(systemName: name)
                    .font(.system(size: size * 0.48, weight: .bold))
                    .foregroundStyle(brand.ink)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A page the research found or cites: its tile, its title (else the site) and, below, the site. A link to the page.
struct WebSourceChip: View {
    let source: WebSource
    var cited = false

    var body: some View {
        let brand = WebSourceBrand.brand(for: source.domain)
        let label = Group {
            HStack(spacing: 9) {
                WebSourceTile(domain: source.domain, size: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(source.title ?? brand.name)
                        .clFont(.footnoteEmphasis)
                        .foregroundStyle(CLColor.ink)
                        .lineLimit(1)
                    Text(brand.name == source.domain ? source.domain : "\(brand.name) · \(source.domain)")
                        .clFont(.caption)
                        .foregroundStyle(CLColor.ink3)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .bold)).foregroundStyle(CLColor.ink4)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(minHeight: CLMetrics.minHitTarget)
            .background(cited ? CLColor.skySoft : CLColor.surface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        if let url = URL(string: source.url), url.scheme == "https" {
            Link(destination: url) { label }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("\(source.title ?? brand.name), \(source.domain)"))
                .accessibilityHint(Text("Opens the page in Safari"))
        } else {
            label
        }
    }
}
