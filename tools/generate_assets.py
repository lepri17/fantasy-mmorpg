"""Draws the prototype art and writes it into the Godot project.

Everything here is drawn from code, so the art is original and fully owned.

Outputs (under client/assets):
  characters/warrior/warrior.png          sprite sheet, 4 rows x 15 columns, 128 px frames
  characters/warrior/warrior_frames.tres  Godot SpriteFrames using that sheet
  characters/warrior/warrior_parts.png    the same frames split into body and gear parts
  characters/warrior/warrior_parts.gd     where each part is, and the order to lay them
  environment/grass.png                   seamless grass tile
  monsters/slime/slime.png                slime sheet, 2 idle frames
  monsters/slime/slime_frames.tres        Godot SpriteFrames for the slime

Sheet layout: rows = down, left, right, up. Columns 0-3 = idle, 4-9 = walk, 10-14 = attack.
Also writes environment/tree.png, environment/rock.png, the app icon (client/icon.png)
and 64 px inventory icons in items/icons/ (gear, potion, coin, bag).

Run:  python tools/generate_assets.py
Needs: Pillow (pip install pillow)
"""

from __future__ import annotations

import colorsys
import math
import random
from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageDraw, ImageOps

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "client" / "assets"

FRAME = 96  # design grid of one warrior frame: all warrior coordinates use it
CELL = 128  # pixels per frame in warrior.png: sharper on phones; the game shows it at 0.75
SCALE = 4  # draw 4x bigger than the design grid, then shrink: gives smooth edges
FEET_Y = 86  # where the feet touch the ground inside a frame

DIRECTIONS = ["down", "left", "right", "up"]
IDLE_FRAMES = 4
WALK_FRAMES = 6
ATTACK_FRAMES = 5
HURT_FRAMES = 1
IDLE_FPS = 4.0
WALK_FPS = 12.0
ATTACK_FPS = 18.0
HURT_FPS = 5.0
COLUMNS = IDLE_FRAMES + WALK_FRAMES + ATTACK_FRAMES + HURT_FRAMES

OUTLINE = (52, 38, 60, 255)
SKIN = (255, 222, 194, 255)
BLUSH = (255, 176, 168, 255)
HAIR = (238, 126, 62, 255)
HAIR_DARK = (204, 92, 44, 255)
ARMOR = (80, 136, 218, 255)
ARMOR_LIGHT = (140, 186, 244, 255)
ARMOR_DARK = (54, 98, 174, 255)
GOLD = (250, 202, 84, 255)
CAPE = (216, 64, 74, 255)
CAPE_DARK = (170, 44, 60, 255)
PANTS = (72, 72, 100, 255)
PANTS_DARK = (56, 56, 80, 255)
BOOT = (122, 80, 54, 255)
BOOT_DARK = (96, 62, 44, 255)
STEEL = (228, 234, 244, 255)
GRIP = (120, 78, 52, 255)
EYE = (58, 42, 70, 255)
WHITE = (255, 255, 255, 255)
SHADOW = (0, 0, 0, 64)
SLIME = (122, 222, 170, 255)
SLIME_LIGHT = (196, 248, 220, 255)
LEAF = (64, 150, 84, 255)
HAIR_LIGHT = (255, 172, 100, 255)
STEEL_DARK = (172, 186, 210, 255)
LEATHER_DARK = (92, 58, 40, 255)
BOOT_LIGHT = (158, 110, 74, 255)
IRIS = (80, 132, 220, 255)
GEM = (110, 226, 248, 255)
TRAIL = (255, 255, 255, 150)
TRAIL_EDGE = (200, 236, 255, 220)
TUNIC = (240, 230, 206, 255)
TUNIC_DARK = (212, 198, 168, 255)
ROPE = (170, 124, 80, 255)
SHOE = (104, 70, 50, 255)

SLIME_FRAME = 64
SLIME_FEET_Y = 56


@dataclass
class Pose:
    """One frame of the warrior. Distances are in design pixels (the 96 grid)."""

    bob: float = 0.0  # the body moves down by this much (breathing, steps)
    legs: tuple = ((0.0, 0.0), (0.0, 0.0))  # (forward, lift) per leg: viewer-left / near first
    arm: float = 0.0  # -1..1: how far the arms swing while walking
    sway: float = 0.0  # -1..1: sway of the cape hem, hair tuft and headband tails
    wind: float = 0.0  # 0..1: how much the cape and tails stream back (walking)
    lean: tuple = (0.0, 0.0)  # shift of the upper body (attack lunge)
    sword: tuple | None = None  # attack frames: (hand, tip, layer) - see sword_layer()
    trail: tuple | None = None  # attack frames: (tip in the previous frame, tip now)
    hurt: bool = False  # squeezed eyes and an open mouth


def idle_poses() -> list[Pose]:
    """Slow breathing: the body rises and falls, cape, hair and tails follow."""
    poses = []
    for i in range(IDLE_FRAMES):
        breath = (1 - math.cos(2 * math.pi * i / IDLE_FRAMES)) / 2  # 0, 0.5, 1, 0.5
        poses.append(Pose(bob=breath * 1.3, sway=breath - 0.5))
    return poses


def walk_poses() -> list[Pose]:
    """One full stride: a leg lifts while it swings forward, the body dips on each step."""
    poses = []
    for i in range(WALK_FRAMES):
        phase = 2 * math.pi * (i + 0.5) / WALK_FRAMES
        s, c = math.sin(phase), math.cos(phase)
        legs = ((s * 2.8, max(0.0, c) * 3.4), (-s * 2.8, max(0.0, -c) * 3.4))
        poses.append(Pose(bob=abs(s) * 1.6 - 0.4, legs=legs, arm=-s, sway=s, wind=1.0))
    return poses


# Sword swing for each drawn direction ("right" is "left" mirrored). Per frame:
# (hand, sword tip, layer, body bob, upper-body lean, slash trail?)
ATTACKS = {
    "down": [
        ((30, 50), (17, 24), "front", -0.8, (0.8, -1.0), False),  # wind-up: sword high, left
        ((32, 64), (6, 70), "front", 0.3, (-0.5, 0.5), True),  # swing down the left side
        ((43, 75), (40, 95), "front", 1.3, (0.0, 1.8), True),  # hit: blade towards the camera
        ((55, 73), (80, 87), "front", 1.0, (1.0, 1.2), True),  # follow-through to the right
        ((38, 72), (22, 50), "back", 0.5, (0.3, 0.6), False),  # back to guard
    ],
    "up": [
        ((68, 58), (90, 44), "back", -0.6, (0.5, -0.5), False),  # wind-up on the right
        ((64, 50), (78, 18), "back", 0.0, (0.0, -1.5), True),  # sword rises over the shoulder
        ((52, 44), (46, 4), "back", 0.8, (-0.5, -1.0), True),  # hit: sweeps over the head
        ((38, 52), (12, 30), "back", 1.0, (-1.0, 0.0), True),  # follow-through to the left
        ((44, 62), (24, 66), "back", 0.5, (-0.5, 0.5), False),  # back to guard
    ],
    "left": [
        ((54, 54), (84, 45), "body", -0.6, (1.5, -0.5), False),  # wind-up: sword pulled back
        ((44, 60), (20, 44), "front", 0.0, (-0.5, 0.0), False),  # swing comes round the front
        ((38, 64), (6, 66), "front", 1.2, (-2.0, 1.0), True),  # hit: blade straight forward
        ((40, 70), (16, 90), "front", 1.0, (-1.5, 1.0), True),  # follow-through down
        ((42, 70), (14, 62), "front", 0.5, (-0.5, 0.5), False),  # back to guard
    ],
}


def hurt_pose(direction: str) -> Pose:
    """Knocked back by a hit: leaning away from the facing, eyes squeezed shut."""
    lean = {"down": (0.0, -1.6), "up": (0.0, 1.2)}.get(direction, (2.6, -0.6))
    return Pose(bob=-0.4, lean=lean, arm=0.6, sway=1.0, hurt=True)


def attack_poses(direction: str) -> list[Pose]:
    view = "left" if direction == "right" else direction
    poses, previous_tip = [], None
    for hand, tip, layer, bob, lean, trail in ATTACKS[view]:
        poses.append(
            Pose(
                bob=bob,
                lean=lean,
                sword=(hand, tip, layer),
                trail=(previous_tip, tip) if trail and previous_tip else None,
            )
        )
        previous_tip = tip
    return poses


class Canvas:
    """Thin wrapper so the drawing code can use design-pixel coordinates."""

    def __init__(self, size: int = FRAME) -> None:
        self.size = size
        self.image = Image.new("RGBA", (size * SCALE, size * SCALE), (0, 0, 0, 0))
        self.draw = ImageDraw.Draw(self.image)
        self.line_width = int(1.5 * SCALE)

    @staticmethod
    def _s(value: float) -> float:
        return value * SCALE

    def _box(self, cx, cy, rx, ry) -> list[float]:
        return [self._s(cx - rx), self._s(cy - ry), self._s(cx + rx), self._s(cy + ry)]

    def ellipse(self, cx, cy, rx, ry, fill, outline=True) -> None:
        box = self._box(cx, cy, rx, ry)
        if outline:
            self.draw.ellipse(box, fill=fill, outline=OUTLINE, width=self.line_width)
        else:
            self.draw.ellipse(box, fill=fill)

    def rect(self, x0, y0, x1, y1, fill, radius=3.0, outline=True) -> None:
        box = [self._s(x0), self._s(y0), self._s(x1), self._s(y1)]
        self.draw.rounded_rectangle(
            box,
            radius=self._s(radius),
            fill=fill,
            outline=OUTLINE if outline else None,
            width=self.line_width if outline else 0,
        )

    def polygon(self, points, fill, outline=True) -> None:
        scaled = [(self._s(x), self._s(y)) for x, y in points]
        self.draw.polygon(scaled, fill=fill)
        if outline:
            loop = scaled + scaled[:2]
            self.draw.line(loop, fill=OUTLINE, width=self.line_width, joint="curve")

    def line(self, points, fill=OUTLINE, width=1.5) -> None:
        scaled = [(self._s(x), self._s(y)) for x, y in points]
        self.draw.line(scaled, fill=fill, width=int(width * SCALE), joint="curve")

    def capsule(self, start, end, radius, fill) -> None:
        """A thick stroke with round ends and an outline (arms, legs)."""
        for color, r in ((OUTLINE, radius), (fill, radius - 1.5)):
            ends = [(self._s(x), self._s(y)) for x, y in (start, end)]
            self.draw.line(ends, fill=color, width=round(self._s(2 * r)))
            for x, y in (start, end):
                self.draw.ellipse(self._box(x, y, r, r), fill=color)

    def use(self, part: str) -> None:
        """Pick the part the next drawing goes to. A plain canvas has one layer for
        everything (icons reuse the warrior's drawing helpers); see PartCanvas."""

    def layer(self) -> Canvas:
        """A clear canvas of the same size, to draw see-through things on (see blend)."""
        return Canvas(self.size)

    def blend(self, layer: Canvas) -> None:
        """Lay a layer over the image. Drawing see-through colours directly would cut holes."""
        self.image.alpha_composite(layer.image)

    def finish(self, out_size: int | None = None) -> Image.Image:
        out = out_size or self.size
        return self.image.resize((out, out), Image.LANCZOS)


def arc_points(cx, cy, rx, ry, start_deg, end_deg, count=24):
    """Points along an ellipse. 0 = right, 90 = bottom, 180 = left, 270 = top."""
    points = []
    for i in range(count + 1):
        angle = math.radians(start_deg + (end_deg - start_deg) * i / count)
        points.append((cx + rx * math.cos(angle), cy + ry * math.sin(angle)))
    return points


def lerp(a, b, t: float):
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)


def draw_shadow(c: Canvas) -> None:
    c.ellipse(48, FEET_Y + 1, 17, 5, SHADOW, outline=False)


# ---------------------------------------------------------------- sword


def draw_sword(c: Canvas, hand, tip) -> None:
    """Knight's sword: two-tone blade with a shine, gold guard with a gem, wrapped grip."""
    hx, hy = hand
    length = math.hypot(tip[0] - hx, tip[1] - hy)
    ux, uy = (tip[0] - hx) / length, (tip[1] - hy) / length  # along the blade
    nx, ny = -uy, ux  # across the blade

    def at(along, across=0.0):
        return (hx + ux * along + nx * across, hy + uy * along + ny * across)

    c.polygon([at(-6, -1.8), at(4, -1.8), at(4, 1.8), at(-6, 1.8)], GRIP)
    for wrap in (-4.0, -1.0):
        c.line([at(wrap, -1.8), at(wrap + 1.2, 1.8)], fill=LEATHER_DARK, width=0.9)
    c.ellipse(*at(-7.2), 2.2, 2.2, GOLD)  # pommel
    base, edge = 6.0, length - 6.5
    blade = [at(base, -3.0), at(edge, -3.0), at(length), at(edge, 3.0), at(base, 3.0)]
    c.polygon(blade, STEEL, outline=False)
    shade = [at(base, 0.3), at(edge, 0.3), at(length - 1, 0.2), at(edge, 3.0), at(base, 3.0)]
    c.polygon(shade, STEEL_DARK, outline=False)
    c.line([at(base + 1.5, -1.4), at(edge - 1, -1.4)], fill=WHITE, width=0.9)  # shine
    c.line(blade + blade[:2])  # outline
    c.polygon([at(3.4, -6.4), at(6.2, -5.6), at(6.2, 5.6), at(3.4, 6.4)], GOLD)  # guard
    c.ellipse(*at(4.8), 1.3, 1.3, GEM, outline=False)


def draw_trail(c: Canvas, start, end, center, width=6.0) -> None:
    """Slash trail: a see-through crescent along the tip's path, widest at the sword."""
    mid = lerp(start, end, 0.5)
    away = (mid[0] - center[0], mid[1] - center[1])
    away_len = math.hypot(*away) or 1.0
    bulge = 0.3 * math.hypot(end[0] - start[0], end[1] - start[1])
    ctrl = (mid[0] + away[0] / away_len * bulge, mid[1] + away[1] / away_len * bulge)
    outer, inner = [], []
    for i in range(17):
        t = i / 16
        a, b, k = (1 - t) ** 2, 2 * (1 - t) * t, t * t
        x = a * start[0] + b * ctrl[0] + k * end[0]
        y = a * start[1] + b * ctrl[1] + k * end[1]
        ix, iy = center[0] - x, center[1] - y
        inward = math.hypot(ix, iy) or 1.0
        outer.append((x, y))
        inner.append((x + ix / inward * width * t, y + iy / inward * width * t))
    layer = c.layer()
    layer.polygon(outer + inner[::-1], TRAIL, outline=False)
    layer.line(outer, fill=TRAIL_EDGE, width=1.0)
    c.blend(layer)


def sword_for(pose: Pose, rest_hand, rest_reach):
    """(hand, tip, layer): the attack frame's sword, or the sword resting in the hand."""
    if pose.sword:
        return pose.sword
    tip = (rest_hand[0] + rest_reach[0], rest_hand[1] + rest_reach[1])
    return rest_hand, tip, "back"


def sword_layer(c: Canvas, pose: Pose, sword, center, layer: str) -> None:
    """Draws the sword and its slash trail if they belong to this layer of the frame:
    "back" = behind the body, "body" = over the body but under the head, "front" = over all.
    Over the body the hand is drawn again, closed round the grip."""
    hand, tip, sword_layer_name = sword
    if sword_layer_name != layer:
        return
    c.use(f"sword_{layer}")
    if pose.trail:
        draw_trail(c, *pose.trail, center)
    draw_sword(c, hand, tip)
    if layer != "back":
        c.use(f"grip_hand_{layer}")
        c.ellipse(hand[0], hand[1], 3.0, 3.0, SKIN)
        c.use(f"grip_glove_{layer}")
        draw_fist(c, hand)


# ---------------------------------------------------------------- parts
# Every frame is drawn as separate parts: the plain body (tunic, sleeves, bare
# hands, shoes) and one or more parts per piece of gear. The game lays the parts
# of the gear the warrior wears over each other, so taking off the armour shows
# the tunic under it. PART_ORDER is the order the parts are laid, per view.

PART_ORDER = {
    "down": [
        "shadow", "cape", "sword_back", "legs", "boots", "torso", "armor", "arms",
        "armor_arms", "bracers", "hands", "gloves", "pauldrons", "scarf", "sword_body",
        "grip_hand_body", "grip_glove_body", "tails", "head", "headband", "sword_front",
        "grip_hand_front", "grip_glove_front",
    ],
    "up": [
        "shadow", "sword_back", "legs", "boots", "torso", "armor", "arms", "armor_arms",
        "bracers", "hands", "gloves", "cape", "pauldrons", "sword_body", "grip_hand_body",
        "grip_glove_body", "head", "headband", "sword_front", "grip_hand_front",
        "grip_glove_front",
    ],
    "side": [
        "shadow", "cape", "arm_far", "armor_arm_far", "bracer_far", "hand_far", "glove_far",
        "sword_back", "legs_far", "boots_far", "legs_near", "boots_near", "torso", "armor",
        "arms", "armor_arms", "bracers", "hands", "gloves", "pauldrons", "scarf",
        "sword_body", "grip_hand_body", "grip_glove_body", "tails", "head", "headband",
        "sword_front", "grip_hand_front", "grip_glove_front",
    ],
}

# Item ids (see client/scripts/items/item_db.gd) a part needs; parts not listed are body.
PART_REQUIRES = {
    "cape": ["red_cape"],
    "scarf": ["red_cape"],
    "sword_back": ["training_sword"],
    "sword_body": ["training_sword"],
    "sword_front": ["training_sword"],
    "grip_hand_body": ["training_sword"],
    "grip_hand_front": ["training_sword"],
    "grip_glove_body": ["training_sword", "leather_gloves"],
    "grip_glove_front": ["training_sword", "leather_gloves"],
    "boots": ["leather_boots"],
    "boots_far": ["leather_boots"],
    "boots_near": ["leather_boots"],
    "armor": ["blue_plate"],
    "armor_arms": ["blue_plate"],
    "armor_arm_far": ["blue_plate"],
    "pauldrons": ["blue_plate"],
    "bracers": ["leather_gloves"],
    "gloves": ["leather_gloves"],
    "bracer_far": ["leather_gloves"],
    "glove_far": ["leather_gloves"],
    "tails": ["red_headband"],
    "headband": ["red_headband"],
}
ALL_GEAR = {item for items in PART_REQUIRES.values() for item in items}

# Gear drawn like another piece but in other colours: item id -> (the item it
# looks like, its inventory icon, the parts to recolour, the recolour rules).
# The recoloured parts are packed as "part@item id"; the game lays them instead
# of the plain part while that item is worn. Rules: ("hue", from, to) moves
# colours near one hue (degrees) to another; ("steel", rgb, mix) tints the
# light grey of a blade.
LOOK_VARIANTS = {
    "verdant_headband": ("red_headband", "headband", ["headband", "tails"], [("hue", 355, 125)]),
    "verdant_cape": ("red_cape", "cape", ["cape", "scarf"], [("hue", 355, 125)]),
    "verdant_gloves": (
        "leather_gloves", "gloves",
        ["gloves", "bracers", "glove_far", "bracer_far", "grip_glove_body", "grip_glove_front"],
        [("hue", 20, 110)],
    ),
    "verdant_boots": (
        "leather_boots", "boots", ["boots", "boots_far", "boots_near"], [("hue", 20, 110)]
    ),
    "crimson_plate": (
        "blue_plate", "armor", ["armor", "armor_arms", "armor_arm_far", "pauldrons"],
        [("hue", 220, 355)],
    ),
    "crimson_sword": (
        "training_sword", "sword", ["sword_back", "sword_body", "sword_front"],
        [("steel", (255, 110, 110), 0.45), ("hue", 30, 350)],
    ),
}


def recolor(image: Image.Image, rules) -> Image.Image:
    """A copy of image with LOOK_VARIANTS rules applied (only inside its content box)."""
    out = image.copy()
    box = out.getchannel("A").getbbox()
    if not box:
        return out
    pixels = out.load()
    for y in range(box[1], box[3]):
        for x in range(box[0], box[2]):
            r, g, b, a = pixels[x, y]
            if a == 0:
                continue
            h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
            for rule in rules:
                if rule[0] == "hue":
                    source, target = rule[1] / 360, rule[2] / 360
                    distance = min(abs(h - source), 1 - abs(h - source))
                    if s > 0.2 and v > 0.15 and distance < 30 / 360:
                        h = (h + target - source) % 1.0
                        r, g, b = (round(c * 255) for c in colorsys.hsv_to_rgb(h, s, v))
                        break
                elif rule[0] == "steel" and s < 0.2 and v > 0.45:
                    tint, mix = rule[1], rule[2]
                    r, g, b = (round(c + (t - c) * mix * v) for c, t in zip((r, g, b), tint))
                    break
            pixels[x, y] = (r, g, b, a)
    return out


def add_look_variants(frames) -> None:
    """Adds the recoloured parts of every LOOK_VARIANTS item to every frame."""
    for parts in frames.values():
        for variant, (_, _, variant_parts, rules) in LOOK_VARIANTS.items():
            for part in variant_parts:
                if part in parts:
                    parts[f"{part}@{variant}"] = recolor(parts[part], rules)


class PartCanvas(Canvas):
    """A canvas with one layer per part. use() picks the layer the next drawing goes to."""

    def __init__(self) -> None:
        super().__init__()
        self.layers: dict[str, tuple] = {}
        self.use("shadow")

    def use(self, part: str) -> None:
        if part not in self.layers:
            size = self.size * SCALE
            image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
            self.layers[part] = (image, ImageDraw.Draw(image))
        self.image, self.draw = self.layers[part]

    def finish_parts(self, out_size: int) -> dict[str, Image.Image]:
        return {
            part: image.resize((out_size, out_size), Image.LANCZOS)
            for part, (image, _) in self.layers.items()
            if image.getchannel("A").getbbox()
        }


def view_of(direction: str) -> str:
    return "side" if direction in ("left", "right") else direction


# ---------------------------------------------------------------- body parts


def draw_fist(c: Canvas, hand) -> None:
    c.ellipse(hand[0], hand[1], 3.3, 3.3, GRIP)  # leather glove


def draw_arm(c: Canvas, shoulder, hand, far: bool = False) -> None:
    """Arm from shoulder to hand: cloth sleeve, armoured sleeve, steel bracer,
    bare hand and glove, each on its own part."""
    c.use("arm_far" if far else "arms")
    c.capsule(shoulder, hand, 3.4, TUNIC)
    c.use("armor_arm_far" if far else "armor_arms")
    c.capsule(shoulder, hand, 3.8, ARMOR_DARK)
    c.use("bracer_far" if far else "bracers")
    c.capsule(lerp(shoulder, hand, 0.55), lerp(shoulder, hand, 0.85), 4.0, STEEL_DARK)
    c.use("hand_far" if far else "hands")
    c.ellipse(hand[0], hand[1], 3.0, 3.0, SKIN)
    c.use("glove_far" if far else "gloves")
    draw_fist(c, hand)


def draw_pauldron(c: Canvas, x, y) -> None:
    c.use("pauldrons")
    c.ellipse(x, y, 6.8, 5.6, ARMOR)
    c.line(arc_points(x, y + 0.4, 5.8, 4.6, 25, 155, 10), fill=GOLD, width=1.5)
    c.ellipse(x - 2.2, y - 2.0, 2.2, 1.4, ARMOR_LIGHT, outline=False)


def draw_torso_front(c: Canvas, cx, oy, back=False) -> None:
    """Plain tunic with a rope belt; over it the chest (or back) plate, belt and hip plates."""
    top, bottom = 54 + oy, 71 + oy
    c.use("torso")
    c.rect(cx - 12, top + 0.5, cx + 12, bottom + 3.2, TUNIC, radius=6)
    c.rect(cx - 10.6, bottom - 6, cx + 10.6, bottom + 1.8, TUNIC_DARK, radius=3, outline=False)
    c.rect(cx - 12.2, bottom - 5.5, cx + 12.2, bottom - 3, ROPE, radius=1)
    if not back:
        c.line([(cx - 3, top + 1), (cx, top + 5), (cx + 3, top + 1)], width=1.2)  # collar
    c.use("armor")
    c.rect(cx - 13, top, cx + 13, bottom, ARMOR, radius=7)
    c.rect(cx - 11.6, bottom - 8, cx + 11.6, bottom - 1.2, ARMOR_DARK, radius=3, outline=False)
    if back:
        c.line([(cx, top + 3), (cx, bottom - 8)], fill=ARMOR_DARK, width=1.2)
    else:
        c.ellipse(cx - 5, top + 5.5, 5, 2.6, ARMOR_LIGHT, outline=False)
        c.polygon([(cx, top + 4), (cx + 3, top + 8), (cx, top + 12), (cx - 3, top + 8)], GOLD)
    c.rect(cx - 13.4, bottom - 6, cx + 13.4, bottom - 2, GRIP, radius=1)  # belt
    if not back:
        c.rect(cx - 2.8, bottom - 6.8, cx + 2.8, bottom - 1.2, GOLD, radius=0.8)  # buckle
    for side in (-1, 1):
        plate = [
            (cx + side * 1.5, bottom - 2),
            (cx + side * 12.8, bottom - 2),
            (cx + side * 12, bottom + 3.5),
            (cx + side * 2.5, bottom + 4),
        ]
        c.polygon(plate, ARMOR)


def draw_torso_side(c: Canvas, cx, oy) -> None:
    top, bottom = 54 + oy, 71 + oy
    c.use("torso")
    c.rect(cx - 8.8, top + 0.5, cx + 9.2, bottom + 3, TUNIC, radius=5)
    c.rect(cx - 7.5, bottom - 6, cx + 7.8, bottom + 1.6, TUNIC_DARK, radius=3, outline=False)
    c.rect(cx - 9, bottom - 5.5, cx + 9.4, bottom - 3, ROPE, radius=1)
    c.use("armor")
    c.rect(cx - 9.5, top, cx + 10, bottom, ARMOR, radius=6)
    c.rect(cx - 8, bottom - 8, cx + 8.6, bottom - 1.2, ARMOR_DARK, radius=3, outline=False)
    c.ellipse(cx - 4, top + 5.5, 3.6, 2.4, ARMOR_LIGHT, outline=False)
    c.rect(cx - 9.9, bottom - 6, cx + 10.4, bottom - 2, GRIP, radius=1)  # belt
    plate = [(cx - 9.5, bottom - 2), (cx + 4, bottom - 2), (cx + 4.5, bottom + 3.8),
             (cx - 8.5, bottom + 3.4)]
    c.polygon(plate, ARMOR)


def draw_boot_front(c: Canvas, x, foot_y) -> None:
    c.rect(x - 5.4, foot_y - 8, x + 5.4, foot_y, BOOT, radius=2.6)
    c.rect(x - 5.9, foot_y - 9, x + 5.9, foot_y - 5.6, BOOT_LIGHT, radius=1.4)  # folded cuff


def draw_legs_front(c: Canvas, cx, oy, legs, toward_camera: bool) -> None:
    """Both legs seen from the front or back; the foot nearer the camera is drawn last."""
    sign = 1 if toward_camera else -1
    placed = []
    for i, (forward, lift) in enumerate(legs):
        x = cx - 5.6 if i == 0 else cx + 5.6
        ground_y = FEET_Y + sign * forward * 0.9
        placed.append((ground_y, x, ground_y - lift))
    for _, x, foot_y in sorted(placed):
        c.use("legs")
        c.capsule((x, 69 + oy), (x, foot_y - 4), 4.2, PANTS)
        c.rect(x - 4.6, foot_y - 5, x + 4.6, foot_y, SHOE, radius=2.4)
        c.use("boots")
        draw_boot_front(c, x, foot_y)


def draw_leg_side(c: Canvas, x, oy, forward, lift, far: bool) -> None:
    fx, fy = x - forward * 2.2, FEET_Y - lift
    c.use("legs_far" if far else "legs_near")
    c.capsule((x, 69 + oy), (fx + 0.5, fy - 4), 4.1, PANTS_DARK if far else PANTS)
    c.rect(fx - 5.8, fy - 5, fx + 3.6, fy, SHOE, radius=2.4)
    c.use("boots_far" if far else "boots_near")
    c.rect(fx - 6.5, fy - 8, fx + 4.2, fy, BOOT_DARK if far else BOOT, radius=2.8)
    c.rect(fx - 4.8, fy - 9, fx + 4.8, fy - 5.6, BOOT if far else BOOT_LIGHT, radius=1.4)


def draw_cape_front(c: Canvas, cx, oy, sway) -> None:
    """From the front only the dark inside of the cape shows, flaring around the legs."""
    c.use("cape")
    s = sway * 1.2
    c.polygon(
        [(cx - 12, 56 + oy), (cx + 12, 56 + oy), (cx + 18 + s, 79 + oy), (cx + 9 + s, 77.5 + oy),
         (cx + s, 80 + oy), (cx - 9 + s, 77.5 + oy), (cx - 18 + s, 79 + oy)],
        CAPE_DARK,
    )


def draw_cape_back(c: Canvas, cx, oy, sway) -> None:
    c.use("cape")
    s = sway * 1.6
    hem = [(cx + 17 + s, 80 + oy), (cx + 8.5 + s, 78 + oy), (cx + s, 81 + oy),
           (cx - 8.5 + s, 78 + oy), (cx - 17 + s, 80 + oy)]
    c.polygon([(cx - 11, 54 + oy), (cx + 11, 54 + oy)] + hem, CAPE)
    c.line([(x, y - 1.8) for x, y in hem], fill=GOLD, width=1.2)  # gold trim
    for fold in (-5.5, 5.5):
        c.line([(cx + fold * 0.7, 60 + oy), (cx + fold + s * 0.7, 76 + oy)], fill=CAPE_DARK,
               width=1.3)


def draw_cape_side(c: Canvas, cx, oy, sway, wind) -> None:
    """Hangs behind the warrior; streams back while he walks."""
    c.use("cape")
    back = (cx + 17 + wind * 6 + sway * 1.5, 79 + oy - wind * 4)
    mid = (cx + 12 + wind * 4 + sway, 76.5 + oy - wind * 2)
    front = (cx + 8 + wind * 2 + sway * 0.5, 79 + oy - wind)
    c.polygon([(cx + 2, 55 + oy), (cx + 10, 56 + oy), back, mid, front, (cx + 3, 73 + oy)], CAPE)
    c.line([(cx + 7, 60 + oy), lerp(mid, back, 0.3)], fill=CAPE_DARK, width=1.2)


def draw_scarf(c: Canvas, x0, x1, oy) -> None:
    c.use("scarf")
    c.rect(x0, 51.5 + oy, x1, 57.5 + oy, CAPE, radius=3)


# ---------------------------------------------------------------- head


def draw_eye(c: Canvas, ex, ey, rx=3.3) -> None:
    """Big anime eye: dark eye, blue iris at the bottom, two shines, a thick upper lid."""
    c.ellipse(ex, ey, rx, 4.7, EYE, outline=False)
    c.ellipse(ex, ey + 1.6, rx * 0.72, 2.6, IRIS, outline=False)
    c.ellipse(ex - rx * 0.3, ey - 1.5, rx * 0.42, 1.5, WHITE, outline=False)
    c.ellipse(ex + rx * 0.36, ey + 2.5, rx * 0.22, 0.75, WHITE, outline=False)
    c.line(arc_points(ex, ey + 0.8, rx + 0.6, 5.2, 205, 335, 8))


def draw_tuft(c: Canvas, cx, cy, sway) -> None:
    c.polygon([(cx - 3, cy - 18), (cx + 7 + sway * 1.5, cy - 29), (cx + 5, cy - 17)], HAIR)


def draw_tails(c: Canvas, root, angle, length, sway) -> None:
    """The two headband tails, flowing from the knot (angle: 0 = right, 90 = down)."""
    for spread, size in ((-12.0, 1.0), (14.0, 0.8)):
        a = math.radians(angle + spread + sway * 9)
        ux, uy = math.cos(a), math.sin(a)
        nx, ny = -uy, ux
        end = (root[0] + ux * length * size, root[1] + uy * length * size)
        w = 2.3
        c.polygon(
            [(root[0] + nx * w, root[1] + ny * w), (end[0] + nx * w * 0.8, end[1] + ny * w * 0.8),
             (end[0] - ux * 2.6, end[1] - uy * 2.6),  # notch
             (end[0] - nx * w * 0.8, end[1] - ny * w * 0.8), (root[0] - nx * w, root[1] - ny * w)],
            CAPE,
        )


def draw_band(c: Canvas, cx, cy, rx) -> None:
    """The red headband round the forehead, dipping where it is nearest the camera."""
    top = arc_points(cx, cy - 7.5, rx, 4.5, 180, 0, 16)
    c.polygon(top + [(x, y + 3.4) for x, y in reversed(top)], CAPE)


def draw_squeezed_eye(c: Canvas, ex, ey, pointing: int) -> None:
    """A shut eye drawn as ">" (pointing = 1) or "<" (pointing = -1)."""
    c.line([(ex - 2.4 * pointing, ey - 2.6), (ex + 2.2 * pointing, ey), (ex - 2.4 * pointing, ey + 2.6)],
           width=1.7)


def draw_head_front(c: Canvas, cx, cy, sway, hurt: bool = False) -> None:
    c.use("tails")
    draw_tails(c, (cx + 17, cy - 5), 32, 14, sway)
    c.use("head")
    draw_tuft(c, cx, cy, sway)
    c.ellipse(cx, cy, 22, 20, SKIN)
    for side in (-1, 1):
        if hurt:
            draw_squeezed_eye(c, cx + side * 8.5, cy + 7.5, -side)
        else:
            draw_eye(c, cx + side * 8.5, cy + 7.5)
        c.ellipse(cx + side * 14, cy + 13.5, 3.2, 1.8, BLUSH, outline=False)
    if hurt:
        c.ellipse(cx, cy + 14, 2.0, 1.7, (150, 60, 70, 255))
    else:
        c.line(arc_points(cx, cy + 13.5, 2.4, 1.8, 20, 160, 8), width=1.2)
    fringe = [(cx + 22, cy), (cx + 18, cy + 7), (cx + 12, cy + 1), (cx + 6, cy + 8), (cx, cy + 1),
              (cx - 6, cy + 8), (cx - 12, cy + 1), (cx - 18, cy + 7), (cx - 22, cy)]
    c.polygon(arc_points(cx, cy, 23, 21.5, 180, 360) + fringe, HAIR)
    c.line(arc_points(cx, cy - 4, 16, 13, 215, 260, 8), fill=HAIR_LIGHT, width=2.2)
    c.use("headband")
    draw_band(c, cx, cy, 21.8)
    c.rect(cx - 4.2, cy - 4.4, cx + 4.2, cy + 1.4, GOLD, radius=1.2)  # forehead plate
    c.ellipse(cx, cy - 1.5, 1.5, 1.5, GEM, outline=False)


def draw_head_back(c: Canvas, cx, cy, sway) -> None:
    c.use("head")
    draw_tuft(c, cx, cy, sway)
    spikes = [(cx + 21, cy + 6), (cx + 16, cy + 19), (cx + 10, cy + 15), (cx + 5, cy + 23),
              (cx, cy + 17), (cx - 5, cy + 23), (cx - 10, cy + 15), (cx - 16, cy + 19),
              (cx - 21, cy + 6)]
    c.polygon(arc_points(cx, cy, 23, 21.5, 165, 375) + spikes, HAIR)
    c.line(arc_points(cx, cy + 2, 14, 10, 30, 150, 10), fill=HAIR_DARK, width=1.4)
    c.line(arc_points(cx, cy - 4, 16, 13, 215, 260, 8), fill=HAIR_LIGHT, width=2.2)
    c.use("headband")
    draw_band(c, cx, cy, 21.8)
    draw_tails(c, (cx, cy - 0.5), 90, 15, sway)
    c.ellipse(cx, cy - 1.3, 2.8, 2.3, CAPE)  # knot


def draw_head_side(c: Canvas, cx, cy, sway, wind, hurt: bool = False) -> None:
    c.use("tails")
    draw_tails(c, (cx + 19, cy - 6), 28 - wind * 18, 15 + wind * 2, sway)
    c.use("head")
    draw_tuft(c, cx + 2, cy, sway)
    c.ellipse(cx, cy, 21, 20, SKIN)
    if hurt:
        draw_squeezed_eye(c, cx - 11.5, cy + 7.5, -1)
    else:
        draw_eye(c, cx - 11.5, cy + 7.5, rx=2.7)
    c.ellipse(cx - 8.5, cy + 13.5, 3.0, 1.8, BLUSH, outline=False)
    c.line(arc_points(cx - 15, cy + 13.5, 1.6, 1.4, 20, 160, 6), width=1.2)
    inner = [(cx + 9, cy + 15), (cx + 3, cy + 9), (cx + 1, cy + 1), (cx - 5, cy + 8),
             (cx - 10, cy), (cx - 16, cy + 6)]
    c.polygon(arc_points(cx, cy, 22, 21.5, 188, 425) + inner, HAIR)
    c.line(arc_points(cx + 1, cy - 4, 16, 13, 220, 265, 8), fill=HAIR_LIGHT, width=2.2)
    c.use("headband")
    draw_band(c, cx, cy, 20.8)
    c.rect(cx - 21.8, cy - 8.6, cx - 18.4, cy - 3, GOLD, radius=1)  # edge of the forehead plate
    c.ellipse(cx + 19.3, cy - 6, 2.8, 2.3, CAPE)  # knot


# ---------------------------------------------------------------- whole frames


def draw_down(c: PartCanvas, pose: Pose) -> None:
    ox, oy = pose.lean[0], pose.bob + pose.lean[1]
    cx, center = 48 + ox, (48 + ox, 62 + oy)
    sword = sword_for(pose, (cx - 17, 70 + oy + pose.arm * 1.2), (-13, -27))
    c.use("shadow")
    draw_shadow(c)
    draw_cape_front(c, cx, oy, pose.sway)
    sword_layer(c, pose, sword, center, "back")
    draw_legs_front(c, 48 + ox * 0.3, oy, pose.legs, toward_camera=True)
    draw_torso_front(c, cx, oy)
    draw_arm(c, (cx - 14, 58 + oy), sword[0])
    draw_arm(c, (cx + 14, 58 + oy), (cx + 17, 70 + oy - pose.arm * 2.2))
    draw_pauldron(c, cx - 15, 57.5 + oy)
    draw_pauldron(c, cx + 15, 57.5 + oy)
    draw_scarf(c, cx - 10, cx + 10, oy)
    sword_layer(c, pose, sword, center, "body")
    draw_head_front(c, cx, 35 + oy, pose.sway, pose.hurt)
    sword_layer(c, pose, sword, center, "front")


def draw_up(c: PartCanvas, pose: Pose) -> None:
    ox, oy = pose.lean[0], pose.bob + pose.lean[1]
    cx, center = 48 + ox, (48 + ox, 62 + oy)
    sword = sword_for(pose, (cx + 17, 70 + oy + pose.arm * 1.2), (13, -27))
    c.use("shadow")
    draw_shadow(c)
    sword_layer(c, pose, sword, center, "back")
    draw_legs_front(c, 48 + ox * 0.3, oy, pose.legs, toward_camera=False)
    draw_torso_front(c, cx, oy, back=True)
    draw_arm(c, (cx + 14, 58 + oy), sword[0])
    draw_arm(c, (cx - 14, 58 + oy), (cx - 17, 70 + oy - pose.arm * 2.2))
    draw_cape_back(c, cx, oy, pose.sway)
    draw_pauldron(c, cx - 15, 57.5 + oy)
    draw_pauldron(c, cx + 15, 57.5 + oy)
    sword_layer(c, pose, sword, center, "body")
    draw_head_back(c, cx, 35 + oy, pose.sway)
    sword_layer(c, pose, sword, center, "front")


def draw_side(c: PartCanvas, pose: Pose) -> None:
    """Facing left. The "right" frames are these, mirrored."""
    ox, oy = pose.lean[0], pose.bob + pose.lean[1]
    cx, center = 47 + ox, (47 + ox, 62 + oy)
    sword = sword_for(pose, (cx - 6 - pose.arm * 3.5, 70 + oy), (-26, -16))
    (near_forward, near_lift), (far_forward, far_lift) = pose.legs
    c.use("shadow")
    draw_shadow(c)
    draw_cape_side(c, cx, oy, pose.sway, pose.wind)
    draw_arm(c, (cx + 4, 58 + oy), (cx + 6 + pose.arm * 3.5, 69 + oy), far=True)
    sword_layer(c, pose, sword, center, "back")
    base = 48 + ox * 0.3
    draw_leg_side(c, base, oy, far_forward, far_lift, far=True)
    draw_leg_side(c, base, oy, near_forward, near_lift, far=False)
    draw_torso_side(c, cx, oy)
    draw_arm(c, (cx + 1, 58 + oy), sword[0])
    draw_pauldron(c, cx + 1, 57.5 + oy)
    draw_scarf(c, cx - 8, cx + 9, oy)
    sword_layer(c, pose, sword, center, "body")
    draw_head_side(c, cx, 35 + oy, pose.sway, pose.wind, pose.hurt)
    sword_layer(c, pose, sword, center, "front")


def warrior_poses(direction: str) -> list[Pose]:
    return idle_poses() + walk_poses() + attack_poses(direction) + [hurt_pose(direction)]


def draw_frame_parts(direction: str, pose: Pose) -> dict[str, Image.Image]:
    """One frame as {part: image}, each image CELL x CELL."""
    canvas = PartCanvas()
    view = view_of(direction)
    {"down": draw_down, "up": draw_up, "side": draw_side}[view](canvas, pose)
    parts = canvas.finish_parts(CELL)
    unknown = set(parts) - set(PART_ORDER[view])
    assert not unknown, f"parts missing from PART_ORDER[{view}]: {unknown}"
    if direction == "right":
        parts = {part: ImageOps.mirror(image) for part, image in parts.items()}
    return parts


def compose(parts: dict[str, Image.Image], view: str, worn: set[str]) -> Image.Image:
    """Lays the parts of one frame over each other, keeping only the gear that is worn."""
    frame = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    for part in PART_ORDER[view]:
        if part in parts and set(PART_REQUIRES.get(part, [])) <= worn:
            frame.alpha_composite(parts[part])
    return frame


def build_warrior_parts() -> dict[tuple[int, int], dict[str, Image.Image]]:
    """Every frame of the sheet as parts, keyed by (row, column)."""
    frames = {}
    for row, direction in enumerate(DIRECTIONS):
        for col, pose in enumerate(warrior_poses(direction)):
            frames[(row, col)] = draw_frame_parts(direction, pose)
    return frames


def build_warrior_sheet(frames, worn: set[str] = ALL_GEAR) -> Image.Image:
    sheet = Image.new("RGBA", (CELL * COLUMNS, CELL * len(DIRECTIONS)), (0, 0, 0, 0))
    for (row, col), parts in frames.items():
        frame = compose(parts, view_of(DIRECTIONS[row]), worn)
        sheet.paste(frame, (col * CELL, row * CELL))
    return sheet


def pack_warrior_parts(frames, width: int = 2048):
    """Crops every part of every frame to its content and packs the crops into one atlas.
    Returns (atlas, pieces) with pieces[part][row] = [[column, x, y, w, h, x in cell,
    y in cell], ...]."""
    crops = []
    for (row, col), parts in frames.items():
        for part, image in parts.items():
            box = image.getchannel("A").getbbox()
            if box:
                crops.append((part, row, col, image.crop(box), box[0], box[1]))
    crops.sort(key=lambda crop: (-crop[3].height, crop[0], crop[1], crop[2]))
    x = y = shelf = 0
    placed = []
    for part, row, col, crop, dx, dy in crops:
        if x + crop.width > width:
            x, y, shelf = 0, y + shelf + 1, 0
        placed.append((part, row, col, crop, x, y, dx, dy))
        x += crop.width + 1
        shelf = max(shelf, crop.height)
    atlas = Image.new("RGBA", (width, y + shelf), (0, 0, 0, 0))
    all_parts = sorted(
        {part for order in PART_ORDER.values() for part in order}
        | {part for parts in frames.values() for part in parts}
    )
    pieces = {part: [[] for _ in DIRECTIONS] for part in all_parts}
    for part, row, col, crop, ax, ay, dx, dy in placed:
        atlas.paste(crop, (ax, ay))
        pieces[part][row].append([col, ax, ay, crop.width, crop.height, dx, dy])
    for rows in pieces.values():
        for row_pieces in rows:
            row_pieces.sort()
    return atlas, pieces


def _gd_list(values) -> str:
    return "[" + ", ".join(f'"{v}"' for v in values) + "]"


def build_parts_script(pieces) -> str:
    """Text of client/assets/characters/warrior/warrior_parts.gd (generated data)."""
    lines = [
        "# gdlint: disable=max-file-lines",
        "extends RefCounted",
        "## Generated by tools/generate_assets.py - do not edit by hand.",
        "## Where each part of the warrior is in warrior_parts.png, the order the parts",
        "## are laid over each other in each direction, and the gear each part needs.",
        "",
        f"const CELL := {CELL}",
        f"const COLUMNS := {COLUMNS}",
        f"const DIRECTIONS := {_gd_list(DIRECTIONS)}",
        "",
        "const ORDER := {",
    ]
    for direction in DIRECTIONS:
        lines.append(f'\t"{direction}": [')
        order = PART_ORDER[view_of(direction)]
        for i in range(0, len(order), 5):
            lines.append("\t\t" + ", ".join(f'"{p}"' for p in order[i:i + 5]) + ",")
        lines.append("\t],")
    lines += ["}", "", "## Part -> item ids it needs. Parts not listed are the plain body.", ""]
    lines.append("const REQUIRES := {")
    for part, items in PART_REQUIRES.items():
        lines.append(f'\t"{part}": {_gd_list(items)},')
    lines += [
        "}",
        "",
        "## Part -> one list per row: [column, atlas x, atlas y, width, height, x, y in cell].",
        "## \"part@item\" is that part recoloured for gear that looks like another piece.",
        "const PIECES := {",
    ]
    for part, rows in pieces.items():
        lines.append(f'\t"{part}": [')
        for row_pieces in rows:
            if not row_pieces:
                lines.append("\t\t[],")
                continue
            lines.append("\t\t[")
            texts = [str(p).replace(" ", "") for p in row_pieces]
            line = "\t\t\t"
            for text in texts:
                if len(line) + len(text) > 92:
                    lines.append(line.rstrip())
                    line = "\t\t\t"
                line += text + ", "
            lines.append(line.rstrip())
            lines.append("\t\t],")
        lines.append("\t],")
    lines += ["}", ""]
    return "\n".join(lines)


def build_sprite_frames(sheet_res_path: str) -> str:
    """Text of a Godot 4 SpriteFrames resource that slices the sheet."""
    idle_end = IDLE_FRAMES
    walk_end = idle_end + WALK_FRAMES
    attack_end = walk_end + ATTACK_FRAMES
    hurt_end = attack_end + HURT_FRAMES
    animations = []  # (name, fps, loop, [(row, column), ...])
    for kind, fps, loop, columns in (
        ("idle", IDLE_FPS, True, range(0, idle_end)),
        ("walk", WALK_FPS, True, range(idle_end, walk_end)),
        ("attack", ATTACK_FPS, False, range(walk_end, attack_end)),
        ("hurt", HURT_FPS, False, range(attack_end, hurt_end)),
    ):
        for row, direction in enumerate(DIRECTIONS):
            cells = [(row, col) for col in columns]
            animations.append((f"{kind}_{direction}", fps, loop, cells))

    frame_count = sum(len(cells) for _, _, _, cells in animations)
    lines = [
        f'[gd_resource type="SpriteFrames" load_steps={frame_count + 2} format=3]',
        "",
        f'[ext_resource type="Texture2D" path="{sheet_res_path}" id="1_sheet"]',
        "",
    ]
    for _, _, _, cells in animations:
        for row, col in cells:
            lines += [
                f'[sub_resource type="AtlasTexture" id="frame_{row}_{col}"]',
                'atlas = ExtResource("1_sheet")',
                f"region = Rect2({col * CELL}, {row * CELL}, {CELL}, {CELL})",
                "",
            ]

    blocks = []
    for name, fps, loop, cells in animations:
        frames = ", ".join(
            '{\n"duration": 1.0,\n"texture": SubResource("frame_%d_%d")\n}' % cell
            for cell in cells
        )
        blocks.append(
            '{\n"frames": [%s],\n"loop": %s,\n"name": &"%s",\n"speed": %.1f\n}'
            % (frames, "true" if loop else "false", name, fps)
        )
    lines += ["[resource]", "animations = [" + ", ".join(blocks) + "]", ""]
    return "\n".join(lines)


def blob(c: Canvas, circles, fill) -> None:
    """Several overlapping ellipses drawn as one shape with a single outline."""
    for cx, cy, rx, ry in circles:
        c.ellipse(cx, cy, rx + 1.5, ry + 1.5, OUTLINE, outline=False)
    for cx, cy, rx, ry in circles:
        c.ellipse(cx, cy, rx, ry, fill, outline=False)


def build_tree() -> Image.Image:
    """160x160, trunk base at (80, 150)."""
    c = Canvas(160)
    c.ellipse(80, 150, 36, 8, SHADOW, outline=False)
    c.rect(69, 98, 91, 150, (134, 92, 60, 255), radius=5)
    c.line([(76, 112), (76, 140)], fill=(108, 72, 48, 255), width=2)
    blob(c, [(80, 58, 42, 40), (50, 82, 28, 26), (110, 82, 28, 26), (80, 92, 32, 22)],
         (70, 160, 84, 255))
    for cx, cy, rx, ry in ((68, 44, 20, 14), (46, 74, 11, 8), (106, 72, 11, 8)):
        c.ellipse(cx, cy, rx, ry, (112, 196, 110, 255), outline=False)
    for cx, cy in ((92, 72), (64, 92), (100, 98)):
        c.ellipse(cx, cy, 5, 3.5, (52, 136, 74, 255), outline=False)
    return c.finish()


def build_rock() -> Image.Image:
    """80x80, base at (40, 66)."""
    c = Canvas(80)
    c.ellipse(40, 66, 30, 6, SHADOW, outline=False)
    blob(c, [(40, 50, 28, 16), (31, 42, 18, 14), (51, 45, 14, 11)], (158, 164, 178, 255))
    c.ellipse(28, 37, 9, 5, (204, 208, 218, 255), outline=False)
    c.ellipse(48, 56, 12, 5, (128, 134, 150, 255), outline=False)
    return c.finish()


def build_coin(out_size: int = 32, shadow: bool = True) -> Image.Image:
    c = Canvas(32)
    if shadow:
        c.ellipse(16, 27, 9, 3, SHADOW, outline=False)
    c.ellipse(16, 15, 10, 10, GOLD)
    c.ellipse(16, 15, 6, 6, (255, 228, 140, 255), outline=False)
    c.ellipse(13.5, 12.5, 2, 2, WHITE, outline=False)
    return c.finish(out_size)


RED_POTION = ((232, 70, 86, 255), (255, 170, 176, 255))
BLUE_POTION = ((70, 130, 235, 255), (175, 210, 255, 255))


def build_potion(out_size: int = 32, shadow: bool = True, colors=RED_POTION) -> Image.Image:
    liquid, shine = colors
    c = Canvas(32)
    if shadow:
        c.ellipse(16, 28, 9, 3, SHADOW, outline=False)
    c.rect(13, 5, 19, 14, (214, 234, 244, 255), radius=1.5)
    c.rect(12, 3, 20, 7, GRIP, radius=1.5)
    c.ellipse(16, 19, 9, 8.5, liquid)
    c.ellipse(13, 16, 2.6, 2, shine, outline=False)
    return c.finish(out_size)


EMBER_STONE = ((240, 118, 48, 255), (255, 206, 120, 255), (186, 66, 38, 255))
MOON_STONE = ((160, 196, 244, 255), (238, 246, 255, 255), (100, 128, 198, 255))


def build_stone(out_size: int = 32, shadow: bool = True, colors=EMBER_STONE) -> Image.Image:
    """An upgrade stone: a cut gem with a bright top facet and a dark lower one."""
    body, light, dark = colors
    c = Canvas(32)
    if shadow:
        c.ellipse(16, 27.5, 9, 3, SHADOW, outline=False)
    c.polygon([(16, 4.5), (25.5, 11), (24.5, 21), (16, 27), (7.5, 21), (6.5, 11)], body)
    c.polygon([(16, 4.5), (25.5, 11), (16, 14.5), (6.5, 11)], light)
    c.polygon([(16, 14.5), (24.5, 21), (16, 27), (7.5, 21)], dark)
    c.ellipse(12.5, 9.5, 1.7, 1.1, WHITE, outline=False)
    return c.finish(out_size)


BOOK_COVER = (196, 72, 52, 255)
BOOK_SPINE = (150, 50, 40, 255)
PAGES = (250, 242, 222, 255)
PARCHMENT = (246, 230, 190, 255)
PARCHMENT_DARK = (220, 190, 140, 255)
INK = (176, 140, 100, 255)


def build_book(out_size: int = 32, shadow: bool = True) -> Image.Image:
    """A skill book: red cover, gold emblem, a ribbon bookmark."""
    c = Canvas(32)
    if shadow:
        c.ellipse(16, 28, 10, 3, SHADOW, outline=False)
    c.rect(9.5, 7, 25, 26, PAGES, radius=1.5)
    c.rect(7, 5, 23, 24, BOOK_COVER, radius=2)
    c.rect(7, 5, 10.5, 24, BOOK_SPINE, radius=1.5)
    c.ellipse(16.5, 14.5, 4, 4, GOLD)
    c.ellipse(16.5, 14.5, 1.8, 1.8, (255, 236, 160, 255), outline=False)
    c.polygon([(18.5, 23.5), (21, 23.5), (21, 29), (19.75, 27.6), (18.5, 29)], GEM)
    c.ellipse(13, 8.5, 1.4, 1, WHITE, outline=False)
    return c.finish(out_size)


def build_scroll(out_size: int = 32, shadow: bool = True) -> Image.Image:
    """A rolled scroll with lines of writing and a red wax seal."""
    c = Canvas(32)
    if shadow:
        c.ellipse(16, 28.5, 10, 3, SHADOW, outline=False)
    c.rect(9, 7, 23, 25, PARCHMENT, radius=1)
    for y in (11.5, 14.5, 17.5):
        c.line([(12, y), (20, y)], fill=INK, width=1)
    c.rect(6.5, 4.5, 25.5, 9, PARCHMENT_DARK, radius=2.2)
    c.rect(6.5, 23, 25.5, 27.5, PARCHMENT_DARK, radius=2.2)
    c.ellipse(16, 21, 3.2, 3.2, CAPE)
    c.ellipse(15.2, 20.2, 1, 1, (255, 160, 160, 255), outline=False)
    return c.finish(out_size)


# ---------------------------------------------------------------- inventory icons
# Drawn on a 48 grid, saved at ICON px. Same palette as the warrior's gear.

ICON = 64


def icon_sword(c: Canvas) -> None:
    draw_sword(c, (16, 33), (40, 9))


def icon_headband(c: Canvas) -> None:
    back = arc_points(24, 21, 15, 7, 180, 360, 16)
    front = arc_points(24, 21, 15, 7, 0, 180, 16)
    c.line(back, width=5.5)
    c.line(back, fill=CAPE_DARK, width=3)
    draw_tails(c, (37.5, 24), 50, 15, 0.0)
    c.line(front, width=6.5)
    c.line(front, fill=CAPE, width=4)
    c.rect(19.5, 24.5, 28.5, 31, GOLD, radius=1.5)  # forehead plate
    c.ellipse(24, 27.8, 1.8, 1.8, GEM, outline=False)


def icon_armor(c: Canvas) -> None:
    c.rect(13, 13, 35, 38, ARMOR, radius=7)
    c.rect(14.5, 29, 33.5, 36.8, ARMOR_DARK, radius=3, outline=False)
    c.ellipse(19.5, 19, 4.5, 2.4, ARMOR_LIGHT, outline=False)
    c.polygon([(24, 17), (27, 21.5), (24, 26), (21, 21.5)], GOLD)  # emblem
    c.rect(12.6, 30, 35.4, 34, GRIP, radius=1)  # belt
    c.rect(21.4, 29.2, 26.6, 34.8, GOLD, radius=0.8)  # buckle
    c.rect(17, 10, 31, 15, CAPE, radius=2.5)  # collar
    draw_pauldron(c, 12, 16)
    draw_pauldron(c, 36, 16)


def icon_gloves(c: Canvas) -> None:
    c.rect(15, 26, 31, 39, STEEL_DARK, radius=3)  # bracer
    c.line([(15.8, 30), (30.2, 30)], fill=GOLD, width=1.4)
    c.ellipse(31.5, 21, 4, 5.5, GRIP)  # thumb
    c.rect(14, 10, 30, 28, GRIP, radius=6)  # fingers and palm
    for x in (18.5, 22.5, 26.5):
        c.line([(x, 11.5), (x, 18)], fill=LEATHER_DARK, width=1.1)


def icon_boots(c: Canvas) -> None:
    c.rect(10, 28, 33, 39, BOOT, radius=5)  # foot, toe to the left
    c.rect(20, 10, 33, 33, BOOT, radius=3)  # shaft
    c.rect(19, 9, 34, 15, BOOT_LIGHT, radius=2)  # folded cuff
    c.rect(10, 36, 33, 39.5, BOOT_DARK, radius=1.5)  # sole


def icon_cape(c: Canvas) -> None:
    hem = [(38, 40), (31, 38), (24, 41), (17, 38), (10, 40)]
    c.polygon([(17, 10), (31, 10)] + hem, CAPE)
    c.line([(x, y - 2.2) for x, y in hem], fill=GOLD, width=1.3)
    c.line([(21, 15), (19, 36)], fill=CAPE_DARK, width=1.3)
    c.line([(27, 15), (29, 36)], fill=CAPE_DARK, width=1.3)
    c.rect(15, 7, 33, 13, CAPE_DARK, radius=2.5)  # collar
    c.ellipse(24, 10, 2.8, 2.8, GOLD)  # clasp


def icon_bag(c: Canvas) -> None:
    c.polygon([(18, 13), (15, 6), (21, 9), (24, 5), (27, 9), (33, 6), (30, 13)], BOOT_LIGHT)
    c.polygon([(18, 22), (30, 22), (29, 12), (19, 12)], BOOT)  # neck
    c.ellipse(24, 31, 15, 12, BOOT)  # pouch
    c.ellipse(18.5, 27, 4.5, 3, BOOT_LIGHT, outline=False)  # shine
    c.rect(16, 18.5, 32, 23.5, BOOT_DARK, radius=2.5)  # cord
    c.ellipse(24, 21, 3, 3, GOLD)  # clasp


def build_item_icons() -> dict[str, Image.Image]:
    """Icons for the inventory and the HUD bag button, by file name."""
    icons = {}
    for name, paint in (
        ("sword", icon_sword),
        ("headband", icon_headband),
        ("armor", icon_armor),
        ("gloves", icon_gloves),
        ("boots", icon_boots),
        ("cape", icon_cape),
        ("bag", icon_bag),
    ):
        c = Canvas(48)
        paint(c)
        icons[name] = c.finish(ICON)
    icons["potion"] = build_potion(ICON, shadow=False)
    icons["coin"] = build_coin(ICON, shadow=False)
    icons["book"] = build_book(ICON, shadow=False)
    icons["blue_potion"] = build_potion(ICON, shadow=False, colors=BLUE_POTION)
    icons["ember_stone"] = build_stone(ICON, shadow=False, colors=EMBER_STONE)
    icons["moon_stone"] = build_stone(ICON, shadow=False, colors=MOON_STONE)
    for variant, (_, icon_name, _, rules) in LOOK_VARIANTS.items():
        icons[variant] = recolor(icons[icon_name], rules)
    icons["scroll"] = build_scroll(ICON, shadow=False)
    return icons


def build_icon(sheet: Image.Image) -> Image.Image:
    """App icon: the warrior's front idle frame on a rounded blue tile."""
    size = 192
    icon = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(icon).rounded_rectangle(
        [0, 0, size - 1, size - 1], radius=40, fill=(96, 170, 232, 255)
    )
    warrior = sheet.crop((0, 0, CELL, CELL)).resize((size, size), Image.LANCZOS)
    icon.alpha_composite(warrior, (0, 6))
    return icon


TILE = 128
# Ground kinds in tiles.png, two seamless variants each, in this column order.
# client/data/maps.json names them in "tile_kinds".
TILE_KINDS = ["grass", "path", "stone", "forest", "cellar"]


def _seamless(size: int, base, paint, seed: int) -> Image.Image:
    """Paints on a 3x3 grid of the tile (paint(draw, rng, everywhere, size, scale)),
    keeps the middle, so the tile repeats without seams."""
    rng = random.Random(seed)
    scale = 2
    full = size * 3 * scale
    image = Image.new("RGBA", (full, full), base)
    draw = ImageDraw.Draw(image)

    def everywhere(shape):
        for ox in range(3):
            for oy in range(3):
                shape(ox * size * scale, oy * size * scale)

    paint(draw, rng, everywhere, size, scale)
    middle = image.crop((size * scale, size * scale, size * 2 * scale, size * 2 * scale))
    return middle.resize((size, size), Image.LANCZOS)


def _paint_path(draw, rng, everywhere, size, scale):
    for _ in range(10):
        x, y = rng.uniform(0, size) * scale, rng.uniform(0, size) * scale
        rx, ry = rng.uniform(14, 30) * scale, rng.uniform(8, 16) * scale
        color = rng.choice([(206, 170, 118, 255), (186, 150, 100, 255)])
        everywhere(lambda ox, oy: draw.ellipse(
            [ox + x - rx, oy + y - ry, ox + x + rx, oy + y + ry], fill=color))
    for _ in range(26):  # pebbles
        x, y = rng.uniform(0, size) * scale, rng.uniform(0, size) * scale
        r = rng.uniform(1.5, 3.2) * scale
        color = rng.choice([(150, 120, 86, 255), (226, 200, 156, 255)])
        everywhere(lambda ox, oy: draw.ellipse([ox + x - r, oy + y - r * 0.7, ox + x + r,
                                                oy + y + r * 0.7], fill=color))


def _paint_stone(draw, rng, everywhere, size, scale):
    stones = 4
    step = size / stones
    for row in range(stones):
        for col in range(stones):
            shift = step / 2 if row % 2 else 0
            x0 = (col * step + shift + rng.uniform(1.5, 3)) * scale
            y0 = (row * step + rng.uniform(1.5, 3)) * scale
            x1 = x0 + (step - rng.uniform(4, 6)) * scale
            y1 = y0 + (step - rng.uniform(4, 6)) * scale
            color = rng.choice([(196, 192, 204, 255), (182, 178, 192, 255), (208, 204, 214, 255)])
            everywhere(lambda ox, oy: draw.rounded_rectangle(
                [ox + x0, oy + y0, ox + x1, oy + y1], radius=6 * scale, fill=color,
                outline=(150, 144, 160, 255), width=scale))
            everywhere(lambda ox, oy: draw.line(
                [(ox + x0 + 4 * scale, oy + y0 + 4 * scale), (ox + x0 + 12 * scale,
                                                            oy + y0 + 4 * scale)],
                fill=(232, 230, 238, 255), width=scale))


def _paint_forest(draw, rng, everywhere, size, scale):
    for _ in range(12):
        x, y = rng.uniform(0, size) * scale, rng.uniform(0, size) * scale
        rx, ry = rng.uniform(16, 34) * scale, rng.uniform(10, 20) * scale
        color = rng.choice([(70, 134, 76, 255), (92, 154, 84, 255), (64, 120, 92, 255)])
        everywhere(lambda ox, oy: draw.ellipse(
            [ox + x - rx, oy + y - ry, ox + x + rx, oy + y + ry], fill=color))
    for _ in range(40):
        x, y = rng.uniform(0, size) * scale, rng.uniform(0, size) * scale
        h = rng.uniform(4, 7) * scale
        color = rng.choice([(52, 110, 64, 255), (110, 170, 96, 255)])
        everywhere(lambda ox, oy: draw.line(
            [(ox + x - 3 * scale, oy + y - h), (ox + x, oy + y), (ox + x + 3 * scale, oy + y - h)],
            fill=color, width=int(1.5 * scale)))


def _paint_cellar(draw, rng, everywhere, size, scale):
    bricks = 4
    step = size / bricks
    for row in range(bricks):
        for col in range(bricks // 2 + 1):
            shift = step if row % 2 else 0
            x0 = (col * step * 2 - shift + 2) * scale
            y0 = (row * step + 2) * scale
            x1, y1 = x0 + (step * 2 - 4) * scale, y0 + (step - 4) * scale
            color = rng.choice([(92, 84, 104, 255), (84, 76, 96, 255), (100, 92, 112, 255)])
            everywhere(lambda ox, oy: draw.rounded_rectangle(
                [ox + x0, oy + y0, ox + x1, oy + y1], radius=4 * scale, fill=color,
                outline=(58, 52, 70, 255), width=scale))


def build_tiles() -> Image.Image:
    """tiles.png: a row of 128 px ground tiles, TILE_KINDS order, two variants each."""
    makers = {
        "grass": lambda seed: build_grass_tile(TILE, seed),
        "path": lambda seed: _seamless(TILE, (196, 160, 110, 255), _paint_path, seed),
        "stone": lambda seed: _seamless(TILE, (160, 154, 170, 255), _paint_stone, seed),
        "forest": lambda seed: _seamless(TILE, (78, 142, 82, 255), _paint_forest, seed),
        "cellar": lambda seed: _seamless(TILE, (60, 54, 72, 255), _paint_cellar, seed),
    }
    sheet = Image.new("RGBA", (TILE * 2 * len(TILE_KINDS), TILE), (0, 0, 0, 0))
    for i, kind in enumerate(TILE_KINDS):
        for variant in range(2):
            sheet.paste(makers[kind](11 + variant * 31 + i), ((i * 2 + variant) * TILE, 0))
    return sheet


def build_grass_tile(size: int = 256, seed: int = 7) -> Image.Image:
    """Seamless tile: everything is drawn on a 3x3 grid, then the middle is kept."""
    rng = random.Random(seed)
    scale = 2
    full = size * 3 * scale
    image = Image.new("RGBA", (full, full), (124, 198, 98, 255))
    draw = ImageDraw.Draw(image)

    def everywhere(shape):
        for ox in range(3):
            for oy in range(3):
                shape(ox * size * scale, oy * size * scale)

    for _ in range(14):  # soft lighter / darker patches
        x, y = rng.uniform(0, size) * scale, rng.uniform(0, size) * scale
        rx, ry = rng.uniform(18, 40) * scale, rng.uniform(10, 22) * scale
        color = rng.choice([(134, 208, 106, 255), (116, 190, 92, 255)])
        everywhere(lambda ox, oy: draw.ellipse(
            [ox + x - rx, oy + y - ry, ox + x + rx, oy + y + ry], fill=color))

    for _ in range(70):  # little grass blades
        x, y = rng.uniform(0, size) * scale, rng.uniform(0, size) * scale
        h = rng.uniform(4, 7) * scale
        color = rng.choice([(92, 168, 78, 255), (152, 220, 116, 255)])
        everywhere(lambda ox, oy: draw.line(
            [(ox + x - 3 * scale, oy + y - h), (ox + x, oy + y), (ox + x + 3 * scale, oy + y - h)],
            fill=color, width=int(1.5 * scale)))

    for _ in range(6):  # tiny flowers
        x, y = rng.uniform(0, size) * scale, rng.uniform(0, size) * scale
        petal = rng.choice([(255, 255, 255, 255), (255, 214, 232, 255)])
        r = 2.2 * scale

        def flower(ox, oy):
            for dx, dy in ((-r, 0), (r, 0), (0, -r), (0, r)):
                draw.ellipse([ox + x + dx - r, oy + y + dy - r, ox + x + dx + r, oy + y + dy + r],
                             fill=petal)
            draw.ellipse([ox + x - r * 0.7, oy + y - r * 0.7, ox + x + r * 0.7, oy + y + r * 0.7],
                         fill=(252, 206, 86, 255))

        everywhere(flower)

    small = image.resize((size * 3, size * 3), Image.LANCZOS)
    return small.crop((size, size, size * 2, size * 2)).convert("RGB")


# (animation, half width, half height, face, droplets) for each slime frame.
SLIME_POSES = [
    ("idle", 22, 17, "normal", 0),
    ("idle", 24, 15, "normal", 0),
    ("attack", 19, 21, "angry", 0),
    ("attack", 27, 12, "angry", 0),
    ("die", 26, 11, "dead", 0),
    ("die", 30, 7, "dead", 6),
    ("die", 31, 4, "none", 5),
]
SLIME_ANIMATIONS = [("idle", 3.0, True), ("attack", 8.0, False), ("die", 8.0, False)]


def draw_slime(rx: float, ry: float, face: str = "normal", droplets: int = 0) -> Image.Image:
    """One slime frame. Its bottom stays on the ground; rx / ry give the squash."""
    c = Canvas(SLIME_FRAME)
    cx, cy = 32, SLIME_FEET_Y - ry
    c.ellipse(cx, SLIME_FEET_Y + 1, max(20, rx - 2), 4, SHADOW, outline=False)
    top = cy - ry
    if face != "none":
        c.line([(cx, top + 2), (cx, top - 6)], width=1.6)
        c.polygon([(cx, top - 5), (cx + 9, top - 11), (cx + 8, top - 3)], LEAF)
        c.polygon([(cx, top - 5), (cx - 8, top - 10), (cx - 7, top - 3)], LEAF)
    for i in range(droplets):
        side = -1 if i % 2 else 1
        dx = side * (rx + 2 + (i // 2) * 4)
        c.ellipse(cx + dx, SLIME_FEET_Y - 3 - (i % 3) * 3, 2.4, 2.0, SLIME)
    c.ellipse(cx, cy, rx, ry, SLIME)
    if ry > 6:
        c.ellipse(cx - rx * 0.4, cy - ry * 0.45, rx * 0.27, ry * 0.2, SLIME_LIGHT, outline=False)
    if face == "none":
        return c.finish()
    eye_y = cy - min(1.0, ry * 0.08)
    for side in (-1, 1):
        ex = cx + side * 8
        if face == "dead":
            c.line([(ex - 2.2, eye_y - 2.2), (ex + 2.2, eye_y + 2.2)], width=1.4)
            c.line([(ex - 2.2, eye_y + 2.2), (ex + 2.2, eye_y - 2.2)], width=1.4)
            continue
        c.ellipse(ex, eye_y, 3.2, min(4.6, ry * 0.3), EYE, outline=False)
        c.ellipse(ex - 1, eye_y - 2, 1.3, 1.3, WHITE, outline=False)
        if face == "angry":
            c.line([(ex + side * 4, eye_y - 7), (ex - side * 2.5, eye_y - 4.5)], width=1.5)
        c.ellipse(cx + side * min(15, rx - 6), cy + min(6, ry * 0.4), 3.0, 1.8, BLUSH, outline=False)
    if face == "angry":
        c.line(arc_points(cx, cy + min(8, ry * 0.5), 2.6, 1.6, 200, 340, 8), width=1.2)
    elif face == "normal":
        c.line(arc_points(cx, cy + 5, 2.6, 1.8, 20, 160, 8), width=1.2)
    return c.finish()


def build_slime_sheet() -> Image.Image:
    sheet = Image.new("RGBA", (SLIME_FRAME * len(SLIME_POSES), SLIME_FRAME), (0, 0, 0, 0))
    for col, (_, rx, ry, face, droplets) in enumerate(SLIME_POSES):
        sheet.paste(draw_slime(rx, ry, face, droplets), (col * SLIME_FRAME, 0))
    return sheet


def build_slime_frames(sheet_res_path: str) -> str:
    """SpriteFrames text for the slime: idle (loops), attack and die."""
    lines = [
        f'[gd_resource type="SpriteFrames" load_steps={len(SLIME_POSES) + 2} format=3]',
        "",
        f'[ext_resource type="Texture2D" path="{sheet_res_path}" id="1_sheet"]',
        "",
    ]
    for col in range(len(SLIME_POSES)):
        lines += [
            f'[sub_resource type="AtlasTexture" id="frame_{col}"]',
            'atlas = ExtResource("1_sheet")',
            f"region = Rect2({col * SLIME_FRAME}, 0, {SLIME_FRAME}, {SLIME_FRAME})",
            "",
        ]
    blocks = []
    for name, fps, loop in SLIME_ANIMATIONS:
        columns = [col for col, pose in enumerate(SLIME_POSES) if pose[0] == name]
        frames = ", ".join(
            '{\n"duration": 1.0,\n"texture": SubResource("frame_%d")\n}' % col for col in columns
        )
        blocks.append(
            '{\n"frames": [%s],\n"loop": %s,\n"name": &"%s",\n"speed": %.1f\n}'
            % (frames, "true" if loop else "false", name, fps)
        )
    lines += ["[resource]", "animations = [" + ", ".join(blocks) + "]", ""]
    return "\n".join(lines)


def main() -> None:
    warrior_dir = ASSETS / "characters" / "warrior"
    environment_dir = ASSETS / "environment"
    warrior_dir.mkdir(parents=True, exist_ok=True)
    environment_dir.mkdir(parents=True, exist_ok=True)

    frames = build_warrior_parts()
    sheet = build_warrior_sheet(frames)
    sheet.save(warrior_dir / "warrior.png")
    add_look_variants(frames)
    atlas, pieces = pack_warrior_parts(frames)
    atlas.save(warrior_dir / "warrior_parts.png")
    (warrior_dir / "warrior_parts.gd").write_text(build_parts_script(pieces), encoding="utf-8")
    build_icon(sheet).save(ROOT / "client" / "icon.png")
    (warrior_dir / "warrior_frames.tres").write_text(
        build_sprite_frames("res://assets/characters/warrior/warrior.png"), encoding="utf-8"
    )
    build_grass_tile().save(environment_dir / "grass.png")
    build_tiles().save(environment_dir / "tiles.png")
    build_tree().save(environment_dir / "tree.png")
    build_rock().save(environment_dir / "rock.png")

    items_dir = ASSETS / "items"
    items_dir.mkdir(parents=True, exist_ok=True)
    build_coin().save(items_dir / "coin.png")
    build_potion().save(items_dir / "potion.png")
    build_book().save(items_dir / "book.png")
    build_potion(colors=BLUE_POTION).save(items_dir / "blue_potion.png")
    build_stone(colors=EMBER_STONE).save(items_dir / "ember_stone.png")
    build_stone(colors=MOON_STONE).save(items_dir / "moon_stone.png")
    build_scroll().save(items_dir / "scroll.png")
    icons_dir = items_dir / "icons"
    icons_dir.mkdir(parents=True, exist_ok=True)
    for name, image in build_item_icons().items():
        image.save(icons_dir / f"{name}.png")

    slime_dir = ASSETS / "monsters" / "slime"
    slime_dir.mkdir(parents=True, exist_ok=True)
    build_slime_sheet().save(slime_dir / "slime.png")
    (slime_dir / "slime_frames.tres").write_text(
        build_slime_frames("res://assets/monsters/slime/slime.png"), encoding="utf-8"
    )
    print("Assets written to", ASSETS)


if __name__ == "__main__":
    main()
