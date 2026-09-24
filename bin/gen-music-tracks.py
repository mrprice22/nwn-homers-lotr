#!/usr/bin/env python3
"""gen-music-tracks.py — turn the MP3 masters into NWN music tracks.

Drop an MP3 into ~/OneDrive/Games/NWNHomersLOTR/music/mp3/ and run this. For
every master it:

  1. resolves a stable resref + ambientmusic.2da row from music/tracks.json,
  2. re-encodes the audio to 44.1 kHz stereo CBR 128 kbps with ffmpeg,
  3. writes music/bmu/<resref>.bmu,
  4. regenerates hak_music/ambientmusic.2da and unpacked/jb_tracks.nss.

Then run bin/build-lotr-music-hak --install to pack and publish the result.

WHY A .bmu IS JUST AN MP3 WITH A HEADER
---------------------------------------
A NWN music file is an MP3 behind the eight literal ASCII bytes "BMU V1.0".
This is not folklore — it is what the stock files are. Hexdump any of them:

    data/mus/mus_bat_aribeth.bmu  ->  42 4d 55 20 56 31 2e 30  ff fb ...
                                      B  M  U     V  1  .  0   (MP3 frame sync)
    data/mus/mus_theme_nwn.bmu    ->  42 4d 55 20 56 31 2e 30  49 44 33 ...
                                                               (an ID3 tag)

Note the game tolerates either a raw frame or an ID3 tag after the header, so
we do not have to strip ffmpeg's tags. The header is CASE-SENSITIVE: "BMU V1.0"
works, "BMU v1.0" does not, which is the single most common way a hand-renamed
file fails silently. The nwn.wiki "Sounds and Music" page claims music files
need no header at all; the stock bytes above say otherwise, so we write it.

WHY THE STOCK TABLE IS SNAPSHOT IN THE REPO
-------------------------------------------
hak_music/ambientmusic.stock.2da is a committed copy of the unmodified 138-row
(0-137) stock table, and every build starts from it rather than re-extracting
the table at run time. Two reasons:

  * Reproducibility. The output depends only on files in this repo, not on which
    game install is present or what is currently sitting in the hak folder.
  * No feedback loop. `nwn_resman_cat --userdirectory` alone does NOT load haks
    (they need --erfs), so today it happens to return stock -- but the moment a
    run passed our own lotr_music.hak it would read OUR table back and append to
    its own output, doubling the rows.

CEP ships no ambientmusic.2da (verified: cep2da.hak contains none), so stock is
genuinely the whole story underneath us.

WHY tracks.json IS COMMITTED AND APPEND-ONLY
--------------------------------------------
Areas and the jukebox refer to a track by its 2DA ROW NUMBER, stored in
<area>.git.json. Renumbering a row silently repoints every area that used it to
somebody else's song. So a row, once handed out, is never reused: deleting the
MP3 retires the entry and leaves the row reserved forever. You may hand-edit an
entry's "resref" or "name" BEFORE its first hak build; after that it is frozen.

Usage:
  bin/gen-music-tracks.py             # dry run - show what would change
  bin/gen-music-tracks.py --apply     # write it
  bin/gen-music-tracks.py --apply --force-encode   # re-encode even if unchanged

  bin/gen-music-tracks.py --catalog           # dry run the player catalogue
  bin/gen-music-tracks.py --catalog --apply   # write jb_catalog.nss + catalog.json
  bin/gen-music-tracks.py --catalog --apply --remeasure   # re-probe every .bmu

--catalog is a separate job from the encode pipeline above and does not need the
MP3 masters: it rebuilds the PLAYER jukebox's table (unpacked/jb_catalog.nss and
music/catalog.json) from the stock 2DA, tlk/dialog.tlk and the stock .bmu
lengths. Re-run it after adding a custom track, so the new row joins the picker.
"""

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import unicodedata

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

DEFAULT_SRC = os.path.expanduser("~/OneDrive/Games/NWNHomersLOTR/music/mp3")
MANIFEST = os.path.join(REPO, "music", "tracks.json")
BMU_DIR = os.path.join(REPO, "music", "bmu")
STOCK_2DA = os.path.join(REPO, "hak_music", "ambientmusic.stock.2da")
OUT_2DA = os.path.join(REPO, "hak_music", "ambientmusic.2da")
OUT_NSS = os.path.join(REPO, "unpacked", "jb_tracks.nss")

BMU_HEADER = b"BMU V1.0"
RESREF_MAX = 16          # every NWN resource name is capped at 16 characters
RESREF_PREFIX = "mus_hl_"
FIRST_ROW = 138          # stock occupies 0-137

# Parenthesised noise that YouTube rips carry around in their filenames.
NOISE_RE = re.compile(
    r"[\(\[][^\)\]]*\b(official|video|audio|lyrics?|hd|hq|4k|music video|"
    r"full|remaster(ed)?|visuali[sz]er)\b[^\)\]]*[\)\]]",
    re.I,
)


def sh(cmd, **kw):
    return subprocess.run(cmd, check=True, capture_output=True, text=True, **kw)


def need(tool):
    p = shutil.which(tool)
    if not p:
        sys.exit("error: %s not found on PATH" % tool)
    return p


def sha1_file(path):
    h = hashlib.sha1()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def ascii_only(s):
    """NWScript sources in this repo must stay ASCII (see bin/ascii-clean-nss.py)."""
    s = unicodedata.normalize("NFKD", s)
    s = s.replace("’", "'").replace("‘", "'")
    s = s.replace("“", '"').replace("”", '"')
    s = s.replace("–", "-").replace("—", "-")
    return s.encode("ascii", "ignore").decode("ascii")


def friendly_name(filename):
    """'Drowning Pool - Bodies (Official HD Music Video).mp3' -> 'Drowning Pool - Bodies'."""
    stem = os.path.splitext(filename)[0]
    stem = NOISE_RE.sub(" ", stem)
    stem = ascii_only(stem)
    # Drop a parenthetical that merely repeats something already in the title
    # ("... Six Flags (Six Flags)"), which YouTube rips collect.
    def drop_echo(m):
        inner = m.group(1).strip()
        before = stem[: m.start()]
        return "" if inner and inner.lower() in before.lower() else m.group(0)
    stem = re.sub(r"[\(\[]([^\)\]]*)[\)\]]", drop_echo, stem)
    stem = re.sub(r"\s+", " ", stem).strip(" -_")
    return stem or os.path.splitext(filename)[0]


def slug_for(name, taken):
    """A <=16-char resref, unique against `taken`. Readable where it fits."""
    budget = RESREF_MAX - len(RESREF_PREFIX)
    words = [w for w in re.split(r"[^A-Za-z0-9]+", name.lower()) if w]
    if not words:
        words = ["track"]

    # Prefer the shortest leading run of whole words that fits; a single word
    # longer than the budget gets cut. Titles here are usually "Artist - Song",
    # so also try the tail (the song) before falling back to a hard truncation.
    cands = []
    for seq in (words, words[::-1][:1], words[-2:]):
        acc = ""
        for w in seq:
            if len(acc) + len(w) > budget:
                break
            acc += w
        if acc:
            cands.append(acc)
    cands.append(words[0][:budget])

    for base in cands:
        cand = RESREF_PREFIX + base
        if base and cand not in taken:
            return cand

    base = (cands[0] or "track")[:budget]
    for n in range(2, 100):
        suffix = str(n)
        cand = RESREF_PREFIX + base[: budget - len(suffix)] + suffix
        if cand not in taken:
            return cand
    sys.exit("error: could not allocate a unique resref for %r" % name)


def load_manifest():
    if os.path.exists(MANIFEST):
        with open(MANIFEST) as fh:
            return json.load(fh)
    return {"_comment": "Append-only. A row, once assigned, is never reused. "
                        "Edit resref/name only before the first hak build.",
            "tracks": []}


def probe(path):
    out = sh([need("ffprobe"), "-v", "error", "-select_streams", "a:0",
              "-show_entries", "stream=sample_rate,channels:format=duration",
              "-of", "json", path]).stdout
    d = json.loads(out)
    st = (d.get("streams") or [{}])[0]
    return {
        "sample_rate": int(st.get("sample_rate", 0) or 0),
        "channels": int(st.get("channels", 0) or 0),
        "duration": round(float(d.get("format", {}).get("duration", 0) or 0), 1),
    }


def encode_bmu(src, dest):
    """Re-encode to 44.1 kHz stereo CBR 128k and prepend the BMU V1.0 header.

    Constant bitrate is deliberate: the engine's music player expects CBR, and a
    VBR track is the classic cause of a song that loops early or drifts.
    """
    tmp = dest + ".tmp.mp3"
    subprocess.run(
        [need("ffmpeg"), "-hide_banner", "-loglevel", "error", "-y",
         "-i", src, "-vn", "-map", "a:0",
         "-c:a", "libmp3lame", "-b:a", "128k", "-ar", "44100", "-ac", "2",
         tmp],
        check=True,
    )
    try:
        with open(dest, "wb") as out:
            out.write(BMU_HEADER)
            with open(tmp, "rb") as fh:
                shutil.copyfileobj(fh, out)
    finally:
        if os.path.exists(tmp):
            os.remove(tmp)
    return os.path.getsize(dest)


# --------------------------------------------------------------- 2DA output --

def column_starts(header_line):
    """Start offset of each column name in the stock header line."""
    cols = []
    for m in re.finditer(r"\S+", header_line):
        cols.append((m.group(0), m.start()))
    return cols


def render_2da(stock_text, rows):
    """Stock lines verbatim + one appended line per custom track."""
    lines = stock_text.replace("\r\n", "\n").split("\n")
    while lines and not lines[-1].strip():
        lines.pop()

    cols = column_starts(lines[2])
    # Index column occupies everything left of the first named column.
    widths = [cols[0][1]]
    for i in range(len(cols) - 1):
        widths.append(cols[i + 1][1] - cols[i][1])
    widths.append(0)  # last column is unpadded

    for t in rows:
        fields = [
            str(t["row"]),
            "****",                                  # Description (a strref)
            t["resref"],                             # Resource
            "****", "****", "****",                  # Stinger1-3
            '"%s"' % t["name"].replace('"', "'"),    # DisplayName (literal)
        ]
        out = ""
        for value, width in zip(fields, widths):
            out += value.ljust(width - 1) + " " if width else value
        lines.append(out.rstrip())

    return "\r\n".join(lines) + "\r\n"


# --------------------------------------------------------------- NSS output --

def render_nss(rows):
    body = []
    body.append("// jb_tracks.nss -- the jukebox's custom music track table.")
    body.append("//")
    body.append("// AUTO-GENERATED by bin/gen-music-tracks.py -- do not hand-edit.")
    body.append("// Add an MP3 to ~/OneDrive/Games/NWNHomersLOTR/music/mp3/ and re-run it.")
    body.append("//")
    body.append("// The row numbers below are ambientmusic.2da rows. NWScript cannot read a")
    body.append("// 2DA, so the table is baked out here; music/tracks.json is the source of")
    body.append("// truth and guarantees a row is never reassigned to another song.")
    body.append("//")
    body.append("// These are RAW ambientmusic.2da rows, and MusicBackgroundChangeDay() takes")
    body.append("// them as-is. (MusicBackgroundGetDayTrack() is the odd one out -- it returns")
    body.append("// row MINUS ONE. jb_inc.nss documents both conventions.)")
    body.append("")
    body.append("int JB_GetTrackCount();")
    body.append("int JB_GetTrackRow(int nIndex);")
    body.append("string JB_GetTrackName(int nIndex);")
    body.append("")
    body.append("int JB_GetTrackCount()")
    body.append("{")
    body.append("    return %d;" % len(rows))
    body.append("}")
    body.append("")
    body.append("int JB_GetTrackRow(int nIndex)")
    body.append("{")
    body.append("    switch (nIndex)")
    body.append("    {")
    for i, t in enumerate(rows):
        body.append("        case %d: return %d;   // %s" % (i, t["row"], t["resref"]))
    body.append("    }")
    body.append("    return -1;")
    body.append("}")
    body.append("")
    body.append("string JB_GetTrackName(int nIndex)")
    body.append("{")
    body.append("    switch (nIndex)")
    body.append("    {")
    for i, t in enumerate(rows):
        body.append('        case %d: return "%s";' % (i, t["name"].replace('"', "'")))
    body.append("    }")
    body.append('    return "";')
    body.append("}")
    body.append("")
    return "\n".join(body)


# ------------------------------------------------------------------ catalog --
#
# THE PLAYER-FACING CATALOGUE (jb_catalog.nss / music/catalog.json)
#
# The admin jukebox only ever needed OUR five tracks, so jb_tracks.nss lists
# rows 138+ and nothing else. The player jukebox lets anyone pick from the STOCK
# music too, and it charges gold per play, so it needs two things jb_tracks.nss
# does not carry:
#
#   * a friendly NAME for every stock row, and
#   * a DURATION, because a paid queue has to know when a song ends.
#
# Neither is available at run time: NWScript cannot read a 2DA, cannot read the
# TLK, and cannot measure an audio file. So both are resolved HERE, offline, and
# baked into unpacked/jb_catalog.nss.
#
# WHY NAMES COME FROM TWO PLACES
# ------------------------------------------------------------------------
# ambientmusic.stock.2da does not name its rows consistently. The OC/SoU/HotU
# era rows carry a dialog.tlk STRREF in Description and DisplayName ****; the
# Tyrants/Daggerford premium rows carry a literal quoted DisplayName and
# Description ****. There is no single column that names every row, so we read
# DisplayName where it exists and resolve the strref through tlk/dialog.tlk
# otherwise, reusing bin/gen-palette-map.py's load_tlk() exactly as
# bin/file-palette-orphans.py does.
#
# WHY DURATIONS ARE MEASURED, NOT GUESSED
# ------------------------------------------------------------------------
# Stock track lengths are not written down anywhere. They are also not uniform:
# they run from well under a minute to over ten (mus_bat_city1 is 633s), so a
# single assumed length would be wrong by an order of magnitude at both ends and
# the queue would either cut songs off or stall on them.
#
# ffprobe CANNOT measure a .bmu through a pipe -- the duration of a streamed MP3
# is not knowable without a seek, and it returns "N/A". The header has to be
# stripped to a real file first. That is the whole reason _bmu_duration() writes
# a temp file instead of piping.
#
# WHAT IS EXCLUDED
# ------------------------------------------------------------------------
# Row 0 (the reserved silence row, Resource ****) and every mus_bat_* battle
# track, because the roadmap item asks for neither. The exclusions are listed in
# the generated file's header so a diff shows what was dropped and why.

CATALOG_JSON = os.path.join(REPO, "music", "catalog.json")
OUT_CATALOG_NSS = os.path.join(REPO, "unpacked", "jb_catalog.nss")
DIALOG_TLK = os.path.join(REPO, "tlk", "dialog.tlk")

# Where the stock .bmu files live. First existing wins; the Steam path is what
# this box has. Only needed to MEASURE durations -- once music/catalog.json is
# committed, a machine without the game installed can still regenerate the .nss.
STOCK_MUS_CANDIDATES = [
    os.path.expanduser("~/.steam/steam/steamapps/common/Neverwinter Nights/data/mus"),
    os.path.expanduser("~/.local/share/Neverwinter Nights/data/mus"),
]

BATTLE_PREFIX = "mus_bat_"
BLANK = "****"


def _load_gen_palette_map():
    """Import bin/gen-palette-map.py for load_tlk(), as file-palette-orphans does."""
    import importlib.util
    path = os.path.join(REPO, "bin", "gen-palette-map.py")
    spec = importlib.util.spec_from_file_location("gen_palette_map", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def split_2da_line(line):
    """Split a 2DA row into fields, keeping a quoted field with spaces whole."""
    fields = []
    i = 0
    n = len(line)
    while i < n:
        while i < n and line[i].isspace():
            i += 1
        if i >= n:
            break
        if line[i] == '"':
            j = line.find('"', i + 1)
            if j < 0:
                sys.exit("error: unterminated quote in 2DA line: %r" % line)
            fields.append(line[i + 1:j])
            i = j + 1
        else:
            j = i
            while j < n and not line[j].isspace():
                j += 1
            fields.append(line[i:j])
            i = j
    return fields


def parse_stock_2da(text):
    """[{row, description, resource, displayname}] for every stock row."""
    lines = text.replace("\r\n", "\n").split("\n")
    if not lines or not lines[0].startswith("2DA"):
        sys.exit("error: %s is not a 2DA V2.0 file" % STOCK_2DA)
    header = split_2da_line(lines[2])
    try:
        i_desc = header.index("Description")
        i_res = header.index("Resource")
        i_disp = header.index("DisplayName")
    except ValueError:
        sys.exit("error: %s header is missing Description/Resource/DisplayName" % STOCK_2DA)

    rows = []
    for line in lines[3:]:
        if not line.strip():
            continue
        f = split_2da_line(line)
        # +1 because the row index occupies field 0, ahead of the named columns.
        if len(f) < i_disp + 2:
            sys.exit("error: short 2DA row in %s: %r" % (STOCK_2DA, line))
        rows.append({
            "row": int(f[0]),
            "description": f[i_desc + 1],
            "resource": f[i_res + 1],
            "displayname": f[i_disp + 1],
        })
    return rows


def _stock_mus_dir():
    for p in STOCK_MUS_CANDIDATES:
        if os.path.isdir(p):
            return p
    return None


def _bmu_duration(path):
    """Seconds, measured. Strips the 8-byte BMU header to a temp file first.

    Piping the stripped stream to ffprobe returns "N/A": the duration of a raw
    MP3 stream is not knowable without seeking. It has to be a real file.
    """
    import tempfile
    fd, tmp = tempfile.mkstemp(suffix=".mp3")
    try:
        with open(path, "rb") as src:
            head = src.read(len(BMU_HEADER))
            if head != BMU_HEADER:
                os.close(fd)
                fd = None
                sys.exit("error: %s does not start with the BMU V1.0 header" % path)
            with os.fdopen(fd, "wb") as out:
                fd = None
                shutil.copyfileobj(src, out)
        measured = sh([need("ffprobe"), "-v", "error",
                       "-show_entries", "format=duration",
                       "-of", "csv=p=0", tmp]).stdout.strip()
        if not measured or measured == "N/A":
            sys.exit("error: ffprobe could not measure %s" % path)
        return round(float(measured), 1)
    finally:
        if fd is not None:
            os.close(fd)
        if os.path.exists(tmp):
            os.remove(tmp)


def build_catalog(live_tracks, previous):
    """The full pickable catalogue: stock rows 1-137 plus our custom rows.

    `previous` is the committed music/catalog.json keyed by row, so a rerun on a
    machine with no game install reuses the measured durations instead of
    failing. A row is only measured when we have no recorded duration for it.
    """
    import pathlib

    with open(STOCK_2DA, "r", newline="") as fh:
        stock_rows = parse_stock_2da(fh.read())

    tlk = None
    mus_dir = _stock_mus_dir()
    entries = []
    excluded = []

    for r in stock_rows:
        resref = r["resource"]
        if resref == BLANK:
            excluded.append((r["row"], "(none)", "reserved silence row"))
            continue
        if resref.lower().startswith(BATTLE_PREFIX):
            excluded.append((r["row"], resref, "battle music"))
            continue

        # Name: the literal DisplayName if the row has one, else its strref.
        name = ""
        if r["displayname"] != BLANK:
            name = r["displayname"].strip()
        elif r["description"] != BLANK:
            if tlk is None:
                if not os.path.exists(DIALOG_TLK):
                    sys.exit("error: missing %s -- needed to name the stock rows" % DIALOG_TLK)
                tlk = _load_gen_palette_map().load_tlk(pathlib.Path(DIALOG_TLK))
            try:
                ref = int(r["description"])
            except ValueError:
                sys.exit("error: row %d Description %r is neither **** nor a strref"
                         % (r["row"], r["description"]))
            if not (0 <= ref < len(tlk)) or not tlk[ref].strip():
                sys.exit("error: row %d (%s) strref %d resolves to nothing in %s"
                         % (r["row"], resref, ref, DIALOG_TLK))
            name = tlk[ref].strip()
        if not name:
            sys.exit("error: row %d (%s) has no DisplayName and no Description strref -- "
                     "cannot name it, and a blank entry in the picker is not acceptable"
                     % (r["row"], resref))
        name = ascii_only(name).strip()
        if not name:
            sys.exit("error: row %d (%s) name is empty after ASCII folding" % (r["row"], resref))

        dur = previous.get(r["row"], {}).get("duration")
        if dur is None:
            if mus_dir is None:
                sys.exit("error: no stock music folder found (looked in %s) and no recorded "
                         "duration for row %d (%s). Run this on a machine with the game "
                         "installed, or restore music/catalog.json."
                         % (", ".join(STOCK_MUS_CANDIDATES), r["row"], resref))
            bmu = os.path.join(mus_dir, resref + ".bmu")
            if not os.path.exists(bmu):
                sys.exit("error: row %d names %s but %s does not exist. That row's premium "
                         "content is not installed, so its length cannot be measured."
                         % (r["row"], resref, bmu))
            dur = _bmu_duration(bmu)
        if not dur or dur <= 0:
            sys.exit("error: row %d (%s) measured a duration of %r" % (r["row"], resref, dur))

        entries.append({"row": r["row"], "resref": resref, "name": name,
                        "duration": dur, "origin": "stock"})

    for t in live_tracks:
        dur = t.get("duration")
        if not dur or dur <= 0:
            sys.exit("error: custom track %s (row %d) has no duration in %s -- "
                     "re-run with --apply to measure it" % (t["resref"], t["row"], MANIFEST))
        entries.append({"row": t["row"], "resref": t["resref"],
                        "name": ascii_only(t["name"]).strip(),
                        "duration": round(float(dur), 1), "origin": "custom"})

    entries.sort(key=lambda e: e["row"])
    return entries, excluded


def render_catalog_nss(entries, excluded):
    body = []
    body.append("// jb_catalog.nss -- every track the player jukebox can play.")
    body.append("//")
    body.append("// AUTO-GENERATED by bin/gen-music-tracks.py --catalog -- do not hand-edit.")
    body.append("// music/catalog.json is the committed source of truth.")
    body.append("//")
    body.append("// This is the PLAYER catalogue: stock rows plus our own. jb_tracks.nss is")
    body.append("// the separate, admin-only table of just the custom tracks, and the old")
    body.append("// jb_conv jukebox still reads that one. Do not merge them.")
    body.append("//")
    body.append("// Names come from ambientmusic.stock.2da's DisplayName where a row has one")
    body.append("// and from tlk/dialog.tlk via its Description strref otherwise -- the stock")
    body.append("// table uses both conventions and neither covers every row.")
    body.append("//")
    body.append("// Durations are MEASURED from the stock .bmu files with ffprobe, because a")
    body.append("// paid queue has to know when a song actually ends and the lengths are not")
    body.append("// uniform (they run from under a minute to over ten).")
    body.append("//")
    body.append("// These are RAW ambientmusic.2da rows -- what MusicBackgroundChangeDay()")
    body.append("// takes. MusicBackgroundGetDayTrack() returns row MINUS ONE; jb_inc.nss")
    body.append("// documents both conventions and JB_Start()/JB_Stop() already handle them.")
    body.append("//")
    body.append("// Excluded, deliberately (%d row(s)):" % len(excluded))
    for row, resref, why in excluded:
        body.append("//   row %-4d %-18s %s" % (row, resref, why))
    body.append("")
    body.append("int JB_CatCount();")
    body.append("int JB_CatRow(int nIndex);")
    body.append("string JB_CatName(int nIndex);")
    body.append("int JB_CatDuration(int nIndex);")
    body.append("")
    body.append("int JB_CatCount()")
    body.append("{")
    body.append("    return %d;" % len(entries))
    body.append("}")
    body.append("")
    body.append("int JB_CatRow(int nIndex)")
    body.append("{")
    body.append("    switch (nIndex)")
    body.append("    {")
    for i, e in enumerate(entries):
        body.append("        case %d: return %d;   // %s" % (i, e["row"], e["resref"]))
    body.append("    }")
    body.append("    return -1;")
    body.append("}")
    body.append("")
    body.append("string JB_CatName(int nIndex)")
    body.append("{")
    body.append("    switch (nIndex)")
    body.append("    {")
    for i, e in enumerate(entries):
        body.append('        case %d: return "%s";' % (i, e["name"].replace('"', "'")))
    body.append("    }")
    body.append('    return "";')
    body.append("}")
    body.append("")
    body.append("// Seconds, rounded to a whole second. The queue uses this to decide when")
    body.append("// the next song starts; it is never zero (the generator refuses to emit a")
    body.append("// row it could not measure).")
    body.append("int JB_CatDuration(int nIndex)")
    body.append("{")
    body.append("    switch (nIndex)")
    body.append("    {")
    for i, e in enumerate(entries):
        body.append("        case %d: return %d;" % (i, int(round(e["duration"]))))
    body.append("    }")
    body.append("    return 0;")
    body.append("}")
    body.append("")
    return "\n".join(body)


def load_catalog_json():
    """{row: entry} from the committed catalogue, or {} when there is none."""
    if not os.path.exists(CATALOG_JSON):
        return {}
    with open(CATALOG_JSON) as fh:
        data = json.load(fh)
    return {e["row"]: e for e in data.get("tracks", [])}


def cmd_catalog(apply_changes, remeasure):
    manifest = load_manifest()
    live = [t for t in manifest["tracks"] if not t.get("retired")]
    previous = {} if remeasure else load_catalog_json()

    entries, excluded = build_catalog(live, previous)

    n_stock = sum(1 for e in entries if e["origin"] == "stock")
    n_custom = len(entries) - n_stock
    print("%d pickable track(s): %d stock + %d custom" % (len(entries), n_stock, n_custom))
    print("%d row(s) excluded (%d battle, %d reserved)"
          % (len(excluded),
             sum(1 for x in excluded if x[2] == "battle music"),
             sum(1 for x in excluded if x[2] != "battle music")))
    total = sum(e["duration"] for e in entries)
    longest = max(entries, key=lambda e: e["duration"])
    print("total runtime %.1f min; longest is %s (%s) at %.0fs"
          % (total / 60.0, longest["name"], longest["resref"], longest["duration"]))

    if not apply_changes:
        print("\ndry run -- nothing written. Re-run with --apply.")
        return

    with open(CATALOG_JSON, "w") as fh:
        json.dump({
            "_comment": "AUTO-GENERATED by bin/gen-music-tracks.py --catalog. "
                        "Committed so the durations are reviewable in a diff and so the "
                        "NSS table can be rebuilt without the game installed.",
            "tracks": entries,
            "excluded": [{"row": r, "resref": s, "reason": w} for r, s, w in excluded],
        }, fh, indent=2)
        fh.write("\n")
    with open(OUT_CATALOG_NSS, "w") as fh:
        fh.write(render_catalog_nss(entries, excluded))

    print("wrote %s" % CATALOG_JSON)
    print("wrote %s" % OUT_CATALOG_NSS)


# --------------------------------------------------------------------- main --

def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--src", default=DEFAULT_SRC, help="folder of MP3 masters")
    ap.add_argument("--apply", action="store_true", help="write changes (default: dry run)")
    ap.add_argument("--force-encode", action="store_true",
                    help="re-encode every .bmu even if the master is unchanged")
    ap.add_argument("--catalog", action="store_true",
                    help="rebuild the player jukebox catalogue instead of encoding")
    ap.add_argument("--remeasure", action="store_true",
                    help="with --catalog: re-probe every .bmu instead of reusing catalog.json")
    args = ap.parse_args()

    # The catalogue is built from the stock table, the TLK and the stock .bmu
    # lengths, so it deliberately runs before -- and without -- the MP3 masters
    # the encode path below requires.
    if args.catalog:
        cmd_catalog(args.apply, args.remeasure)
        return

    if not os.path.isdir(args.src):
        sys.exit("error: MP3 folder not found: %s" % args.src)
    if not os.path.exists(STOCK_2DA):
        sys.exit("error: missing stock snapshot %s\n"
                 "       recreate with: nwn_resman_cat --root '<NWN install>' "
                 "--no-ovr ambientmusic.2da" % STOCK_2DA)

    manifest = load_manifest()
    tracks = manifest["tracks"]
    by_source = {t["source"]: t for t in tracks}
    taken_resrefs = {t["resref"] for t in tracks}
    next_row = max([t["row"] for t in tracks], default=FIRST_ROW - 1) + 1

    masters = sorted(f for f in os.listdir(args.src) if f.lower().endswith(".mp3"))
    if not masters:
        sys.exit("error: no .mp3 files in %s" % args.src)

    changed = []
    for fname in masters:
        path = os.path.join(args.src, fname)
        digest = sha1_file(path)
        entry = by_source.get(fname)
        if entry is None:
            name = friendly_name(fname)
            entry = {
                "source": fname,
                "name": name,
                "resref": slug_for(name, taken_resrefs),
                "row": next_row,
                "sha1": None,
            }
            taken_resrefs.add(entry["resref"])
            next_row += 1
            tracks.append(entry)
            by_source[fname] = entry
            print("NEW   row %-4d %-16s %s" % (entry["row"], entry["resref"], entry["name"]))
        entry.pop("retired", None)

        info = probe(path)
        bmu = os.path.join(BMU_DIR, entry["resref"] + ".bmu")
        stale = args.force_encode or entry.get("sha1") != digest or not os.path.exists(bmu)
        if stale:
            changed.append((entry, path, bmu, digest, info))
            print("ENCODE      %-16s %s  (%d Hz, %dch, %.0fs)"
                  % (entry["resref"], fname, info["sample_rate"],
                     info["channels"], info["duration"]))
        else:
            print("ok          %-16s %s" % (entry["resref"], fname))

    for t in tracks:
        if t["source"] not in by_source or not os.path.exists(os.path.join(args.src, t["source"])):
            if not t.get("retired"):
                t["retired"] = True
                print("RETIRE row %-4d %-16s (master gone; row stays reserved)"
                      % (t["row"], t["resref"]))

    live = [t for t in tracks if not t.get("retired")]
    live.sort(key=lambda t: t["row"])

    print("\n%d live track(s), rows %s"
          % (len(live), ", ".join(str(t["row"]) for t in live) or "-"))

    if not args.apply:
        print("\ndry run — nothing written. Re-run with --apply.")
        return

    os.makedirs(BMU_DIR, exist_ok=True)
    for entry, path, bmu, digest, info in changed:
        size = encode_bmu(path, bmu)
        entry["sha1"] = digest
        entry["duration"] = info["duration"]
        entry["bytes"] = size
        # NWSync refuses to publish a file over 15 MB.
        if size > 15 * 1024 * 1024:
            print("WARNING: %s is %.1f MB — over NWSync's 15 MB per-file limit; "
                  "clients will not receive it." % (os.path.basename(bmu), size / 1048576.0))
        print("wrote %s (%.1f MB)" % (bmu, size / 1048576.0))

    with open(MANIFEST, "w") as fh:
        json.dump(manifest, fh, indent=2)
        fh.write("\n")

    with open(STOCK_2DA, "r", newline="") as fh:
        stock = fh.read()
    with open(OUT_2DA, "w", newline="") as fh:
        fh.write(render_2da(stock, live))
    with open(OUT_NSS, "w") as fh:
        fh.write(render_nss(live))

    print("wrote %s" % MANIFEST)
    print("wrote %s (%d rows)" % (OUT_2DA, FIRST_ROW + len(live)))
    print("wrote %s" % OUT_NSS)
    print("\nnext: bin/build-lotr-music-hak --install")


if __name__ == "__main__":
    main()
