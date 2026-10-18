#!/usr/bin/env python3
"""design/tokens.json is the source of the colours. Fails when Palette.swift or the Mini App's styles.css differ.
   usage: scripts/check-tokens.py [path-to-miniapp/src/styles.css]"""
import json, re, sys, os
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
tok = json.load(open(os.path.join(root, "design/tokens.json")))
bad = []
swift = open(os.path.join(root, "Sources/Core/Palette.swift")).read()
for name, (l, d) in tok.items():
    m = re.search(r"static let %s: Pair = \(0x([0-9a-f]{6}), 0x([0-9a-f]{6})\)" % name, swift)
    if not m or ("#" + m.group(1), "#" + m.group(2)) != (l, d):
        bad.append("Palette.swift: " + name)
if len(sys.argv) > 1:
    css = open(sys.argv[1]).read()
    light, dark = css.split(':root[data-theme="dark"]')[0], css.split(':root[data-theme="dark"]')[1].split("}")[0]
    for name in ("muted", "accent", "good", "warn", "bad", "text", "bg"):
        for part, i in ((light, 0), (dark, 1)):
            m = re.search(r"--%s: (#[0-9a-f]{6});" % name, part)
            if not m or m.group(1) != tok[name][i]:
                bad.append("styles.css: %s %s" % (name, "dark" if i else "light"))
print("tokens OK" if not bad else "MISMATCH:\n  " + "\n  ".join(bad))
sys.exit(1 if bad else 0)
