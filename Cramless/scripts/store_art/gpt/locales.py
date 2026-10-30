"""The words of Capling's header and Search card, for every App Store Connect language, and the font each script is set in.

Written 2026-10-30 by Claude, NOT by native speakers: every row is a draft for a native read before the listing goes in for review. The
art re-renders in seconds from this table (directions.py poster, build_locales_page.py), so a fix is one edit here.

Per language: `lines` the two-line headline (the app's own "A little every day. Ready on exam day.", kept to two short lines so the type
can be big), `label` the word under the 78% in the ring, and the three strings on the white cards, which mirror the real result screen
("Chem 110 Quiz", "42% → 78% ready · 2 days left", "On track for 80%"). Where a language marks gender the ring and cards use a neutral
form; the headline uses the usual generic form and says so in `note`. These strings should become the app's own when it is localized
(Localizable.xcstrings holds only English today), so the store and the app say the same thing.
`rtl` sets the picture right to left (the layout mirrors); `pct_prefix` writes %78 (Turkish).
"""
import glob
import os
import unicodedata

from PIL import ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))

L = dict


def _row(name, native, script, lines, label, title, sub, track, rtl=False, pct_prefix=False, note="", ocr=None):
    return dict(name=name, native=native, script=script, lines=lines, label=label, title=title, sub=sub, track=track, rtl=rtl,
                pct_prefix=pct_prefix, note=note, ocr=ocr)


# code: App Store Connect locale. ocr: the Vision languages to read the picture back with (None: Vision cannot read this language).
LOCALES = {
    "en-US": _row("English (U.S.)", "English", "latin", ["Ready on", "exam day."], "ready", "Chem 110 Quiz",
                  "42% → 78% ready · 2 days left", "On track for 80%", ocr=["en-US"]),
    "ar-SA": _row("Arabic", "العربية", "ar", ["جاهز في", "يوم الامتحان."], "جاهزية", "اختبار الكيمياء 110",
                  "42% ← 78% · تبقى يومان", "في طريقك إلى \u200e80%", rtl=True,
                  note="Masculine generic headline; Western digits; the arrow points left for right-to-left reading; an invisible left-to-right mark keeps the percent sign right of 80.",
                  ocr=["ar-SA"]),
    "ca": _row("Catalan", "Català", "latin", ["A punt per a", "l'examen."], "a punt", "Control de Química 110",
               "42 % → 78 % · queden 2 dies", "En camí cap al 80 %", note="Invariable \"a punt\", so no gender; space before % (IEC).", ocr=["en-US"]),
    "zh-Hans": _row("Chinese (Simplified)", "简体中文", "zh-Hans", ["考试当天，", "准备就绪。"], "就绪", "化学110 小测",
                    "42% → 78% · 还剩 2 天", "有望达到 80%", ocr=["zh-Hans"]),
    "zh-Hant": _row("Chinese (Traditional)", "繁體中文", "zh-Hant", ["考試當天，", "準備就緒。"], "就緒", "化學110 小考",
                    "42% → 78% · 還剩 2 天", "有望達到 80%", ocr=["zh-Hant"]),
    "hr": _row("Croatian", "Hrvatski", "latin", ["Spreman za", "ispit."], "spremno", "Test iz kemije 110",
               "42 % → 78 % · još 2 dana", "Na putu do 80 %", note="Masculine generic headline; space before % (Croatian norm).", ocr=["en-US"]),
    "cs": _row("Czech", "Čeština", "latin", ["Připraven", "na zkoušku."], "připraveno", "Test z chemie 110",
               "42 % → 78 % · zbývají 2 dny", "Na cestě k 80 %", note="Masculine generic.", ocr=["cs-CZ"]),
    "da": _row("Danish", "Dansk", "latin", ["Klar til", "eksamen."], "klar", "Kemi 110-quiz",
               "42 % → 78 % · 2 dage tilbage", "På vej mod 80 %", ocr=["da-DK"]),
    "nl-NL": _row("Dutch", "Nederlands", "latin", ["Klaar voor", "je examen."], "klaar", "Toets scheikunde 110",
                  "42% → 78% · nog 2 dagen", "Op koers voor 80%", ocr=["nl-NL"]),
    "fi": _row("Finnish", "Suomi", "latin", ["Valmiina", "kokeeseen."], "valmis", "Kemia 110 -koe",
               "42 % → 78 % · 2 päivää jäljellä", "Matkalla kohti 80 %", ocr=["en-US"]),
    "fr-FR": _row("French", "Français", "latin", ["Prêt le", "jour J."], "prêt", "Contrôle de chimie 110",
                  "42 % → 78 % · 2 jours restants", "En route vers les 80 %",
                  note="\"Le jour J\" is the idiom for the big day; masculine generic.", ocr=["fr-FR"]),
    "fr-CA": _row("French (Canada)", "Français (Canada)", "latin", ["Prêt le", "jour J."], "prêt", "Quiz de chimie 110",
                  "42 % → 78 % · 2 jours restants", "En route vers les 80 %", note="Quebec says \"quiz\" for a class quiz.", ocr=["fr-FR"]),
    "de-DE": _row("German", "Deutsch", "latin", ["Bereit zur", "Prüfung."], "bereit", "Test Chemie 110",
                  "42 % → 78 % bereit · noch 2 Tage", "Auf dem Weg zu 80 %", note="\"Ready for the exam\": the literal line is too long to set big.",
                  ocr=["de-DE"]),
    "el": _row("Greek", "Ελληνικά", "greek", ["Έτοιμος για", "τις εξετάσεις."], "έτοιμο", "Τεστ Χημείας 110",
               "42% → 78% · απομένουν 2 ημέρες", "Σε καλό δρόμο για το 80%", note="Masculine generic.", ocr=None),
    "he": _row("Hebrew", "עברית", "he", ["מוכנים", "ליום המבחן."], "מוכנות", "בוחן כימיה 110",
               "42% ← 78% · נותרו יומיים", "בדרך ל-80%", rtl=True, note="Plural generic in the headline.", ocr=None),
    "hi": _row("Hindi", "हिन्दी", "hi", ["परीक्षा के दिन", "पूरी तैयारी।"], "तैयार", "रसायन 110 क्विज़",
               "42% → 78% · 2 दिन बाकी", "80% की राह पर", ocr=None),
    "hu": _row("Hungarian", "Magyar", "latin", ["Készen állsz", "a vizsgára."], "kész", "Kémia 110 teszt",
               "42% → 78% · még 2 nap", "Úton a 80% felé", ocr=["en-US"]),
    "id": _row("Indonesian", "Bahasa Indonesia", "latin", ["Siap di hari", "ujian."], "siap", "Kuis Kimia 110",
               "42% → 78% · sisa 2 hari", "Sesuai target 80%", ocr=["id-ID"]),
    "it": _row("Italian", "Italiano", "latin", ["Pronto per", "l'esame."], "pronto", "Quiz di Chimica 110",
               "42% → 78% · mancano 2 giorni", "Verso l'80%", note="Masculine generic.", ocr=["it-IT"]),
    "ja": _row("Japanese", "日本語", "ja", ["試験当日、", "準備万端。"], "準備OK", "化学110 小テスト",
               "42% → 78% · あと2日", "80%に向けて順調", ocr=["ja-JP"]),
    "ko": _row("Korean", "한국어", "ko", ["시험 날엔", "준비 완료."], "준비 완료", "화학 110 퀴즈",
               "42% → 78% · 2일 남음", "80% 목표 순항 중", ocr=["ko-KR"]),
    "ms": _row("Malay", "Bahasa Melayu", "latin", ["Sedia untuk", "peperiksaan."], "sedia", "Kuiz Kimia 110",
               "42% → 78% · baki 2 hari", "Menuju sasaran 80%", ocr=["ms-MY"]),
    "no": _row("Norwegian", "Norsk", "latin", ["Klar for", "eksamen."], "klar", "Kjemi 110-quiz",
               "42 % → 78 % · 2 dager igjen", "På vei mot 80 %", ocr=["no-NO"]),
    "pl": _row("Polish", "Polski", "latin", ["Gotowy na", "egzamin."], "gotowości", "Kartkówka z chemii 110",
               "42% → 78% · zostały 2 dni", "Na dobrej drodze do 80%", note="Masculine generic.", ocr=["pl-PL"]),
    "pt-BR": _row("Portuguese (Brazil)", "Português (Brasil)", "latin", ["Pronto para", "a prova."], "pronto", "Teste de Química 110",
                  "42% → 78% · faltam 2 dias", "Rumo aos 80%", note="Masculine generic.", ocr=["pt-BR"]),
    "pt-PT": _row("Portuguese (Portugal)", "Português (Portugal)", "latin", ["Pronto para", "o exame."], "pronto", "Teste de Química 110",
                  "42% → 78% · faltam 2 dias", "A caminho dos 80%", note="Masculine generic.", ocr=["pt-BR"]),
    "ro": _row("Romanian", "Română", "latin", ["Gata de", "examen."], "gata", "Test de Chimie 110",
               "42% → 78% · încă 2 zile", "Pe drumul spre 80%", note="Invariable \"gata\", so no gender.", ocr=["ro-RO"]),
    "ru": _row("Russian", "Русский", "cyrillic", ["Готовы к", "экзамену."], "готовности", "Тест по химии 110",
               "42% → 78% · осталось 2 дня", "На пути к 80%", note="Plural \"you\" (gender-neutral); the ring says \"78% of readiness\".", ocr=["ru-RU"]),
    "sk": _row("Slovak", "Slovenčina", "latin", ["Pripravený", "na skúšku."], "pripravené", "Test z chémie 110",
               "42 % → 78 % · zostávajú 2 dni", "Na ceste k 80 %", note="Masculine generic.", ocr=["en-US"]),
    "es-MX": _row("Spanish (Mexico)", "Español (México)", "latin", ["Listo para", "tu examen."], "listo", "Quiz de Química 110",
                  "42% → 78% · faltan 2 días", "Rumbo al 80%", note="Masculine generic.", ocr=["es-ES"]),
    "es-ES": _row("Spanish (Spain)", "Español (España)", "latin", ["Listo para", "el examen."], "listo", "Control de Química 110",
                  "42 % → 78 % · quedan 2 días", "En camino al 80 %", note="Masculine generic.", ocr=["es-ES"]),
    "sv": _row("Swedish", "Svenska", "latin", ["Redo för", "provet."], "redo", "Kemi 110-quiz",
               "42 % → 78 % · 2 dagar kvar", "På väg mot 80 %", ocr=["sv-SE"]),
    "th": _row("Thai", "ไทย", "th", ["พร้อมสอบ", "ในวันจริง"], "พร้อม", "แบบทดสอบเคมี 110",
               "42% → 78% · เหลืออีก 2 วัน", "ตามเป้า 80%", note="\"Ready to sit it, on the real day\": the idiomatic form.", ocr=["th-TH"]),
    "tr": _row("Turkish", "Türkçe", "latin", ["Sınav günü", "hazırsın."], "hazır", "Kimya 110 Sınavı",
               "%42 → %78 hazır · 2 gün kaldı", "%80 hedefine doğru", pct_prefix=True,
               note="Informal \"you\", as in the app's voice; the percent sign comes first in Turkish.", ocr=["tr-TR"]),
    "uk": _row("Ukrainian", "Українська", "cyrillic", ["Готові до", "іспиту."], "готовності", "Тест з хімії 110",
               "42% → 78% · залишилось 2 дні", "На шляху до 80%", note="Plural \"you\" (gender-neutral); the ring says \"78% of readiness\".", ocr=["uk-UA"]),
    "vi": _row("Vietnamese", "Tiếng Việt", "latin", ["Sẵn sàng cho", "ngày thi."], "sẵn sàng", "Bài kiểm tra Hóa 110",
               "42% → 78% · còn 2 ngày", "Đúng tiến độ đạt 80%", ocr=["vi-VT"]),
}

# Languages that use another language's picture as they are (English has no regional wording here).
REUSE = {"en-AU": "en-US", "en-CA": "en-US", "en-GB": "en-US"}


# ---- type: one heavy face per script (the Latin one is the brand's own Bricolage) ---------------------------------------------

BRICOLAGE = os.path.join(REPO, "Cramless", "Resources", "Fonts", "BricolageGrotesque-Display.ttf")
SYS = "/System/Library/Fonts"


def sysfont(name, folder=SYS):
    """A file in a system font folder by its name (macOS keeps Japanese file names in a different Unicode form than a source file)."""
    want = unicodedata.normalize("NFC", name)
    for p in glob.glob(os.path.join(folder, "*")):
        if unicodedata.normalize("NFC", os.path.basename(p)) == want:
            return p
    raise FileNotFoundError(f"{name} in {folder}")


def spec(path, index=0, var=None, stroke=0.0):
    return dict(path=path, index=index, var=var, stroke=stroke)


def _hira(w):
    return spec(sysfont(f"ヒラギノ角ゴシック W{w}.ttc"))


SFNS = os.path.join(SYS, "SFNS.ttf")
SF_ROUNDED_BLACK = "/Library/Fonts/SF-Pro-Rounded-Black.otf"
_cyr = dict(head=spec(SF_ROUNDED_BLACK if os.path.exists(SF_ROUNDED_BLACK) else SFNS, var=None if os.path.exists(SF_ROUNDED_BLACK) else "Black"),
            semi=spec(SFNS, var="Semibold"), reg=spec(SFNS, var="Regular"))

FONTS = {
    "latin": dict(head=spec(BRICOLAGE), semi=spec(SFNS, var="Semibold"), reg=spec(SFNS, var="Regular")),
    "cyrillic": _cyr,
    "greek": _cyr,
    "ja": dict(head=_hira(8), semi=_hira(6), reg=_hira(3)),
    "zh-Hant": dict(head=_hira(8), semi=_hira(6), reg=_hira(3)),
    "zh-Hans": dict(head=spec(os.path.join(SYS, "Hiragino Sans GB.ttc"), 2, stroke=0.014), semi=spec(os.path.join(SYS, "Hiragino Sans GB.ttc"), 2),
                    reg=spec(os.path.join(SYS, "Hiragino Sans GB.ttc"), 0)),
    "ko": dict(head=spec(os.path.join(SYS, "AppleSDGothicNeo.ttc"), 16), semi=spec(os.path.join(SYS, "AppleSDGothicNeo.ttc"), 4),
               reg=spec(os.path.join(SYS, "AppleSDGothicNeo.ttc"), 0)),
    "th": dict(head=spec(os.path.join(SYS, "Supplemental", "Thonburi.ttc"), 1), semi=spec(os.path.join(SYS, "Supplemental", "Thonburi.ttc"), 1),
               reg=spec(os.path.join(SYS, "Supplemental", "Thonburi.ttc"), 0)),
    # the SF Arabic and Hebrew faces have no Western digits, and a right-to-left line cannot be split across fonts, so the small text uses
    # Arial (Arabic, Hebrew, digits and the arrow in one face)
    "ar": dict(head=spec(os.path.join(SYS, "SFArabicRounded.ttf"), var="Heavy"), semi=spec(os.path.join(SYS, "Supplemental", "Arial Bold.ttf")),
               reg=spec(os.path.join(SYS, "Supplemental", "Arial.ttf"))),
    "he": dict(head=spec(os.path.join(SYS, "SFHebrewRounded.ttf"), var="Heavy"), semi=spec(os.path.join(SYS, "Supplemental", "Arial Bold.ttf")),
               reg=spec(os.path.join(SYS, "Supplemental", "Arial.ttf"))),
    "hi": dict(head=spec(os.path.join(SYS, "Kohinoor.ttc"), 3), semi=spec(os.path.join(SYS, "Kohinoor.ttc"), 2), reg=spec(os.path.join(SYS, "Kohinoor.ttc"), 0)),
}


def load(sp, px):
    """An ImageFont for a font spec at a size (a variable font takes its named weight)."""
    f = ImageFont.truetype(sp["path"], max(1, int(round(px))), index=sp["index"])
    if sp["var"]:
        f.set_variation_by_name(sp["var"])
    return f


def text_kw(code):
    """What Raqm needs to shape a right-to-left line."""
    return dict(direction="rtl", language=code.split("-")[0]) if LOCALES[code]["rtl"] else {}


_CMAPS = {}


def cmap_of(sp):
    """The set of code points a font spec has a glyph for."""
    key = (sp["path"], sp["index"])
    if key not in _CMAPS:
        from fontTools.ttLib import TTFont
        p = sp["path"]
        tt = TTFont(p, fontNumber=sp["index"], lazy=True) if p.lower().endswith((".ttc", ".otc")) else TTFont(p, lazy=True)
        _CMAPS[key] = set(tt.getBestCmap().keys())
    return _CMAPS[key]


# The face that fills in a character the language's own small-text font lacks (the arrow, the middle dot, digits).
FALLBACK = {"semi": spec(SFNS, var="Semibold"), "reg": spec(SFNS, var="Regular")}


def runs(text, sp):
    """[[segment, covered]]: the text cut where the font spec starts or stops having a glyph (spaces go with their neighbours)."""
    cm = cmap_of(sp)
    out = []
    for ch in text:
        ok = ord(ch) in cm or ch.isspace()
        if out and out[-1][1] == ok:
            out[-1][0] += ch
        else:
            out.append([ch, ok])
    return out


def missing_glyphs(code):
    """Characters of a language's strings that neither its font nor the fallback has (a box would show): [] when everything is covered.
    The headline and a right-to-left line get no fallback: they are set in one face."""
    row = LOCALES[code]
    F = FONTS[row["script"]]
    need = [("head", t) for t in row["lines"]] + [("semi", row["title"]), ("reg", row["sub"]), ("semi", row["track"]), ("semi", row["label"])]
    out = set()
    for role, text in need:
        cm = cmap_of(F[role])
        fb = cmap_of(FALLBACK[role]) if role != "head" and not row["rtl"] else set()
        out |= {c for c in text if not c.isspace() and ord(c) not in cm and ord(c) not in fb}
    return sorted(out)
