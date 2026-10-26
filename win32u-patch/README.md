# win32u-patch

`patch-driver-version.sh` makes `app/Sources/AmbaplayApp/Resources/win32u-winecx-11.17.so`
from runtime 4.7.3's `lib/wine/x86_64-unix/win32u.so` (winecx `e0aa380`). It is a binary edit,
not a source patch: `driver_vendor_to_version()` reports NVIDIA as `35.0.15.6094` (560.94) in
the display class key's `DriverVersion`, which games that read it (Deadlock) call out of date,
hiding DLSS. The script replaces that string and the DirectX key's QWORD `DriverVersion`
(`35.0.15.8180`) with `35.0.15.9541` (595.41), the version `nvapi-shim` reports, and signs the
file ad hoc with its original identifier. Keep it in step with `wined3d-patch` and `nvapi-shim`.

```sh
win32u-patch/patch-driver-version.sh "<runtime 4.7.3>/lib/wine/x86_64-unix/win32u.so"
```

The script refuses any input other than runtime 4.7.3's `win32u.so` (sha256
`5ea985227c89b57e5f48d7422059db933d32a213e172577d68e4415d6f7c2a71`). Output sha256
`b012382d09b2ff1b3c0750d93867f72dd04a7c902bc4179be406b6c558ab162d`, pinned in
`FreeEngineWinecx.swift`.
