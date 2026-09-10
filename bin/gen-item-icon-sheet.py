#!/usr/bin/env python3
"""gen-item-icon-sheet.py -- render a contact sheet of every inventory icon a
base item can wear, so you can PICK a ModelPart1 by looking at it.

The problem this exists to solve: a blueprint's appearance is an integer, and
nothing in the toolset, the JSON or the wiki says what that integer looks like.
Guessing produces a "Party Popper" that is a rolled-up letter and a "Fireworks
Finale Staff" that is a severed dragon head -- both real, both shipped, both
found only when a player looked in their pack.

The icons themselves are the answer: `iit_midmisc_051.tga` IS what ModelPart1 51
looks like. This extracts them out of the resman (game data + CEP haks + this
module's overrides, exactly as the server resolves them) and lays them out in a
labelled grid you can read in one look.

    python3 bin/gen-item-icon-sheet.py --base 29        # miscmedium
    python3 bin/gen-item-icon-sheet.py --class it_glove
    python3 bin/gen-item-icon-sheet.py --base 29 --only 2,11,12,94

Sheets land in module-index/icons/<class>/ (gitignored, like the rest of
module-index). The durable findings -- "midmisc 94 is the two-faced theatre
mask" -- belong in CLAUDE-item-appearances.md, not here: this tool is the
microscope, that file is the lab notebook.

Two icon families, and you need both:

  * SIMPLE items (baseitems.2da ModelType 0/2 -- every misc class, wands, rods)
    carry a plain `iit_<itemclass>_<nnn>.tga`, sometimes shadowed by a `.dds`.
  * ARMOUR PARTS (ModelType 1 -- helmets, cloaks, armour) carry `i<part>_<nnn>.plt`
    instead: a two-byte-per-pixel paletted format whose colours are chosen at
    runtime from the wearer's dyes. We render the colour channel as greyscale,
    which loses the tint and keeps the SHAPE -- which is the question being
    asked ("is this a crown or a great helm?").

Extraction is slow (a full CEP resman scan is minutes per pattern), so results
are cached under module-index/icons/<class>/raw and reused; pass --refresh to
re-extract.
"""

import argparse
import os
import re
import shutil
import struct
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_ROOT = os.path.join(REPO, "module-index", "icons")

# Armour parts are keyed by the PART name, not by ItemClass: a helmet's icons are
# ihelm_NNN.plt, a cloak's are iit_cloak_NNN.tga even though both are ModelType 1.
# Rather than guess, we try each family and keep whichever produced files.
PLT_PREFIX = {"helm": "ihelm_"}


def sh(cmd, **kw):
    return subprocess.run(cmd, check=True, capture_output=True, text=True, **kw)


def server_env():
    env = {}
    path = os.path.join(REPO, "server.env")
    for line in open(path):
        m = re.match(r'\s*(?:export\s+)?([A-Z_0-9]+)=(.*)', line)
        if m:
            env[m.group(1)] = m.group(2).strip().strip('"').strip("'")
    return env


def nwn_home():
    home = server_env().get("NWN_HOME_DIR", "")
    home = os.path.expandvars(home).replace("$HOME", os.path.expanduser("~"))
    if not os.path.isdir(home):
        sys.exit("server.env NWN_HOME_DIR does not exist: %r" % home)
    return home


def tool(name):
    for cand in (os.path.expanduser("~/.nimble/bin/" + name), name):
        if os.path.isabs(cand) and os.path.exists(cand):
            return cand
        if shutil.which(cand):
            return cand
    sys.exit("%s not found (neverwinter.nim tools)" % name)


def baseitem_row(idx):
    """(label, ItemClass, ModelType) for a baseitems.2da row, hak overrides applied."""
    out = sh([tool("nwn_resman_cat"), "--userdirectory", nwn_home(), "baseitems.2da"]).stdout
    rows = out.splitlines()
    hdr = ["idx"] + rows[2].split()
    for r in rows[3:]:
        p = r.split()
        if len(p) < 10 or p[0] != str(idx):
            continue
        d = dict(zip(hdr, p))
        return d["label"], d["ItemClass"], d["ModelType"]
    sys.exit("no baseitems.2da row %s" % idx)


def extract(pattern, dest):
    os.makedirs(dest, exist_ok=True)
    subprocess.run([tool("nwn_resman_extract"), "--userdirectory", nwn_home(),
                    "-p", pattern, "-d", dest],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return sorted(f for f in os.listdir(dest) if f.lower().endswith((".tga", ".plt")))


def load_plt(path):
    """Greyscale image from a PLT's colour channel. Shape only -- see the header."""
    from PIL import Image
    data = open(path, "rb").read()
    if data[:8] != b"PLT V1  ":
        return None
    w, h = struct.unpack("<II", data[16:24])
    if len(data) < 24 + w * h * 2:
        return None
    px = data[24:]
    img = Image.new("L", (w, h))
    img.putdata([px[i * 2] for i in range(w * h)])
    return img.transpose(Image.FLIP_TOP_BOTTOM)


def sheet(files, raw_dir, out_path, cell=96, cols=8, per_sheet=48):
    from PIL import Image, ImageDraw, ImageFont
    try:
        font = ImageFont.truetype(
            "/usr/share/fonts/dejavu-sans-fonts/DejaVuSans-Bold.ttf", 16)
    except OSError:
        font = ImageFont.load_default()

    written = []
    for page in range(0, len(files), per_sheet):
        chunk = files[page:page + per_sheet]
        rows = (len(chunk) + cols - 1) // cols
        pad, label_h = 8, 20
        W = cols * (cell + pad) + pad
        H = rows * (cell + pad + label_h) + pad
        canvas = Image.new("RGB", (W, H), (48, 48, 48))
        draw = ImageDraw.Draw(canvas)
        for i, name in enumerate(chunk):
            path = os.path.join(raw_dir, name)
            img = load_plt(path) if name.lower().endswith(".plt") else Image.open(path)
            if img is None:
                continue
            img = img.convert("RGBA").resize((cell, cell), Image.LANCZOS)
            cx = pad + (i % cols) * (cell + pad)
            cy = pad + (i // cols) * (cell + pad + label_h)
            canvas.paste(img, (cx, cy), img)
            num = re.search(r'(\d+)\.\w+$', name)
            draw.text((cx + cell // 2 - 14, cy + cell + 2),
                      num.group(1) if num else name, fill=(240, 240, 240), font=font)
        path = out_path if len(files) <= per_sheet else \
            out_path.replace(".png", "_%02d.png" % (page // per_sheet))
        canvas.save(path)
        written.append(path)
    return written


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--base", type=int, help="baseitems.2da row (e.g. 29 = miscmedium)")
    g.add_argument("--class", dest="cls", help="ItemClass directly (e.g. it_glove)")
    ap.add_argument("--only", help="comma-separated model numbers, for a zoomed sheet")
    ap.add_argument("--refresh", action="store_true", help="re-extract instead of reusing the cache")
    args = ap.parse_args()

    if args.base is not None:
        label, cls, model_type = baseitem_row(args.base)
        print("base item %d = %s (ItemClass %s, ModelType %s)" % (args.base, label, cls, model_type))
    else:
        cls, label = args.cls, args.cls

    cls_l = cls.lower()
    out_dir = os.path.join(OUT_ROOT, cls_l)
    raw_dir = os.path.join(out_dir, "raw")
    cached = os.path.isdir(raw_dir) and os.listdir(raw_dir) and not args.refresh

    if cached:
        files = sorted(f for f in os.listdir(raw_dir) if f.lower().endswith((".tga", ".plt")))
        print("using %d cached icons in %s (--refresh to re-extract)" % (len(files), raw_dir))
    else:
        if args.refresh and os.path.isdir(raw_dir):
            shutil.rmtree(raw_dir)
        # A full resman scan takes minutes; say so before going quiet.
        patterns = ["iit_%s_" % cls_l, PLT_PREFIX.get(cls_l, "i%s_" % cls_l)]
        files = []
        for pat in patterns:
            print("extracting %s ... (a full CEP scan takes several minutes)" % pat)
            files = extract(pat, raw_dir)
            if files:
                break
        if not files:
            sys.exit("no icons found for %s -- tried %s" % (cls, ", ".join(patterns)))
        print("extracted %d icons" % len(files))

    if args.only:
        want = {n.strip().zfill(3) for n in args.only.split(",")}
        keep = []
        for f in files:
            m = re.search(r'(\d+)\.\w+$', f)
            if m and m.group(1) in want:
                keep.append(f)
        files = keep

    # One entry per model number: the .tga and its .dds twin are the same icon.
    seen, uniq = set(), []
    for f in files:
        m = re.search(r'(\d+)\.\w+$', f)
        if not m or m.group(1) in seen:
            continue
        seen.add(m.group(1))
        uniq.append(f)

    os.makedirs(out_dir, exist_ok=True)
    written = sheet(uniq, raw_dir, os.path.join(out_dir, "%s_sheet.png" % cls_l))
    for p in written:
        print("wrote", os.path.relpath(p, REPO))


if __name__ == "__main__":
    main()
