#!/usr/bin/env python3
"""Prepend a token to the Steam launch options of the given app IDs.

usage: steam-launch-options.py <localconfig.vdf> <TOKEN> <appid...>

Edits userdata/<id>/config/localconfig.vdf in place. Run it only while Steam
is fully closed (Steam rewrites the file on exit). A token already present is
left alone; an app with no launch options gets "<TOKEN> %command%".

A token is written with the public 3.0.0 spelling (AMBAPLAY_*, ~/.ambaplay/...)
even when given as NOTPROTON_* or ~/.notproton/...; either spelling already in the
launch options counts as present.
"""
import re
import sys


def public(t):
    return re.sub(r"\bNOTPROTON_", "AMBAPLAY_", t.replace("/.notproton/", "/.ambaplay/"))


def legacy(t):
    return re.sub(r"\bAMBAPLAY_", "NOTPROTON_", t.replace("/.ambaplay/", "/.notproton/"))


path, token = sys.argv[1], public(sys.argv[2])
spellings = {token, legacy(token)}
ids = set(sys.argv[3:])
lines = open(path, encoding="utf-8").read().split("\n")
out, done, in_apps, i = [], set(), False, 0
while i < len(lines):
    line = lines[i]
    out.append(line)
    if line == '\t\t\t\t"apps"':
        in_apps = True
    m = re.fullmatch(r'\t{5}"(\d+)"', line)
    if in_apps and m and m.group(1) in ids and i + 1 < len(lines) and lines[i + 1] == "\t\t\t\t\t{":
        out.append(lines[i + 1])
        i += 2
        block = []
        while i < len(lines) and lines[i] != "\t\t\t\t\t}":
            block.append(lines[i])
            i += 1
        found = False
        for k, b in enumerate(block):
            mm = re.fullmatch(r'(\t{6}"LaunchOptions"\t\t")(.*)(")', b)
            if mm:
                found = True
                val = mm.group(2)
                if not spellings & set(val.split()):
                    rest = val if "%command%" in val else (val + " %command%").strip()
                    val = f"{token} {rest}"
                block[k] = mm.group(1) + val + mm.group(3)
        if not found:
            block.append(f'\t\t\t\t\t\t"LaunchOptions"\t\t"{token} %command%"')
        out.extend(block)
        done.add(m.group(1))
        continue
    i += 1
open(path, "w", encoding="utf-8").write("\n".join(out))
print("updated", sorted(done), "missing", sorted(ids - done))
