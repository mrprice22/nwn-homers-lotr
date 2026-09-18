#!/usr/bin/env python3
"""content-hash.py — hash what a file MEANS, not the bytes its builder stamped on it.

WHY THIS EXISTS
---------------
`bin/nwsync-copy-from` may only publish another realm's manifest if the two
realms really do serve the same content, so it verifies `lotr_rules.hak` and
`lotr.tlk` match. It did that with a whole-file SHA1 — and on 2026-09-18 that
refused a season 2 promotion whose hak was, resource for resource, IDENTICAL to
dev's:

    hak/lotr_rules.hak differs between the realms
    (14a59912f0690a25f6c5494a07be16e4e359091c vs d6168094c07e59a3acfb996553cd4e4e028933a5)

Exactly **one byte** differed, at offset 36: the ERF header's `BuildDay` field.
Dev's hak had been built on the 17th and the target's was rebuilt on the 18th.
All 21 resources inside were byte-identical. The guard was rejecting a date
stamp, which means it would refuse any promotion where the two haks were not
built on the same day — nearly all of them.

So: parse the container and hash the RESOURCES. An ERF's identity here is the
set of (resref, restype, bytes) it carries, and nothing else — not the build
date, not the order they happen to be laid out in, not the 116 reserved bytes.

ERF layout (nwn.wiki "ERF"): a 160-byte header, then EntryCount × 24-byte key
entries (ResRef[16], ResID u32, ResType u16, pad u16), then EntryCount × 8-byte
resource entries (offset u32, size u32). `BuildYear` and `BuildDay` sit at
offsets 32 and 36 — the two fields that made the old check wrong.

Anything that is not an ERF (the TLK) is hashed whole: its format carries no
build stamp, so a byte difference there is a real difference.

Usage:
    bin/content-hash.py FILE [FILE...]      # one "<sha1>  <path>" line each
    bin/content-hash.py --verbose FILE      # also say how it was hashed

Exit status is 1 if any file could not be read or parsed, so a caller can tell
"these differ" from "I could not tell".
"""
import hashlib
import struct
import sys
from pathlib import Path

ERF_MAGICS = {b"ERF ", b"HAK ", b"MOD ", b"SAV ", b"ALS ", b"NWM "}
HEADER_SIZE = 160
KEY_ENTRY = 24
RES_ENTRY = 8


def erf_content_hash(data: bytes) -> str:
    """SHA1 over every resource's name, type and bytes, in a canonical order.

    Sorted, so two ERFs that carry the same resources laid out in a different
    order still hash the same — the layout is the container's business, not the
    content's.
    """
    if len(data) < HEADER_SIZE:
        raise ValueError("shorter than an ERF header")
    (entry_count, _loc_off, key_off, res_off) = struct.unpack_from("<IIII", data, 16)
    if key_off + entry_count * KEY_ENTRY > len(data):
        raise ValueError("key list runs past the end of the file")
    if res_off + entry_count * RES_ENTRY > len(data):
        raise ValueError("resource list runs past the end of the file")

    entries = []
    for i in range(entry_count):
        k = key_off + i * KEY_ENTRY
        resref = data[k:k + 16].split(b"\0", 1)[0].lower()
        restype = struct.unpack_from("<H", data, k + 20)[0]
        offset, size = struct.unpack_from("<II", data, res_off + i * RES_ENTRY)
        if offset + size > len(data):
            raise ValueError(f"resource {resref!r} runs past the end of the file")
        entries.append((resref, restype, data[offset:offset + size]))

    h = hashlib.sha1()
    for resref, restype, blob in sorted(entries, key=lambda e: (e[0], e[1])):
        # Length-prefixed, so no concatenation of names and payloads can be
        # rearranged into the same byte stream.
        h.update(resref)
        h.update(struct.pack("<HI", restype, len(blob)))
        h.update(blob)
    return h.hexdigest()


def content_hash(path: Path):
    data = path.read_bytes()
    if data[:4] in ERF_MAGICS:
        return erf_content_hash(data), f"erf: {data[:4].decode().strip()}"
    return hashlib.sha1(data).hexdigest(), "whole file"


def main(argv):
    verbose = False
    paths = []
    for arg in argv:
        if arg in ("-v", "--verbose"):
            verbose = True
        elif arg in ("-h", "--help"):
            print(__doc__)
            return 0
        else:
            paths.append(Path(arg))
    if not paths:
        print("usage: content-hash.py FILE [FILE...]", file=sys.stderr)
        return 2

    rc = 0
    for p in paths:
        try:
            digest, how = content_hash(p)
        except (OSError, ValueError, struct.error) as exc:
            print(f"content-hash: {p}: {exc}", file=sys.stderr)
            rc = 1
            continue
        print(f"{digest}  {p}" + (f"  [{how}]" if verbose else ""))
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
