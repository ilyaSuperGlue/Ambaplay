# Native installer validation

Local validation on 2026-10-21, Apple Silicon, macOS 27.0.1. The implementation is based
on upstream `9ada9fe`; this records local evidence, not a maintainer-signed release approval.

| Check | Result |
|---|---|
| Toolchain | Xcode 27.1, Swift 6.4, macOS SDK 27.0; initial standalone builds also passed with CLT Swift 6.2.3 |
| Full product build | Passed: Dobby, native components, bridge, fonts, payload and code-signed Ambaplay.app |
| Installer Swift Testing suites | 30 tests in two suites passed, including build resets and read-only prior backups |
| Localization | Main app: 660 strings; installer: 55 strings, translated into Italian and Simplified Chinese |
| Opt-in Setup Assistant snapshots | All three tests passed separately: motion frames, six wizard steps and Status page; the caller created the frames output directory first |
| Existing Setup Assistant visual comparison | Six reference/candidate snapshots; static content panes match pixel-for-pixel, excluding animated rail and changing free-space value |
| Final local release DMG | 781,225 bytes; below the 5 MiB packaging budget |
| `codesign --verify --strict --deep` on installer app | Passed (ad hoc local signature) |
| CI check targets | All 30 targets passed across the full run and the corrected localization rerun; initial full-run failure was limited to localization target scoping |
| Full app Swift tests | 699 tests in 79 suites passed; opt-in real-keychain, mock-endpoint, real-prefix rebuild, GPTK-import and snapshot tests were skipped by their defaults |
| `make scriptcheck runcheck` | Passed with ShellCheck 0.11.0; 41 shell scripts |
| `make native-installercheck` | Passed: signed fixtures, install/update detection, save/config preservation, rejected inputs, lock, rollback, recovery; eight cleanup-identification checks |
| Build ordering after public version reset | Passed: a higher build with a lower 0.x public version remains eligible and installs |
| Live production release 0.7.0 / build 44 | Downloaded 79,164,423 bytes; EdDSA verification, extraction, code signature, isolated installation and installed-state check passed |
| UI download and running-app guard | Real network progress observed; installation refused while the user's Ambaplay was running |
| Already-current wizard | Current signed 3.5.0 fixture detected; no reinstall requested |
| Mounted-DMG completion | Finish with Open disabled ejected the disposable source image and moved that exact DMG to Trash; verified both outcomes |
| Packaged resources and translations | App rendered en, it and zh-Hans with development resource bundles unavailable; all 55 source strings have translations |
| Release dry-run | Completed with no publication and an ephemeral signing key; DMG included as a release asset, while the appcast contains only Ambaplay.zip |
| Independent source review | Four material issues found and fixed: cross-user lock access, offline recovery, cleanup working directory and shared initializer visibility; a subsequent review also caught and resolved read-only backup rotation |

The mounted-image test started the executable with its working directory on that image.
The cleanup helper moved to an external working directory before waiting for exit, so it
did not keep the image busy. The real installed Ambaplay app was not replaced or quit;
Steam, prefixes, saves and user configuration were not deployed to or modified.

## Remaining gates

Public-distribution verification still requires a maintainer signing decision and an actual
quarantined/browser-downloaded launch, including App Translocation and Downloads access.
The local ad hoc build is not notarized. Installer flock serializes installers, while the
process guard provides best-effort coordination with Sparkle; a newly launched updater can
still race it. Multiple real macOS users and external/non-APFS/case-sensitive volumes require
additional runtime coverage. No gameplay, Steam deployment or engine-compatibility claims
are made from bootstrap tests.

Local DMG SHA-256 at the recorded size:

```text
b673af3fdb9a2827ffdfa94e99526921a09feb989e57005d68d5512291fa99ea
```
