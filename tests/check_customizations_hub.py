#!/usr/bin/env python3
"""Player Customizations reference check (build-time smoke test).

The player reference is split into hand-edited topic pages under
docs.manual/Customizations/ plus a hub, docs.manual/Customizations.html, that
bin/gen-customizations-hub.py generates from them (search index, cards, nav, and
the forwarding map for old links). This gate fails the build when:

  1. the hub or a topic page's generated cz: blocks are stale -- someone edited a
     topic page and did not re-run the generator, so search and nav disagree with it;
  2. an anchor that was ever published (tests/customizations_anchors.txt) no longer
     resolves -- every link anyone shared to Customizations.html#<it> would break;
  3. docs.manual/Customizations/LegendaryFeats.html no longer matches FEATS in
     bin/gen-legendary-feats.py -- a feat shipped (or changed) without its page;
  4. a link in this repo to Customizations.html#<anchor> (roadmap.yaml, the manual,
     an in-game string, the CLAUDE docs) points at an anchor that does not exist;
  5. a roadmap idea's `docs:` field names a page or anchor that does not exist.

The generators' own --check modes cover 1-3, so this gate and the tool can never
disagree about them.

Exits 0 on success, 1 on any failure.
"""
import importlib.util
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("gen_cz", ROOT / "bin" / "gen-customizations-hub.py")
gen = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gen)

# Where links into the reference live. docs/ is the generated wiki (stale by design), so
# it is not scanned; its source (docs.manual/) is.
SCAN = ["roadmap.yaml", "docs.manual/**/*.html", "unpacked/*.nss", "unpacked/*.dlg.json",
        "unpacked/module.jrl.json", "CLAUDE*.md", "QuestGuide-DM-Notes.md"]
RE_LINK = re.compile(r"Customizations\.html#([A-Za-z0-9_-]+)")


def bad_docs_fields(amap: dict) -> list[str]:
    """Every roadmap `docs:` value that does not resolve to a real page + anchor."""
    import yaml
    manual = ROOT / "docs.manual"
    out = []
    for idea in (yaml.safe_load((ROOT / "roadmap.yaml").read_text(encoding="utf-8"))
                 .get("ideas") or []):
        docs = idea.get("docs")
        if docs is None or docs == "none":
            continue
        where = f"roadmap.yaml '{idea.get('id')}': docs {docs!r}"
        page, _, anchor = str(docs).partition("#")
        path = (manual / page).resolve()
        if ".." in page or manual.resolve() not in path.parents or not path.is_file():
            out.append(f"{where} -- no such page under docs.manual/")
        elif anchor and page == "Customizations.html":
            if anchor not in amap:
                out.append(f"{where} -- no such anchor")
        elif anchor and f'id="{anchor}"' not in path.read_text(encoding="utf-8"):
            out.append(f"{where} -- no such anchor on {page}")
    return out


def main() -> int:
    rc = gen.build(check=True)
    feats = subprocess.run([sys.executable, str(ROOT / "bin" / "gen-legendary-feats-doc.py"),
                            "--check"])
    rc = rc or feats.returncode

    amap = gen.anchor_map(gen.load_pages())
    broken = []
    for pattern in SCAN:
        for path in sorted(ROOT.glob(pattern)):
            if path == gen.HUB:
                continue
            text = path.read_text(encoding="utf-8", errors="replace")
            for m in RE_LINK.finditer(text):
                if m.group(1) not in amap:
                    line = text.count("\n", 0, m.start()) + 1
                    broken.append(f"{path.relative_to(ROOT)}:{line}: #{m.group(1)}")
    broken += bad_docs_fields(amap)
    if broken:
        print("customizations link check FAILED -- these links point at no anchor on any "
              "docs.manual/Customizations/ page (fix the link, or add the anchor):")
        for b in broken:
            print(f"  {b}")
        rc = 1
    elif rc == 0:
        print(f"customizations link check OK: every Customizations.html#anchor link resolves.")
    return rc


if __name__ == "__main__":
    sys.exit(main())
