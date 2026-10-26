#!/usr/bin/env python3
"""Write compat/reported.json: Steam games that AppleGamingWiki players report as Perfect or
Playable under CrossOver (WineCX + D3DMetal, the engine Ambaplay uses).

These are not Ambaplay test results. The site shows them as "Should work" for games
games.json has not tested yet. Data is CC BY-NC-SA 3.0 from AppleGamingWiki; keep the
attribution in the output and on the page.

Usage: scripts/compat-reported.py   (about 2 requests a second; takes a few minutes)
"""
import datetime
import json
import os
import re
import sys
import time
import urllib.parse
import urllib.request

API = "https://www.applegamingwiki.com/w/api.php"
UA = "Ambaplay compat list (https://github.com/raymondchins/Ambaplay)"
GOOD = {"perfect", "playable"}
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "compat", "reported.json")


def api(**params):
    params.update(format="json", formatversion="2")
    req = urllib.request.Request(API + "?" + urllib.parse.urlencode(params), headers={"User-Agent": UA})
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                # Some wikitext carries raw control characters, which strict JSON rejects.
                return json.loads(r.read().decode("utf-8"), strict=False)
        except Exception as e:  # noqa: BLE001 - retry any network or decode error
            if attempt == 3:
                raise
            print(f"  retry after {e}", file=sys.stderr)
            time.sleep(5 * (attempt + 1))
        finally:
            time.sleep(0.5)


def pages():
    cont = {}
    while True:
        d = api(action="query", list="embeddedin", eititle="Template:Compatibility/macOS",
                einamespace=0, eilimit=500, **cont)
        yield from (p["title"] for p in d["query"]["embeddedin"])
        if "continue" not in d:
            return
        cont = {"eicontinue": d["continue"]["eicontinue"]}


def field(text, name):
    m = re.search(r"^\s*\|\s*" + re.escape(name) + r"\s*=\s*(.*)$", text, re.M | re.I)
    return m.group(1).strip() if m else ""


def main():
    titles = list(pages())
    print(f"{len(titles)} pages with macOS compatibility", file=sys.stderr)
    games = {}
    for i in range(0, len(titles), 50):
        d = api(action="query", prop="revisions", rvprop="content", rvslots="main", titles="|".join(titles[i:i + 50]))
        for p in d["query"]["pages"]:
            text = (p.get("revisions") or [{}])[0].get("slots", {}).get("main", {}).get("content", "")
            rating = field(text, "crossover").lower()
            if rating in GOOD:
                for value in field(text, "steam appid").split(","):
                    appid = value.strip()
                    if appid.isdigit():
                        games[int(appid)] = {
                            "appid": int(appid), "name": p["title"], "crossover": rating,
                            "page": "https://www.applegamingwiki.com/wiki/" +
                                    urllib.parse.quote(p["title"].replace(" ", "_")),
                        }
        print(f"  {min(i + 50, len(titles))}/{len(titles)}: {len(games)} should work", file=sys.stderr)
    out = {
        "source": "AppleGamingWiki, CrossOver ratings (https://www.applegamingwiki.com)",
        "license": "CC BY-NC-SA 3.0 (https://creativecommons.org/licenses/by-nc-sa/3.0/)",
        "fetched": datetime.date.today().isoformat(),
        "games": sorted(games.values(), key=lambda g: g["name"].lower()),
    }
    with open(OUT, "w") as f:
        json.dump(out, f, indent=1, ensure_ascii=False)
        f.write("\n")
    print(f"wrote {OUT}: {len(games)} games", file=sys.stderr)


if __name__ == "__main__":
    main()
