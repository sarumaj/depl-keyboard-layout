// Types with the installed macOS layout as macOS does (UCKeyTranslate on the
// layout macOS compiled from the bundle) and compares with what it should type:
// the Polish letters on Option, the moved @ € ~, and Mac German elsewhere.
//
// Usage: swift scripts/test-macos-layout.swift "/Library/Keyboard Layouts/depl.bundle"
import Carbon
import Foundation

let sourceID = "org.ciepiela.keyboardlayout.depl.depl"
let bundle = URL(fileURLWithPath: CommandLine.arguments[1])
TISRegisterInputSource(bundle as CFURL)
let filter = [kTISPropertyInputSourceID as String: sourceID] as CFDictionary
guard
    let sources = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource],
    let source = sources.first,
    let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
else {
    print("macOS has no input source \(sourceID) from \(bundle.path)")
    exit(1)
}
let layoutData = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue() as Data

let none: UInt32 = 0
let shift = UInt32(shiftKey >> 8) & 0xFF
let option = UInt32(optionKey >> 8) & 0xFF

// Types the keys (key code, modifiers) one after the other, dead keys included.
func type(_ keys: [(UInt16, UInt32)]) -> String {
    var deadKeyState: UInt32 = 0
    var typed = ""
    layoutData.withUnsafeBytes { raw in
        let layout = raw.baseAddress!.assumingMemoryBound(to: UCKeyboardLayout.self)
        for (code, modifiers) in keys {
            var chars = [UniChar](repeating: 0, count: 8)
            var length = 0
            UCKeyTranslate(
                layout, code, UInt16(kUCKeyActionDown), modifiers, UInt32(LMGetKbdType()),
                0, &deadKeyState, chars.count, &length, &chars)
            typed += String(utf16CodeUnits: chars, count: length)
        }
    }
    return typed
}

// Key codes: A 0, S 1, X 7, C 8, Q 12, E 14, German Z 16, 4 21, 6 22, 5 23,
// ´ 24, 9 25, 7 26, 8 28, + 30, O 31, L 37, N 45, space 49, ^ 10, < 50.
let letters: [(UInt16, String, String)] = [
    (0, "ą", "Ą"), (8, "ć", "Ć"), (14, "ę", "Ę"), (37, "ł", "Ł"), (45, "ń", "Ń"),
    (31, "ó", "Ó"), (1, "ś", "Ś"), (7, "ź", "Ź"), (16, "ż", "Ż"),
]
var cases: [([(UInt16, UInt32)], String)] = [
    ([(49, none)], " "),
    ([(0, none), (49, none), (16, shift)], "a Z"),
    ([(12, option)], "@"),
    ([(21, option)], "€"),
    ([(30, option), (45, none)], "ñ"),
    ([(23, option), (22, option), (26, option), (28, option), (25, option)], "[]|{}"),
    ([(26, option | shift)], "\\"),
    ([(24, none), (14, none)], "é"),
    ([(10, none), (49, none)], "^"),
    ([(50, none)], "<"),
]
for (code, lower, upper) in letters {
    cases.append(([(code, option)], lower))
    cases.append(([(code, option | shift)], upper))
}

var failed = 0
for (keys, expected) in cases {
    let typed = type(keys)
    if typed != expected {
        print("keys \(keys.map { "\($0.0)+\($0.1)" }): \(typed) instead of \(expected)")
        failed += 1
    }
}
if failed > 0 {
    exit(1)
}
print("The layout types \(cases.count) key sequences as it should.")
