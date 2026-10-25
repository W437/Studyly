#!/usr/bin/env python3
"""Renames the product (what people see, and the identifiers that become permanent) from one name to another.

    scripts/rename_brand.py Cramless Capling            dry run: what would change, file by file
    scripts/rename_brand.py Cramless Capling --apply    do it

What changes (the product's name):
  - words people read: "Cramless Pro", "Open Cramless", the wordmark, usage descriptions, widget and notification copy, String
    Catalog keys and values, StoreKit names;
  - identifiers that are permanent once an app is registered: bundle ids (com.loopware.<Name>[.Widgets|.pro.monthly|…]), the App Group,
    StoreKit product ids, the URL scheme (<name>://), the Squad link's domain (<name>.app), UserDefaults and notification key
    prefixes (<name>.…), export file names.
What stays (the code name, which nobody sees): the module, targets, folders and file names (`Cramless/`, `CramlessTests`,
`Cramless.xcodeproj`, `Cramless.app`, `@testable import Cramless`), type names (`CramlessLink`), the DEBUG switches
(`CRAMLESS_UITEST` …), Info.plist keys read by the code (`CramlessSupabaseHost`), the backend's own names (`cramless_squad_invite`,
the local stack's containers).

Swift, catalogs, plists, entitlements, StoreKit and the backend's TypeScript get every rule; scripts and docs get only the identifier
rules (so a doc that says `Cramless/App/…` isn't turned into a path that doesn't exist). project.yml gets only its bundle ids.
Run from the Cramless folder. Nothing outside it is touched.
"""
import re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def rules(old, new):
    old_l, new_l, old_u, new_u = old.lower(), new.lower(), old.upper(), new.upper()

    def identifiers(text):
        text = text.replace(f"com.loopware.{old}", f"com.loopware.{new}")
        text = text.replace(f"{old_l}://", f"{new_l}://").replace(f"{old_u}://", f"{new_u}://")
        text = re.sub(rf"(?<![A-Za-z0-9_])https?://{old_l}\.app", f"https://{new_l}.app", text)
        text = re.sub(rf"(?<![A-Za-z0-9_/.\-]){old_l}\.app(?=/|\b)", f"{new_l}.app", text)
        text = text.replace(f"@{old_l}.test", f"@{new_l}.test")
        return text

    def prose(text):
        text = identifiers(text)
        # keys and prefixes: cramless.study, cramless.capTouch.bag, cramless-export
        text = re.sub(rf"(?<![A-Za-z0-9_/.\-]){old_l}\.(?=[a-z])", f"{new_l}.", text)
        text = text.replace(f"{old_l}-export", f"{new_l}-export").replace(f'"{old_l}."', f'"{new_l}."')
        # the wordmark and the URL scheme as exact strings (not the local backend's project id, which names its containers)
        text = "\n".join(line if "project_id" in line else line.replace(f'"{old_l}"', f'"{new_l}"').replace(f"<string>{old_l}</string>", f"<string>{new_l}</string>")
                         for line in text.split("\n"))
        # the code name stays where code names a module
        text = text.replace(f"import {old}", "import \u0001MODULE\u0001")
        # the product's name in words: not part of a longer name, a path, a file name, a module-qualified reference, a header or a switch
        text = re.sub(rf"(?<![A-Za-z0-9_/.\-]){old}(?![A-Za-z0-9_/\-]|\.[A-Za-z])", new, text)
        text = re.sub(rf"(?<![A-Za-z0-9_/.\-]){old_u}(?![A-Za-z0-9_])", new_u, text)
        return text.replace("\u0001MODULE\u0001", old)

    return identifiers, prose


def files(patterns):
    seen = []
    for pattern in patterns:
        for p in sorted(ROOT.glob(pattern)):
            if p.is_file() and not any(part in ("build", "node_modules", "DerivedData", "Cramless.xcodeproj") or part.startswith("build-") for part in p.relative_to(ROOT).parts):
                if p not in seen:
                    seen.append(p)
    return seen


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 2:
        sys.exit(__doc__)
    old, new = args
    apply = "--apply" in sys.argv
    identifiers, prose = rules(old, new)

    full = files(["Cramless/**/*.swift", "Shared/**/*.swift", "CramlessWidgets/**/*.swift", "CramlessTests/**/*.swift",
                  "Cramless/Resources/*.xcstrings", "CramlessWidgets/*.xcstrings", "Shared/*.xcstrings", "Shared/**/*.xcstrings",
                  "Cramless/Resources/Info.plist", "CramlessWidgets/Info.plist", "Cramless/Resources/*.entitlements",
                  "CramlessWidgets/*.entitlements", "*.storekit",
                  "supabase/functions/**/*.ts", "supabase/functions/**/*.json", "supabase/functions/.env.example", "supabase/tests/**/*.sql"])
    ids = files(["scripts/**/*.sh", "scripts/**/*.py", "scripts/**/*.swift", "docs/**/*.md", "README.md", "CLAUDE.md", "supabase/**/*.md"])
    ids = [p for p in ids if p not in full and p.name != "rename_brand.py"]

    changed = 0
    report = []
    for kind, group, fn in (("all rules", full, prose), ("identifiers", ids, identifiers)):
        for p in group:
            try:
                before = p.read_text()
            except UnicodeDecodeError:
                continue
            after = fn(before)
            if after != before:
                changed += 1
                lines = [(a.strip(), b.strip()) for a, b in zip(before.splitlines(), after.splitlines()) if a != b]
                report.append((p.relative_to(ROOT), kind, len(lines), lines[:2]))
                if apply:
                    p.write_text(after)

    # project.yml: only the bundle ids
    yml = ROOT / "project.yml"
    text = yml.read_text()
    out = []
    n = 0
    for line in text.splitlines(keepends=True):
        if "PRODUCT_BUNDLE_IDENTIFIER" in line and f"com.loopware.{old}" in line:
            line = line.replace(f"com.loopware.{old}", f"com.loopware.{new}")
            n += 1
        out.append(line)
    if n:
        changed += 1
        report.append((Path("project.yml"), "bundle ids", n, []))
        if apply:
            yml.write_text("".join(out))

    for path, kind, count, samples in sorted(report, key=lambda r: str(r[0])):
        print(f"{str(path):70} {kind:12} {count:4} line(s)")
    print(f"\n{changed} file(s) {'changed' if apply else 'would change'}")
    if not apply:
        print("\nsamples (first two changed lines of a few files):")
        for path, kind, count, samples in report[:0]:
            pass
        shown = 0
        for path, kind, count, samples in sorted(report, key=lambda r: -r[2]):
            for a, b in samples[:1]:
                print(f"  {path}\n    - {a[:150]}\n    + {b[:150]}")
            shown += 1
            if shown >= 12:
                break


if __name__ == "__main__":
    main()
