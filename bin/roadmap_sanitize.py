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


def _safe_href(value: str) -> str | None:
    v = (value or "").strip()
    if v.startswith("#"):
        return v
    if v.lower().startswith(_SAFE_URL_SCHEMES):
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


class _Sanitizer(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.parts: list[str] = []

    def handle_starttag(self, tag, attrs):
        tag = tag.lower()
        if tag not in ALLOWED_TAGS:
            return  # unwrap: drop the tag, keep its children's text
        attr_str = _clean_attrs(tag, attrs)
        if tag in VOID_TAGS:
            self.parts.append(f"<{tag}{attr_str}>")
        else:
            self.parts.append(f"<{tag}{attr_str}>")

    def handle_startendtag(self, tag, attrs):
        tag = tag.lower()
        if tag not in ALLOWED_TAGS:
            return
        attr_str = _clean_attrs(tag, attrs)
        self.parts.append(f"<{tag}{attr_str}>")

    def handle_endtag(self, tag):
        tag = tag.lower()
        if tag not in ALLOWED_TAGS or tag in VOID_TAGS:
            return
        self.parts.append(f"</{tag}>")

    def handle_data(self, data):
        self.parts.append(escape(data, quote=False))

    def result(self) -> str:
        return "".join(self.parts)


def sanitize_notes(html: str | None) -> str:
    """Return `html` reduced to the whitelist; '' for falsy/empty input."""
    if not html:
        return ""
    parser = _Sanitizer()
    parser.feed(html)
    parser.close()
    return parser.result().strip()
