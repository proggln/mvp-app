"""Makes the release build use our own key (android/key.properties + android/app/release.jks).
Works with both the Kotlin (.kts) and Groovy Gradle files that `flutter create` can produce."""
import glob
import os
import re
import sys

root = sys.argv[1]  # the android folder
files = glob.glob(os.path.join(root, "app", "build.gradle*"))
if not files:
    sys.exit("app build.gradle not found")
path = files[0]
s = open(path, encoding="utf-8").read()
kts = path.endswith(".kts")

if kts:
    block = '''    signingConfigs {
        create("release") {
            val props = java.util.Properties()
            props.load(java.io.FileInputStream(rootProject.file("key.properties")))
            keyAlias = props["keyAlias"] as String
            keyPassword = props["keyPassword"] as String
            storeFile = file(props["storeFile"] as String)
            storePassword = props["storePassword"] as String
        }
    }

'''
    use = 'signingConfig = signingConfigs.getByName("release")'
else:
    block = '''    signingConfigs {
        release {
            def props = new Properties()
            props.load(new FileInputStream(rootProject.file("key.properties")))
            keyAlias props["keyAlias"]
            keyPassword props["keyPassword"]
            storeFile file(props["storeFile"])
            storePassword props["storePassword"]
        }
    }

'''
    use = "signingConfig signingConfigs.release"
    if "import java.util.Properties" not in s:
        s = "import java.util.Properties\nimport java.io.FileInputStream\n" + s

m = re.search(r"^[ \t]*buildTypes\s*\{", s, re.M)
if not m:
    sys.exit("buildTypes block not found")
s = s[: m.start()] + block + s[m.start():]
s, n = re.subn(r"signingConfig\s*=?\s*signingConfigs[\w.()\"']*", use, s, count=1)
if n != 1:
    sys.exit("signingConfig line not found")
open(path, "w", encoding="utf-8").write(s)
print("patched", path)
