"""Adds the permissions the app needs and the app name to the generated AndroidManifest.xml."""
import re
import sys

path = sys.argv[1]
s = open(path, encoding="utf-8").read()
perms = (
    '    <uses-permission android:name="android.permission.INTERNET"/>\n'
    '    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>\n'
)
if "android.permission.INTERNET" not in s:
    s = s.replace("<application", perms + "    <application", 1)
s = re.sub(r'android:label="[^"]*"', 'android:label="MVP"', s, count=1)
open(path, "w", encoding="utf-8").write(s)
print("manifest patched")
