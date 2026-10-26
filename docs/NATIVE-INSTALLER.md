# Native installer

`Ambaplay Installer.app` (shipped as `Ambaplay-Setup.zip` on every app release) installs
or updates `/Applications/Ambaplay.app`. It downloads the app from the release named in
Ambaplay's Sparkle feed and checks its EdDSA signature before extracting it. On a Mac
without Game Porting Toolkit or Steam it also downloads the one-click installer zip
(`Ambaplay-Installer.zip` on the `installer` release, signature in the `.sig` beside it),
checks it against the same key, and runs its `Install.command` without the app step and
without Terminal. That zip carries GPTK, DXMT, DXVK and the default configs, not Wine: the app
downloads the WineCX runtime from dappermint/winecx-gptk during its Setup Assistant (see
[NOTICE](../NOTICE)). Discussion: [issue #17](https://github.com/raymondchins/Ambaplay/issues/17).

## Build

```sh
make native-installer
```

This builds the `AmbaplayInstaller` SwiftPM product for arm64, copies its two resource
bundles, compiles installer translations, renders the Ambaplay mark as the icon, signs the
app and packages `out/Ambaplay-Setup.zip`: the app, `READ ME FIRST.html` (Gatekeeper steps,
with the Geist font inline), `LICENSE`, `NOTICE` and `OFL-Geist.txt`. A ZIP, not a DMG,
because a downloaded DMG makes Gatekeeper ask twice. The default is an ad hoc local build;
`AMBAPLAY_SIGN_IDENTITY` selects the maintainer's signing identity. Packaging fails above
5 MiB unless `AMBAPLAY_INSTALLER_MAX_BYTES` raises the budget for a deliberate size review.

CI packages the ZIP as a build artifact and runs `native-installercheck`.
`scripts/release-local.sh` attaches it to each app release after generating the appcast, so
it never becomes a Sparkle update for the product; its dry run builds an ad hoc copy. The
bootstrap builds without the Wine toolchain; the product build is in
[BUILD-LOCAL.md](BUILD-LOCAL.md). An ad hoc build has no Developer ID signature or
notarization.

## Behavior

The wizard checks the release and installed app, then offers Install or Update. An already
current app requires no download. A newer installed build is kept; the installer refuses a
downgrade. A different application or unsafe destination is not replaced.

The app archive is authenticated with the same public key as the installed app's Sparkle
updater. The app's identity, build, version and code signature are checked before replacement.
The installer stages on the destination volume, coordinates through a persistent lock,
refuses an active Ambaplay/updater process, and keeps the prior app in the hidden
`.Ambaplay.app.previous` sibling for recovery. An interrupted replacement is recovered
locally before release discovery, including when the network is unavailable. Unexpected
backup contents are preserved and reported instead of deleted. An older recovery bundle is
rotated by rename before replacement. Retired copies owned by another account or containing
read-only directories stay intact as `.Ambaplay.app.previous-<UUID>` siblings; an
administrator can remove them in Finder. They do not block subsequent updates.

Prefixes, saves and Steam libraries are never touched. The components step writes only what
`Install.command` writes (`gptk/`, `gamefixes-default/`, the cached DXMT/DXVK archives, and
`default.conf` unless the user edited it; see [installer/README.md](../installer/README.md)).
Opening the installed app continues its Setup Assistant, which downloads the WineCX engine
and sets up Steam. Neither installer changes Sparkle's update feed.

On Finish, users may open Ambaplay. When the installer was started from a mounted disk
image that `hdiutil` identifies exactly, it also offers to eject the image and move it to
Trash; a helper outside the volume does that after the installer exits. Failures keep the
image and show a message. Nothing is deleted permanently.

## Verification

Run the focused installer core tests with the full app tests on the supported Xcode:

```sh
make app-tests
make scriptcheck runcheck native-installercheck
```

`scripts/test-native-installer.sh` runs an additional standalone smoke suite against the
production core sources without depending on the full app test bundle. It uses generated
signing keys and temporary app roots, leaving installed apps and game data alone.

For visual review, the executable supports deterministic, non-mutating preview states:

```sh
app/.build/debug/AmbaplayInstaller --preview update --screenshot /tmp/installer-update.png
```

For an isolated GUI test, a debug build also accepts `--test-destination` with a
`Ambaplay.app` path inside the macOS temporary directory. Release builds always use
Applications. Do not open the installed test app unless you intend to exercise real setup.

States are `review`, `update`, `download`, `install`, `done`, `current`, and `error`.
Preview screenshots establish appearance; they do not establish install/update success.

Before public rollout, exercise a fresh install, older/current/newer app, real component
setup, offline/retry, rejected signatures, low disk/permission failures, concurrent
install/update, interrupted replacement, multiple macOS users, external/case-sensitive
volumes, supported OS versions, all locales, keyboard/VoiceOver, and cleanup enabled/disabled.
Record the actual packaged size and separate local ad hoc verification from maintainer-signed
release validation. The contributor writes the PR description personally per CONTRIBUTING.md;
release publishing and keys remain with the maintainer.
