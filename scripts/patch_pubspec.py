"""Registers the assets folder in the generated pubspec.yaml and writes the launcher icon config."""
import sys

path = sys.argv[1]
s = open(path, encoding="utf-8").read()
if "assets/logo.png" not in s:
    s = s.replace("uses-material-design: true", "uses-material-design: true\n  assets:\n    - assets/logo.png\n    - assets/coin.png\n    - assets/sword.png", 1)
    if "assets/logo.png" not in s:
        sys.exit("could not add the assets to pubspec.yaml")
open(path, "w", encoding="utf-8").write(s)
print("pubspec patched")
