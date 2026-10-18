"""Turns on core library desugaring (needed by the in-app updater plugin). Works with Kotlin (.kts) and Groovy Gradle."""
import glob
import os
import re
import sys

root = sys.argv[1]
files = glob.glob(os.path.join(root, "app", "build.gradle*"))
if not files:
    sys.exit("app build.gradle not found")
path = files[0]
kts = path.endswith(".kts")
s = open(path, encoding="utf-8").read()
if "coreLibraryDesugaring" in s or "CoreLibraryDesugaringEnabled" in s:
    print("desugaring already on")
    sys.exit(0)
flag = "isCoreLibraryDesugaringEnabled = true" if kts else "coreLibraryDesugaringEnabled true"
m = re.search(r"compileOptions\s*\{", s)
if not m:
    sys.exit("compileOptions not found in " + path)
s = s[: m.end()] + "\n        " + flag + s[m.end():]
dep = 'coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")' if kts else "coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'"
if re.search(r"^dependencies\s*\{", s, re.M):
    s = re.sub(r"^dependencies\s*\{", "dependencies {\n    " + dep, s, count=1, flags=re.M)
else:
    s += "\ndependencies {\n    " + dep + "\n}\n"
open(path, "w", encoding="utf-8").write(s)
print("desugaring enabled in", path)
