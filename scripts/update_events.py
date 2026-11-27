#!/usr/bin/env python3
"""Validate events.json and fill in results for finished events.

An event can carry two optional hints so the script can find its result on ESPN:
  "espn":  "<sport>/<league>[?extra=params]", for example "golf/pga" or "football/nfl?seasontype=3"
  "match": text that appears in the ESPN event name, for example "Masters"
Events without hints are only validated; their results stay hand-compiled.
"""
import datetime as dt
import json
import sys
import urllib.request

PATH = "events.json"


def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": "agate-events/1.0"})
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.load(r)


def winner_of(espn, match, day):
    path, _, query = espn.partition("?")
    url = (f"https://site.api.espn.com/apis/site/v2/sports/{path}/scoreboard?"
           + (query + "&" if query else "") + f"dates={day:%Y%m%d}")
    data = fetch(url)
    for ev in data.get("events", []):
        comp = (ev.get("competitions") or [{}])[0]
        notes = " ".join(n.get("headline", "") for n in comp.get("notes", []))
        name = (ev.get("name") or "") + " " + (ev.get("shortName") or "") + " " + notes
        if match.lower() not in name.lower():
            continue
        if (ev.get("status", {}).get("type", {}).get("state") or "") != "post":
            return None
        comps = comp.get("competitors") or []
        win = next((c for c in comps if c.get("winner")), None)
        if win is None:
            win = next((c for c in comps if str(c.get("order")) == "1"), None)
        if win is None:
            return None
        who = (win.get("athlete") or win.get("team") or {}).get("displayName") or ""
        if not who:
            return None
        if len(comps) == 2 and all(c.get("score") for c in comps) and "team" in comps[0]:
            other = next(c for c in comps if c is not win)
            return f"{who} {win['score']}, {(other.get('team') or {}).get('displayName', '')} {other['score']}"
        score = win.get("score")
        return f"{who} won" + (f" ({score})" if score and str(score) not in ("0", "") else "")
    return None


def main():
    data = json.load(open(PATH))
    today = dt.date.today()
    problems, changed = [], 0
    for e in data["events"]:
        try:
            s = dt.date.fromisoformat(e["start"])
            en = dt.date.fromisoformat(e.get("end") or e["start"])
        except Exception:
            problems.append(f"bad date: {e.get('title')}")
            continue
        if en < s:
            problems.append(f"end before start: {e['title']}")
        if e.get("tier") not in (None, 1):
            problems.append(f"tier must be 1 or absent: {e['title']}")
        if e.get("result") or not (e.get("espn") and e.get("match")):
            continue
        if en >= today or (today - en).days > 21:
            continue
        try:
            res = winner_of(e["espn"], e["match"], en)
        except Exception as ex:
            print(f"lookup failed for {e['title']}: {ex}", file=sys.stderr)
            continue
        if res:
            e["result"] = res
            changed += 1
            print(f"result: {e['title']}: {res}")
    if problems:
        print("\n".join(problems), file=sys.stderr)
        sys.exit(1)
    if changed:
        data["updated"] = today.isoformat()
        json.dump(data, open(PATH, "w"), indent=1, ensure_ascii=False)
        open(PATH, "a").write("\n")


if __name__ == "__main__":
    if len(sys.argv) == 4 and sys.argv[1] == "--test":
        espn, rest = sys.argv[2], sys.argv[3]
        match, day = rest.split("@")
        print(winner_of(espn, match, dt.date.fromisoformat(day)))
    else:
        main()
