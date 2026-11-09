#!/usr/bin/env python3
"""Build every platform's layout from layout/depl.toml into dist/.

Kalamine writes the Windows and Linux drivers; this script sets the release's
version, corrects what Kalamine gets wrong for a German keyboard and lays out
what the release publishes:

- dist/depl.klc: Windows (MSKLC's source; scripts/build-windows.ps1 compiles it),
- dist/depl.ahk: Windows without administrator rights (AutoHotkey v1),
- dist/depl.bundle: macOS (packed by scripts/build-macos.sh): Apple's German
  layout, macos/German.keylayout, with the recipe's Polish letters on Option
  (see mac_keylayout),
- dist/depl.xkb_symbols, dist/depl.xkb_keymap: Linux (xkb already has it as de(pl)),
- dist/depl.svg: a picture of the layout.

Usage: scripts/build.py [--version X.Y.Z] [--out DIR]
"""

import argparse
import hashlib
import json
import pathlib
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import tomllib

ROOT = pathlib.Path(__file__).resolve().parent.parent
LAYOUT = ROOT / "layout" / "depl.toml"
BUNDLE_ID = "org.ciepiela.keyboardlayout.depl"

# Apple's German layout as Ukelele 3.7.1 ships it (Ukelele_3.7.1.dmg, Resources/
# Standard Keyboards/Roman.bundle); the checksum notices an unintended change.
MAC_GERMAN = ROOT / "macos" / "German.keylayout"
MAC_GERMAN_SHA256 = "f99b8cb39b4ff66e6c427877703476ee4262a25029e77269087f62c04b9ef5dc"
MAC_NAME = "Polish (Germany, Mac)"

# A custom macOS layout needs an ID of its own, other than German's (-15844).
# Negative IDs are the ones Apple leaves to others.
KEYLAYOUT_ID = "-23571"

# Apple's key codes of the letter keys, by the US key at the same place (the
# recipe's names, as Kalamine's JSON writes them): KeyY is German Z.
APPLE_KEY_CODES = {
    f"Key{letter}": code
    for letter, code in zip(
        "ASDFHGZXCVBQWERYTOUIPLJKNM",
        (0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 11, 12, 13, 14, 15, 16, 17)
        + (31, 32, 34, 35, 37, 38, 40, 45, 46),
    )
}
POLISH_LETTERS = "ąćęłńóśźż"

# On the Mac the Polish letters take Option and Option+Shift of their keys, where
# Mac German has å ç € @ ~ ø ‚ ≈ Ω (and Å Ç ‰ ﬂ › Ø Í Ù ˇ). Of those, the ones the
# keys show move to where AltGr has them on the PC (de(pl)): @ to Option+Q, € to
# Option+4 and the ~ dead key to Option++, which give up «, ¢ and ±.
MAC_MOVED = {
    12: 'output="@"',  # Q
    21: 'output="€"',  # 4
    30: 'action="~"',  # +
}

# Windows' German layout (KBDGR) gives these keys these virtual keys, which
# applications' shortcuts refer to (Ctrl+# and the like); Kalamine gives them
# the ones of the US keys at the same place.
GERMAN_VIRTUAL_KEYS = {
    "0c": "OEM_4",  # ß
    "0d": "OEM_6",  # ´
    "1a": "OEM_1",  # ü
    "1b": "OEM_PLUS",  # +
    "27": "OEM_3",  # ö
    "28": "OEM_7",  # ä
    "29": "OEM_5",  # ^
    "2b": "OEM_2",  # #
    "56": "OEM_102",  # <
}


def kalamine(layout: pathlib.Path, workdir: pathlib.Path) -> pathlib.Path:
    """Runs Kalamine on the layout in workdir and returns the directory of its files."""
    subprocess.run(
        [sys.executable, "-m", "kalamine.cli", "build", str(layout)],
        cwd=workdir,
        check=True,
        stdout=subprocess.DEVNULL,
    )
    return workdir / "dist"


def fix_klc(path: pathlib.Path, author: str) -> None:
    """Gives the German keys KBDGR's virtual keys and the DLL its copyright.

    The file is UTF-16 with CR/LF. Kalamine's copyright names its own years.
    """
    text = path.read_text(encoding="utf-16")
    text = re.sub(
        r'^COPYRIGHT\t"[^"]*"', f'COPYRIGHT\t"(c) {author}"', text, flags=re.M
    )
    fixed = 0

    def virtual_key(match: re.Match[str]) -> str:
        nonlocal fixed
        fixed += 1
        return f"{match[1]}\t{GERMAN_VIRTUAL_KEYS[match[1]]}\t"

    pattern = "|".join(GERMAN_VIRTUAL_KEYS)
    text = re.sub(rf"^({pattern})\t(OEM_\w+)\t", virtual_key, text, flags=re.M)
    if fixed != len(GERMAN_VIRTUAL_KEYS):
        sys.exit(f"{path}: {fixed} of {len(GERMAN_VIRTUAL_KEYS)} German keys found")
    path.write_text(text, encoding="utf-16", newline="")


def polish_letters(keymap: dict[str, list[str]]) -> dict[int, tuple[str, str]]:
    """Returns the Polish letters of the recipe (AltGr, AltGr+Shift) by Apple key code."""
    letters = {
        APPLE_KEY_CODES[key]: (levels[2], levels[3])
        for key, levels in keymap.items()
        if len(levels) == 4 and levels[2] in POLISH_LETTERS
    }
    if len(letters) != len(POLISH_LETTERS):
        sys.exit(f"the recipe has {len(letters)} Polish letters on AltGr, not 9")
    return letters


def set_key(keymap: str, code: int, key: str) -> str:
    """Replaces the key of this code in a keyMap element (Apple writes action
    before code, output after it)."""
    pattern = rf'<key (?:action="[^"]*" code="{code}"|code="{code}" output="[^"]*")/>'
    keymap, count = re.subn(pattern, f'<key code="{code}" {key}/>', keymap)
    if count != 1:
        sys.exit(f"{MAC_GERMAN}: key code {code} found {count} times in a key map")
    return keymap


def mac_keylayout(letters: dict[int, tuple[str, str]]) -> str:
    """Apple's German layout with the Polish letters on Option (MAC_MOVED).

    Its key maps 3, 4 and 5 are Option, Option+Shift and Option with Caps Lock;
    Caps Lock gives the capitals, as Mac German's does. The other key maps and
    the JIS keyboards' (which take the ANSI ones) stay as Apple has them.
    """
    data = MAC_GERMAN.read_bytes()
    if hashlib.sha256(data).hexdigest() != MAC_GERMAN_SHA256:
        sys.exit(f"{MAC_GERMAN} is not the file of MAC_GERMAN_SHA256")
    text = data.decode("utf-8")
    text, named = re.subn(
        r'<keyboard group="126" id="-15844" maxout="1" name="German">',
        f'<keyboard group="126" id="{KEYLAYOUT_ID}" maxout="1" name="{MAC_NAME}">',
        text,
    )
    if named != 1:
        sys.exit(f"{MAC_GERMAN}: no <keyboard> element of Apple's German")

    def option_map(match: re.Match[str]) -> str:
        index, keymap = int(match[1]), match[0]
        for code, (lower, upper) in letters.items():
            letter = lower if index == 3 else upper
            keymap = set_key(keymap, code, f'output="{letter}"')
        if index != 4:
            for code, key in MAC_MOVED.items():
                keymap = set_key(keymap, code, key)
        return keymap

    ansi = re.search(r'<keyMapSet id="ANSI">.*?</keyMapSet>', text, re.S)
    if not ansi:
        sys.exit(f"{MAC_GERMAN}: no ANSI key maps")
    keymaps, count = re.subn(
        r'<keyMap index="([345])">.*?</keyMap>', option_map, ansi[0], flags=re.S
    )
    if count != 3:
        sys.exit(f"{MAC_GERMAN}: {count} of the Option key maps 3, 4 and 5 found")
    return text.replace(ansi[0], keymaps)


def fix_xkb(path: pathlib.Path, name: str) -> None:
    """Names the xkb layout by the layout's name, not its description."""
    text = path.read_text(encoding="utf-8")
    text = re.sub(r'name\[group1\]\s*=\s*"[^"]*"', f'name[group1]= "{name}"', text)
    path.write_text(text, encoding="utf-8")


def bundle(keylayout: str, out: pathlib.Path, version: str) -> None:
    """Makes the macOS bundle: the layout with its name and version."""
    resources = out / "Contents" / "Resources"
    resources.mkdir(parents=True)
    (resources / "depl.keylayout").write_text(keylayout, encoding="utf-8")
    info = {
        "CFBundleIdentifier": BUNDLE_ID,
        "CFBundleName": MAC_NAME,
        "CFBundleShortVersionString": version,
        "CFBundleVersion": version,
        "KLInfo_"
        + MAC_NAME: {
            "TISInputSourceID": f"{BUNDLE_ID}.depl",
            "TISIntendedLanguage": "de",
        },
    }
    with (out / "Contents" / "Info.plist").open("wb") as file:
        plistlib.dump(info, file)


def main() -> None:
    """Builds the layouts."""
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--version", help="the release's version, X.Y.Z (a tag's v is dropped)"
    )
    parser.add_argument("--out", type=pathlib.Path, default=ROOT / "dist")
    args = parser.parse_args()

    source = LAYOUT.read_text(encoding="utf-8")
    meta = tomllib.loads(source)
    name = meta["name"]
    version = (args.version or meta["version"]).removeprefix("v")
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        sys.exit(f"version {version!r} is not X.Y.Z")
    source = re.sub(
        r"^version\s*=.*$", f'version     = "{version}"', source, count=1, flags=re.M
    )

    shutil.rmtree(args.out, ignore_errors=True)
    args.out.mkdir(parents=True)
    with tempfile.TemporaryDirectory() as tmp:
        layout = pathlib.Path(tmp) / "depl.toml"
        layout.write_text(source, encoding="utf-8")
        built = kalamine(layout, pathlib.Path(tmp))
        for suffix in (
            ".klc",
            ".ahk",
            ".xkb_symbols",
            ".xkb_keymap",
            ".svg",
        ):
            shutil.copy(built / f"depl{suffix}", args.out)
        keymap = json.loads((built / "depl.json").read_text(encoding="utf-8"))["keymap"]

    fix_klc(args.out / "depl.klc", meta["author"])
    for suffix in (".xkb_symbols", ".xkb_keymap"):
        fix_xkb(args.out / f"depl{suffix}", name)
    bundle(mac_keylayout(polish_letters(keymap)), args.out / "depl.bundle", version)
    (args.out / "VERSION").write_text(version + "\n", encoding="utf-8")
    print(f"{name} {version}: {', '.join(sorted(p.name for p in args.out.iterdir()))}")


if __name__ == "__main__":
    main()
