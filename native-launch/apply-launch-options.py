#!/usr/bin/env python3
"""Point the native macOS games' Steam launch options at np-native.

    python3 native-launch/apply-launch-options.py [--dry-run] <localconfig.vdf>

For each app id in GAMES the LaunchOptions value becomes

    ~/.ambaplay/np-native NP_PAD_MODE=<mode> [SDL_JOYSTICK_MFI=0] \
        MTL_HUD_ENABLED=1 [other VAR=VALUE kept from the old prefix] \
        %command% <game flags that followed %command%>

The old prefix may be the `/usr/bin/arch ... -e VAR=VALUE` form, a
`/usr/bin/env VAR=VALUE` form, plain `VAR=VALUE` tokens or an earlier np-native
line, including one under the pre-3.0 ~/.notproton/np-native path; anything
else is reported and that app is left untouched. Running it twice changes
nothing the second time.

Steam rewrites localconfig.vdf on exit, so the script refuses to run while
steam_osx is up. --allow-running exists for tests on a copy and is refused
for files inside the Steam folder. A timestamped backup is written next to
the file before the first change.
"""
import argparse
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import time

NP_NATIVE = os.path.join(os.path.expanduser("~"), ".ambaplay", "np-native")
LEGACY_NP_NATIVE = os.path.join(os.path.expanduser("~"), ".notproton", "np-native")
STEAM_DIR = os.path.join(os.path.expanduser("~"), "Library", "Application Support", "Steam")

# app id -> pad mode (from the per-game research in native-games.json)
GAMES = {
    "1049410": "hid",  # Superliminal
    "1091500": "gc",   # Cyberpunk 2077
    "1145350": "hid",  # Hades II
    "1145360": "hid",  # Hades
    "1703340": "hid",  # The Stanley Parable Ultra Deluxe
    "239140": "hid",   # Dying Light
    "250900": "hid",  # The Binding of Isaac Rebirth
    "274190": "hid",  # Broforce
    "275850": "gc",  # No Man's Sky
    "286160": "hid",  # Tabletop Simulator
    "49520": "hid",  # Borderlands 2
    "570": "hid",      # Dota 2
    "728880": "hid",  # Overcooked! 2
    "870780": "gc",  # Control
    "934700": "gc",  # Dead Island 2
    "3569420": "hid",  # Chained Beasts
    "3978510": "hid",  # Chained Beasts Demo
}
# SDL builds with their own MFi backend would see the pad twice
NO_MFI = {"1145350", "570"}

MANAGED = {"DYLD_INSERT_LIBRARIES", "NP_PAD_MODE", "SDL_JOYSTICK_MFI", "MTL_HUD_ENABLED"}
ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
NP_NAME = re.compile(r"^[A-Z_][A-Z0-9_]*$")  # what np-native accepts
WRAPPERS = {"/usr/bin/arch", "/usr/bin/env", "arch", "env", NP_NATIVE, LEGACY_NP_NATIVE}
ARCH_FLAGS = {"-arm64", "-x86_64", "-arm64e", "-i386"}

LINE = re.compile(r'^(?P<ind>\s*)"(?P<key>(?:[^"\\]|\\.)*)"(?:(?P<sep>\s+)"(?P<val>(?:[^"\\]|\\.)*)")?\s*$')


def vdf_unescape(s):
    return re.sub(r"\\(.)", lambda m: {"n": "\n", "t": "\t"}.get(m.group(1), m.group(1)), s)


def vdf_escape(s):
    return s.replace("\\", "\\\\").replace('"', '\\"')


def new_options(appid, old):
    """Returns (new value, None) or (None, reason it was skipped)."""
    if "%command%" in old:
        pre, post = old.split("%command%", 1)
    else:
        pre, post = "", old  # Steam appends bare options to the command
    flags = post.strip()
    try:
        toks = shlex.split(pre)
    except ValueError as e:
        return None, "cannot parse prefix (%s)" % e
    extras = []
    i = 0
    while i < len(toks):
        t = toks[i]
        if t == "-e" and i + 1 < len(toks):
            i += 1
            t = toks[i]
            if not ASSIGN.match(t):
                return None, "unexpected '-e %s' in prefix" % t
        if ASSIGN.match(t):
            name = t.split("=", 1)[0]
            if name not in MANAGED:
                if not NP_NAME.match(name):
                    return None, "np-native only takes [A-Z_][A-Z0-9_]* names, not %r" % name
                extras.append(t)
        elif t in WRAPPERS or t in ARCH_FLAGS or t == "--":
            pass
        else:
            return None, "unknown token %r before %%command%%" % t
        i += 1
    parts = [NP_NATIVE, "NP_PAD_MODE=" + GAMES[appid]]
    if appid in NO_MFI:
        parts.append("SDL_JOYSTICK_MFI=0")
    parts.append("MTL_HUD_ENABLED=1")
    parts += [shlex.quote(e) for e in extras]
    parts.append("%command%")
    if flags:
        parts.append(flags)
    return " ".join(parts), None


def in_apps(path):
    """True for the key path <root>/Software/Valve/Steam/apps."""
    return len(path) == 5 and all(path) and \
        [k.lower() for k in path[1:]] == ["software", "valve", "steam", "apps"]


def rewrite(text):
    """Returns (new text, report lines, number of changed apps)."""
    lines = text.splitlines(keepends=True)
    stack = []          # key path of open blocks
    pending = None      # key waiting for its "{"
    apps = {}           # appid -> dict(open=idx of "{", close=idx, opt=idx, indent)
    for idx, raw in enumerate(lines):
        s = raw.strip()
        if s == "{":
            stack.append(pending)
            pending = None
            if in_apps(stack[:-1]) and stack[-1] in GAMES:
                apps[stack[-1]] = {"open": idx, "opt": None,
                                   "indent": re.match(r"\s*", raw).group(0)}
            continue
        if s == "}":
            if not stack:
                raise SystemExit("malformed vdf: unbalanced '}' at line %d" % (idx + 1))
            closed = stack.pop()
            if closed in apps and in_apps(stack):
                apps[closed]["close"] = idx
            continue
        if not s:
            continue
        m = LINE.match(raw.rstrip("\r\n"))
        if not m:
            raise SystemExit("malformed vdf at line %d: %r" % (idx + 1, s[:80]))
        if m.group("val") is None:
            pending = vdf_unescape(m.group("key"))
            continue
        if m.group("key").lower() == "launchoptions" and stack[-1:] and stack[-1] in apps \
                and in_apps(stack[:-1]):
            apps[stack[-1]]["opt"] = idx
    if stack:
        raise SystemExit("malformed vdf: %d unclosed block(s)" % len(stack))

    report, changed, inserts = [], 0, []
    for appid in GAMES:
        a = apps.get(appid)
        if a is None:
            report.append("%-8s MISSING (no app block in Software/Valve/Steam/apps)" % appid)
            continue
        if a["opt"] is not None:
            m = LINE.match(lines[a["opt"]].rstrip("\r\n"))
            old = vdf_unescape(m.group("val"))
        else:
            old = ""
        new, why = new_options(appid, old)
        if new is None:
            report.append("%-8s SKIPPED: %s\n         old: %s" % (appid, why, old))
            continue
        if new == old:
            report.append("%-8s unchanged: %s" % (appid, old))
            continue
        changed += 1
        report.append("%-8s before: %s\n         after:  %s" % (appid, old or "(none)", new))
        if a["opt"] is not None:
            raw = lines[a["opt"]]
            eol = raw[len(raw.rstrip("\r\n")):]
            m = LINE.match(raw.rstrip("\r\n"))
            lines[a["opt"]] = '%s"%s"%s"%s"%s' % (m.group("ind"), m.group("key"),
                                                 m.group("sep"), vdf_escape(new), eol)
        else:
            raw = lines[a["open"]]
            eol = raw[len(raw.rstrip("\r\n")):] or "\n"
            inserts.append((a["open"] + 1,
                            '%s\t"LaunchOptions"\t\t"%s"%s' % (a["indent"], vdf_escape(new), eol)))
    for pos, line in sorted(inserts, reverse=True):
        lines.insert(pos, line)
    return "".join(lines), report, changed


def steam_running():
    try:
        return subprocess.run(["/usr/bin/pgrep", "-x", "steam_osx"],
                              stdout=subprocess.DEVNULL).returncode == 0
    except OSError:
        return True  # cannot tell: assume it is


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("vdf", help="path to userdata/<id>/config/localconfig.vdf")
    ap.add_argument("--dry-run", action="store_true", help="print the changes, write nothing")
    ap.add_argument("--allow-running", action="store_true",
                    help="skip the Steam check (only for copies outside the Steam folder)")
    args = ap.parse_args()

    path = os.path.realpath(args.vdf)
    in_steam = path.startswith(os.path.realpath(STEAM_DIR) + os.sep)
    if args.allow_running and in_steam:
        sys.exit("refusing --allow-running for a file inside the Steam folder: %s" % path)
    if not args.allow_running and not args.dry_run and steam_running():
        sys.exit("Steam is running (steam_osx); quit Steam first, it rewrites %s on exit"
                 % os.path.basename(path))

    with open(path, encoding="utf-8", newline="") as f:
        text = f.read()
    new, report, changed = rewrite(text)
    print("\n".join(report))
    if not changed:
        print("==> nothing to change")
        return
    if args.dry_run:
        print("==> %d app(s) would change (dry run)" % changed)
        return
    backup = "%s.bak-np-native-%s" % (path, time.strftime("%Y%m%d-%H%M%S"))
    shutil.copy2(path, backup)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".localconfig.")
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="") as f:
            f.write(new)
        shutil.copymode(path, tmp)
        os.replace(tmp, path)
    except BaseException:
        os.unlink(tmp)
        raise
    print("==> %d app(s) changed; backup at %s" % (changed, backup))


if __name__ == "__main__":
    main()
