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

On a Mac the layout is _Polish (Germany, Mac)_: Apple's German, Option ⌥ (the
key labelled alt) taking AltGr's place for the Polish letters. Three symbols the
keys show move to where AltGr has them on the PC:

| Symbol     | Mac German | This layout |
| ---------- | ---------- | ----------- |
| @          | ⌥L         | ⌥Q          |
| €          | ⌥E         | ⌥4          |
| ~ dead key | ⌥N         | ⌥+          |

Gone are what the keys had besides: å ‚ ≈ ç ø Ω and Å Í Ù Ç ‰ ﬂ › Ø ˇ on the
nine letter keys, « ¢ ± on ⌥Q, ⌥4 and ⌥+. Everything else is Mac German, dead
keys included.

## Install

From the
[latest release](https://github.com/sarumaj/depl-keyboard-layout/releases/latest):

- **Windows** (64-bit or 32-bit, not ARM): `depl-<version>-windows-setup.exe`.
  It adds the layout to German (Germany) and to your keyboards; switch with
  Win+Space. Without administrator rights:
  `depl-<version>-windows-autohotkey.ahk` with
  [AutoHotkey v1](https://www.autohotkey.com/).
- **macOS**: `depl-<version>-macos.pkg`. The package is not signed, so macOS
  refuses to open it; take the mark of the download off first:
  `xattr -d com.apple.quarantine depl-<version>-macos.pkg`, then open it (or
  `sudo installer -pkg depl-<version>-macos.pkg -target /`). Log out and in
  again, then System Settings, Keyboard, Text Input, Edit, +, German, _Polish
  (Germany, Mac)_. Without the package: unpack
  `depl-<version>-macos-bundle.zip`,
  `xattr -dr com.apple.quarantine depl.bundle`, move it into
  `~/Library/Keyboard Layouts` and log out and in again. To remove it: take it
  out of the input sources, delete `depl.bundle` from
  `/Library/Keyboard Layouts` (or `~/Library/Keyboard Layouts`) and log out and
  in again.
- **Linux**: xkb has it already: _Polish (Germany, no dead keys)_ in the
  keyboard settings (`setxkbmap de pl`). `depl-<version>-linux-xkb.zip` holds
  the same as files.

A version before 2.0.0 (MSKLC's `Layout02`) is a layout of its own: uninstall it
in Windows' _Apps_ first.

## Build

The layout is written once, in [layout/depl.toml](layout/depl.toml), as a
drawing of the keyboard. [Kalamine](https://github.com/OneDeadKey/kalamine)
makes the Windows and Linux drivers from it. The Mac layout is Apple's German
(`macos/German.keylayout`, as [Ukelele](https://software.sil.org/ukelele/) 3.7.1
ships it) with the recipe's Polish letters put on Option:

```bash
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
# dist/: .klc, .ahk, depl.bundle, xkb, .svg
.venv/bin/python scripts/build.py
# Still xkb's de(pl)? Needs xkbcli, xkb-data and x11proto-dev.
scripts/check.py
```

The installers need their systems: `scripts/build-windows.ps1` compiles the
Windows DLLs with MSKLC's kbdutool and packs them with
[Inno Setup](https://jrsoftware.org/isinfo.php) (`windows/depl.iss`),
`scripts/build-macos.sh` makes the macOS package. `scripts/test-windows.ps1` and
`scripts/test-macos.sh` install them and type with them.

CI: Forgejo builds and checks the layouts (`.forgejo/workflows/build.yml`). Its
GitHub copy builds and tests the installers on Windows and macOS and, for a tag
`vX.Y.Z`, publishes the release (`.github/workflows/release.yml`), which comes
back to Forgejo.

Releases: commits are
[Conventional Commits](https://www.conventionalcommits.org/) (`.cz.toml`). The
release bot on Forgejo tags the release they call for and writes its section of
`CHANGELOG.md`, from the hand-written `## Unreleased` where there is one; the
tag publishes the release.

## Fonts

The repository also holds two fonts of my handwriting, `DaveFont-Regular.otf`
and `DaveFont-Regular.ttf`.
