"""Applies the Google Services Gradle plugin (reads google-services.json) to the generated Android project.
Works with both the Kotlin (.kts) and the Groovy Gradle files that `flutter create` can produce."""
import glob
import os
import re
import sys

root = sys.argv[1]  # the android folder


def patch(path):
    lines = open(path, encoding="utf-8").read().split("\n")
    for i, line in enumerate(lines):
        if re.search(r"com\.android\.application", line) and "google-services" not in line:
            new = line.replace("com.android.application", "com.google.gms.google-services")
            if "version" in new:
                new = re.sub(r'version\s*"[^"]*"', 'version "4.5.0"', new)
            lines.insert(i + 1, new)
            open(path, "w", encoding="utf-8").write("\n".join(lines))
            print("patched", path)
            return True
    return False


settings = [p for p in glob.glob(os.path.join(root, "settings.gradle*"))]
app = [p for p in glob.glob(os.path.join(root, "app", "build.gradle*"))]
ok = all(patch(p) for p in settings[:1]) and all(patch(p) for p in app[:1])
if not (settings and app and ok):
    sys.exit("could not patch the Gradle files")
