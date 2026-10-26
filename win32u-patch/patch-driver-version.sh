#!/bin/sh
# Rebuilds app/Sources/AmbaplayApp/Resources/win32u-winecx-11.17.so from runtime 4.7.3's
# win32u.so (winecx e0aa380). Its driver_vendor_to_version() reports NVIDIA as
# "35.0.15.6094" (560.94) in the display class key's DriverVersion; games that read it
# (Source 2 / Deadlock) call that out of date and hide DLSS behind the NVIDIA identity
# D3DMetal is given. The one copy of the string becomes "35.0.15.9541" (595.41, the
# version nvapi-shim reports), same length, and so does the DirectX key's QWORD
# DriverVersion (35.0.15.8180), then the file is signed ad hoc with its original identifier.
set -eu
src=${1:?usage: patch-driver-version.sh <runtime lib/wine/x86_64-unix/win32u.so>}
out="$(cd "$(dirname "$0")/.." && pwd)/app/Sources/AmbaplayApp/Resources/win32u-winecx-11.17.so"
want=5ea985227c89b57e5f48d7422059db933d32a213e172577d68e4415d6f7c2a71
[ "$(shasum -a 256 "$src" | cut -d' ' -f1)" = "$want" ] || { echo "not runtime 4.7.3's win32u.so" >&2; exit 1; }
ident=$(codesign -dv "$src" 2>&1 | sed -n 's/^Identifier=//p')
python3 - "$src" "$out" <<'PY'
import sys
data = open(sys.argv[1], 'rb').read()
import struct
old, new = b'35.0.15.6094\x00', b'35.0.15.9541\x00'
assert data.count(old) == 1
data = data.replace(old, new)
# HKLM\Software\Microsoft\DirectX\<luid>\DriverVersion, a QWORD immediate: 35.0.15.8180
# (581.80) becomes 35.0.15.9541 too, so every place a game reads the version agrees.
old, new = struct.pack('<Q', 0x230000000f1ff4), struct.pack('<Q', 0x230000000f2545)
assert data.count(old) == 1
open(sys.argv[2], 'wb').write(data.replace(old, new))
PY
codesign -fs - -i "$ident" "$out"
shasum -a 256 "$out"
