#!/usr/bin/env python3
"""Turns docs/privacy-wording.md into build/review/ask-cap-assistant/privacy.html: the same words as a page the owner can open on a
laptop or phone, with a button that copies the policy section. A small converter for the subset that file uses (headings, one
blockquote, tables, bullets, numbered lists, **bold**, `code`), because no markdown library is installed here.

    build_privacy_page.py
"""
import html
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "docs/privacy-wording.md"
OUT = ROOT / "build/review/ask-cap-assistant/privacy.html"


def inline(text: str) -> str:
    text = html.escape(text, quote=False)
    text = re.sub(r"`([^`]+)`", r"<code>\1</code>", text)
    text = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", text)
    return text


def table(rows: list[str]) -> str:
    cells = [[c.strip() for c in r.strip().strip("|").split("|")] for r in rows]
    head, body = cells[0], [r for r in cells[2:]]
    out = ["<div class=\"scroll\"><table><thead><tr>" + "".join(f"<th>{inline(c)}</th>" for c in head) + "</tr></thead><tbody>"]
    for r in body:
        out.append("<tr>" + "".join(f"<td>{inline(c)}</td>" for c in r) + "</tr>")
    out.append("</tbody></table></div>")
    return "".join(out)


def blocks(lines: list[str]) -> str:
    out, i = [], 0
    while i < len(lines):
        line = lines[i]
        if not line.strip():
            i += 1
        elif line.startswith("### "):
            out.append(f"<h3>{inline(line[4:])}</h3>")
            i += 1
        elif line.startswith("## "):
            out.append(f"<h2>{inline(line[3:])}</h2>")
            i += 1
        elif line.startswith("# "):
            out.append(f"<h1>{inline(line[2:])}</h1>")
            i += 1
        elif line.startswith("|"):
            j = i
            while j < len(lines) and lines[j].startswith("|"):
                j += 1
            out.append(table(lines[i:j]))
            i = j
        elif re.match(r"^(- |\d+\. )", line):
            ordered = bool(re.match(r"^\d+\. ", line))
            items, j = [], i
            while j < len(lines) and (re.match(r"^(- |\d+\. )", lines[j]) or (lines[j].startswith("  ") and items)):
                if re.match(r"^(- |\d+\. )", lines[j]):
                    items.append(re.sub(r"^(- |\d+\. )", "", lines[j]))
                else:
                    items[-1] += " " + lines[j].strip()
                j += 1
            tag = "ol" if ordered else "ul"
            out.append(f"<{tag}>" + "".join(f"<li>{inline(t)}</li>" for t in items) + f"</{tag}>")
            i = j
        else:
            j = i
            while j < len(lines) and lines[j].strip() and not re.match(r"^(#|\||- |\d+\. )", lines[j]):
                j += 1
            out.append(f"<p>{inline(' '.join(l.strip() for l in lines[i:j]))}</p>")
            i = j
    return "\n".join(out)


def main() -> None:
    lines = SRC.read_text().splitlines()
    out, i = [], 0
    while i < len(lines):
        if lines[i].startswith(">"):
            j = i
            while j < len(lines) and lines[j].startswith(">"):
                j += 1
            inner = [re.sub(r"^> ?", "", l) for l in lines[i:j]]
            out.append("<div class=\"policy\"><button type=\"button\" id=\"copy\">Copy this section</button>"
                       f"<blockquote id=\"policy\">{blocks(inner)}</blockquote></div>")
            i = j
        else:
            j = i
            while j < len(lines) and not lines[j].startswith(">"):
                j += 1
            out.append(blocks(lines[i:j]))
            i = j
    page = f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Privacy wording for Ask Cap</title>
<style>
:root {{ --bg:#fbfaf7; --ink:#1d2433; --ink2:#556070; --card:#fff; --line:#e3e0d8; --accent:#f77f1d; --code:#f1eee8; }}
@media (prefers-color-scheme: dark) {{ :root {{ --bg:#141a26; --ink:#eef0f4; --ink2:#a6afbf; --card:#1c2433; --line:#2c3547; --code:#243049; }} }}
body {{ margin:0; background:var(--bg); color:var(--ink); font:17px/1.55 -apple-system, system-ui, sans-serif; }}
main {{ max-width:760px; margin:0 auto; padding:24px 16px 80px; }}
h1 {{ font-size:28px; line-height:1.2; font-weight:700; }} h2 {{ font-size:21px; margin-top:36px; font-weight:700; }} h3 {{ font-size:18px; margin:18px 0 6px; font-weight:700; }}
strong, th {{ font-weight:700; }}
p, li {{ color:var(--ink); }} code {{ background:var(--code); padding:1px 5px; border-radius:5px; font-size:.9em; overflow-wrap:anywhere; }}
.policy {{ position:relative; margin:16px 0; }}
blockquote {{ margin:0; padding:14px 16px 6px; background:var(--card); border:1px solid var(--line); border-left:4px solid var(--accent); border-radius:10px; }}
#copy {{ position:absolute; top:-14px; right:10px; min-height:44px; padding:0 16px; border:0; border-radius:22px; background:var(--accent); color:#fff; font:600 15px system-ui; }}
.scroll {{ overflow-x:auto; margin:12px 0; }} table {{ border-collapse:collapse; width:100%; font-size:15px; }}
th, td {{ text-align:left; vertical-align:top; padding:8px 10px; border-bottom:1px solid var(--line); }} th {{ color:var(--ink2); font-weight:600; }}
.back {{ color:var(--ink2); font-size:15px; }}
</style></head><body><main>
<p class="back"><a href="./">&larr; Ask Cap review page</a></p>
{chr(10).join(out)}
</main>
<script>
document.getElementById('copy').addEventListener('click', function () {{
  var node = document.getElementById('policy'), text = node.innerText, button = this;
  function done(ok) {{ button.textContent = ok ? 'Copied' : 'Select the text and copy it'; setTimeout(function () {{ button.textContent = 'Copy this section'; }}, 2000); }}
  if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(text).then(function () {{ done(true); }}, function () {{ done(false); }});
  else {{ var r = document.createRange(); r.selectNodeContents(node); var s = getSelection(); s.removeAllRanges(); s.addRange(r); try {{ done(document.execCommand('copy')); }} catch (e) {{ done(false); }} }}
}});
</script></body></html>
"""
    OUT.write_text(page)
    print("wrote", OUT)


if __name__ == "__main__":
    main()
