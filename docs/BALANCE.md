# BALANCE – טבלאות איזון

נוצר אוטומטית מקובצי הנתונים (`client/data/*.json`) על ידי `tools/balance.py`. לא לערוך ידנית: משנים את הנתונים ומריצים את הכלי מחדש. המספרים הם ממוצעים לפי חוקי המשחק.

## הגיבור לפי רמה

ציוד ההתחלה, וכל נקודות הסטטים במאפיין הראשי של המקצוע (STR ללוחם, DEX לקשת, ENE לקוסם). DPS = נזק לשנייה בתקיפה רגילה נגד המפלצת של אותה רמה, כולל קומבו, קריטי, החטאות והגנה.

### Warrior

| רמה | HP | התקפה | הגנה | קריטי | שנ' בין מכות | מפלצת | DPS | שנ' להריגה | שנ' עד שהיא הורגת |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 100 | 8~12 | 4 | 8.0% | 0.45 | Slime | 26.4 | 1.5 | 25 |
| 2 | 115 | 13~19 | 4 | 8.0% | 0.45 | Slime | 42.2 | 0.9 | 29 |
| 3 | 130 | 18~26 | 4 | 8.0% | 0.45 | Blue Slime | 52.9 | 2.1 | 12 |
| 4 | 145 | 22~34 | 4 | 8.0% | 0.45 | Spore Shroom | 71.3 | 1.0 | 31 |
| 5 | 160 | 27~41 | 4 | 8.0% | 0.45 | Spore Shroom | 87.1 | 0.8 | 34 |
| 6 | 175 | 32~48 | 4 | 8.0% | 0.45 | Spore Shroom | 102.9 | 0.7 | 37 |
| 8 | 205 | 42~62 | 4 | 8.0% | 0.45 | Spore Shroom | 134.5 | 0.5 | 43 |
| 10 | 235 | 51~77 | 4 | 8.0% | 0.45 | Spore Shroom | 166.1 | 0.4 | 49 |
| 12 | 265 | 61~91 | 4 | 8.0% | 0.45 | Spore Shroom | 197.8 | 0.4 | 56 |
| 15 | 310 | 75~113 | 4 | 8.0% | 0.45 | Spore Shroom | 245.2 | 0.3 | 65 |

### Archer

| רמה | HP | התקפה | הגנה | קריטי | שנ' בין מכות | מפלצת | DPS | שנ' להריגה | שנ' עד שהיא הורגת |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 80 | 7~11 | 2 | 13.0% | 0.50 | Slime | 21.9 | 1.8 | 15 |
| 2 | 93 | 10~16 | 2 | 15.5% | 0.49 | Slime | 34.7 | 1.2 | 18 |
| 3 | 106 | 14~22 | 2 | 18.0% | 0.47 | Blue Slime | 44.9 | 2.4 | 9 |
| 4 | 119 | 18~26 | 2 | 20.5% | 0.46 | Spore Shroom | 61.0 | 1.1 | 22 |
| 5 | 132 | 22~32 | 2 | 23.0% | 0.45 | Spore Shroom | 78.4 | 0.9 | 24 |
| 6 | 145 | 25~37 | 2 | 25.5% | 0.43 | Spore Shroom | 93.9 | 0.7 | 27 |
| 8 | 171 | 32~48 | 2 | 30.5% | 0.41 | Spore Shroom | 131.2 | 0.5 | 31 |
| 10 | 197 | 39~59 | 2 | 35.5% | 0.39 | Spore Shroom | 173.1 | 0.4 | 36 |
| 12 | 223 | 46~70 | 2 | 40.5% | 0.38 | Spore Shroom | 219.7 | 0.3 | 41 |
| 15 | 262 | 58~86 | 2 | 48.0% | 0.35 | Spore Shroom | 301.3 | 0.2 | 48 |

### Mage (מוסתר כרגע)

| רמה | HP | התקפה | הגנה | קריטי | שנ' בין מכות | מפלצת | DPS | שנ' להריגה | שנ' עד שהיא הורגת |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 70 | 7~11 | 1 | 5.0% | 0.60 | Slime | 17.6 | 2.3 | 11 |
| 2 | 81 | 12~18 | 1 | 5.0% | 0.60 | Slime | 29.2 | 1.4 | 13 |
| 3 | 92 | 17~25 | 1 | 5.0% | 0.60 | Blue Slime | 37.1 | 3.0 | 7 |
| 4 | 103 | 22~32 | 1 | 5.0% | 0.60 | Spore Shroom | 50.7 | 1.4 | 17 |
| 5 | 114 | 26~40 | 1 | 5.0% | 0.60 | Spore Shroom | 62.4 | 1.1 | 18 |
| 6 | 125 | 31~47 | 1 | 5.0% | 0.60 | Spore Shroom | 74.1 | 0.9 | 20 |
| 8 | 147 | 41~61 | 1 | 5.0% | 0.60 | Spore Shroom | 97.4 | 0.7 | 24 |
| 10 | 169 | 50~76 | 1 | 5.0% | 0.60 | Spore Shroom | 120.8 | 0.6 | 27 |
| 12 | 191 | 60~90 | 1 | 5.0% | 0.60 | Spore Shroom | 144.2 | 0.5 | 31 |
| 15 | 224 | 74~112 | 1 | 5.0% | 0.60 | Spore Shroom | 179.2 | 0.4 | 36 |

## מפלצות

"שנ' להריגה": לוחם ברמה של המפלצת, תקיפה רגילה בלבד. "פגיעה בלוחם רמה 1": נזק ממוצע למכה (אחרי הגנה והתחמקות).

| מפלצת | רמה | HP | נזק | הגנה | התחמקות | EXP | זהב (ממוצע) | EXP ל-HP | שנ' להריגה | פגיעה בלוחם רמה 1 |
|---|---|---|---|---|---|---|---|---|---|---|
| Slime | 1 | 40 | 9 | 0 | 5% | 20 | 3.0 | 0.50 | 1.5 | 4.8 |
| Blue Slime | 3 | 110 | 18 | 2 | 5% | 70 | 10.0 | 0.64 | 2.1 | 13.3 |
| Spore Shroom | 4 | 70 | 14 | 1 | 5% | 55 | 7.0 | 0.79 | 1.0 | 9.5 |
| Slime King | 8 | 1500 | 30 | 4 | 0% | 900 | 225.0 | 0.60 | 11.2 | 24.7 |
| Golden Slime | 3 | 60 | 8 | 1 | 10% | 60 | 37.5 | 1.00 | 1.1 | 3.8 |

## קצב עליית רמות (לוחם)

EXP לרמה: 80 x רמה^2.2. מפלצת שרמתה נמוכה בהרבה נותנת פחות EXP (באחוזים בטבלה). בכל רמה נבחרה המפלצת שנותנת הכי הרבה EXP לדקה, מבין המפלצות שרמתן לכל היותר רמה אחת מעל הגיבור. זמן לכל מפלצת: זמן ההריגה ועוד 5 שנ' הליכה ואיסוף. בלי משימות, בוס ומבוך.

| רמה | EXP לרמה הבאה | מפלצת | EXP להריגה | הריגות | דקות | דקות מההתחלה |
|---|---|---|---|---|---|---|
| 1 | 80 | Slime | 20 (100%) | 4 | 0.4 | 0 |
| 2 | 368 | Blue Slime | 74 (105%) | 5 | 0.7 | 1 |
| 3 | 897 | Blue Slime | 70 (100%) | 13 | 1.5 | 3 |
| 4 | 1689 | Blue Slime | 70 (100%) | 24 | 2.7 | 5 |
| 5 | 2759 | Blue Slime | 70 (100%) | 39 | 4.1 | 9 |
| 6 | 4121 | Blue Slime | 60 (85%) | 69 | 7.0 | 16 |
| 7 | 5785 | Spore Shroom | 47 (85%) | 123 | 11.5 | 28 |
| 8 | 7760 | Spore Shroom | 39 (70%) | 199 | 18.3 | 46 |
| 9 | 10056 | Spore Shroom | 30 (55%) | 335 | 30.5 | 77 |
| 10 | 12679 | Spore Shroom | 22 (40%) | 576 | 52.1 | 129 |
| 11 | 15637 | Spore Shroom | 14 (25%) | 1117 | 100.2 | 229 |
| 12 | 18936 | Blue Slime | 7 (10%) | 2705 | 250.8 | 480 |
| 13 | 22582 | Blue Slime | 7 (10%) | 3226 | 296.9 | 777 |
| 14 | 26581 | Blue Slime | 7 (10%) | 3797 | 347.1 | 1124 |
| 15 | 30938 | Blue Slime | 7 (10%) | 4420 | 401.7 | 1526 |


EXP לפי פער הרמות (רמת הגיבור פחות רמת המפלצת):

| פער | EXP |
|---|---|
| -5 | 125% |
| -3 | 115% |
| -1 | 105% |
| +0 | 100% |
| +2 | 100% |
| +3 | 85% |
| +4 | 70% |
| +5 | 55% |
| +6 | 40% |
| +8 | 10% |
| +10 | 10% |

## מה נותנת כל נקודה

לכל נקודה (מתוך 5 בכל רמה). העמודות האחרונות: מה משנות 10 נקודות לגיבור ברמה 10.

| מקצוע | סטט | לכל נקודה | HP (10 נק') | הגנה (10 נק') | DPS (10 נק') |
|---|---|---|---|---|---|
| Warrior | STR | attack 1 | +0 | +0 | +58% |
| Warrior | DEX | attack 0.34, crit_chance 0.005, attack_speed 0.006, accuracy 0.01 | +0 | +0 | +35% |
| Warrior | VIT | max_hp 5, defense 0.3334 | +50 | +3 | +0% |
| Warrior | ENE | max_stamina 2, skill_damage 0.01 | +0 | +0 | +0% |
| Archer | STR | attack 0.5, max_hp 2 | +20 | +0 | +31% |
| Archer | DEX | attack 0.7, crit_chance 0.005, attack_speed 0.006, accuracy 0.01 | +0 | +0 | +64% |
| Archer | VIT | max_hp 5, defense 0.3334 | +50 | +3 | +0% |
| Archer | ENE | max_stamina 2, skill_damage 0.01 | +0 | +0 | +0% |
| Mage | STR | attack 0.5, max_hp 2 | +20 | +0 | +31% |
| Mage | DEX | attack 0.34, crit_chance 0.005, attack_speed 0.006, accuracy 0.01 | +0 | +0 | +36% |
| Mage | VIT | max_hp 5, defense 0.3334 | +50 | +3 | +0% |
| Mage | ENE | max_stamina 2, skill_damage 0.01, attack 1 | +0 | +0 | +62% |

## בניות לדוגמה (רמה 10, נגד Blue Slime)

"מאוזן": 60% בסטט הראשי, 20% ב-VIT, והשאר ב-DEX (לקשת: ב-STR).

| מקצוע | בנייה | HP | התקפה | הגנה | קריטי | שנ' בין מכות | DPS | שנ' עד שהיא הורגת |
|---|---|---|---|---|---|---|---|---|
| Warrior | הכול בסטט הראשי | 235 | 64 | 4 | 8% | 0.45 | 164 | 21 |
| Warrior | מאוזן | 280 | 49 | 7 | 12% | 0.43 | 141 | 32 |
| Warrior | הכול ב-VIT | 460 | 19 | 19 | 8% | 0.45 | 45 | 163 |
| Archer | הכול בסטט הראשי | 197 | 49 | 2 | 36% | 0.39 | 170 | 16 |
| Archer | מאוזן | 260 | 41 | 5 | 26% | 0.43 | 124 | 26 |
| Archer | הכול ב-VIT | 422 | 18 | 17 | 13% | 0.50 | 39 | 152 |
| Mage | הכול בסטט הראשי | 169 | 63 | 1 | 5% | 0.60 | 119 | 12 |
| Mage | מאוזן | 214 | 48 | 4 | 10% | 0.57 | 102 | 19 |
| Mage | הכול ב-VIT | 394 | 18 | 16 | 5% | 0.60 | 31 | 127 |

## סקילים (רמה 5, נגד Blue Slime)

"DPS למטרה": הנזק של שימוש אחד לחלק בזמן עד השימוש הבא, לפי ה-Cooldown או לפי קצב המילוי של ה-Stamina, הארוך מביניהם. הסקילים מצטרפים לתקיפה הרגילה, ולא באים במקומה.

| מקצוע | סקיל | נזק | Cooldown | עלות | DPS למטרה | מטרות | נזק לשימוש |
|---|---|---|---|---|---|---|---|
| Warrior | תקיפה רגילה | - | 0.45 | - | 84.6 | 1 / קשת | - |
| Warrior | Spin Slash | x2.0 | 1.0 | 40 | 19.6 | אזור | 65 |
| Warrior | Power Strike | x3.0 | 4.0 | 25 | 24.7 | אחת | 99 |
| Warrior | War Cry | - | 20.0 | 30 | - | באף | - |
| Warrior | Ground Slam | x2.2 | 8.0 | 35 | 9.0 | אזור | 72 |
| Warrior | Great Cleave | x4.0 | 8.0 | 45 | 16.6 | אזור | 132 |
| Archer | תקיפה רגילה | - | 0.45 | - | 75.7 | 1 / קשת | - |
| Archer | Multi Shot | x1.4 | 1.4 | 22 | 22.0 | אזור | 40 |
| Archer | Piercing Arrow | x2.6 | 4.0 | 25 | 19.0 | קו | 76 |
| Archer | Eagle Eye | - | 20.0 | 30 | - | באף | - |
| Archer | Arrow Rain | x0.9 x4 | 9.0 | 40 | 11.0 | אזור | 99 |
| Archer | Spirit Arrow | x4.5 | 7.0 | 45 | 19.2 | קו | 134 |
| Mage | תקיפה רגילה | - | 0.60 | - | 60.5 | 1 / קשת | - |
| Mage | Fireball | x2.0 | 1.2 | 18 | 43.9 | אזור | 79 |
| Mage | Frost Nova | x1.5 | 5.0 | 30 | 11.7 | אזור | 58 |
| Mage | Mana Shield | - | 20.0 | 30 | - | באף | - |
| Mage | Meteor | x3.2 | 10.0 | 45 | 12.7 | אזור | 127 |
| Mage | Chain Lightning | x2.8 | 7.0 | 45 | 15.7 | אזור | 110 |

## קריטי

מכה קריטית = x1.5 ועוד ה-Critical Damage. ההגנה יורדת מהמכה, אבל נשאר לפחות 20% ממנה. ההתחמקות פחות הדיוק, עד 60%.

| סיכוי | מכפיל | תוספת ממוצעת לנזק |
|---|---|---|
| 5% | x1.50 | x1.025 |
| 5% | x1.65 | x1.032 |
| 5% | x1.80 | x1.040 |
| 8% | x1.50 | x1.040 |
| 8% | x1.65 | x1.052 |
| 8% | x1.80 | x1.064 |
| 10% | x1.50 | x1.050 |
| 10% | x1.65 | x1.065 |
| 10% | x1.80 | x1.080 |
| 15% | x1.50 | x1.075 |
| 15% | x1.65 | x1.097 |
| 15% | x1.80 | x1.120 |
| 30% | x1.50 | x1.150 |
| 30% | x1.65 | x1.195 |
| 30% | x1.80 | x1.240 |

## ציוד (נגד Blue Slime)

"הכי טוב": בכל משבצת, הפריט הרגיל (Common) שהגיבור יכול ללבוש ברמה הזאת ונותן הכי הרבה DPS כפול שניות חיים. כולל ציוד שדרוג המקצוע ברמה 10. "+6": אותו ציוד משודרג לכל +6 (אבני Ember, בלי סיכון). נקודות הסטטים כולן בסטט הראשי.

| מקצוע | רמה | ציוד | התקפה | HP | הגנה | DPS | DPS מול ההתחלה | שנ' בחיים | פריטים |
|---|---|---|---|---|---|---|---|---|---|
| Warrior | 1 | התחלה | 10 | 100 | 4 | 21 | +0% | 9 | Red Headband, Training Sword, Leather Gloves, Red Cape, Blue Plate Armor, Leather Boots |
| Warrior | 1 | הכי טוב | 10 | 100 | 4 | 21 | +0% | 9 | Red Headband, Training Sword, Leather Gloves, Red Cape, Blue Plate Armor, Leather Boots |
| Warrior | 6 | התחלה | 40 | 175 | 4 | 100 | +0% | 16 | Red Headband, Training Sword, Leather Gloves, Red Cape, Blue Plate Armor, Leather Boots |
| Warrior | 6 | הכי טוב | 52 | 215 | 8 | 132 | +32% | 29 | Verdant Headband, Crimson Sword, Verdant Gloves, Verdant Cape, Crimson Plate, Verdant Boots |
| Warrior | 6 | הכי טוב +6 | 70 | 287 | 20 | 179 | +79% | 108 | Verdant Headband, Crimson Sword, Verdant Gloves, Verdant Cape, Crimson Plate, Verdant Boots |
| Warrior | 10 | התחלה | 64 | 235 | 4 | 164 | +0% | 21 | Red Headband, Training Sword, Leather Gloves, Red Cape, Blue Plate Armor, Leather Boots |
| Warrior | 10 | הכי טוב | 76 | 293 | 8 | 207 | +26% | 36 | Verdant Headband, Crimson Sword, Verdant Gloves, Champion Cape, Crimson Plate, Swift Boots |
| Warrior | 10 | הכי טוב +6 | 94 | 365 | 20 | 257 | +57% | 127 | Verdant Headband, Crimson Sword, Verdant Gloves, Champion Cape, Crimson Plate, Swift Boots |
| Archer | 1 | התחלה | 9 | 80 | 2 | 17 | +0% | 7 | Green Hood, Short Bow, Leather Gloves, Ranger Vest, Leather Boots |
| Archer | 1 | הכי טוב | 9 | 85 | 2 | 17 | +0% | 7 | Green Hood, Short Bow, Leather Gloves, Ranger Vest, Leather Boots, Red Cape |
| Archer | 6 | התחלה | 31 | 145 | 2 | 91 | +0% | 12 | Green Hood, Short Bow, Leather Gloves, Ranger Vest, Leather Boots |
| Archer | 6 | הכי טוב | 35 | 188 | 3 | 105 | +16% | 17 | Green Hood, Crimson Bow, Hawk Gloves, Shadow Vest, Verdant Boots, Verdant Cape |
| Archer | 6 | הכי טוב +6 | 53 | 260 | 15 | 162 | +78% | 85 | Green Hood, Crimson Bow, Hawk Gloves, Shadow Vest, Verdant Boots, Verdant Cape |
| Archer | 10 | התחלה | 49 | 197 | 2 | 170 | +0% | 16 | Green Hood, Short Bow, Leather Gloves, Ranger Vest, Leather Boots |
| Archer | 10 | הכי טוב | 53 | 236 | 3 | 213 | +25% | 21 | Azure Hood, Crimson Bow, Hawk Gloves, Shadow Vest, Swift Boots, Duelist Cape |
| Archer | 10 | הכי טוב +6 | 71 | 308 | 15 | 288 | +69% | 97 | Azure Hood, Crimson Bow, Hawk Gloves, Shadow Vest, Swift Boots, Duelist Cape |
| Mage | 1 | התחלה | 9 | 70 | 1 | 14 | +0% | 5 | Sage Hat, Oak Staff, Violet Robe, Leather Boots |
| Mage | 1 | הכי טוב | 10 | 75 | 1 | 16 | +16% | 6 | Sage Hat, Oak Staff, Violet Robe, Leather Boots, Leather Gloves, Red Cape |
| Mage | 6 | התחלה | 39 | 125 | 1 | 72 | +0% | 9 | Sage Hat, Oak Staff, Violet Robe, Leather Boots |
| Mage | 6 | הכי טוב | 44 | 168 | 3 | 87 | +20% | 14 | Sage Hat, Ember Staff, Midnight Robe, Verdant Boots, Hawk Gloves, Verdant Cape |
| Mage | 6 | הכי טוב +6 | 62 | 240 | 15 | 124 | +71% | 73 | Sage Hat, Ember Staff, Midnight Robe, Verdant Boots, Hawk Gloves, Verdant Cape |
| Mage | 10 | התחלה | 63 | 169 | 1 | 119 | +0% | 12 | Sage Hat, Oak Staff, Violet Robe, Leather Boots |
| Mage | 10 | הכי טוב | 68 | 209 | 3 | 148 | +24% | 17 | Starlit Hat, Ember Staff, Midnight Robe, Swift Boots, Hawk Gloves, Duelist Cape |
| Mage | 10 | הכי טוב +6 | 86 | 281 | 15 | 188 | +58% | 81 | Starlit Hat, Ember Staff, Midnight Robe, Swift Boots, Hawk Gloves, Duelist Cape |

## שדרוג ציוד

| שלב | אבן | סיכוי | אבנים בממוצע | בכישלון |
|---|---|---|---|---|
| +0 -> +1 | Ember Stone | 100% | 1.0 | נשאר |
| +1 -> +2 | Ember Stone | 100% | 1.0 | נשאר |
| +2 -> +3 | Ember Stone | 100% | 1.0 | נשאר |
| +3 -> +4 | Ember Stone | 100% | 1.0 | נשאר |
| +4 -> +5 | Ember Stone | 100% | 1.0 | נשאר |
| +5 -> +6 | Ember Stone | 100% | 1.0 | נשאר |
| +6 -> +7 | Moon Stone | 60% | 1.7 | נשאר |
| +7 -> +8 | Moon Stone | 60% | 1.7 | נשאר |
| +8 -> +9 | Moon Stone | 60% | 1.7 | נשאר |
| +9 -> +10 | Moon Stone | 35% | 2.9 | יורד רמה |
| +10 -> +11 | Moon Stone | 35% | 2.9 | יורד רמה |
| +11 -> +12 | Moon Stone | 35% | 2.9 | יורד רמה |
| +12 -> +13 | Moon Stone | 35% | 2.9 | יורד רמה |
| +13 -> +14 | Moon Stone | 35% | 2.9 | יורד רמה |
| +14 -> +15 | Moon Stone | 35% | 2.9 | יורד רמה |

| משבצת | תוספת לכל +1 |
|---|---|
| head | +1 defense, +2 max_hp |
| weapon | +2 attack |
| gloves | +1 attack |
| cape | +3 max_hp |
| armor | +1 defense, +4 max_hp |
| boots | +3 max_hp |

## כלכלה ושלל

| פריט | מחיר | הריגות Slime | הריגות Blue Slime |
|---|---|---|---|
| Red Potion | 20 | 7 | 2 |
| Blue Potion | 30 | 10 | 3 |
| Ember Stone | 300 | 100 | 30 |
| Training Sword | 120 | 40 | 12 |
| Blue Plate Armor | 200 | 67 | 20 |
| Book: Ground Slam | 800 | 267 | 80 |
| Rebirth Scroll | 1500 | 500 | 150 |

| דרגה | משקל | בונוסים אקראיים |
|---|---|---|
| common | 60 | 0 |
| uncommon | 28 | 1 |
| rare | 10 | 2 |
| epic | 2 | 3 |

| בונוס אקראי | טווח |
|---|---|
| attack | 1 ~ 3 |
| max_hp | 5 ~ 15 |
| defense | 1 ~ 2 |
| crit_chance | 0.01 ~ 0.03 |
| evasion | 0.01 ~ 0.02 |
| max_stamina | 5 ~ 15 |
| crit_damage | 0.05 ~ 0.15 |
| accuracy | 0.02 ~ 0.05 |
| attack_speed | 0.03 ~ 0.08 |
