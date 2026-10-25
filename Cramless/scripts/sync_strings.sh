#!/bin/bash
# Merges the strings the last build extracted into the String Catalogs, the way Xcode's editor does (a command-line
# build extracts them but doesn't write them back), then applies the English plural forms in docs/l10n/plurals.json
# and marks text that is never translated ("%@" from `.verbatim`). scripts/xc.sh runs it after every successful
# build or test run.
#
#   scripts/sync_strings.sh [derived-data folder]       default: build
set -eu
cd "$(dirname "$0")/.."
derived=${1:-build}
objects="$derived/Build/Intermediates.noindex/Cramless.build"
sync() {  # sync <catalog> <target>
  local data
  data=$(find "$objects"/*/"$2.build/Objects-normal/arm64" -name "*.stringsdata" 2>/dev/null | head -1000)
  [ -n "$data" ] || return 0
  # shellcheck disable=SC2086
  xcrun xcstringstool sync "$1" $(printf -- "--stringsdata %s " $data)
}
sync Cramless/Resources/Localizable.xcstrings Cramless
sync CramlessWidgets/Localizable.xcstrings CramlessWidgetsExtension

python3 - Cramless/Resources/Localizable.xcstrings CramlessWidgets/Localizable.xcstrings <<'PY'
import json, sys
plurals = {k: v for k, v in json.load(open("docs/l10n/plurals.json")).items() if not k.startswith("_")}
unit = lambda value: {"stringUnit": {"state": "translated", "value": value}}
for path in sys.argv[1:]:
    catalog = json.load(open(path))
    strings = catalog["strings"]
    for key, forms in plurals.items():
        if key not in strings:
            continue
        if "substitutions" in forms:
            subs = {name: {"argNum": s["argNum"], "formatSpecifier": s.get("formatSpecifier", "lld"),
                           "variations": {"plural": {"one": unit(s["one"]), "other": unit(s["other"])}}}
                    for name, s in forms["substitutions"].items()}
            english = {"stringUnit": unit(forms["value"])["stringUnit"], "substitutions": subs}
        else:
            english = {"variations": {"plural": {"one": unit(forms["one"]), "other": unit(forms["other"])}}}
        entry = strings[key]
        entry.setdefault("localizations", {})["en"] = english
    for key in ("%@", ""):
        if key in strings:
            strings[key]["shouldTranslate"] = False
    with open(path, "w") as f:
        json.dump(catalog, f, indent=2, ensure_ascii=False, sort_keys=True, separators=(",", " : "))
        f.write("\n")
PY
