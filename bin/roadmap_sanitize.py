"""Whitelist sanitizer for roadmap idea `notes` (trusted-but-pasted author HTML).

`notes` is rich text typed (or pasted) into the roadmap editor's contenteditable
widget. A paste from Discord drags in that app's entire DOM — chrome classes,
`aria-*`/`data-*` attributes, bare `<li>` outside any list, remote emoji `<img>`
— which mangles the generated Roadmap.html when injected verbatim.

`sanitize_notes()` keeps a small whitelist of formatting tags and safe
attributes, drops everything else (unwrapping unknown tags so their text
survives), and HTML-escapes text. It runs both at save time (so roadmap.yaml
stays clean) and at build time in gen-roadmap.py (last line of defense).

Stdlib only — no `bleach`/`lxml` dependency.
"""
from __future__ import annotations

import re
from html import escape
from html.parser import HTMLParser

# Tags we keep. Anything else is unwrapped (dropped, text content preserved).
ALLOWED_TAGS = {
    "a", "b", "strong", "i", "em", "u", "ul", "ol", "li",
    "p", "br", "hr", "div", "span", "font", "img", "blockquote",
}

# Tags that never have a closing tag / take no children.
VOID_TAGS = {"br", "hr", "img"}

# Per-tag attribute whitelist. Tags absent here keep no attributes.
ALLOWED_ATTRS = {
    "a": {"href", "target", "rel"},
    "font": {"color"},
    "img": {"src", "alt", "width", "height"},
}

_SAFE_URL_SCHEMES = ("http://", "https://", "mailto:")

# A sibling manual page, optionally with an anchor — e.g. "QuestGuide.html#gloison".
# Roadmap.html is copied into docs/manual/ alongside the other manual pages, so a
# bare filename resolves correctly both there and in docs.manual/. Deliberately
# no path separators: '/' would allow protocol-relative "//evil.com", and '..'
# would escape the manual directory.
_REL_PAGE = re.compile(r"^[A-Za-z0-9._-]+\.html(#[\w-]+)?$")


def _safe_href(value: str) -> str | None:
    v = (value or "").strip()
    if v.startswith("#"):
        return v
    if v.lower().startswith(_SAFE_URL_SCHEMES):
        return v
    if ".." not in v and _REL_PAGE.match(v):
        return v
    return None


def _safe_src(value: str) -> str | None:
    v = (value or "").strip()
    return v if v.lower().startswith(("http://", "https://")) else None


def _clean_attrs(tag: str, attrs: list[tuple[str, str | None]]) -> str:
    allowed = ALLOWED_ATTRS.get(tag)
    if not allowed:
        return ""
    out = []
    for name, value in attrs:
        name = name.lower()
        if name not in allowed:
            continue
        value = value or ""
        if tag == "a" and name == "href":
            value = _safe_href(value)
            if value is None:
                continue
        elif tag == "img" and name == "src":
            value = _safe_src(value)
            if value is None:
                continue
        out.append(f' {name}="{escape(value, quote=True)}"')
    return "".join(out)


# Tags that end an open <p> when they start, the way a browser does. Emitting
# the </p> ourselves keeps our output tree and the browser's identical.
BLOCK_TAGS = {"div", "p", "ul", "ol", "blockquote", "hr"}
LIST_TAGS = {"ul", "ol"}


class _Sanitizer(HTMLParser):
    """Whitelist filter that also GUARANTEES a well-nested result.

    The whitelist alone is not enough, and a real page proved it: a Discord
    paste carried bare <li> elements sitting inside <div>s, with no list around
    them. `li` is on the whitelist, so they were emitted verbatim into the card
    template's own <li class="rm-item">. In the HTML5 parsing algorithm a <li>
    start tag CLOSES the open list item and everything inside it, so the card
    ended early and the trailing </div>s of the note went on to close the page's
    layout container: 168 of 192 cards escaped the content column and rendered
    as flex siblings of the sidebar. Nothing in the source looked wrong - the
    tags balance, and a lenient parser (html.parser, libxml2) rebuilds the tree
    the intended way. Only a browser diverges.

    So the parser keeps a stack and enforces three invariants:
      * a `li` outside any list is unwrapped (its content survives);
      * an end tag with no matching open tag is dropped, never emitted;
      * anything still open at the end is closed.
    Together those make the output well-nested by construction, which is what
    the page layout actually depends on.
    """

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.parts: list[str] = []
        self.stack: list[str] = []

    # -- helpers ----------------------------------------------------------
    def _close_through(self, tag: str) -> None:
        """Close `tag` and everything opened inside it."""
        while self.stack:
            top = self.stack.pop()
            self.parts.append(f"</{top}>")
            if top == tag:
                return

    def _open(self, tag: str, attrs) -> None:
        attr_str = _clean_attrs(tag, attrs)
        if tag in BLOCK_TAGS and "p" in self.stack:
            self._close_through("p")
        self.parts.append(f"<{tag}{attr_str}>")
        if tag not in VOID_TAGS:
            self.stack.append(tag)

    # -- HTMLParser hooks -------------------------------------------------
    def handle_starttag(self, tag, attrs):
        tag = tag.lower()
        if tag not in ALLOWED_TAGS:
            return  # unwrap: drop the tag, keep its children's text
        if tag == "li" and not (set(self.stack) & LIST_TAGS):
            return  # bare list item: unwrap it rather than break the page
        self._open(tag, attrs)

    def handle_startendtag(self, tag, attrs):
        tag = tag.lower()
        if tag not in ALLOWED_TAGS:
            return
        if tag == "li" and not (set(self.stack) & LIST_TAGS):
            return
        self.parts.append(f"<{tag}{_clean_attrs(tag, attrs)}>")

    def handle_endtag(self, tag):
        tag = tag.lower()
        if tag not in ALLOWED_TAGS or tag in VOID_TAGS:
            return
        if tag not in self.stack:
            return  # stray close: it would pop one of OUR containers instead
        self._close_through(tag)

    def handle_data(self, data):
        self.parts.append(escape(data, quote=False))

    def result(self) -> str:
        while self.stack:
            self.parts.append(f"</{self.stack.pop()}>")
        return "".join(self.parts)


def sanitize_notes(html: str | None) -> str:
    """Return `html` reduced to the whitelist; '' for falsy/empty input."""
    if not html:
        return ""
    parser = _Sanitizer()
    parser.feed(html)
    parser.close()
    return parser.result().strip()
