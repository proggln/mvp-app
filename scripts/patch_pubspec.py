"""Registers the assets folder in the generated pubspec.yaml and writes the launcher icon config."""
import sys

path = sys.argv[1]
s = open(path, encoding="utf-8").read()
if "assets/logo.png" not in s:
    s = s.replace("uses-material-design: true", "uses-material-design: true\n  assets:\n    - assets/logo.png\n    - assets/coin.png\n    - assets/sword.png\n    - assets/tex_diamond.png\n    - assets/tex_netherite.png\n    - assets/tex_obsidian.png\n    - assets/sticker_approved.png\n    - assets/sticker_pending.png\n    - assets/sticker_denied.png\n    - assets/ic_people.png\n    - assets/ic_warning.png\n    - assets/ic_show.png\n    - assets/ic_on.png\n    - assets/ic_off.png\n    - assets/ic_baltop.png\n    - assets/ic_daily.png\n    - assets/ic_streak.png\n    - assets/ic_info.png\n    - assets/ic_lock.png\n    - assets/ic_history.png\n    - assets/ic_heart.png\n    - assets/ic_mail.png\n    - assets/ic_cart.png\n    - assets/ic_home.png\n    - assets/ic_calendar.png\n    - assets/ic_skull.png\n    - assets/ic_bell.png\n    - assets/ic_phone.png\n    - assets/ic_monitor.png\n    - assets/ic_settings.png\n    - assets/ic_sun.png\n    - assets/ic_card.png\n    - assets/ic_news.png\n    - assets/ic_close.png\n    - assets/ic_check.png\n    - assets/ic_comments.png", 1)
    if "assets/logo.png" not in s:
        sys.exit("could not add the assets to pubspec.yaml")
open(path, "w", encoding="utf-8").write(s)
print("pubspec patched")
