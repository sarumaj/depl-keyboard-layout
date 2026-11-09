# depl-keyboard-layout

A keyboard layout to type German and Polish on a German keyboard: German QWERTZ
without dead keys, with the Polish letters on AltGr (on a Mac: Option) and the
letter. It is the layout Ubuntu ships as _Polish (Germany, no dead keys)_, xkb's
`de(pl)`, for Windows and macOS as well.

| Letter | Key         |
| ------ | ----------- |
| ą ć ę  | AltGr+A C E |
| ł ń ó  | AltGr+L N O |
| ś ź ż  | AltGr+S X Z |
| Ą … Ż  | with Shift  |
| €      | AltGr+4     |

AltGr+E is ę, so € moves to AltGr+4. The rest is German without dead keys (`^`,
`´`, `` ` `` type themselves).

## Install

From the
[latest release](https://github.com/sarumaj/depl-keyboard-layout/releases/latest):

- **Windows** (64-bit or 32-bit, not ARM): `depl-<version>-windows-setup.exe`.
  It adds the layout to German (Germany) and to your keyboards; switch with
  Win+Space. Without administrator rights:
  `depl-<version>-windows-autohotkey.ahk` with
  [AutoHotkey v1](https://www.autohotkey.com/).
- **macOS**: `depl-<version>-macos.pkg`. The package is not signed: open it with
  a right click, _Open_. Then System Settings, Keyboard, Text Input, Edit, +,
  German, _Polish (Germany, no dead keys)_. Without the package: unpack
  `depl-<version>-macos-bundle.zip` into `~/Library/Keyboard Layouts` and log
  out and in again.
- **Linux**: xkb has it already: _Polish (Germany, no dead keys)_ in the
  keyboard settings (`setxkbmap de pl`). `depl-<version>-linux-xkb.zip` holds
  the same as files.

A version before 2.0.0 (MSKLC's `Layout02`) is a layout of its own: uninstall it
in Windows' _Apps_ first.

## Build

The layout is written once, in [layout/depl.toml](layout/depl.toml), as a
drawing of the keyboard. [Kalamine](https://github.com/OneDeadKey/kalamine)
makes each system's driver from it:

```bash
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
# dist/: .klc, .ahk, .keylayout, depl.bundle, xkb, .svg
.venv/bin/python scripts/build.py
# Still xkb's de(pl)? Needs xkbcli, xkb-data and x11proto-dev.
scripts/check.py
```

The installers need their systems: `scripts/build-windows.ps1` compiles the
Windows DLLs with MSKLC's kbdutool and packs them with
[Inno Setup](https://jrsoftware.org/isinfo.php) (`windows/depl.iss`),
`scripts/build-macos.sh` makes the macOS package. `scripts/test-windows.ps1` and
`scripts/test-macos.sh` install them and check them.

CI: Forgejo builds and checks the layouts (`.forgejo/workflows/build.yml`). Its
GitHub copy builds and tests the installers on Windows and macOS and, for a tag
`vX.Y.Z`, publishes the release (`.github/workflows/release.yml`), which comes
back to Forgejo.

## Fonts

The repository also holds two fonts of my handwriting, `DaveFont-Regular.otf`
and `DaveFont-Regular.ttf`.
