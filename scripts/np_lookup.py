"""Shared lookups for the Ambaplay compat tooling (stdlib only).

Sources: Steam store appdetails (platforms), PCGamingWiki page wikitext (API / middleware
templates; its Cargo API is closed to anonymous queries), AreWeAntiCheatYet games.json.
"""
import json
import re
import time
import urllib.parse
import urllib.request

UA = {"User-Agent": "ambaplay-compat-tools/1.0 (+https://github.com/raymondchins/Ambaplay)"}
_last = {}


def _get(url, host_delay=1.0):
    host = urllib.parse.urlsplit(url).netloc
    wait = _last.get(host, 0) + host_delay - time.time()
    if wait > 0:
        time.sleep(wait)
    _last[host] = time.time()
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read().decode("utf-8", "replace")


def store(appid):
    """-> dict(name, windows, mac, linux, type) or None when the store has no entry."""
    url = f"https://store.steampowered.com/api/appdetails?appids={appid}&filters=basic,platforms"
    try:
        d = json.loads(_get(url, 1.6)).get(str(appid), {})
    except Exception:
        return None
    if not d.get("success"):
        return None
    data = d["data"]
    p = data.get("platforms", {})
    return {"name": data.get("name"), "type": data.get("type"), "windows": bool(p.get("windows")),
            "mac": bool(p.get("mac")), "linux": bool(p.get("linux"))}


def _mw(**params):
    params.update(format="json", formatversion="2")
    return json.loads(_get("https://www.pcgamingwiki.com/w/api.php?" + urllib.parse.urlencode(params)))


def _field(text, label):
    m = re.search(r"^\|\s*" + label + r"\s*=([^\n]*)", text, re.I | re.M)
    return m.group(1).strip() if m else ""


def pcgw(appid, name):
    """-> dict(page, d3d, vulkan, win64, anticheat[]) or None. Finds the page by title search
    and verifies the wikitext's `steam appid` field contains appid."""
    clean = re.sub(r"[™®©]", "", name or "").strip()
    titles = []
    for q in dict.fromkeys([clean, clean.split(":")[0], re.sub(r"\s*\(.*?\)", "", clean)]):
        if not q:
            continue
        try:
            titles += [h["title"] for h in _mw(action="query", list="search", srsearch=q, srlimit=4)["query"]["search"]]
        except Exception:
            pass
    for title in dict.fromkeys(titles):
        try:
            wt = _mw(action="parse", page=title, prop="wikitext", redirects="1")["parse"]["wikitext"]
        except Exception:
            continue
        ids = re.findall(r"\d+", _field(wt, r"steam appid") + "," + _field(wt, r"steam appid side"))
        if str(appid) not in ids:
            continue
        ac = [a.strip() for a in re.split(r",|<br\s*/?>", _field(wt, r"anticheat")) if a.strip()]
        return {"page": title, "d3d": _field(wt, r"direct3d versions"), "vulkan": _field(wt, r"vulkan versions"),
                "win64": _field(wt, r"windows 64-bit exe(?:cutable)?"), "anticheat": ac,
                "vr_only": _field(wt, r"vr only").lower() == "true",
                "ray_tracing": _field(wt, r"ray tracing").lower()}
    return None


_awacy = None


def awacy(appid):
    """-> (status, [anticheats]) from AreWeAntiCheatYet, or (None, [])."""
    global _awacy
    if _awacy is None:
        raw = _get("https://raw.githubusercontent.com/AreWeAntiCheatYet/AreWeAntiCheatYet/HEAD/games.json")
        _awacy = {str(g.get("storeIds", {}).get("steam")): g for g in json.loads(raw)}
    g = _awacy.get(str(appid))
    return (g["status"], g.get("anticheats", [])) if g else (None, [])


def api_summary(info):
    """Human API string from a pcgw() result: 'D3D11', 'D3D9+D3D11', 'Vulkan', 'D3D11/Vulkan', '?'."""
    if not info:
        return "?"
    parts = []
    for v in dict.fromkeys(re.findall(r"(?<![\d.])(\d+)", info["d3d"])):
        parts.append("D3D" + v)
    if info["vulkan"].strip():
        parts.append("Vulkan")
    return "+".join(parts) if parts else "?"


def suggest_backend(api, mac_native):
    if mac_native:
        return "native (macOS build)"
    if "D3D11" in api or "D3D10" in api:
        return "dxmt"  # incl. D3D11+D3D12 titles: the main exe only imports d3d12 when D3D12-only
    if "D3D12" in api:
        return "wined3d (d3dmetal when available)"
    if "D3D9" in api:
        return "dxvk"
    if "Vulkan" in api:
        return "dxvk (MoltenVK)"
    if api != "?":
        return "wined3d"
    return "dxmt (unknown API)"


def anticheat_text(info, awacy_res):
    s = []
    if awacy_res[1]:
        s += awacy_res[1]
    if info:
        s += [a for a in info["anticheat"] if a not in s]
    return ", ".join(s) if s else "none known"
