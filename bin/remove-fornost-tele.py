import json, pathlib

DLG_DIR = pathlib.Path("unpacked")
FILES = ["goodtele.dlg.json", "neutraltele.dlg.json", "eviltele.dlg.json"]
SCRIPT_TO_REMOVE = "fornostjump"

for fname in FILES:
    path = DLG_DIR / fname
    data = json.loads(path.read_text())
    replies = data["ReplyList"]["value"]

    pos = next(i for i, r in enumerate(replies) if r.get("Script", {}).get("value") == SCRIPT_TO_REMOVE)

    replies.pop(pos)

    for entry in data["EntryList"]["value"]:
        links = entry["RepliesList"]["value"]
        entry["RepliesList"]["value"] = [
            dict(lk, **{"Index": {"type": "dword", "value": lk["Index"]["value"] - 1}})
            if lk["Index"]["value"] > pos else lk
            for lk in links
            if lk["Index"]["value"] != pos
        ]

    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
    print(f"{fname}: removed Fornost at position {pos}")
