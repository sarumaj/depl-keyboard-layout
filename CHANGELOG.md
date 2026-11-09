# Changelog

## Unreleased

## 2.0.0 - 2026-11-09

The layout is built from one recipe (`layout/depl.toml`) for Windows, macOS and
Linux, and the release has installers for Windows and macOS.

### Added

- macOS: _Polish (Germany, Mac)_, Apple's German with ą ć ę ł ń ó ś ź ż on
  ⌥A C E L N O S X Z (⌥⇧ for the capitals); @ moves to ⌥Q, € to ⌥4, the ~ dead
  key to ⌥+. A package installs it.
- Windows: an installer for 64-bit and 32-bit Windows that adds the layout to
  German (Germany) and to the keyboards of the person installing; an AutoHotkey
  script for Windows without administrator rights.
- Linux: xkb's _Polish (Germany, no dead keys)_ as files.

### Removed

- BREAKING: the MSKLC layout `Layout02` of 1.0.0. The new Windows layout is
  `depl.dll`, a layout of its own: uninstall `Layout02` in Windows' _Apps_ first.

