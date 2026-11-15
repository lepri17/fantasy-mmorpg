# Fantasy MMORPG – Prototype

משחק 2D מלמעלה ל-Android, בסגנון Chibi Anime Fantasy. כרגע: לוחם אחד במפת אימונים עם עצים, אבנים ושבילים, שנלחם בסליימים.

## איך מריצים
1. מורידים Godot 4 (הגרסה הרגילה, לא .NET) מ-godotengine.org.
2. פותחים את Godot, לוחצים Import ובוחרים את `client/project.godot`.
3. לוחצים F5.

מקשים: WASD או חצים. רווח = Attack (אפשר להחזיק). בקרבת הסליים הלוחם תוקף אותו.
אפשר לגרור את הג'ויסטיק שעל המסך גם עם העכבר.

## APK אוטומטי מ-GitHub
בכל Push ל-`main` GitHub בונה APK. נכנסים ללשונית Actions, פותחים את הריצה האחרונה, ובתחתית העמוד מורידים את `fantasy-mmorpg-debug-apk`. מחלצים את ה-ZIP, מעבירים את ה-APK לטלפון ומתקינים (הטלפון יבקש אישור "Install unknown apps").
אפשר גם להפעיל ידנית: Actions → Build Android APK → Run workflow.

## איך מתקינים בטלפון Android דרך Godot
הכנה חד-פעמית:
1. ב-Godot: Editor → Manage Export Templates → Download and Install.
2. להתקין Android Studio (מביא איתו את Android SDK ו-JDK).
3. ב-Godot: Editor → Editor Settings → Export → Android, ולמלא את Java SDK Path ואת Android SDK Path.
4. בטלפון: להפעיל Developer Options ו-USB Debugging, ולחבר בכבל.

בכל פעם:
- הכי מהיר: Project → Export → Add → Android, ואז כפתור ה-Android בפינה הימנית העליונה של העורך מתקין ומריץ ישר בטלפון.
- או: Project → Export → Export Project, לשמור APK ולהעביר לטלפון.

## מבנה
- `client/` – פרויקט Godot (סצנות, סקריפטים, נכסים).
- `tools/` – כלי Python.
- `docs/PROJECT_CONTEXT.md` – מצב העבודה, החלטות, מה נבדק ומה הלאה.

## כלי Python
```
pip install pillow gdtoolkit
python tools/generate_assets.py   # מצייר מחדש את הלוחם והדשא
python tools/check_project.py     # בודק שהקבצים מחוברים נכון, בלי Godot
```

## בדיקה אוטומטית ב-Godot
מתוך `client/`:
```
godot --headless -s res://tests/smoke_test.gd
```
מריץ את המשחק בלי מסך ובודק תנועה, מכשולים וקרב. רץ גם ב-GitHub בכל Push, לפני בניית ה-APK.

כל הגרפיקה מצוירת בקוד ב-`tools/generate_assets.py`, כך שהיא מקורית ובבעלות הפרויקט.
