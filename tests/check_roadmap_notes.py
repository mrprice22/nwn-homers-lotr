#!/usr/bin/env python3
"""Build gate: idea `notes` must sanitize to WELL-NESTED html.

`notes` is rich text pasted into the roadmap editor, most often straight out of
Discord, and it lands inside the roadmap card template's own
`<li class="rm-item">`. bin/roadmap_sanitize.py whitelists the tags; this gate
checks the structural half, which a whitelist alone does not give you.

The failure it exists to catch actually shipped. A paste carried bare `<li>`
elements sitting inside `<div>`s with no list around them. `li` is on the
whitelist, so they went out verbatim - and in the HTML5 parsing algorithm a
`<li>` start tag closes the open list item, so each one ended the card early and
the note's trailing `</div>`s went on to close the page's layout container. 168
of 192 cards escaped the content column and rendered as flex siblings of the
sidebar. Nothing looked wrong in the source: the tags balance, and every lenient
parser (html.parser, libxml2) rebuilds the intended tree. Only a browser
diverges, so only a browser showed the bug.

Two checks, both cheap and stdlib-only:
  1. adversarial fixtures - the shapes a paste actually produces;
  2. every note in roadmap.yaml, sanitized, must come out well-nested.

Exit 0 = clean, 1 = a note (or the sanitizer) can break the page layout.
"""
from __future__ import annotations

import sys
from html.parser import HTMLParser
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "bin"))

from roadmap_sanitize import VOID_TAGS, sanitize_notes  # noqa: E402

import yaml  # noqa: E402

NOTE_FIELDS = ("notes", "impl_notes")

# (name, input) — each must sanitize to something well nested, and must not
# leave a list item outside a list.
FIXTURES = [
    ("bare li in a div", "<div><span>a</span><li><div>b</div></li></div>"),
    ("li with no list at all", "<li>one</li><li>two</li>"),
    ("stray closing tags", "text</div></div></li>"),
    ("unclosed div", "<div>text"),
    ("crossed tags", "<b>bold <i>both</b> italic</i>"),
    ("div inside p", "<p>one<div>two</div></p>"),
    ("real list survives", "<ul><li>keep</li></ul>"),
]


class _Nesting(HTMLParser):
    """Strict well-nestedness check: no stray end tag, nothing left open, and
    no `li` outside a list."""

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.stack: list[str] = []
        self.errors: list[str] = []

    def handle_starttag(self, tag, attrs):
        if tag in VOID_TAGS:
            return
        if tag == "li" and not ({"ul", "ol"} & set(self.stack)):
            self.errors.append("<li> outside any <ul>/<ol>")
        self.stack.append(tag)

    def handle_endtag(self, tag):
        if tag in VOID_TAGS:
            return
        if not self.stack or self.stack[-1] != tag:
            self.errors.append(f"</{tag}> does not close the open "
                               f"<{self.stack[-1] if self.stack else 'nothing'}>")
            return
        self.stack.pop()

    def close(self):
        super().close()
        if self.stack:
            self.errors.append("left open: " + ", ".join(self.stack))


def problems(html: str) -> list[str]:
    p = _Nesting()
    p.feed(html)
    p.close()
    return p.errors


def main() -> int:
    bad = 0

    for name, raw in FIXTURES:
        errs = problems(sanitize_notes(raw))
        if errs:
            bad += 1
            print(f"FAIL roadmap-notes: fixture {name!r}: {'; '.join(errs)}")

    doc = yaml.safe_load((REPO / "roadmap.yaml").read_text(encoding="utf-8")) or {}
    checked = 0
    for idea in (doc.get("ideas") or []) + (doc.get("epics") or []):
        for field in NOTE_FIELDS:
            raw = idea.get(field)
            if not raw:
                continue
            checked += 1
            errs = problems(sanitize_notes(raw))
            if errs:
                bad += 1
                print(f"FAIL roadmap-notes: {idea.get('id')}.{field}: "
                      f"{'; '.join(errs)}")

    if bad:
        print(f"FAIL roadmap-notes: {bad} problem(s) — a card can break the "
              "page layout in a browser. Fix bin/roadmap_sanitize.py.")
        return 1
    print(f"ok roadmap-notes: {len(FIXTURES)} fixtures + {checked} notes "
          "sanitize to well-nested html")
    return 0


if __name__ == "__main__":
    sys.exit(main())
