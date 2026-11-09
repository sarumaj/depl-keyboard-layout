#!/usr/bin/env python3
"""Check that the built layout is xkb's de(pl), the layout it copies.

Compiles xkb's "Polish (Germany, no dead keys)" and dist/depl.xkb_keymap with
xkbcli and compares the four levels of every key of the typing area. Needs
xkbcli (libxkbcommon-tools), xkb-data and keysymdef.h (x11proto-dev).

Usage: scripts/check.py [DIST]
"""

import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
KEYSYMDEF = pathlib.Path("/usr/include/X11/keysymdef.h")
KEYS = (
    ["TLDE", "BKSL", "LSGT"]
    + [f"AE{i:02}" for i in range(1, 13)]
    + [f"AD{i:02}" for i in range(1, 13)]
    + [f"AC{i:02}" for i in range(1, 12)]
    + [f"AB{i:02}" for i in range(1, 11)]
)


def keysym_chars() -> dict[str, str]:
    """Maps keysym names to their characters, from keysymdef.h.

    A Latin-1 keysym's value is its character, as is the low part of a Unicode
    keysym's (0x01000000 + code point); the others name theirs in a comment
    (U+20AC). Aliases (guillemotright) have their value but no comment.
    """
    chars = {}
    pattern = re.compile(
        r"^#define XK_(\w+)\s+0x([0-9a-f]+)(?:\s*/\*[ (]*U\+([0-9A-F]{4,6}))?", re.M
    )
    for name, value, code in pattern.findall(KEYSYMDEF.read_text(encoding="utf-8")):
        keysym = int(value, 16)
        if 0x20 <= keysym <= 0xFF:
            chars[name] = chr(keysym)
        elif keysym & 0xFF000000 == 0x01000000:
            chars[name] = chr(keysym & 0xFFFFFF)
        elif code:
            chars[name] = chr(int(code, 16))
    return chars


def levels(keymap: str, chars: dict[str, str]) -> dict[str, list[str]]:
    """Returns the characters of the first four levels of each key of a compiled keymap."""
    symbols = keymap[keymap.index("xkb_symbols") :]
    result = {}
    for name, body in re.findall(r"key <(\w+)>\s*\{(.*?)\};", symbols, re.S):
        # xkbcli writes symbols[Group1]= [...] for a key with a type, [...] alone otherwise.
        group = re.search(r"symbols\[Group1\]\s*=\s*\[([^\]]*)\]", body) or re.search(
            r"\[([^\]]*)\]", body
        )
        if not group:
            continue
        syms = [s.strip() for s in group[1].split(",")][:4]
        result[name] = [
            (
                chr(int(s[1:], 16))
                if re.fullmatch(r"U[0-9A-Fa-f]{4,6}", s)
                else chars.get(s, s)
            )
            for s in syms
        ]
    return result


def compile_keymap(*args: str, stdin: str | None = None) -> str:
    """Runs xkbcli compile-keymap and returns the keymap.

    The exit code is not looked at: with --from-xkb, xkbcli up to 1.7 (Ubuntu
    24.04, Debian 13) exits with 1 after printing the keymap.
    """
    result = subprocess.run(
        ["xkbcli", "compile-keymap", *args],
        input=stdin,
        capture_output=True,
        text=True,
        check=False,
    )
    if "xkb_symbols" not in result.stdout:
        sys.exit(f"xkbcli compile-keymap {' '.join(args)} failed:\n{result.stderr}")
    return result.stdout


def main() -> None:
    """Compares the built layout with xkb's de(pl)."""
    dist = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "dist"
    chars = keysym_chars()
    expected = levels(compile_keymap("--layout", "de", "--variant", "pl"), chars)
    built_keymap = (dist / "depl.xkb_keymap").read_text(encoding="utf-8")
    built = levels(compile_keymap("--from-xkb", stdin=built_keymap), chars)
    errors = [
        f"<{key}>: {' '.join(built.get(key, []))} instead of {' '.join(expected[key])}"
        for key in KEYS
        if built.get(key) != expected[key]
    ]
    if errors:
        sys.exit("The layout differs from xkb's de(pl):\n" + "\n".join(errors))
    print(f"The layout is xkb's de(pl): {len(KEYS)} keys, four levels each.")


if __name__ == "__main__":
    main()
