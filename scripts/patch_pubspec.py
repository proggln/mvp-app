"""Registers the assets folder in the generated pubspec.yaml and writes the launcher icon config."""
import sys

path = sys.argv[1]
s = open(path, encoding="utf-8").read()
if "assets/logo.png" not in s:
    s = s.replace("uses-material-design: true", "uses-material-design: true\n  assets:\n    - assets/logo.png\n    - assets/coin.png\n    - assets/sword.png\n    - assets/tex_diamond.png\n    - assets/tex_netherite.png\n    - assets/tex_obsidian.png\n    - assets/sticker_approved.png\n    - assets/sticker_pending.png\n    - assets/sticker_denied.png", 1)
    if "assets/logo.png" not in s:
        sys.exit("could not add the assets to pubspec.yaml")
open(path, "w", encoding="utf-8").write(s)
print("pubspec patched")
