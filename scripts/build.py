#!/usr/bin/env python3
"""Build every platform's layout from layout/depl.toml into dist/.

Kalamine writes the drivers; this script sets the release's version, corrects
what Kalamine gets wrong for a German keyboard and lays out what the release
publishes:

- dist/depl.klc: Windows (MSKLC's source; scripts/build-windows.ps1 compiles it),
- dist/depl.ahk: Windows without administrator rights (AutoHotkey v1),
- dist/depl.bundle: macOS (packed by scripts/build-macos.sh),
- dist/depl.xkb_symbols, dist/depl.xkb_keymap: Linux (xkb already has it as de(pl)),
- dist/depl.svg: a picture of the layout.

Usage: scripts/build.py [--version X.Y.Z] [--out DIR]
"""

import argparse
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

# A custom macOS layout needs an ID of its own: Kalamine writes 0, the ID of
# Apple's U.S. layout. Negative IDs are the ones Apple leaves to others.
KEYLAYOUT_ID = "-23571"

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


def fix_keylayout(path: pathlib.Path, name: str) -> None:
    """Names the layout, gives it an ID of its own and swaps ^ and < back.

    Kalamine puts the key left of 1 on key code 50 and the one right of the left
    Shift on 10; Apple's ISO keyboards send them the other way round, as Apple's
    German layout has them (https://github.com/OneDeadKey/kalamine/issues/210).
    The file is declared XML 1.1, as Apple's layouts are: its control keys'
    outputs (&#x0008; for backspace) are not allowed in XML 1.0. A layout without
    dead keys has no terminators, and Apple's DTD wants none rather than an empty
    element.

    Kalamine types the space bar through actions (for its dead keys), and macOS
    typed nothing with them. Without dead keys the space bar outputs its character
    directly, as in Apple's layouts, and no actions are left.
    """
    text = path.read_text(encoding="utf-8")
    text = text.replace('<?xml version="1.0"', '<?xml version="1.1"', 1)
    text = re.sub(r"\n\s*<terminators>\s*</terminators>", "", text)
    text = re.sub(
        r'action="spce_x([0-9a-f]{4})"',
        lambda m: f'output="{chr(int(m[1], 16))}"',
        text,
    )
    if "action=" in text:
        sys.exit(f"{path}: a key other than the space bar has an action")
    text = re.sub(r"\n\s*<actions>.*?</actions>", "", text, flags=re.S)
    text, named = re.subn(
        r'<keyboard group="0" id="0" name="[^"]*"',
        f'<keyboard group="0" id="{KEYLAYOUT_ID}" name="{name}"',
        text,
    )
    swap = {"10": "50", "50": "10"}
    text, swapped = re.subn(
        r'<key code="(10|50)"', lambda m: f'<key code="{swap[m[1]]}"', text
    )
    if named != 1 or swapped == 0:
        sys.exit(
            f"{path}: Kalamine's output changed (named {named}, swapped {swapped})"
        )
    path.write_text(text, encoding="utf-8")


def fix_xkb(path: pathlib.Path, name: str) -> None:
    """Names the xkb layout by the layout's name, not its description."""
    text = path.read_text(encoding="utf-8")
    text = re.sub(r'name\[group1\]\s*=\s*"[^"]*"', f'name[group1]= "{name}"', text)
    path.write_text(text, encoding="utf-8")


def bundle(keylayout: pathlib.Path, out: pathlib.Path, name: str, version: str) -> None:
    """Makes the macOS bundle: the layout with its name and version."""
    resources = out / "Contents" / "Resources"
    resources.mkdir(parents=True)
    shutil.copy(keylayout, resources / "depl.keylayout")
    info = {
        "CFBundleIdentifier": BUNDLE_ID,
        "CFBundleName": name,
        "CFBundleShortVersionString": version,
        "CFBundleVersion": version,
        "KLInfo_"
        + name: {
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
            ".keylayout",
            ".xkb_symbols",
            ".xkb_keymap",
            ".svg",
        ):
            shutil.copy(built / f"depl{suffix}", args.out)

    fix_klc(args.out / "depl.klc", meta["author"])
    fix_keylayout(args.out / "depl.keylayout", name)
    for suffix in (".xkb_symbols", ".xkb_keymap"):
        fix_xkb(args.out / f"depl{suffix}", name)
    bundle(args.out / "depl.keylayout", args.out / "depl.bundle", name, version)
    (args.out / "VERSION").write_text(version + "\n", encoding="utf-8")
    print(f"{name} {version}: {', '.join(sorted(p.name for p in args.out.iterdir()))}")


if __name__ == "__main__":
    main()
