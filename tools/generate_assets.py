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
    pull: float = 0.0  # bow frames: how far the string is drawn back (0..1)
    off_hand: tuple | None = None  # bow frames: where the hand that draws the string is


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


# Bow shot for each drawn direction. Per frame: (hand on the bow, a point the arrow
# aims at, layer, body bob, upper-body lean, trail?, string drawn 0..1, the hand
# on the string). The arrow itself flies as a projectile in the game.
BOW_ATTACKS = {
    "down": [
        ((40, 67), (40, 87), "front", -0.4, (0.0, -0.4), False, 0.4, (50, 63)),
        ((46, 68), (46, 88), "front", -0.2, (0.0, -0.8), False, 1.0, (52, 60)),
        ((46, 70), (46, 90), "front", 0.6, (0.0, 0.6), False, 0.0, (58, 61)),
        ((45, 70), (45, 90), "front", 0.4, (0.0, 0.4), False, 0.0, (60, 65)),
        ((36, 70), (18, 72), "back", 0.2, (0.0, 0.2), False, 0.0, None),
    ],
    "up": [
        ((60, 54), (60, 34), "body", -0.4, (0.0, -0.4), False, 0.4, (52, 60)),
        ((58, 50), (58, 30), "body", -0.2, (0.0, -0.8), False, 1.0, (54, 62)),
        ((58, 50), (58, 30), "body", 0.6, (0.0, -0.2), False, 0.0, (44, 60)),
        ((60, 54), (60, 34), "body", 0.4, (0.0, 0.2), False, 0.0, (42, 64)),
        ((64, 68), (82, 70), "back", 0.2, (0.0, 0.2), False, 0.0, None),
    ],
    "left": [
        ((30, 62), (10, 62), "front", -0.4, (0.5, 0.0), False, 0.4, (40, 60)),
        ((25, 60), (5, 60), "front", -0.2, (1.0, 0.0), False, 1.0, (40, 59)),
        ((25, 60), (5, 60), "front", 0.6, (-0.8, 0.4), False, 0.0, (46, 58)),
        ((28, 62), (8, 62), "front", 0.4, (-0.4, 0.4), False, 0.0, (44, 62)),
        ((34, 68), (20, 80), "front", 0.2, (0.0, 0.2), False, 0.0, None),
    ],
}


def attack_poses(direction: str) -> list[Pose]:
    view = "left" if direction == "right" else direction
    poses, previous_tip = [], None
    for entry in HERO["attacks"][view]:
        hand, tip, layer, bob, lean, trail = entry[:6]
        pull, off_hand = entry[6:] if len(entry) > 6 else (0.0, None)
        poses.append(
            Pose(
                bob=bob,
                lean=lean,
                sword=(hand, tip, layer),
                trail=(previous_tip, tip) if trail and previous_tip else None,
                pull=pull,
                off_hand=off_hand,
            )
        )
        previous_tip = tip
    return poses


# ---------------------------------------------------------------- heroes
# The three classes share the chibi body and the idle, walk and hurt frames.
# Each has its own weapon (drawn in the sword_* parts), head gear, armour, hair
# and reach; the archer also has its own attack frames (BOW_ATTACKS).

WOOD = (156, 104, 62, 255)
WOOD_DARK = (116, 74, 44, 255)
ORB = (110, 214, 255, 255)
ORB_GLOW = (150, 226, 255, 110)
ROBE = (128, 88, 204, 255)
ROBE_DARK = (94, 60, 160, 255)
ROBE_LIGHT = (176, 144, 238, 255)
HOOD = (74, 150, 88, 255)
HOOD_DARK = (50, 110, 64, 255)
VEST = (156, 104, 64, 255)
VEST_DARK = (120, 78, 48, 255)
STRING = (244, 240, 226, 255)
FLETCH = (236, 96, 86, 255)

HEROES = {
    "warrior": {
        "weapon": "sword",
        "gear": ["red_headband", "training_sword", "leather_gloves", "red_cape", "blue_plate",
                 "leather_boots"],
        "attacks": ATTACKS,
        "reach": {"down": (-13, -27), "up": (13, -27), "side": (-26, -16)},
        "hair": ((238, 126, 62, 255), (204, 92, 44, 255), (255, 172, 100, 255)),
        "tuft": True,
        "trail": ((255, 255, 255, 150), (200, 236, 255, 220)),
    },
    "mage": {
        "weapon": "staff",
        "gear": ["sage_hat", "oak_staff", "leather_gloves", "red_cape", "violet_robe",
                 "leather_boots"],
        "attacks": ATTACKS,
        "reach": {"down": (-5, -30), "up": (5, -30), "side": (-9, -29)},
        "hair": ((150, 192, 242, 255), (108, 146, 210, 255), (208, 230, 255, 255)),
        "tuft": False,
        "trail": ((205, 160, 255, 150), (236, 214, 255, 220)),
    },
    "archer": {
        "weapon": "bow",
        "gear": ["green_hood", "short_bow", "leather_gloves", "red_cape", "ranger_vest",
                 "leather_boots"],
        "attacks": BOW_ATTACKS,
        "reach": {"down": (-20, 3), "up": (20, 3), "side": (-14, 14)},
        "hair": ((134, 84, 58, 255), (98, 60, 42, 255), (184, 126, 90, 255)),
        "tuft": False,
        "trail": ((255, 255, 255, 150), (200, 236, 255, 220)),
    },
}
HERO = HEROES["warrior"]  # the class being drawn now (build_hero_parts switches it)


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


def draw_staff(c: Canvas, hand, tip) -> None:
    """Mage's staff: a long wooden shaft, a ring at the top holding a glowing orb."""
    hx, hy = hand
    length = math.hypot(tip[0] - hx, tip[1] - hy)
    ux, uy = (tip[0] - hx) / length, (tip[1] - hy) / length
    nx, ny = -uy, ux

    def at(along, across=0.0):
        return (hx + ux * along + nx * across, hy + uy * along + ny * across)

    top = length + 1.0
    c.polygon([at(-13, -1.6), at(top - 4, -1.6), at(top - 4, 1.6), at(-13, 1.6)], WOOD)
    c.line([at(-9, -1.6), at(-7.5, 1.6)], fill=WOOD_DARK, width=0.9)
    c.ellipse(*at(-13.5), 1.9, 1.9, WOOD_DARK)  # foot of the staff
    glow = c.layer()
    glow.ellipse(*at(top), 7.5, 7.5, ORB_GLOW, outline=False)
    c.blend(glow)
    c.ellipse(*at(top), 5.0, 5.0, WOOD)  # ring
    for side in (-1, 1):  # two little prongs
        c.polygon([at(top - 3, side * 3.5), at(top + 1, side * 7), at(top, side * 3.0)], WOOD)
    c.ellipse(*at(top), 3.4, 3.4, ORB)
    c.ellipse(*at(top + 1.2, -1.2), 1.1, 1.1, WHITE, outline=False)


def draw_bow(c: Canvas, hand, aim, pull: float = 0.0) -> None:
    """Archer's bow held at the hand, its back towards the aim. Drawn back (pull > 0),
    the string bends to the other hand and an arrow lies on it."""
    hx, hy = hand
    length = math.hypot(aim[0] - hx, aim[1] - hy) or 1.0
    ux, uy = (aim[0] - hx) / length, (aim[1] - hy) / length  # towards the target
    nx, ny = -uy, ux  # along the bow

    def at(forward, along):
        return (hx + ux * forward + nx * along, hy + uy * forward + ny * along)

    half = 17.0
    limb = [at(5.0 * (1 - (t / half) ** 2) - 1.5, t) for t in
            [half * (i / 8 - 1) for i in range(17)]]
    string_mid = at(-1.5 - pull * 11.0, 0)
    c.line([limb[0], string_mid, limb[-1]], fill=STRING, width=0.8)
    if pull > 0:
        tail, head = string_mid, at(9.0, 0)
        c.line([tail, head], fill=WOOD_DARK, width=1.1)
        c.polygon([at(12.5, 0), at(8.0, -2.4), at(8.0, 2.4)], STEEL)
        c.polygon([tail, at(-1.5 - pull * 11.0 + 4.5, -2.6), at(-1.5 - pull * 11.0 + 3.0, 0)],
                  FLETCH, outline=False)
        c.polygon([tail, at(-1.5 - pull * 11.0 + 4.5, 2.6), at(-1.5 - pull * 11.0 + 3.0, 0)],
                  FLETCH, outline=False)
    c.line(limb, fill=OUTLINE, width=3.8)
    c.line(limb, fill=WOOD, width=2.3)
    for end in (limb[0], limb[-1]):
        c.ellipse(end[0], end[1], 1.5, 1.5, GOLD)
    c.polygon([at(3.0, -3.2), at(5.0, -3.2), at(5.0, 3.2), at(3.0, 3.2)], GRIP)  # grip


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
    fill, edge = HERO["trail"]
    layer = c.layer()
    layer.polygon(outer + inner[::-1], fill, outline=False)
    layer.line(outer, fill=edge, width=1.0)
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
    if HERO["weapon"] == "staff":
        draw_staff(c, hand, tip)
    elif HERO["weapon"] == "bow":
        draw_bow(c, hand, tip, pose.pull)
    else:
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
        "shadow", "cape", "quiver", "sword_back", "legs", "boots", "torso", "armor", "robe",
        "vest", "arms", "armor_arms", "robe_arms", "bracers", "hands", "gloves", "pauldrons",
        "scarf", "sword_body", "grip_hand_body", "grip_glove_body", "tails", "head", "headband",
        "hood", "hat", "sword_front", "grip_hand_front", "grip_glove_front",
    ],
    "up": [
        "shadow", "sword_back", "legs", "boots", "torso", "armor", "robe", "vest", "arms",
        "armor_arms", "robe_arms", "bracers", "hands", "gloves", "cape", "quiver", "pauldrons",
        "sword_body", "grip_hand_body", "grip_glove_body", "head", "headband", "hood", "hat",
        "sword_front", "grip_hand_front", "grip_glove_front",
    ],
    "side": [
        "shadow", "cape", "quiver", "arm_far", "armor_arm_far", "robe_arm_far", "bracer_far",
        "hand_far", "glove_far", "sword_back", "legs_far", "boots_far", "legs_near",
        "boots_near", "torso", "armor", "robe", "vest", "arms", "armor_arms", "robe_arms",
        "bracers", "hands", "gloves", "pauldrons", "scarf", "sword_body", "grip_hand_body",
        "grip_glove_body", "tails", "head", "headband", "hood", "hat", "sword_front",
        "grip_hand_front", "grip_glove_front",
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
    "hat": ["sage_hat"],
    "robe": ["violet_robe"],
    "robe_arms": ["violet_robe"],
    "robe_arm_far": ["violet_robe"],
    "hood": ["green_hood"],
    "vest": ["ranger_vest"],
    "quiver": ["short_bow"],
}
ALL_GEAR = set(HEROES["warrior"]["gear"])


def requires_for(hero: str) -> dict:
    """PART_REQUIRES for one class: the sword_* parts hold that class's weapon."""
    weapon = HEROES[hero]["gear"][1]
    return {
        part: [weapon if item == "training_sword" else item for item in items]
        for part, items in PART_REQUIRES.items()
    }

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
    "swift_boots": (
        "leather_boots", "boots", ["boots", "boots_far", "boots_near"], [("hue", 20, 190)]
    ),
    "hawk_gloves": (
        "leather_gloves", "gloves",
        ["gloves", "bracers", "glove_far", "bracer_far", "grip_glove_body", "grip_glove_front"],
        [("hue", 20, 45)],
    ),
    "duelist_cape": ("red_cape", "cape", ["cape", "scarf"], [("hue", 355, 215)]),
    # The Elderwood tier (level 12, Elder Grove): jade green on the same pieces.
    "elderwood_blade": (
        "training_sword", "sword", ["sword_back", "sword_body", "sword_front"],
        [("steel", (120, 230, 190), 0.4), ("hue", 30, 160)],
    ),
    "elderwood_bow": (
        "short_bow", "bow", ["sword_back", "sword_body", "sword_front", "quiver"], [("hue", 26, 160)]
    ),
    "elderwood_staff": (
        "oak_staff", "staff", ["sword_back", "sword_body", "sword_front"], [("hue", 197, 150)]
    ),
    "elderwood_plate": (
        "blue_plate", "armor", ["armor", "armor_arms", "armor_arm_far", "pauldrons"], [("hue", 220, 160)],
    ),
    "elderwood_vest": ("ranger_vest", "vest", ["vest"], [("hue", 26, 160)]),
    "elderwood_robe": (
        "violet_robe", "robe", ["robe", "robe_arms", "robe_arm_far"], [("hue", 261, 160)]
    ),
    "elderwood_band": ("red_headband", "headband", ["headband", "tails"], [("hue", 355, 160)]),
    "elderwood_hood": ("green_hood", "hood", ["hood"], [("hue", 131, 165)]),
    "elderwood_hat": ("sage_hat", "hat", ["hat"], [("hue", 261, 160)]),
    "elderwood_gloves": (
        "leather_gloves", "gloves",
        ["gloves", "bracers", "glove_far", "bracer_far", "grip_glove_body", "grip_glove_front"],
        [("hue", 20, 160)],
    ),
    "elderwood_boots": (
        "leather_boots", "boots", ["boots", "boots_far", "boots_near"], [("hue", 20, 160)]
    ),
    "elderwood_cape": ("red_cape", "cape", ["cape", "scarf"], [("hue", 355, 160)]),
    # The Moonfall tier (level 18, Moonfall Ruins): moonlit indigo and silver.
    "moonfall_blade": (
        "training_sword", "sword", ["sword_back", "sword_body", "sword_front"],
        [("steel", (190, 205, 255), 0.45), ("hue", 30, 250)],
    ),
    "moonfall_bow": (
        "short_bow", "bow", ["sword_back", "sword_body", "sword_front", "quiver"], [("hue", 26, 250)]
    ),
    "moonfall_staff": (
        "oak_staff", "staff", ["sword_back", "sword_body", "sword_front"], [("hue", 197, 250)]
    ),
    "moonfall_plate": (
        "blue_plate", "armor", ["armor", "armor_arms", "armor_arm_far", "pauldrons"], [("hue", 220, 268)],
    ),
    "moonfall_vest": ("ranger_vest", "vest", ["vest"], [("hue", 26, 250)]),
    "moonfall_robe": (
        "violet_robe", "robe", ["robe", "robe_arms", "robe_arm_far"], [("hue", 261, 228)]
    ),
    "moonfall_band": ("red_headband", "headband", ["headband", "tails"], [("hue", 355, 250)]),
    "moonfall_hood": ("green_hood", "hood", ["hood"], [("hue", 131, 250)]),
    "moonfall_hat": ("sage_hat", "hat", ["hat"], [("hue", 261, 228)]),
    "moonfall_gloves": (
        "leather_gloves", "gloves",
        ["gloves", "bracers", "glove_far", "bracer_far", "grip_glove_body", "grip_glove_front"],
        [("hue", 20, 250)],
    ),
    "moonfall_boots": (
        "leather_boots", "boots", ["boots", "boots_far", "boots_near"], [("hue", 20, 250)]
    ),
    "moonfall_cape": ("red_cape", "cape", ["cape", "scarf"], [("hue", 355, 250)]),
    # The Frostfang tier (level 22, Frostfang Hollow): ice blue and frost white.
    "frostfang_blade": (
        "training_sword", "sword", ["sword_back", "sword_body", "sword_front"],
        [("steel", (215, 240, 255), 0.5), ("hue", 30, 195)],
    ),
    "frostfang_bow": (
        "short_bow", "bow", ["sword_back", "sword_body", "sword_front", "quiver"], [("hue", 26, 195)]
    ),
    "frostfang_staff": (
        "oak_staff", "staff", ["sword_back", "sword_body", "sword_front"],
        [("hue", 30, 200), ("hue", 197, 178)],
    ),
    "frostfang_plate": (
        "blue_plate", "armor", ["armor", "armor_arms", "armor_arm_far", "pauldrons"], [("hue", 220, 190)],
    ),
    "frostfang_vest": ("ranger_vest", "vest", ["vest"], [("hue", 26, 195)]),
    "frostfang_robe": (
        "violet_robe", "robe", ["robe", "robe_arms", "robe_arm_far"], [("hue", 261, 192)]
    ),
    "frostfang_band": ("red_headband", "headband", ["headband", "tails"], [("hue", 355, 195)]),
    "frostfang_hood": ("green_hood", "hood", ["hood"], [("hue", 131, 195)]),
    "frostfang_hat": ("sage_hat", "hat", ["hat"], [("hue", 261, 192)]),
    "frostfang_gloves": (
        "leather_gloves", "gloves",
        ["gloves", "bracers", "glove_far", "bracer_far", "grip_glove_body", "grip_glove_front"],
        [("hue", 20, 195)],
    ),
    "frostfang_boots": (
        "leather_boots", "boots", ["boots", "boots_far", "boots_near"], [("hue", 20, 195)]
    ),
    "frostfang_cape": ("red_cape", "cape", ["cape", "scarf"], [("hue", 355, 195)]),
    "crimson_plate": (
        "blue_plate", "armor", ["armor", "armor_arms", "armor_arm_far", "pauldrons"],
        [("hue", 220, 355)],
    ),
    "crimson_sword": (
        "training_sword", "sword", ["sword_back", "sword_body", "sword_front"],
        [("steel", (255, 110, 110), 0.45), ("hue", 30, 350)],
    ),
    "champion_cape": ("red_cape", "cape", ["cape", "scarf"], [("hue", 355, 285)]),
    "ember_staff": (
        "oak_staff", "staff", ["sword_back", "sword_body", "sword_front"], [("hue", 197, 18)]
    ),
    "midnight_robe": (
        "violet_robe", "robe", ["robe", "robe_arms", "robe_arm_far"], [("hue", 261, 222)]
    ),
    "starlit_hat": ("sage_hat", "hat", ["hat"], [("hue", 261, 212)]),
    "crimson_bow": (
        "short_bow", "bow", ["sword_back", "sword_body", "sword_front", "quiver"],
        [("hue", 26, 352)],
    ),
    "shadow_vest": ("ranger_vest", "vest", ["vest"], [("hue", 26, 225)]),
    "azure_hood": ("green_hood", "hood", ["hood"], [("hue", 131, 205)]),
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


# Townspeople: the warrior's plain body (no gear) with the tunic dyed and the
# hair recoloured. look -> (tunic hue, tunic saturation, hair hue or None for
# grey hair).
NPC_LOOKS = {
    "merchant": (130, 0.45, 30),
    "healer": (330, 0.28, 48),
    "keeper": (28, 0.5, None),
    "guide": (270, 0.45, 205),
    "captain": (0, 0.55, 18),
    "master": (45, 0.6, 265),
}


def _dye(image: Image.Image, hue: float, saturation: float) -> Image.Image:
    """The pale cream tunic (hue near 40, low saturation, light) in another colour."""
    out = image.copy()
    box = out.getchannel("A").getbbox()
    if not box:
        return out
    pixels = out.load()
    for y in range(box[1], box[3]):
        for x in range(box[0], box[2]):
            r, g, b, a = pixels[x, y]
            h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
            if a and s < 0.35 and v > 0.55 and abs(h * 360 - 40) < 30:
                r, g, b = (round(c * 255) for c in colorsys.hsv_to_rgb(hue / 360, saturation, v))
                pixels[x, y] = (r, g, b, a)
    return out


def _hair(image: Image.Image, hue) -> Image.Image:
    """The orange hair (strongly coloured, unlike the skin) in another colour, or grey."""
    out = image.copy()
    box = out.getchannel("A").getbbox()
    if not box:
        return out
    pixels = out.load()
    for y in range(box[1], box[3]):
        for x in range(box[0], box[2]):
            r, g, b, a = pixels[x, y]
            h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
            if a and s > 0.5 and v > 0.3 and (h * 360 < 45 or h * 360 > 350):
                if hue is None:
                    rgb = colorsys.hsv_to_rgb(0, 0.04, min(1.0, v * 0.95))
                else:
                    rgb = colorsys.hsv_to_rgb(hue / 360, s, v)
                pixels[x, y] = (*(round(c * 255) for c in rgb), a)
    return out


def build_npc_sheet(frames, look: str) -> Image.Image:
    """Four idle frames (facing down) of a townsperson, side by side."""
    tunic_hue, tunic_saturation, hair_hue = NPC_LOOKS[look]
    sheet = Image.new("RGBA", (CELL * IDLE_FRAMES, CELL), (0, 0, 0, 0))
    for col in range(IDLE_FRAMES):
        parts = dict(frames[(0, col)])
        for part in ("torso", "arms"):
            if part in parts:
                parts[part] = _dye(parts[part], tunic_hue, tunic_saturation)
        if "head" in parts:
            parts["head"] = _hair(parts["head"], hair_hue)
        sheet.paste(compose(parts, "down", set()), (col * CELL, 0))
    return sheet


def build_jelly(out_size: int = 32, shadow: bool = True) -> Image.Image:
    """Slime Jelly: a wobbly green drop that slimes leave behind."""
    c = Canvas(32)
    if shadow:
        c.ellipse(16, 27.5, 9, 3, SHADOW, outline=False)
    c.ellipse(16, 19, 10, 8, (118, 214, 110, 255))
    c.ellipse(16, 13.5, 5.5, 5, (118, 214, 110, 255), outline=False)
    c.ellipse(12.5, 15.5, 2.6, 2, (214, 255, 200, 255), outline=False)
    c.ellipse(20, 21, 1.4, 1.1, (214, 255, 200, 255), outline=False)
    return c.finish(out_size)


def add_look_variants(frames, hero: str = "warrior") -> None:
    """Adds the recoloured parts of the LOOK_VARIANTS items the class can wear."""
    gear = set(HEROES[hero]["gear"])
    for parts in frames.values():
        for variant, (base, _, variant_parts, rules) in LOOK_VARIANTS.items():
            if base not in gear:
                continue
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
    c.use("robe_arm_far" if far else "robe_arms")
    cuff = lerp(shoulder, hand, 0.78)
    c.capsule(shoulder, cuff, 4.3, ROBE)
    c.ellipse(cuff[0], cuff[1], 4.4, 3.8, ROBE_LIGHT)
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


def draw_robe_front(c: Canvas, cx, oy, back=False) -> None:
    """The mage's robe: from the shoulders down past the knees, with a gold sash."""
    top, bottom, hem = 54 + oy, 71 + oy, 81 + oy
    c.use("robe")
    c.polygon([(cx - 12.5, top + 1), (cx + 12.5, top + 1), (cx + 16, hem), (cx - 16, hem)], ROBE)
    c.polygon([(cx - 15.3, hem - 3.6), (cx + 15.3, hem - 3.6), (cx + 15.6, hem - 0.8),
               (cx - 15.6, hem - 0.8)], ROBE_DARK, outline=False)
    c.line([(cx - 15.2, hem - 3.6), (cx + 15.2, hem - 3.6)], fill=GOLD, width=1.1)
    if back:
        c.line([(cx, top + 4), (cx, hem - 4)], fill=ROBE_DARK, width=1.2)
    else:
        c.polygon([(cx - 5, top + 1), (cx + 5, top + 1), (cx, top + 9)], TUNIC)
        c.line([(cx, top + 9), (cx, hem - 4)], fill=ROBE_DARK, width=1.2)
        c.ellipse(cx - 6.5, top + 6, 3.4, 2.0, ROBE_LIGHT, outline=False)
    c.rect(cx - 13.4, bottom - 6, cx + 13.4, bottom - 3, GOLD, radius=1)  # sash
    if not back:
        c.ellipse(cx, bottom - 4.5, 2.2, 2.2, ORB)


def draw_robe_side(c: Canvas, cx, oy, wind) -> None:
    top, bottom, hem = 54 + oy, 71 + oy, 81 + oy
    c.use("robe")
    flare = 3.5 + wind * 3
    c.polygon([(cx - 9, top + 1), (cx + 9.5, top + 1), (cx + 10 + flare, hem), (cx - 12, hem)],
              ROBE)
    c.polygon([(cx - 11.6, hem - 3.6), (cx + 9.5 + flare, hem - 3.6), (cx + 9.8 + flare, hem - 0.8),
               (cx - 11.8, hem - 0.8)], ROBE_DARK, outline=False)
    c.line([(cx - 11.5, hem - 3.6), (cx + 9.4 + flare, hem - 3.6)], fill=GOLD, width=1.1)
    c.ellipse(cx - 4, top + 5.5, 3.0, 2.0, ROBE_LIGHT, outline=False)
    c.rect(cx - 9.8, bottom - 6, cx + 10.2, bottom - 3, GOLD, radius=1)  # sash


def draw_vest_front(c: Canvas, cx, oy, back=False) -> None:
    """The archer's leather vest with a belt; in front the quiver strap crosses it."""
    top, bottom = 54 + oy, 71 + oy
    c.use("vest")
    c.rect(cx - 12.6, top + 0.5, cx + 12.6, bottom + 1, VEST, radius=6)
    if back:
        c.line([(cx - 10, top + 4), (cx + 10, bottom - 7)], fill=VEST_DARK, width=2.4)
    else:
        c.polygon([(cx - 5, top + 0.5), (cx + 5, top + 0.5), (cx, top + 8)], TUNIC)
        c.line([(cx - 11, top + 3), (cx + 10, bottom - 5)], fill=VEST_DARK, width=2.6)
        c.ellipse(cx - 6, top + 6, 3.2, 1.8, (196, 144, 98, 255), outline=False)
    c.rect(cx - 13, bottom - 6, cx + 13, bottom - 2.6, GRIP, radius=1)  # belt
    if not back:
        c.rect(cx - 2.5, bottom - 6.6, cx + 2.5, bottom - 2, GOLD, radius=0.8)


def draw_vest_side(c: Canvas, cx, oy) -> None:
    top, bottom = 54 + oy, 71 + oy
    c.use("vest")
    c.rect(cx - 9.4, top + 0.5, cx + 9.8, bottom + 1, VEST, radius=5)
    c.line([(cx - 8, top + 3), (cx + 8, bottom - 5)], fill=VEST_DARK, width=2.4)
    c.rect(cx - 9.8, bottom - 6, cx + 10.2, bottom - 2.6, GRIP, radius=1)  # belt


def draw_quiver(c: Canvas, cx, oy, view: str) -> None:
    """Quiver on the archer's back. From the front only the arrow ends show."""
    c.use("quiver")
    if view == "down":
        for i, x in enumerate((cx + 9.5, cx + 13, cx + 16.5)):
            tip = (x + 1.5, 44 + oy - i)
            c.line([(x, 52 + oy), tip], fill=WOOD_DARK, width=1.0)
            c.polygon([tip, (tip[0] - 2.2, tip[1] + 4), (tip[0] + 2.2, tip[1] + 4)], FLETCH)
        return
    if view == "up":
        box = [(cx + 3, 49 + oy), (cx + 11, 51 + oy), (cx + 3, 76 + oy), (cx - 5, 74 + oy)]
        top = [(cx + 4.5, 49 + oy), (cx + 7.5, 48 + oy), (cx + 10.5, 50 + oy)]
    else:
        box = [(cx + 7, 50 + oy), (cx + 13.5, 51 + oy), (cx + 12.5, 73 + oy), (cx + 6, 72 + oy)]
        top = [(cx + 8, 50 + oy), (cx + 10.5, 49 + oy), (cx + 13, 50.5 + oy)]
    for x, y in top:
        c.line([(x, y), (x + 1, y - 7)], fill=WOOD_DARK, width=1.0)
        c.polygon([(x + 1, y - 9), (x - 1.2, y - 5), (x + 3.2, y - 5)], FLETCH)
    c.polygon(box, VEST)
    c.line([box[0], box[1]], fill=GOLD, width=1.2)


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
    if HERO["tuft"]:
        c.polygon([(cx - 3, cy - 18), (cx + 7 + sway * 1.5, cy - 29), (cx + 5, cy - 17)],
                  HERO["hair"][0])


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
    hair, _, hair_light = HERO["hair"]
    c.polygon(arc_points(cx, cy, 23, 21.5, 180, 360) + fringe, hair)
    c.line(arc_points(cx, cy - 4, 16, 13, 215, 260, 8), fill=hair_light, width=2.2)
    c.use("headband")
    draw_band(c, cx, cy, 21.8)
    c.rect(cx - 4.2, cy - 4.4, cx + 4.2, cy + 1.4, GOLD, radius=1.2)  # forehead plate
    c.ellipse(cx, cy - 1.5, 1.5, 1.5, GEM, outline=False)
    draw_hat(c, cx, cy, sway, "down")
    draw_hood(c, cx, cy, sway, "down")


def draw_head_back(c: Canvas, cx, cy, sway) -> None:
    c.use("head")
    draw_tuft(c, cx, cy, sway)
    spikes = [(cx + 21, cy + 6), (cx + 16, cy + 19), (cx + 10, cy + 15), (cx + 5, cy + 23),
              (cx, cy + 17), (cx - 5, cy + 23), (cx - 10, cy + 15), (cx - 16, cy + 19),
              (cx - 21, cy + 6)]
    hair, hair_dark, hair_light = HERO["hair"]
    c.polygon(arc_points(cx, cy, 23, 21.5, 165, 375) + spikes, hair)
    c.line(arc_points(cx, cy + 2, 14, 10, 30, 150, 10), fill=hair_dark, width=1.4)
    c.line(arc_points(cx, cy - 4, 16, 13, 215, 260, 8), fill=hair_light, width=2.2)
    c.use("headband")
    draw_band(c, cx, cy, 21.8)
    draw_tails(c, (cx, cy - 0.5), 90, 15, sway)
    c.ellipse(cx, cy - 1.3, 2.8, 2.3, CAPE)  # knot
    draw_hat(c, cx, cy, sway, "up")
    draw_hood(c, cx, cy, sway, "up")


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
    hair, _, hair_light = HERO["hair"]
    c.polygon(arc_points(cx, cy, 22, 21.5, 188, 425) + inner, hair)
    c.line(arc_points(cx + 1, cy - 4, 16, 13, 220, 265, 8), fill=hair_light, width=2.2)
    c.use("headband")
    draw_band(c, cx, cy, 20.8)
    c.rect(cx - 21.8, cy - 8.6, cx - 18.4, cy - 3, GOLD, radius=1)  # edge of the forehead plate
    c.ellipse(cx + 19.3, cy - 6, 2.8, 2.3, CAPE)  # knot
    draw_hat(c, cx, cy, sway, "side")
    draw_hood(c, cx, cy, sway, "side")


def draw_hat(c: Canvas, cx, cy, sway, view: str) -> None:
    """The mage's pointed hat: a wide brim and a cone whose tip flops over."""
    c.use("hat")
    lean = {"down": 1, "up": -1, "side": 1}[view]
    bx = cx + (2 if view == "side" else 0)
    c.ellipse(bx, cy - 7, 25 if view == "side" else 27, 6.0, ROBE_DARK)  # brim
    tip = (bx + lean * 17 + sway * 1.5, cy - 30)
    cone = [(bx - 13, cy - 9), (bx + 13, cy - 9), (bx + lean * 8, cy - 22), tip,
            (bx + lean * 1, cy - 27)]
    if lean < 0:
        cone = [(bx - 13, cy - 9), (bx + 13, cy - 9), (bx - lean * 1, cy - 27), tip,
                (bx + lean * 8, cy - 22)]
    c.polygon(cone, ROBE)
    c.polygon([(bx - 13, cy - 9), (bx + 13, cy - 9), (bx + 11.4, cy - 13.2),
               (bx - 11.4, cy - 13.2)], GOLD)  # band
    if view == "down":
        star = [(cx - 3 + 3.2 * math.cos(math.radians(a)) * (1 if i % 2 == 0 else 0.45),
                 cy - 19 + 3.2 * math.sin(math.radians(a)) * (1 if i % 2 == 0 else 0.45))
                for i, a in enumerate(range(-90, 270, 36))]
        c.polygon(star, GOLD, outline=False)
    c.ellipse(tip[0], tip[1], 2.0, 2.0, GOLD)


def draw_hood(c: Canvas, cx, cy, sway, view: str) -> None:
    """The archer's hood with a short mantle over the shoulders."""
    c.use("hood")
    if view == "down":
        outer = arc_points(cx, cy + 1, 25.5, 24, 145, 395, 24)
        inner = arc_points(cx, cy + 2.5, 20.5, 18.5, 395, 145, 24)
        c.polygon(outer + inner, HOOD)
        c.line(arc_points(cx, cy + 2.5, 20.5, 18.5, 200, 340, 16), fill=HOOD_DARK, width=1.6)
        c.polygon([(cx + 10, cy - 20), (cx + 24 + sway, cy - 25), (cx + 19, cy - 12)], HOOD)
        mantle = [(cx - 15, cy + 16), (cx + 15, cy + 16), (cx + 19, cy + 24), (cx, cy + 27),
                  (cx - 19, cy + 24)]
        c.polygon(mantle, HOOD)
        c.ellipse(cx, cy + 18.5, 2.2, 2.2, GOLD)  # clasp
    elif view == "up":
        c.polygon([(cx - 10, cy - 20), (cx - 24 - sway, cy - 25), (cx - 19, cy - 12)], HOOD)
        c.ellipse(cx, cy + 1, 25, 24, HOOD)
        c.line([(cx - 6, cy - 16), (cx - 3, cy + 14)], fill=HOOD_DARK, width=1.3)
        c.line([(cx + 7, cy - 15), (cx + 4, cy + 14)], fill=HOOD_DARK, width=1.3)
        c.polygon([(cx - 19, cy + 15), (cx + 19, cy + 15), (cx + 20, cy + 24), (cx, cy + 28),
                   (cx - 20, cy + 24)], HOOD)
    else:
        outer = arc_points(cx + 1, cy + 1, 24.5, 24, 235, 470, 24)
        inner = [(cx - 2, cy + 18), (cx - 6, cy + 8), (cx - 9, cy - 4), (cx - 13, cy - 18)]
        c.polygon(outer + inner, HOOD)
        c.line(inner, fill=HOOD_DARK, width=1.5)
        c.polygon([(cx + 14, cy - 18), (cx + 28 + sway, cy - 20), (cx + 22, cy - 8)], HOOD)
        c.polygon([(cx - 8, cy + 16), (cx + 14, cy + 16), (cx + 17, cy + 24), (cx - 9, cy + 24)],
                  HOOD)


# ---------------------------------------------------------------- whole frames


def draw_down(c: PartCanvas, pose: Pose) -> None:
    ox, oy = pose.lean[0], pose.bob + pose.lean[1]
    cx, center = 48 + ox, (48 + ox, 62 + oy)
    sword = sword_for(pose, (cx - 17, 70 + oy + pose.arm * 1.2), HERO["reach"]["down"])
    c.use("shadow")
    draw_shadow(c)
    draw_cape_front(c, cx, oy, pose.sway)
    draw_quiver(c, cx, oy, "down")
    sword_layer(c, pose, sword, center, "back")
    draw_legs_front(c, 48 + ox * 0.3, oy, pose.legs, toward_camera=True)
    draw_torso_front(c, cx, oy)
    draw_robe_front(c, cx, oy)
    draw_vest_front(c, cx, oy)
    draw_arm(c, (cx - 14, 58 + oy), sword[0])
    draw_arm(c, (cx + 14, 58 + oy), pose.off_hand or (cx + 17, 70 + oy - pose.arm * 2.2))
    draw_pauldron(c, cx - 15, 57.5 + oy)
    draw_pauldron(c, cx + 15, 57.5 + oy)
    draw_scarf(c, cx - 10, cx + 10, oy)
    sword_layer(c, pose, sword, center, "body")
    draw_head_front(c, cx, 35 + oy, pose.sway, pose.hurt)
    sword_layer(c, pose, sword, center, "front")


def draw_up(c: PartCanvas, pose: Pose) -> None:
    ox, oy = pose.lean[0], pose.bob + pose.lean[1]
    cx, center = 48 + ox, (48 + ox, 62 + oy)
    sword = sword_for(pose, (cx + 17, 70 + oy + pose.arm * 1.2), HERO["reach"]["up"])
    c.use("shadow")
    draw_shadow(c)
    sword_layer(c, pose, sword, center, "back")
    draw_legs_front(c, 48 + ox * 0.3, oy, pose.legs, toward_camera=False)
    draw_torso_front(c, cx, oy, back=True)
    draw_robe_front(c, cx, oy, back=True)
    draw_vest_front(c, cx, oy, back=True)
    draw_arm(c, (cx + 14, 58 + oy), sword[0])
    draw_arm(c, (cx - 14, 58 + oy), pose.off_hand or (cx - 17, 70 + oy - pose.arm * 2.2))
    draw_cape_back(c, cx, oy, pose.sway)
    draw_quiver(c, cx, oy, "up")
    draw_pauldron(c, cx - 15, 57.5 + oy)
    draw_pauldron(c, cx + 15, 57.5 + oy)
    sword_layer(c, pose, sword, center, "body")
    draw_head_back(c, cx, 35 + oy, pose.sway)
    sword_layer(c, pose, sword, center, "front")


def draw_side(c: PartCanvas, pose: Pose) -> None:
    """Facing left. The "right" frames are these, mirrored."""
    ox, oy = pose.lean[0], pose.bob + pose.lean[1]
    cx, center = 47 + ox, (47 + ox, 62 + oy)
    sword = sword_for(pose, (cx - 6 - pose.arm * 3.5, 70 + oy), HERO["reach"]["side"])
    (near_forward, near_lift), (far_forward, far_lift) = pose.legs
    c.use("shadow")
    draw_shadow(c)
    draw_cape_side(c, cx, oy, pose.sway, pose.wind)
    draw_quiver(c, cx, oy, "side")
    far_hand = pose.off_hand or (cx + 6 + pose.arm * 3.5, 69 + oy)
    draw_arm(c, (cx + 4, 58 + oy), far_hand, far=True)
    sword_layer(c, pose, sword, center, "back")
    base = 48 + ox * 0.3
    draw_leg_side(c, base, oy, far_forward, far_lift, far=True)
    draw_leg_side(c, base, oy, near_forward, near_lift, far=False)
    draw_torso_side(c, cx, oy)
    draw_robe_side(c, cx, oy, pose.wind)
    draw_vest_side(c, cx, oy)
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


def build_hero_parts(hero: str = "warrior") -> dict[tuple[int, int], dict[str, Image.Image]]:
    """Every frame of one class's sheet as parts, keyed by (row, column). Only the
    parts of gear that class can wear are kept."""
    global HERO
    HERO = HEROES[hero]
    requires = requires_for(hero)
    gear = set(HERO["gear"])
    frames = {}
    for row, direction in enumerate(DIRECTIONS):
        for col, pose in enumerate(warrior_poses(direction)):
            parts = draw_frame_parts(direction, pose)
            frames[(row, col)] = {
                part: image for part, image in parts.items()
                if set(requires.get(part, [])) <= gear
            }
    HERO = HEROES["warrior"]
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


def build_parts_script(pieces, hero: str = "warrior") -> str:
    """Text of client/assets/characters/<hero>/<hero>_parts.gd (generated data)."""
    lines = [
        "# gdlint: disable=max-file-lines",
        "extends RefCounted",
        "## Generated by tools/generate_assets.py - do not edit by hand.",
        f"## Where each part of the {hero} is in {hero}_parts.png, the order the parts",
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
    for part, items in requires_for(hero).items():
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


def icon_staff(c: Canvas) -> None:
    draw_staff(c, (18, 33), (33, 12))


def icon_hat(c: Canvas) -> None:  # on a 64 canvas: the brim is wide
    draw_hat(c, 31, 46, 0.0, "down")


def icon_robe(c: Canvas) -> None:
    for side in (-1, 1):
        c.capsule((24 + side * 12, 16), (24 + side * 17, 30), 4.3, ROBE)
        c.ellipse(24 + side * 17, 30, 4.4, 3.8, ROBE_LIGHT)
    draw_robe_front(c, 24, -41)


def icon_bow(c: Canvas) -> None:
    draw_bow(c, (24, 24), (42, 24), 0.6)


def icon_hood(c: Canvas) -> None:  # on a 64 canvas
    c.ellipse(32, 33, 20, 18, HOOD_DARK)
    draw_hood(c, 32, 30, 0.0, "down")


def icon_vest(c: Canvas) -> None:
    draw_vest_front(c, 24, -37)


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
    for name, paint, size in (
        ("sword", icon_sword, 48),
        ("headband", icon_headband, 48),
        ("armor", icon_armor, 48),
        ("gloves", icon_gloves, 48),
        ("boots", icon_boots, 48),
        ("cape", icon_cape, 48),
        ("bag", icon_bag, 48),
        ("staff", icon_staff, 48),
        ("hat", icon_hat, 64),
        ("robe", icon_robe, 48),
        ("bow", icon_bow, 48),
        ("hood", icon_hood, 64),
        ("vest", icon_vest, 48),
    ):
        c = Canvas(size)
        paint(c)
        icons[name] = c.finish(ICON)
    icons["potion"] = build_potion(ICON, shadow=False)
    icons["coin"] = build_coin(ICON, shadow=False)
    icons["book"] = build_book(ICON, shadow=False)
    icons["blue_potion"] = build_potion(ICON, shadow=False, colors=BLUE_POTION)
    icons["jelly"] = build_jelly(ICON, shadow=False)
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
TILE_KINDS = ["grass", "path", "stone", "forest", "cellar", "twilight", "grove", "sand", "crag", "ruin",
              "snow", "ice"]


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


def _blobs(draw, rng, everywhere, size, scale, count, colors, rx_range, ry_range):
    for _ in range(count):
        x, y = rng.uniform(0, size) * scale, rng.uniform(0, size) * scale
        rx, ry = rng.uniform(*rx_range) * scale, rng.uniform(*ry_range) * scale
        color = rng.choice(colors)
        everywhere(lambda ox, oy: draw.ellipse(
            [ox + x - rx, oy + y - ry, ox + x + rx, oy + y + ry], fill=color))


def _tufts(draw, rng, everywhere, size, scale, count, colors):
    for _ in range(count):
        x, y = rng.uniform(0, size) * scale, rng.uniform(0, size) * scale
        h = rng.uniform(4, 7) * scale
        color = rng.choice(colors)
        everywhere(lambda ox, oy: draw.line(
            [(ox + x - 3 * scale, oy + y - h), (ox + x, oy + y), (ox + x + 3 * scale, oy + y - h)],
            fill=color, width=int(1.5 * scale)))


def _paint_twilight(draw, rng, everywhere, size, scale):
    """Twilight Woods: a dim blue-green floor with fallen leaves."""
    _blobs(draw, rng, everywhere, size, scale, 12,
           [(52, 94, 90, 255), (66, 112, 98, 255), (46, 84, 90, 255)], (16, 34), (10, 20))
    _blobs(draw, rng, everywhere, size, scale, 14,
           [(150, 112, 74, 255), (118, 96, 136, 255), (92, 128, 90, 255)], (2.5, 4.0), (1.5, 2.5))
    _tufts(draw, rng, everywhere, size, scale, 34, [(40, 80, 72, 255), (84, 128, 104, 255)])


def _paint_grove(draw, rng, everywhere, size, scale):
    """Elder Grove: deep moss crossed by old roots, with a few glowing specks."""
    _blobs(draw, rng, everywhere, size, scale, 12,
           [(52, 100, 62, 255), (38, 76, 50, 255), (60, 112, 68, 255)], (16, 34), (10, 20))
    for _ in range(4):
        x, y = rng.uniform(0, size) * scale, rng.uniform(0, size) * scale
        phase = rng.uniform(0, 6)
        step = rng.uniform(8, 13) * scale
        points = [(x + k * step, y + math.sin(k * 1.2 + phase) * 5 * scale) for k in range(7)]
        everywhere(lambda ox, oy: draw.line(
            [(ox + px, oy + py) for px, py in points], fill=(86, 64, 44, 255), width=int(3 * scale),
            joint="curve"))
    _tufts(draw, rng, everywhere, size, scale, 20, [(34, 70, 46, 255), (78, 128, 82, 255)])
    _blobs(draw, rng, everywhere, size, scale, 10, [(160, 236, 196, 255)], (1.0, 1.4), (1.0, 1.4))


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


def _paint_sand(draw, rng, everywhere, size, scale):
    """Sunpetal Lake's beaches: warm sand with ripple marks, shells and pebbles."""
    _blobs(draw, rng, everywhere, size, scale, 10,
           [(232, 206, 150, 255), (220, 192, 136, 255), (240, 218, 166, 255)], (16, 32), (8, 16))
    for _ in range(5):  # ripple marks left by the wind
        x, y = rng.uniform(0, size) * scale, rng.uniform(0, size) * scale
        width = rng.uniform(14, 26) * scale
        everywhere(lambda ox, oy: draw.arc(
            [ox + x - width, oy + y - 4 * scale, ox + x + width, oy + y + 4 * scale], 200, 340,
            fill=(204, 174, 120, 255), width=int(1.5 * scale)))
    _blobs(draw, rng, everywhere, size, scale, 8, [(250, 236, 214, 255), (196, 170, 130, 255)],
           (1.4, 2.4), (1.0, 1.8))


def _paint_crag(draw, rng, everywhere, size, scale):
    """Galeclaw Ridge: hard grey-brown rock with cracks, gravel and dry tufts."""
    _blobs(draw, rng, everywhere, size, scale, 9,
           [(150, 138, 124, 255), (132, 122, 110, 255), (162, 152, 138, 255)], (18, 34), (10, 20))
    for _ in range(4):  # cracks
        x, y = rng.uniform(0, size), rng.uniform(0, size)
        points = [(x, y)]
        for _ in range(3):
            x, y = x + rng.uniform(-14, 14), y + rng.uniform(4, 12)
            points.append((x, y))
        scaled = [(px * scale, py * scale) for px, py in points]
        everywhere(lambda ox, oy: draw.line([(ox + px, oy + py) for px, py in scaled],
                                            fill=(96, 86, 78, 255), width=int(1.6 * scale)))
    _blobs(draw, rng, everywhere, size, scale, 14, [(112, 102, 94, 255), (182, 172, 160, 255)],
           (1.6, 3.2), (1.2, 2.4))
    _tufts(draw, rng, everywhere, size, scale, 5, [(150, 150, 96, 255), (124, 128, 82, 255)])


def _paint_ruin(draw, rng, everywhere, size, scale):
    """Moonfall Ruins: old flagstones, worn and cracked, grass in the joints."""
    rows = 4
    step = size / rows
    for row in range(rows):
        shift = step * 0.5 if row % 2 else 0
        for col in range(-1, rows + 1):
            x0 = (col * step + shift + 2) * scale
            y0 = (row * step + 2) * scale
            x1, y1 = x0 + (step - 4) * scale, y0 + (step - 4) * scale
            color = rng.choice([(170, 172, 180, 255), (158, 160, 170, 255), (180, 180, 186, 255),
                                (150, 154, 160, 255)])
            everywhere(lambda ox, oy: draw.rounded_rectangle(
                [ox + x0, oy + y0, ox + x1, oy + y1], radius=3 * scale, fill=color,
                outline=(112, 116, 120, 255), width=scale))
    for _ in range(3):  # cracks
        x, y = rng.uniform(0, size), rng.uniform(0, size)
        points = [(x, y), (x + rng.uniform(-10, 10), y + rng.uniform(5, 12)),
                  (x + rng.uniform(-14, 14), y + rng.uniform(12, 20))]
        scaled = [(px * scale, py * scale) for px, py in points]
        everywhere(lambda ox, oy: draw.line([(ox + px, oy + py) for px, py in scaled],
                                            fill=(110, 112, 118, 255), width=int(1.4 * scale)))
    _blobs(draw, rng, everywhere, size, scale, 6, [(108, 150, 90, 255), (92, 134, 80, 255)], (4, 9), (2, 4))
    _tufts(draw, rng, everywhere, size, scale, 7, [(88, 140, 78, 255), (120, 170, 96, 255)])


def _paint_snow(draw, rng, everywhere, size, scale):
    """Frostfang Hollow: deep, soft snow with drifts, footprints of the wind and sparkles."""
    _blobs(draw, rng, everywhere, size, scale, 10,
           [(236, 242, 250, 255), (224, 232, 246, 255), (244, 248, 255, 255)], (18, 36), (10, 20))
    _blobs(draw, rng, everywhere, size, scale, 6, [(206, 218, 238, 255)], (10, 22), (3, 6))  # drift shadows
    _blobs(draw, rng, everywhere, size, scale, 14, [(255, 255, 255, 255), (196, 226, 255, 255)],
           (0.8, 1.6), (0.8, 1.6))


def _paint_ice(draw, rng, everywhere, size, scale):
    """Frostfang Hollow: smooth blue ice with white cracks and frosted patches."""
    _blobs(draw, rng, everywhere, size, scale, 8,
           [(160, 204, 232, 255), (148, 196, 228, 255), (172, 214, 238, 255)], (20, 40), (12, 24))
    for _ in range(4):
        x, y = rng.uniform(0, size), rng.uniform(0, size)
        points = [(x, y)]
        for _ in range(3):
            x, y = x + rng.uniform(-16, 16), y + rng.uniform(-12, 12)
            points.append((x, y))
        scaled = [(px * scale, py * scale) for px, py in points]
        everywhere(lambda ox, oy: draw.line([(ox + px, oy + py) for px, py in scaled],
                                            fill=(236, 248, 255, 255), width=int(1.3 * scale)))
    _blobs(draw, rng, everywhere, size, scale, 5, [(214, 236, 250, 255)], (6, 12), (3, 6))


def build_tiles() -> Image.Image:
    """tiles.png: a row of 128 px ground tiles, TILE_KINDS order, two variants each."""
    makers = {
        "grass": lambda seed: build_grass_tile(TILE, seed),
        "path": lambda seed: _seamless(TILE, (196, 160, 110, 255), _paint_path, seed),
        "stone": lambda seed: _seamless(TILE, (160, 154, 170, 255), _paint_stone, seed),
        "forest": lambda seed: _seamless(TILE, (78, 142, 82, 255), _paint_forest, seed),
        "cellar": lambda seed: _seamless(TILE, (60, 54, 72, 255), _paint_cellar, seed),
        "twilight": lambda seed: _seamless(TILE, (58, 102, 92, 255), _paint_twilight, seed),
        "grove": lambda seed: _seamless(TILE, (46, 88, 60, 255), _paint_grove, seed),
        "sand": lambda seed: _seamless(TILE, (228, 200, 144, 255), _paint_sand, seed),
        "crag": lambda seed: _seamless(TILE, (142, 132, 120, 255), _paint_crag, seed),
        "ruin": lambda seed: _seamless(TILE, (122, 128, 128, 255), _paint_ruin, seed),
        "snow": lambda seed: _seamless(TILE, (232, 238, 248, 255), _paint_snow, seed),
        "ice": lambda seed: _seamless(TILE, (156, 200, 230, 255), _paint_ice, seed),
    }
    sheet = Image.new("RGBA", (TILE * 2 * len(TILE_KINDS), TILE), (0, 0, 0, 0))
    for i, kind in enumerate(TILE_KINDS):
        first = makers[kind](11 + i)
        sheet.paste(first, (i * 2 * TILE, 0))
        sheet.paste(_soft_variant(first, makers[kind](11 + 31 + i)), ((i * 2 + 1) * TILE, 0))
    return sheet


def _soft_variant(base: Image.Image, other: Image.Image) -> Image.Image:
    """A ground kind's second variant: the first one at its edges and the other
    in a soft round patch in the middle. Cells of the two variants side by
    side then meet with no square seam, so the ground does not look like a grid."""
    size = base.width
    mask = Image.new("L", (size, size), 0)
    pixels = mask.load()
    half = size / 2.0
    for y in range(size):
        for x in range(size):
            t = min(1.0, max(0.0, (0.88 - math.hypot(x + 0.5 - half, y + 0.5 - half) / half) / 0.33))
            pixels[x, y] = int(255 * t * t * (3 - 2 * t))
    return Image.composite(other, base, mask)


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


SHROOM_CAP = (150, 92, 206, 255)
SHROOM_SPOT = (226, 200, 252, 255)
SHROOM_STEM = (246, 232, 206, 255)
SPORE = (176, 232, 120, 255)
# (animation, cap half-width, cap half-height, stem height, face, spores)
SHROOM_POSES = [
    ("idle", 21, 13, 18, "normal", 0),
    ("idle", 22, 12, 17, "normal", 0),
    ("attack", 25, 15, 19, "angry", 0),
    ("attack", 19, 10, 16, "angry", 5),
    ("die", 22, 12, 12, "dead", 0),
    ("die", 24, 9, 7, "dead", 3),
    ("die", 0, 0, 0, "none", 7),
]


def draw_shroom(cap_rx: float, cap_ry: float, stem: float, face: str, spores: int) -> Image.Image:
    """One Spore Shroom frame: a spotted cap on a stem with a face; spores when it shoots."""
    c = Canvas(SLIME_FRAME)
    cx, feet = 32, SLIME_FEET_Y
    c.ellipse(cx, feet + 1, 15, 4, SHADOW, outline=False)
    rng = random.Random(spores * 7 + int(cap_rx))
    if cap_rx == 0:  # only a cloud of spores is left
        for _ in range(spores):
            c.ellipse(cx + rng.uniform(-14, 14), feet - rng.uniform(2, 16), 2.4, 2.4, SPORE)
        return c.finish()
    top = feet - stem
    c.rect(cx - 9, top - 2, cx + 9, feet, SHROOM_STEM, radius=5)
    eye_y = top + stem * 0.55
    for side in (-1, 1):
        ex = cx + side * 4.5
        if face == "dead":
            c.line([(ex - 1.8, eye_y - 1.8), (ex + 1.8, eye_y + 1.8)], width=1.2)
            c.line([(ex - 1.8, eye_y + 1.8), (ex + 1.8, eye_y - 1.8)], width=1.2)
            continue
        c.ellipse(ex, eye_y, 1.9, 2.5, EYE, outline=False)
        c.ellipse(ex - 0.6, eye_y - 1.1, 0.8, 0.8, WHITE, outline=False)
        if face == "angry":
            c.line([(ex + side * 3, eye_y - 4.5), (ex - side * 1.5, eye_y - 3)], width=1.2)
    if face == "normal":
        c.line(arc_points(cx, eye_y + 3.5, 1.8, 1.2, 20, 160, 6), width=1.0)
    elif face == "angry":
        c.line(arc_points(cx, eye_y + 4.5, 1.8, 1.0, 200, 340, 6), width=1.0)
    cap_y = top - cap_ry * 0.6
    c.ellipse(cx, cap_y, cap_rx, cap_ry, SHROOM_CAP)
    for dx, dy, r in ((-0.45, -0.3, 3.4), (0.35, -0.45, 2.6), (0.15, 0.2, 2.2), (-0.1, -0.7, 1.8)):
        c.ellipse(cx + cap_rx * dx, cap_y + cap_ry * dy, r, r * 0.8, SHROOM_SPOT, outline=False)
    for _ in range(spores):
        c.ellipse(cx + rng.uniform(-18, 18), cap_y - cap_ry - rng.uniform(1, 9), 2.0, 2.0, SPORE)
    return c.finish()


def build_crown(out_size: int = 64) -> Image.Image:
    """The Slime King's crown: gold points with gems, worn on top of the slime."""
    c = Canvas(32)
    points = [(5, 22), (5, 10), (10.5, 16), (16, 7), (21.5, 16), (27, 10), (27, 22)]
    c.polygon(points, GOLD)
    c.rect(5, 19, 27, 24, (232, 176, 60, 255), radius=1)
    for x, y, color in ((5, 10, GEM), (16, 7, (110, 200, 255, 255)), (27, 10, GEM)):
        c.ellipse(x, y, 2.2, 2.2, color)
    c.ellipse(16, 21.5, 2.2, 1.6, (110, 230, 140, 255))
    c.ellipse(10, 14, 1.2, 1.8, (255, 236, 160, 255), outline=False)
    return c.finish(out_size)


def build_shroom_sheet() -> Image.Image:
    sheet = Image.new("RGBA", (SLIME_FRAME * len(SHROOM_POSES), SLIME_FRAME), (0, 0, 0, 0))
    for col, (_, rx, ry, stem, face, spores) in enumerate(SHROOM_POSES):
        sheet.paste(draw_shroom(rx, ry, stem, face, spores), (col * SLIME_FRAME, 0))
    return sheet


# --- the deep forest: Twilight Woods and Elder Grove

BOAR = (138, 92, 64, 255)
BOAR_DARK = (100, 66, 46, 255)
SNOUT = (236, 168, 150, 255)
TUSK = (250, 244, 226, 255)
BRAMBLE = (74, 124, 70, 255)
THORN = (210, 228, 170, 255)
DUST = (196, 180, 150, 180)
# (animation, body half-width, half-height, face, dust)
BOAR_POSES = [
    ("idle", 21, 14, "normal", 0),
    ("idle", 21.6, 13.3, "normal", 0),
    ("attack", 23, 12.6, "angry", 3),
    ("attack", 24, 12, "angry", 6),
    ("die", 22, 12, "dead", 0),
    ("die", 23, 8.5, "dead", 2),
    ("die", 0, 0, "none", 6),
]


def _eyes(c, cx, eye_y, gap, face, size=1.0, color=EYE):
    """Two eyes as the slimes have them: shut with crosses when dead, brows when angry."""
    for side in (-1, 1):
        ex = cx + side * gap
        if face == "dead":
            c.line([(ex - 2 * size, eye_y - 2 * size), (ex + 2 * size, eye_y + 2 * size)], width=1.3)
            c.line([(ex - 2 * size, eye_y + 2 * size), (ex + 2 * size, eye_y - 2 * size)], width=1.3)
            continue
        c.ellipse(ex, eye_y, 2.2 * size, 2.8 * size, color, outline=False)
        c.ellipse(ex - 0.7 * size, eye_y - 1.2 * size, 0.9 * size, 0.9 * size, WHITE, outline=False)
        if face == "angry":
            c.line([(ex + side * 3.6 * size, eye_y - 5 * size), (ex - side * 1.6 * size, eye_y - 3.2 * size)],
                   width=1.3)


def draw_boar(rx: float, ry: float, face: str, dust: int) -> Image.Image:
    """Bramble Boar: a round boar with a thorny bramble mane, a pink snout and tusks."""
    c = Canvas(SLIME_FRAME)
    cx, feet = 32, SLIME_FEET_Y
    c.ellipse(cx, feet + 1, 20, 4, SHADOW, outline=False)
    rng = random.Random(dust * 5 + int(rx))
    if rx == 0:  # only bramble leaves are left
        for _ in range(dust):
            c.ellipse(cx + rng.uniform(-16, 16), feet - rng.uniform(1, 12), 2.8, 1.8, BRAMBLE)
        return c.finish()
    for i in range(dust):  # dust kicked up behind a charge
        side = -1 if i % 2 else 1
        c.ellipse(cx + side * (rx + 3 + (i // 2) * 4), feet - 3 - (i % 3) * 2, 3.2, 2.4, DUST, outline=False)
    cy = feet - ry - 4
    for side in (-1, 1):
        for leg in (11, 4):
            c.rect(cx + side * leg - 3, feet - 8, cx + side * leg + 3, feet, BOAR_DARK, radius=2)
    for k in range(6):  # the bramble mane over the back
        angle = math.radians(196 + k * 30)
        c.ellipse(cx + math.cos(angle) * rx * 0.78, cy + math.sin(angle) * ry * 0.95, 5.2, 4.2, BRAMBLE)
    c.ellipse(cx, cy, rx, ry, BOAR)
    for k in range(6):  # thorns out of the mane
        angle = math.radians(198 + k * 30)
        tx, ty = cx + math.cos(angle) * (rx * 0.78 + 5), cy + math.sin(angle) * (ry * 0.95 + 5)
        tip = (tx + math.cos(angle) * 3.4, ty + math.sin(angle) * 3.4)
        c.polygon([(tx - 1.6, ty), (tx + 1.6, ty), tip], THORN)
    for side in (-1, 1):  # ears
        ex = cx + side * rx * 0.58
        c.polygon([(ex - 4, cy - ry * 0.55), (ex + 4, cy - ry * 0.55), (ex + side * 2.5, cy - ry - 3)], BOAR_DARK)
    _eyes(c, cx, cy - 3, 7, face)
    if face == "dead":
        c.ellipse(cx, cy + 5, 7, 4.5, SNOUT)
        return c.finish()
    for side in (-1, 1):  # tusks
        c.polygon([(cx + side * 5, cy + 7), (cx + side * 8, cy + 6), (cx + side * 10, cy + 0.5)], TUSK)
    c.ellipse(cx, cy + 5, 7, 5, SNOUT)
    for side in (-1, 1):
        c.ellipse(cx + side * 2.6, cy + 5, 1.2, 1.8, BOAR_DARK, outline=False)
    return c.finish()


WISP_HALO = (255, 236, 160, 70)
WISP_BODY = (255, 230, 140, 255)
WISP_CORE = (255, 252, 230, 255)
WISP_SPARK = (255, 214, 120, 255)
# (animation, size, sway of the tip, face, sparks)
WISP_POSES = [
    ("idle", 1.0, -2.5, "normal", 0),
    ("idle", 1.0, 2.5, "normal", 0),
    ("attack", 1.14, 0, "angry", 3),
    ("attack", 1.06, -1, "angry", 6),
    ("die", 0.86, 0, "dead", 2),
    ("die", 0.62, 0, "dead", 5),
    ("die", 0.0, 0, "none", 8),
]


def draw_wisp(size: float, sway: float, face: str, sparks: int) -> Image.Image:
    """Lantern Wisp: a little floating flame with a soft glow round it."""
    c = Canvas(SLIME_FRAME)
    cx, cy = 32, 32
    c.ellipse(cx, SLIME_FEET_Y + 1, 9, 2.6, SHADOW, outline=False)
    rng = random.Random(sparks * 3 + 1)
    for _ in range(sparks):
        sx, sy = cx + rng.uniform(-20, 20), cy + rng.uniform(-22, 16)
        c.polygon([(sx, sy - 2.4), (sx + 1.6, sy), (sx, sy + 2.4), (sx - 1.6, sy)], WISP_SPARK, outline=False)
    if size == 0:
        return c.finish()
    r = 11.5 * size
    c.ellipse(cx, cy, 21 * size, 21 * size, WISP_HALO, outline=False)
    body = arc_points(cx, cy + 3, r, r * 0.95, -25, 205, 18) + [(cx + sway, cy - r * 1.75)]
    c.polygon(body, WISP_BODY)
    c.ellipse(cx, cy + 4, r * 0.55, r * 0.5, WISP_CORE, outline=False)
    _eyes(c, cx, cy + 2, 4.6 * size, face, 0.9 * size)
    return c.finish()


BARK = (138, 98, 68, 255)
BARK_DARK = (98, 68, 46, 255)
SPROUT = (116, 196, 92, 255)
ROOT_EYE = (176, 255, 150, 255)
# (animation, height, arms: 1 up / 0 down / -1 striking, face, wood chips)
ROOTLING_POSES = [
    ("idle", 30, 0, "normal", 0),
    ("idle", 29, 0, "normal", 0),
    ("attack", 31, 1, "angry", 0),
    ("attack", 27, -1, "angry", 3),
    ("die", 24, 0, "dead", 0),
    ("die", 15, 0, "dead", 4),
    ("die", 0, 0, "none", 7),
]


def draw_rootling(height: float, arms: int, face: str, chips: int) -> Image.Image:
    """Rootling: a walking stump on root legs, with a sprout on its head and glowing eyes."""
    c = Canvas(SLIME_FRAME)
    cx, feet = 32, SLIME_FEET_Y
    c.ellipse(cx, feet + 1, 15, 3.6, SHADOW, outline=False)
    rng = random.Random(chips * 7 + int(height))
    for _ in range(chips):
        x, y = cx + rng.uniform(-16, 16), feet - rng.uniform(1, 10)
        c.rect(x - 2.2, y - 1.4, x + 2.2, y + 1.4, BARK, radius=0.8)
    if height == 0:
        return c.finish()
    top = feet - height
    for dx, end in ((-7, -14), (-2, -6), (3, 6), (8, 14)):  # root legs
        c.line([(cx + dx, feet - 7), (cx + dx + (end - dx) * 0.5, feet - 2), (cx + end, feet)], fill=BARK_DARK,
               width=2.6)
    for side in (-1, 1):  # root arms
        shoulder = (cx + side * 10, top + 13)
        if arms == 1:
            hand = (cx + side * 17, top + 2)
        elif arms == -1:
            hand = (cx + side * 19, top + 20)
        else:
            hand = (cx + side * 15, top + 19)
        c.line([shoulder, hand], fill=BARK_DARK, width=3.2)
    c.rect(cx - 11, top, cx + 11, feet - 5, BARK, radius=7)
    for x in (cx - 5, cx + 4):
        c.line([(x, top + 5), (x + 1, feet - 9)], fill=BARK_DARK, width=1.2)
    c.ellipse(cx, top + 1.5, 10, 3.2, (176, 134, 96, 255))  # the cut top with rings
    c.ellipse(cx, top + 1.5, 5, 1.6, (150, 110, 78, 255), outline=False)
    if face != "dead":
        c.line([(cx + 2, top), (cx + 3, top - 7)], width=1.4)
        c.polygon([(cx + 3, top - 6), (cx + 11, top - 11), (cx + 10, top - 4)], SPROUT)
        c.polygon([(cx + 3, top - 6), (cx - 4, top - 10), (cx - 3, top - 3)], SPROUT)
    _eyes(c, cx, top + 11, 4.6, face, 0.95, ROOT_EYE if face != "dead" else EYE)
    if face == "angry":
        c.line(arc_points(cx, top + 18, 2.4, 1.4, 200, 340, 8), width=1.2)
    elif face == "normal":
        c.line(arc_points(cx, top + 16, 2.2, 1.4, 20, 160, 8), width=1.1)
    return c.finish()


GOLEM_STONE = (134, 140, 134, 255)
GOLEM_DARK = (100, 106, 102, 255)
GOLEM_MOSS = (96, 156, 82, 255)
GOLEM_MOSS_LIGHT = (140, 196, 106, 255)
GOLEM_EYE = (140, 255, 226, 255)
# (animation, bob down, arms: 1 up / 0 down / -1 slam, face, loose rocks)
GOLEM_POSES = [
    ("idle", 0, 0, "normal", 0),
    ("idle", 1, 0, "normal", 0),
    ("attack", -2, 1, "angry", 0),
    ("attack", 2, -1, "angry", 4),
    ("die", 3, -1, "dead", 3),
    ("die", 8, -1, "dead", 6),
    ("die", 0, 0, "none", 9),
]


def draw_golem(bob: float, arms: int, face: str, rocks: int) -> Image.Image:
    """Moss Golem: a chunky stone body with moss on the head and shoulders, glowing eyes."""
    c = Canvas(SLIME_FRAME)
    cx, feet = 32, SLIME_FEET_Y
    c.ellipse(cx, feet + 1, 20, 4, SHADOW, outline=False)
    rng = random.Random(rocks * 11 + int(bob))
    for _ in range(rocks):
        c.ellipse(cx + rng.uniform(-20, 20), feet - rng.uniform(0, 5), rng.uniform(2, 3.6), 2.2, GOLEM_DARK)
    if face == "none":
        return c.finish()
    top = feet - 36 + bob
    for side in (-1, 1):  # legs
        c.rect(cx + side * 9 - 5, feet - 9, cx + side * 9 + 5, feet, GOLEM_DARK, radius=2)
    for side in (-1, 1):  # arms
        if arms == 1:
            box = (cx + side * 17 - 5, top - 6, cx + side * 17 + 5, top + 12)
        elif arms == -1:
            box = (cx + side * 21 - 6, top + 16, cx + side * 21 + 6, top + 30)
        else:
            box = (cx + side * 19 - 5, top + 9, cx + side * 19 + 5, top + 26)
        c.rect(min(box[0], box[2]), box[1], max(box[0], box[2]), box[3], GOLEM_STONE, radius=4)
    c.rect(cx - 15, top + 6, cx + 15, feet - 6, GOLEM_STONE, radius=7)
    c.rect(cx - 10, top - 6, cx + 10, top + 10, GOLEM_STONE, radius=5)
    for x, y, rx, ry in ((-6, -5, 6, 3.2), (5, -6, 5, 2.8), (-12, 7, 5, 3), (11, 8, 5.5, 3.2), (0, 20, 4, 2.4)):
        c.ellipse(cx + x, top + y, rx, ry, GOLEM_MOSS, outline=False)
        c.ellipse(cx + x - rx * 0.3, top + y - ry * 0.3, rx * 0.4, ry * 0.4, GOLEM_MOSS_LIGHT, outline=False)
    eye_y = top + 3
    for side in (-1, 1):
        ex = cx + side * 4.5
        if face == "dead":
            c.line([(ex - 2, eye_y - 1), (ex + 2, eye_y + 1)], width=1.3)
            continue
        c.rect(ex - 2.2, eye_y - 1.6, ex + 2.2, eye_y + 1.6, GOLEM_EYE, radius=1, outline=False)
        if face == "angry":
            c.line([(ex + side * 3.6, eye_y - 4.4), (ex - side * 2, eye_y - 2.6)], width=1.4)
    if face == "dead":
        c.line([(cx - 8, top + 12), (cx - 2, top + 20), (cx - 5, top + 28)], width=1.2)
        c.line([(cx + 6, top + 10), (cx + 2, top + 18)], width=1.2)
    return c.finish()


TRUNK = (114, 80, 54, 255)
TRUNK_DARK = (82, 56, 38, 255)
CROWN = (56, 116, 64, 255)
CROWN_LIGHT = (94, 158, 82, 255)
TREANT_EYE = (255, 204, 96, 255)
BEARD = (128, 170, 100, 255)
FALLING_LEAF = (110, 170, 84, 255)
# (animation, sway of the crown, branches: 1 up / 0 down / -1 slam, face, falling leaves)
TREANT_POSES = [
    ("idle", -1.2, 0, "normal", 0),
    ("idle", 1.2, 0, "normal", 0),
    ("attack", 0, 1, "angry", 0),
    ("attack", 0, -1, "angry", 4),
    ("die", 2, -1, "dead", 3),
    ("die", 5, -1, "dead", 6),
    ("die", 0, 0, "none", 9),
]


def draw_treant(sway: float, branches: int, face: str, leaves: int) -> Image.Image:
    """Elder Treant: an old tree with a face, branch arms, a mossy beard and a leafy crown."""
    c = Canvas(SLIME_FRAME)
    cx, feet = 32, SLIME_FEET_Y
    c.ellipse(cx, feet + 1, 21, 4, SHADOW, outline=False)
    rng = random.Random(leaves * 13 + 5)
    if face == "none":  # a fallen log and leaves
        c.rect(cx - 20, feet - 8, cx + 20, feet - 1, TRUNK, radius=4)
        c.ellipse(cx + 20, feet - 4.5, 3, 3.5, (176, 134, 96, 255))
    for _ in range(leaves):
        x, y = cx + rng.uniform(-24, 24), feet - rng.uniform(2, 30)
        c.ellipse(x, y, 2.4, 1.6, FALLING_LEAF)
    if face == "none":
        return c.finish()
    for dx in (-13, -6, 6, 13):  # roots
        c.polygon([(cx + dx * 0.6 - 3, feet - 8), (cx + dx * 0.6 + 3, feet - 8), (cx + dx, feet)], TRUNK_DARK)
    for side in (-1, 1):  # branch arms with leafy ends
        shoulder = (cx + side * 8, feet - 22)
        if branches == 1:
            hand = (cx + side * 22, feet - 40)
        elif branches == -1:
            hand = (cx + side * 25, feet - 10)
        else:
            hand = (cx + side * 22, feet - 22)
        c.line([shoulder, hand], fill=TRUNK_DARK, width=3.4)
        c.ellipse(hand[0], hand[1], 4.4, 3.6, CROWN)
    c.rect(cx - 10, feet - 32, cx + 10, feet - 4, TRUNK, radius=4)
    for x in (cx - 6, cx + 5):
        c.line([(x, feet - 28), (x - 1, feet - 8)], fill=TRUNK_DARK, width=1.1)
    for x, y, rx, ry, color in ((-11, -38, 12, 9, CROWN), (11, -38, 12, 9, CROWN), (0, -45, 15, 10, CROWN),
                                (-5, -46, 6, 3.6, CROWN_LIGHT), (8, -40, 5, 3, CROWN_LIGHT)):
        c.ellipse(cx + x + sway, feet + y, rx, ry, color, outline=color is CROWN)
    eye_y = feet - 23
    for side in (-1, 1):
        ex = cx + side * 4.5
        if face == "dead":
            c.line([(ex - 2, eye_y - 2), (ex + 2, eye_y + 2)], width=1.3)
            c.line([(ex - 2, eye_y + 2), (ex + 2, eye_y - 2)], width=1.3)
            continue
        c.ellipse(ex, eye_y, 2.4, 2.0, TREANT_EYE, outline=False)
        brow_in = 3.2 if face == "angry" else 1.6
        c.line([(ex + side * 3.4, eye_y - 3.6 - (1.2 if face == "angry" else 0)), (ex - side * 2.4, eye_y - brow_in)],
               width=1.6)
    c.polygon([(cx - 6, feet - 17), (cx + 6, feet - 17), (cx + 3, feet - 9), (cx, feet - 11), (cx - 3, feet - 9)],
              BEARD)
    c.line([(cx - 3, feet - 18.5), (cx + 3, feet - 18.5)], width=1.3)
    return c.finish()


# Monster folder -> (drawing, poses). Each gets <name>.png and <name>_frames.tres.
SHELL = (104, 132, 74, 255)
SHELL_DARK = (74, 98, 56, 255)
SHELL_RIM = (196, 176, 112, 255)
TURTLE_SKIN = (126, 186, 150, 255)
TURTLE_SKIN_DARK = (92, 146, 116, 255)
BEAK = (244, 204, 96, 255)
# (animation, how far the head is out 0..1, lunge 0..1, face, shell bits when broken)
TURTLE_POSES = [
    ("idle", 1.0, 0.0, "normal", 0),
    ("idle", 0.92, 0.0, "normal", 0),
    ("attack", 1.0, 0.6, "angry", 0),
    ("attack", 1.0, 1.0, "angry", 0),
    ("die", 0.7, 0.0, "dead", 0),
    ("die", 0.4, 0.0, "dead", 3),
    ("die", 0.0, 0.0, "none", 6),
    ("shell", 0.0, 0.0, "hidden", 0),
    ("shell", 0.0, 0.0, "peek", 0),
]


def draw_turtle(head: float, lunge: float, face: str, bits: int) -> Image.Image:
    """Snapjaw Turtle: a domed, plated shell, stubby legs and a beaked head that
    snaps forward. Hidden, only the shell shows (with eyes peeking out)."""
    c = Canvas(SLIME_FRAME)
    cx, feet = 32, SLIME_FEET_Y
    c.ellipse(cx, feet + 1, 22, 4.5, SHADOW, outline=False)
    if face == "none":  # only bits of shell are left
        rng = random.Random(bits)
        for _ in range(bits):
            c.ellipse(cx + rng.uniform(-18, 18), feet - rng.uniform(2, 9), 3.4, 2.4, SHELL)
        return c.finish()
    hidden = face in ("hidden", "peek")
    shell_y = feet - (10 if hidden else 12)
    if not hidden:
        for side in (-1, 1):  # legs
            c.ellipse(cx + side * 17, feet - 4, 6, 4.5, TURTLE_SKIN_DARK)
    c.ellipse(cx, shell_y + 6, 24, 7, SHELL_RIM)  # the rim under the dome
    c.ellipse(cx, shell_y, 22, 17, SHELL)
    plates = [(0, -8, 6.5, 5), (-11, -2, 5.5, 4.5), (11, -2, 5.5, 4.5), (-6, 6, 5, 3.5), (6, 6, 5, 3.5)]
    for dx, dy, rx, ry in plates:
        c.ellipse(cx + dx, shell_y + dy, rx, ry, SHELL_DARK, outline=False)
    c.ellipse(cx - 7, shell_y - 11, 5, 2.4, (150, 178, 112, 255), outline=False)  # shine
    if hidden:
        c.ellipse(cx, shell_y + 6, 7, 3.6, (40, 34, 30, 255), outline=False)  # the dark opening
        if face == "peek":
            for side in (-1, 1):
                c.ellipse(cx + side * 2.6, shell_y + 6, 1.2, 1.2, (255, 236, 150, 255), outline=False)
        return c.finish()
    hx, hy = cx, feet - 8 + lunge * 3
    radius = 7 + head * 2 + lunge * 1.5
    c.ellipse(hx, hy - head * 2, radius, radius * 0.85, TURTLE_SKIN)
    if bits:
        rng = random.Random(bits)
        for _ in range(bits):
            c.ellipse(cx + rng.uniform(-24, 24), feet - rng.uniform(0, 6), 2.2, 1.6, SHELL)
    _eyes(c, hx, hy - head * 2 - 2.5, 4.2, face, 0.9)
    open_mouth = lunge * 3.0
    c.polygon([(hx - 4, hy + 1), (hx + 4, hy + 1), (hx, hy + 5 - open_mouth * 0.3)], BEAK)
    if open_mouth > 0.5:
        c.polygon([(hx - 3.4, hy + 2 + open_mouth), (hx + 3.4, hy + 2 + open_mouth),
                   (hx, hy + 6 + open_mouth)], BEAK)
    return c.finish()


FROG = (108, 182, 96, 255)
FROG_DARK = (78, 140, 72, 255)
FROG_BELLY = (230, 238, 176, 255)
FROG_SPOT = (70, 128, 66, 255)
FROG_EYE = (250, 214, 92, 255)
# (animation, body squash: half-width, half-height, face, legs out 0..1)
FROG_POSES = [
    ("idle", 18, 13, "normal", 0.0),
    ("idle", 19, 12, "puff", 0.0),
    ("attack", 21, 10, "angry", 0.0),
    ("attack", 22, 9, "angry", 0.0),
    ("die", 19, 9, "dead", 0.0),
    ("die", 20, 6, "dead", 0.3),
    ("die", 0, 0, "none", 0.0),
    ("leap", 14, 17, "angry", 1.0),
]


def draw_frog(rx: float, ry: float, face: str, legs: float) -> Image.Image:
    """Marsh Frog: a squat green frog with a pale belly, spots and big golden
    eyes on top. It crouches flat before a leap and stretches out in the air."""
    c = Canvas(SLIME_FRAME)
    cx, feet = 32, SLIME_FEET_Y
    c.ellipse(cx, feet + 1, 18, 4, SHADOW, outline=False)
    if face == "none":
        for k in range(4):
            c.ellipse(cx - 12 + k * 8, feet - 3 - (k % 2) * 3, 2.6, 2.0, FROG)
        return c.finish()
    cy = feet - ry - 2
    for side in (-1, 1):  # back legs: folded, or stretched in a leap
        if legs > 0.5:
            c.polygon([(cx + side * 8, cy + 4), (cx + side * 20, feet + 2), (cx + side * 14, feet + 4)], FROG_DARK)
        else:
            c.ellipse(cx + side * (rx - 3), feet - 5, 7, 5, FROG_DARK)
        c.ellipse(cx + side * 8, feet - 2, 4, 2.4, FROG_DARK)  # front feet
    c.ellipse(cx, cy, rx, ry, FROG)
    c.ellipse(cx, cy + ry * 0.35, rx * 0.62, ry * 0.5, FROG_BELLY, outline=False)
    for dx, dy in ((-9, -4), (8, -6), (11, 2)):
        c.ellipse(cx + dx * rx / 18, cy + dy * ry / 13, 2.6, 2.0, FROG_SPOT, outline=False)
    if face == "puff":  # the throat swells
        c.ellipse(cx, cy + ry * 0.55, 7, 5, (246, 246, 206, 255))
    for side in (-1, 1):  # eyes up on top
        ex, ey = cx + side * rx * 0.48, cy - ry * 0.75
        c.ellipse(ex, ey, 6, 5.5, FROG)
        if face == "dead":
            c.line([(ex - 2.4, ey - 2.4), (ex + 2.4, ey + 2.4)], width=1.3)
            c.line([(ex - 2.4, ey + 2.4), (ex + 2.4, ey - 2.4)], width=1.3)
            continue
        c.ellipse(ex, ey, 4, 3.8, FROG_EYE, outline=False)
        c.ellipse(ex, ey + 0.4, 1.4, 2.8, EYE, outline=False)
        if face == "angry":
            c.line([(ex - side * 4.5, ey - 5.5), (ex + side * 2.5, ey - 3.5)], width=1.3)
    mouth = cy + ry * 0.1
    c.line(arc_points(cx, mouth - 2, rx * 0.55, 3, 20, 160, 10), width=1.3)
    return c.finish()


BEETLE_SHELL = (128, 122, 114, 255)
BEETLE_SHELL_DARK = (98, 92, 86, 255)
BEETLE_SHELL_LIGHT = (170, 164, 152, 255)
BEETLE_BODY = (72, 62, 58, 255)
BEETLE_GEM = (126, 214, 232, 255)
# (animation, jaws open 0..1, face, rolled up: 0, or roll frame 1 / 2, bits of shell)
BEETLE_POSES = [
    ("idle", 0.0, "normal", 0, 0),
    ("idle", 0.25, "normal", 0, 0),
    ("attack", 0.8, "angry", 0, 0),
    ("attack", 1.0, "angry", 0, 0),
    ("die", 0.0, "dead", 0, 0),
    ("die", 0.0, "dead", 0, 3),
    ("die", 0.0, "none", 0, 6),
    ("roll", 0.0, "none", 1, 0),
    ("roll", 0.0, "none", 2, 0),
]


def draw_beetle(jaws: float, face: str, rolled: int, bits: int) -> Image.Image:
    """Rock Beetle: a stony shell split down the back with glinting crystals, six
    little legs and pincer jaws. It curls into a striped ball to roll."""
    c = Canvas(SLIME_FRAME)
    cx, feet = 32, SLIME_FEET_Y
    c.ellipse(cx, feet + 1, 19, 4.5, SHADOW, outline=False)
    if rolled:
        cy = feet - 15
        c.ellipse(cx, cy, 16, 15, BEETLE_SHELL)
        shift = 0 if rolled == 1 else 5  # the bands move between the two frames
        for k in range(-2, 3):
            y = cy + k * 6 + shift - 2.5
            if abs(y - cy) < 13:
                half = (15 ** 2 - (y - cy) ** 2) ** 0.5
                c.line([(cx - half + 1.5, y), (cx + half - 1.5, y)], fill=BEETLE_SHELL_DARK, width=1.6)
        c.ellipse(cx - 5, cy - 8, 4.5, 2.4, BEETLE_SHELL_LIGHT, outline=False)
        c.ellipse(cx + 6, cy + 4 - shift, 2.2, 2.2, BEETLE_GEM, outline=False)
        return c.finish()
    if face == "none":
        rng = random.Random(bits)
        for _ in range(bits):
            c.ellipse(cx + rng.uniform(-18, 18), feet - rng.uniform(1, 8), 3.4, 2.6, BEETLE_SHELL)
        return c.finish()
    cy = feet - 14
    for side in (-1, 1):
        for k, dy in enumerate((-5, 0, 5)):
            c.line([(cx + side * 13, cy + dy), (cx + side * (21 + k), cy + dy + 2), (cx + side * (23 + k), cy + dy + 7)],
                   fill=BEETLE_BODY, width=2.6)
    c.ellipse(cx, cy + 2, 18, 13, BEETLE_BODY)
    c.ellipse(cx, cy - 1, 19, 14, BEETLE_SHELL)
    c.line([(cx, cy - 14), (cx, cy + 12)], width=1.4)
    for dx, dy, r in ((-9, -5, 3.0), (8, -2, 2.4), (-5, 6, 2.0), (10, 7, 2.2)):
        c.ellipse(cx + dx, cy + dy, r, r * 0.8, BEETLE_SHELL_DARK, outline=False)
    for dx, dy in ((-11, 1), (6, -8)):
        c.polygon([(cx + dx, cy + dy - 4), (cx + dx + 3, cy + dy), (cx + dx, cy + dy + 3.5),
                   (cx + dx - 3, cy + dy)], BEETLE_GEM)
    c.ellipse(cx - 7, cy - 9, 5, 2.4, BEETLE_SHELL_LIGHT, outline=False)
    hx, hy = cx, feet - 5
    c.ellipse(hx, hy, 9, 6.5, BEETLE_BODY)
    for side in (-1, 1):  # the pincers open before a bite
        spread = 2 + jaws * 4
        c.polygon([(hx + side * 3, hy + 3), (hx + side * (3 + spread), hy + 9), (hx + side * 1.2, hy + 6.5)],
                  BEETLE_SHELL_DARK)
    _eyes(c, hx, hy - 1.5, 3.4, face, 0.75, color=(240, 232, 150, 255))
    if bits:
        rng = random.Random(bits)
        for _ in range(bits):
            c.ellipse(cx + rng.uniform(-22, 22), feet - rng.uniform(0, 6), 2.2, 1.6, BEETLE_SHELL)
    return c.finish()


IMP = (198, 94, 72, 255)
IMP_DARK = (150, 64, 52, 255)
IMP_BELLY = (238, 172, 132, 255)
IMP_HORN = (242, 228, 198, 255)
ROCK = (140, 130, 122, 255)
# (animation, rock heaved up 0..1, face, bob, bits)
IMP_POSES = [
    ("idle", 0.0, "normal", 0.0, 0),
    ("idle", 0.0, "normal", 1.5, 0),
    ("attack", 0.7, "angry", 0.0, 0),
    ("attack", 1.0, "angry", -1.0, 0),
    ("die", 0.0, "dead", 2.0, 0),
    ("die", 0.0, "dead", 4.0, 0),
    ("die", 0.0, "none", 0.0, 0),
]


def draw_imp(arm: float, face: str, bob: float, bits: int) -> Image.Image:
    """Crag Imp: a little red imp with curled horns, bat ears and a pointed tail,
    holding a rock that it heaves over its head to throw."""
    c = Canvas(SLIME_FRAME)
    cx, feet = 32, SLIME_FEET_Y
    c.ellipse(cx, feet + 1, 14, 3.6, SHADOW, outline=False)
    if face == "none":
        for k in range(3):
            c.ellipse(cx - 8 + k * 8, feet - 2 - (k % 2) * 2, 2.6, 1.8, IMP)
        c.ellipse(cx + 13, feet - 3, 4.5, 3.6, ROCK)
        return c.finish()
    by = feet - 13 + bob
    c.line([(cx + 6, by + 6), (cx + 15, by + 2), (cx + 18, by - 6)], fill=IMP_DARK, width=2.2)
    c.polygon([(cx + 18, by - 11), (cx + 21.5, by - 5), (cx + 15, by - 5)], IMP_DARK)
    for side in (-1, 1):
        c.ellipse(cx + side * 5, feet - 2.5, 4, 2.6, IMP_DARK)
    c.ellipse(cx, by + 3, 10, 9, IMP)
    c.ellipse(cx, by + 5, 6, 5, IMP_BELLY, outline=False)
    hy = by - 11
    rock = (cx, hy - 13 - arm * 4) if arm > 0.5 else (cx + 10, by + 2)
    if arm > 0.5:  # heaved over its head: the arms go up behind it
        for side in (-1, 1):
            c.line([(cx + side * 8, by - 1), (cx + side * 14, hy - 3), (rock[0] + side * 6, rock[1] + 3)],
                   fill=IMP_DARK, width=3.2)
    for side in (-1, 1):  # bat ears and curled horns
        c.polygon([(cx + side * 7, hy - 2), (cx + side * 17, hy - 8), (cx + side * 9, hy + 3)], IMP_DARK)
        c.polygon([(cx + side * 4, hy - 6), (cx + side * 6, hy - 15), (cx + side * 9, hy - 14),
                   (cx + side * 7.5, hy - 5)], IMP_HORN)
    c.ellipse(cx, hy, 9.5, 8.5, IMP)
    _eyes(c, cx, hy - 0.5, 3.4, face, 0.8, color=(250, 222, 96, 255))
    c.line(arc_points(cx, hy + 3, 3.6, 2.2, 20, 160, 8), width=1.2)
    if arm <= 0.5:
        c.line([(cx + 7, by - 1), (rock[0] - 3, rock[1])], fill=IMP_DARK, width=3.2)
        c.line([(cx - 7, by - 1), (cx - 10, by + 5)], fill=IMP_DARK, width=3.2)
    c.ellipse(rock[0], rock[1], 6.5, 5.5, ROCK)
    c.ellipse(rock[0] - 2, rock[1] - 2, 2.2, 1.3, (180, 172, 164, 255), outline=False)
    return c.finish()


HARPY = (150, 132, 196, 255)
HARPY_DARK = (108, 92, 156, 255)
HARPY_LIGHT = (214, 204, 240, 255)
HARPY_CREST = (96, 196, 206, 255)
TALON = (240, 196, 92, 255)
# (animation, wings: -1 down .. 1 up, 2 spread wide, -2 folded, face, body drop, bits)
HARPY_POSES = [
    ("idle", 1.0, "normal", 0.0, 0),
    ("idle", -1.0, "normal", 2.0, 0),
    ("attack", 1.0, "angry", -2.0, 0),
    ("attack", -1.0, "angry", 3.0, 0),
    ("die", -1.0, "dead", 4.0, 0),
    ("die", -1.0, "dead", 7.0, 0),
    ("die", 0.0, "none", 0.0, 0),
    ("soar", 2.0, "normal", 0.0, 0),
    ("soar", 1.6, "normal", 1.0, 0),
    ("dive", -2.0, "angry", 0.0, 0),
]


def draw_harpy(wings: float, face: str, drop: float, bits: int) -> Image.Image:
    """Gale Harpy: a round, fluffy storm bird with a teal crest, big wings and
    golden talons. It soars with its wings spread and dives with them folded."""
    c = Canvas(SLIME_FRAME)
    cx, feet = 32, SLIME_FEET_Y
    c.ellipse(cx, feet + 1, 14, 3.6, SHADOW, outline=False)
    if face == "none":
        rng = random.Random(7)
        for _ in range(6):  # a puff of feathers
            x, y = cx + rng.uniform(-16, 16), feet - rng.uniform(1, 10)
            c.ellipse(x, y, 4, 1.8, HARPY_LIGHT if rng.random() < 0.5 else HARPY)
        return c.finish()
    cy = feet - 24 + drop
    for side in (-1, 1):  # wings behind the body
        if wings >= 2.0:  # spread wide, soaring
            tip = (cx + side * 31, cy - 10 * (wings - 1.0))
            c.polygon([(cx + side * 6, cy - 4), tip, (cx + side * 27, cy + 2), (cx + side * 18, cy + 6),
                       (cx + side * 8, cy + 6)], HARPY_DARK)
        elif wings <= -2.0:  # folded tight for a dive
            c.polygon([(cx + side * 8, cy - 6), (cx + side * 13, cy + 8), (cx + side * 6, cy + 12)], HARPY_DARK)
        else:
            tip = (cx + side * 26, cy - 12 * wings)
            c.polygon([(cx + side * 7, cy - 4), tip, (cx + side * 22, cy + 4 - 4 * wings),
                       (cx + side * 9, cy + 7)], HARPY_DARK)
    if wings > -2.0:
        for side in (-1, 1):  # legs with talons
            c.line([(cx + side * 4, cy + 8), (cx + side * 5, feet - 3 + drop * 0.3)], fill=TALON, width=2.2)
            c.polygon([(cx + side * 2, feet - 2 + drop * 0.3), (cx + side * 8, feet - 2 + drop * 0.3),
                       (cx + side * 5, feet + 1 + drop * 0.3)], TALON)
    c.ellipse(cx, cy, 12, 12, HARPY)
    c.ellipse(cx, cy + 3, 7, 7, HARPY_LIGHT, outline=False)
    for k, dx in enumerate((-4, 0, 4)):  # the crest
        c.polygon([(cx + dx - 2, cy - 10), (cx + dx * 1.6, cy - 19 - (k % 2) * 3), (cx + dx + 2, cy - 10)],
                  HARPY_CREST)
    _eyes(c, cx, cy - 3, 4.2, face, 0.85, color=(60, 42, 80, 255))
    c.polygon([(cx - 2.6, cy + 0.5), (cx + 2.6, cy + 0.5), (cx, cy + 5)], TALON)
    return c.finish()


STONE = (150, 152, 160, 255)
STONE_DARK = (112, 114, 124, 255)
STONE_LIGHT = (186, 188, 196, 255)
EMBER_EYE = (255, 170, 70, 255)
# (animation, wings open 0..1, face: "statue" asleep / normal / angry / dead / none, claws up, bits)
GARGOYLE_POSES = [
    ("sleep", 0.0, "statue", 0.0, 0),
    ("idle", 0.6, "normal", 0.0, 0),
    ("idle", 0.8, "normal", 1.0, 0),
    ("attack", 1.0, "angry", 1.0, 0),
    ("attack", 1.0, "angry", 0.0, 0),
    ("die", 0.4, "dead", 0.0, 2),
    ("die", 0.2, "dead", 0.0, 5),
    ("die", 0.0, "none", 0.0, 8),
]


def draw_gargoyle(wings: float, face: str, claws: float, bits: int) -> Image.Image:
    """Stone Gargoyle: a horned, winged imp of grey stone that sits on a plinth
    like a statue, eyes shut, until someone comes close; awake, its eyes glow."""
    c = Canvas(SLIME_FRAME)
    cx, feet = 32, SLIME_FEET_Y
    c.ellipse(cx, feet + 1, 18, 4.2, SHADOW, outline=False)
    rng = random.Random(bits * 7 + 1)
    if face == "none":
        for _ in range(bits):
            c.polygon(_chip(cx + rng.uniform(-18, 18), feet - rng.uniform(1, 8), rng), STONE)
        return c.finish()
    if face == "statue":
        c.rect(cx - 15, feet - 7, cx + 15, feet + 1, STONE_DARK, radius=1.5)  # the plinth
    by = feet - (19 if face == "statue" else 16)
    for side in (-1, 1):  # wings
        spread = 8 + wings * 14
        c.polygon([(cx + side * 6, by - 8), (cx + side * (8 + spread), by - 16 - wings * 6),
                   (cx + side * (6 + spread), by + 2), (cx + side * 8, by + 6)], STONE_DARK)
    c.ellipse(cx, by + 4, 11, 10, STONE)  # body, crouched
    for side in (-1, 1):  # arms and claws
        hand = (cx + side * 11, by + 6 - claws * 12)
        c.line([(cx + side * 8, by + 1), hand], fill=STONE_DARK, width=3.4)
        for k in (-1, 0, 1):
            c.line([hand, (hand[0] + side * 2 + k * 1.6, hand[1] - 3.5)], fill=STONE_LIGHT, width=1.2)
    hy = by - 10
    for side in (-1, 1):  # horns
        c.polygon([(cx + side * 4, hy - 5), (cx + side * 9, hy - 14), (cx + side * 7.5, hy - 3)], STONE_LIGHT)
    c.ellipse(cx, hy, 9, 8, STONE)
    if face == "statue":
        for side in (-1, 1):  # eyes shut, carved
            c.line([(cx + side * 2, hy - 0.5), (cx + side * 5.5, hy - 0.5)], fill=STONE_DARK, width=1.4)
        c.line([(cx - 9, by - 2), (cx - 4, by + 4), (cx - 6, by + 9)], fill=STONE_DARK, width=1.0)
    else:
        _eyes(c, cx, hy - 0.5, 3.4, face, 0.8, color=EMBER_EYE)
    c.line(arc_points(cx, hy + 3.2, 3.4, 1.8, 20, 160, 8), fill=STONE_DARK, width=1.2)
    c.ellipse(cx - 4, by - 1, 3, 1.6, STONE_LIGHT, outline=False)
    for _ in range(bits):
        c.polygon(_chip(cx + rng.uniform(-20, 20), feet - rng.uniform(0, 6), rng), STONE)
    return c.finish()


def _chip(x, y, rng):
    """A little broken bit of stone."""
    r = rng.uniform(2.0, 3.6)
    return [(x - r, y), (x - r * 0.3, y - r), (x + r, y - r * 0.4), (x + r * 0.6, y + r * 0.6)]


MIMIC_WOOD = (150, 98, 56, 255)
MIMIC_WOOD_DARK = (110, 70, 40, 255)
MIMIC_GOLD = (246, 200, 84, 255)
MIMIC_MOUTH = (90, 30, 44, 255)
MIMIC_TONGUE = (226, 96, 110, 255)
# (animation, lid open 0..1, face, hop, bits)
MIMIC_POSES = [
    ("sleep", 0.0, "normal", 0.0, 0),
    ("idle", 0.45, "normal", 0.0, 0),
    ("idle", 0.35, "normal", 2.0, 0),
    ("attack", 0.9, "angry", -2.0, 0),
    ("attack", 1.0, "angry", 0.0, 0),
    ("die", 0.6, "dead", 0.0, 3),
    ("die", 0.8, "dead", 0.0, 6),
    ("die", 0.0, "none", 0.0, 8),
]


def draw_mimic(lid: float, face: str, hop: float, bits: int) -> Image.Image:
    """Mimic: a treasure chest, wood with gold bands and a lock, just like a real
    one; until someone walks up, when its lid gapes open on teeth and a tongue."""
    c = Canvas(SLIME_FRAME)
    cx, feet = 32, SLIME_FEET_Y
    c.ellipse(cx, feet + 1, 19, 4.2, SHADOW, outline=False)
    rng = random.Random(bits * 3 + 2)
    if face == "none":
        for _ in range(bits):
            x, y = cx + rng.uniform(-18, 18), feet - rng.uniform(1, 7)
            c.rect(x - 4, y - 1.5, x + 4, y + 1.5, MIMIC_WOOD if rng.random() < 0.7 else MIMIC_GOLD, radius=0.8)
        return c.finish()
    base = feet - 2 - hop
    c.rect(cx - 16, base - 16, cx + 16, base, MIMIC_WOOD, radius=2)  # the box
    for x in (-11, 8):
        c.rect(cx + x, base - 16, cx + x + 4, base, MIMIC_GOLD, radius=0.8, outline=False)
    if lid > 0.05:  # open: the mouth with teeth and tongue
        gap = 4 + lid * 11
        c.rect(cx - 15, base - 16 - gap, cx + 15, base - 15, MIMIC_MOUTH, radius=2)
        c.ellipse(cx, base - 16 - gap * 0.35, 8, gap * 0.3 + 1, MIMIC_TONGUE, outline=False)
        for k in range(6):
            x = cx - 13 + k * 5.2
            c.polygon([(x, base - 16), (x + 2.6, base - 16 - 4), (x + 5.2, base - 16)], (250, 248, 236, 255))
            c.polygon([(x, base - 16 - gap), (x + 2.6, base - 16 - gap + 4), (x + 5.2, base - 16 - gap)],
                      (250, 248, 236, 255))
        top = base - 16 - gap
    else:
        top = base - 16
    c.rect(cx - 17, top - 9, cx + 17, top, MIMIC_WOOD, radius=3)  # the lid
    for x in (-11, 8):
        c.rect(cx + x, top - 9, cx + x + 4, top, MIMIC_GOLD, radius=0.8, outline=False)
    if lid > 0.05:
        _eyes(c, cx, top - 4.5, 5.5, face, 0.8, color=(255, 236, 120, 255))
    else:
        c.rect(cx - 3, top - 3, cx + 3, top + 4, MIMIC_GOLD, radius=1)  # the lock
    for _ in range(bits):
        x, y = cx + rng.uniform(-20, 20), feet - rng.uniform(0, 5)
        c.rect(x - 3, y - 1, x + 3, y + 1, MIMIC_WOOD, radius=0.6)
    return c.finish()


SENTINEL_STONE = (120, 128, 150, 255)
SENTINEL_DARK = (88, 94, 116, 255)
SENTINEL_GLOW = (110, 236, 255, 255)
# (animation, eye glow 0..1, face, bob, bits)
SENTINEL_POSES = [
    ("idle", 0.4, "normal", 0.0, 0),
    ("idle", 0.5, "normal", 2.0, 0),
    ("attack", 0.9, "angry", 0.0, 0),
    ("attack", 1.0, "angry", -1.0, 0),
    ("die", 0.2, "dead", 3.0, 3),
    ("die", 0.0, "dead", 6.0, 6),
    ("die", 0.0, "none", 0.0, 8),
]


def draw_sentinel(glow: float, face: str, bob: float, bits: int) -> Image.Image:
    """Ruin Sentinel: a floating ball of carved stone with one great glowing eye
    and two stones circling it. Its eye flares as it charges its beam."""
    c = Canvas(SLIME_FRAME)
    cx, feet = 32, SLIME_FEET_Y
    c.ellipse(cx, feet + 1, 13, 3.4, SHADOW, outline=False)
    rng = random.Random(bits * 5 + 3)
    if face == "none":
        for _ in range(bits):
            c.polygon(_chip(cx + rng.uniform(-16, 16), feet - rng.uniform(1, 7), rng), SENTINEL_STONE)
        return c.finish()
    cy = feet - 26 + bob
    for side in (-1, 1):  # the circling stones
        c.ellipse(cx + side * 19, cy + side * 4, 4, 3.4, SENTINEL_DARK)
    c.ellipse(cx, cy, 15, 15, SENTINEL_STONE)
    c.line(arc_points(cx, cy, 11.5, 11.5, 200, 340, 12), fill=SENTINEL_DARK, width=1.6)  # carved rings
    c.line(arc_points(cx, cy, 11.5, 11.5, 20, 160, 12), fill=SENTINEL_DARK, width=1.6)
    if face == "dead":
        c.line([(cx - 5, cy - 5), (cx + 5, cy + 5)], width=1.8)
        c.line([(cx - 5, cy + 5), (cx + 5, cy - 5)], width=1.8)
    else:
        c.ellipse(cx, cy, 8 + glow * 2, 8 + glow * 2, (SENTINEL_GLOW[0], SENTINEL_GLOW[1], SENTINEL_GLOW[2], int(90 * glow)), outline=False)
        c.ellipse(cx, cy, 7, 7, (236, 248, 255, 255))
        c.ellipse(cx, cy, 4, 4, SENTINEL_GLOW, outline=False)
        c.ellipse(cx, cy, 1.8, 1.8, (30, 60, 80, 255), outline=False)
        if face == "angry":
            c.line([(cx - 8, cy - 9), (cx + 8, cy - 9)], fill=SENTINEL_DARK, width=2.2)
    for _ in range(bits):
        c.polygon(_chip(cx + rng.uniform(-18, 18), feet - rng.uniform(0, 6), rng), SENTINEL_STONE)
    return c.finish()


WOLF_FUR = (214, 222, 236, 255)
WOLF_DARK = (150, 162, 188, 255)
WOLF_LIGHT = (246, 248, 255, 255)
WOLF_NOSE = (60, 52, 70, 255)
# (animation, stride -1..1, face, crouch, bits)
WOLF_POSES = [
    ("idle", 0.0, "normal", 0.0, 0),
    ("idle", 0.3, "normal", 1.0, 0),
    ("attack", 1.0, "angry", 3.0, 0),
    ("attack", -1.0, "angry", -1.0, 0),
    ("die", 0.0, "dead", 4.0, 0),
    ("die", 0.0, "dead", 7.0, 0),
    ("die", 0.0, "none", 0.0, 0),
]


def draw_wolf(stride: float, face: str, crouch: float, bits: int) -> Image.Image:
    """Snow Wolf: a fluffy white wolf with frosty blue markings, pointed ears
    and a bushy tail; it crouches low before it pounces."""
    c = Canvas(SLIME_FRAME)
    cx, feet = 32, SLIME_FEET_Y
    c.ellipse(cx, feet + 1, 20, 4.4, SHADOW, outline=False)
    if face == "none":
        for k in range(4):
            c.ellipse(cx - 12 + k * 8, feet - 3 - (k % 2) * 2, 3.2, 2.2, WOLF_FUR)
        return c.finish()
    by = feet - 14 + crouch
    c.polygon([(cx + 13, by - 2), (cx + 26, by - 12 + stride * 2), (cx + 24, by + 2)], WOLF_FUR)  # tail
    for dx in (-10, -4, 6, 12):  # legs
        lift = stride * (2 if dx in (-10, 6) else -2)
        c.rect(cx + dx - 2.4, by + 2, cx + dx + 2.4, feet - 1 + min(0, lift), WOLF_DARK, radius=1.2)
    c.ellipse(cx + 2, by, 15, 9, WOLF_FUR)  # body
    c.ellipse(cx + 4, by + 3, 9, 4, WOLF_LIGHT, outline=False)
    hx, hy = cx - 12, by - 7 - crouch * 0.4
    for side in (-1, 1):  # ears
        c.polygon([(hx + side * 4 - 2, hy - 5), (hx + side * 6, hy - 14), (hx + side * 8, hy - 4)], WOLF_DARK)
    c.ellipse(hx, hy, 9, 8, WOLF_FUR)
    c.ellipse(hx - 5, hy + 3, 5, 3.6, WOLF_LIGHT)  # muzzle
    c.ellipse(hx - 9, hy + 2.4, 1.6, 1.4, WOLF_NOSE, outline=False)
    _eyes(c, hx + 1, hy - 1.5, 3.2, face, 0.75, color=(80, 160, 230, 255))
    if face == "angry":
        c.polygon([(hx - 8, hy + 5), (hx - 3, hy + 5), (hx - 5.5, hy + 8)], (250, 250, 250, 255))
    return c.finish()


WRAITH = (176, 214, 246, 200)
WRAITH_DARK = (110, 150, 210, 220)
# (animation, sway, face, fade, bits)
WRAITH_POSES = [
    ("idle", -1.0, "normal", 0.0, 0),
    ("idle", 1.0, "normal", 0.0, 0),
    ("attack", 0.0, "angry", 0.0, 0),
    ("attack", 2.0, "angry", 0.0, 0),
    ("die", 0.0, "dead", 0.4, 0),
    ("die", 0.0, "dead", 0.7, 0),
    ("die", 0.0, "none", 1.0, 0),
]


def draw_wraith(sway: float, face: str, fade: float, bits: int) -> Image.Image:
    """Frost Wraith: a floating ghost of ice mist with a tattered hem, frost
    shards circling it and pale glowing eyes."""
    c = Canvas(SLIME_FRAME)
    cx, feet = 32, SLIME_FEET_Y
    c.ellipse(cx, feet + 1, 12, 3, SHADOW, outline=False)
    if face == "none":
        for k in range(5):
            c.ellipse(cx - 12 + k * 6, feet - 6 - (k % 2) * 4, 2, 2, (220, 240, 255, 160), outline=False)
        return c.finish()
    alpha = int(255 * (1.0 - fade))
    body = (WRAITH[0], WRAITH[1], WRAITH[2], min(WRAITH[3], alpha))
    cy = feet - 26
    hem = [(cx - 13 + sway, cy + 6)]
    for k in range(6):  # the tattered hem, in points
        hem.append((cx - 11 + k * 4.4 + sway * (1 - k / 5), feet - 6 - (k % 2) * 5))
    hem.append((cx + 13 + sway, cy + 6))
    c.polygon(hem, body)
    c.ellipse(cx, cy, 13, 14, body)
    for side in (-1, 1):  # arms trailing mist
        c.polygon([(cx + side * 10, cy), (cx + side * 20, cy + 8 + sway), (cx + side * 11, cy + 9)], body)
    for k, (dx, dy) in enumerate(((-18, -12), (17, -6), (-15, 10))):  # frost shards
        c.polygon([(cx + dx, cy + dy - 4), (cx + dx + 2.4, cy + dy), (cx + dx, cy + dy + 4),
                   (cx + dx - 2.4, cy + dy)], (226, 244, 255, 230))
    _eyes(c, cx, cy - 1, 4, face, 0.85, color=(236, 252, 255, 255))
    return c.finish()


WYRM = (132, 182, 222, 255)
WYRM_DARK = (86, 128, 178, 255)
WYRM_BELLY = (218, 236, 248, 255)
WYRM_HORN = (236, 244, 252, 255)
# (animation, jaw open 0..1, face, coil, bits)
WYRM_POSES = [
    ("idle", 0.0, "normal", 0.0, 0),
    ("idle", 0.1, "normal", 1.5, 0),
    ("attack", 0.7, "angry", -1.0, 0),
    ("attack", 1.0, "angry", 0.0, 0),
    ("die", 0.2, "dead", 3.0, 0),
    ("die", 0.0, "dead", 6.0, 0),
    ("die", 0.0, "none", 0.0, 0),
]


def draw_wyrm(jaw: float, face: str, coil: float, bits: int) -> Image.Image:
    """Frost Wyrm: a coiled serpent dragon of pale blue scales, with icy horns,
    a frilled crest and small wings; it rears up and breathes frost."""
    c = Canvas(SLIME_FRAME)
    cx, feet = 32, SLIME_FEET_Y
    c.ellipse(cx, feet + 1, 22, 4.6, SHADOW, outline=False)
    if face == "none":
        for k in range(5):
            c.ellipse(cx - 16 + k * 8, feet - 3 - (k % 2) * 2, 3.6, 2.4, WYRM)
        return c.finish()
    c.ellipse(cx + 4, feet - 6 + coil * 0.3, 19, 7, WYRM_DARK)  # the coil on the ground
    c.ellipse(cx + 4, feet - 8 + coil * 0.3, 16, 5, WYRM, outline=False)
    c.polygon([(cx + 18, feet - 8), (cx + 28, feet - 13), (cx + 22, feet - 4)], WYRM_DARK)  # tail tip
    for side in (-1, 1):  # little wings
        c.polygon([(cx + side * 5, feet - 24 + coil), (cx + side * 19, feet - 34 + coil),
                   (cx + side * 16, feet - 22 + coil)], WYRM_DARK)
    c.ellipse(cx, feet - 20 + coil, 9, 13, WYRM)  # the neck, rearing up
    c.ellipse(cx, feet - 17 + coil, 5, 9, WYRM_BELLY, outline=False)
    hy = feet - 34 + coil
    for side in (-1, 1):  # horns and the crest frill
        c.polygon([(cx + side * 4, hy - 4), (cx + side * 10, hy - 14), (cx + side * 7, hy - 3)], WYRM_HORN)
    c.ellipse(cx, hy, 10, 8, WYRM)
    c.ellipse(cx, hy + 5 + jaw * 2, 7, 3 + jaw * 3, WYRM_BELLY)  # the snout and jaw
    if jaw > 0.5:
        c.ellipse(cx, hy + 6 + jaw * 2, 4.5, 1.8 + jaw * 2, (60, 90, 140, 255), outline=False)
    _eyes(c, cx, hy - 1.5, 4.2, face, 0.8, color=(150, 240, 255, 255))
    return c.finish()


FOREST_MONSTERS = {
    "boar": (draw_boar, BOAR_POSES),
    "wisp": (draw_wisp, WISP_POSES),
    "rootling": (draw_rootling, ROOTLING_POSES),
    "golem": (draw_golem, GOLEM_POSES),
    "treant": (draw_treant, TREANT_POSES),
    "turtle": (draw_turtle, TURTLE_POSES),
    "frog": (draw_frog, FROG_POSES),
    "beetle": (draw_beetle, BEETLE_POSES),
    "imp": (draw_imp, IMP_POSES),
    "harpy": (draw_harpy, HARPY_POSES),
    "gargoyle": (draw_gargoyle, GARGOYLE_POSES),
    "mimic": (draw_mimic, MIMIC_POSES),
    "sentinel": (draw_sentinel, SENTINEL_POSES),
    "wolf": (draw_wolf, WOLF_POSES),
    "wraith": (draw_wraith, WRAITH_POSES),
    "wyrm": (draw_wyrm, WYRM_POSES),
}


def build_monster_sheet(draw, poses) -> Image.Image:
    sheet = Image.new("RGBA", (SLIME_FRAME * len(poses), SLIME_FRAME), (0, 0, 0, 0))
    for col, pose in enumerate(poses):
        sheet.paste(draw(*pose[1:]), (col * SLIME_FRAME, 0))
    return sheet


EXTRA_FPS = {"roll": 12.0}  # the beetle's ball spins fast; other own poses play at 4 fps


def build_slime_frames(sheet_res_path: str, poses=SLIME_POSES) -> str:
    """SpriteFrames text for a monster sheet: idle (loops), attack and die."""
    lines = [
        f'[gd_resource type="SpriteFrames" load_steps={len(poses) + 2} format=3]',
        "",
        f'[ext_resource type="Texture2D" path="{sheet_res_path}" id="1_sheet"]',
        "",
    ]
    for col in range(len(poses)):
        lines += [
            f'[sub_resource type="AtlasTexture" id="frame_{col}"]',
            'atlas = ExtResource("1_sheet")',
            f"region = Rect2({col * SLIME_FRAME}, 0, {SLIME_FRAME}, {SLIME_FRAME})",
            "",
        ]
    blocks = []
    extra = []  # a monster's own poses, such as the turtle's shell or the frog's leap
    for pose in poses:
        if pose[0] not in [a[0] for a in SLIME_ANIMATIONS + extra]:
            extra.append((pose[0], EXTRA_FPS.get(pose[0], 4.0), True))
    for name, fps, loop in SLIME_ANIMATIONS + extra:
        columns = [col for col, pose in enumerate(poses) if pose[0] == name]
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

    frames = build_hero_parts("warrior")
    sheet = build_warrior_sheet(frames)
    sheet.save(warrior_dir / "warrior.png")
    npc_dir = ASSETS / "characters" / "npcs"
    npc_dir.mkdir(parents=True, exist_ok=True)
    for look in NPC_LOOKS:
        build_npc_sheet(frames, look).save(npc_dir / f"{look}.png")
    add_look_variants(frames)
    atlas, pieces = pack_warrior_parts(frames)
    atlas.save(warrior_dir / "warrior_parts.png")
    (warrior_dir / "warrior_parts.gd").write_text(build_parts_script(pieces), encoding="utf-8")
    for hero in ("mage", "archer"):
        hero_dir = ASSETS / "characters" / hero
        hero_dir.mkdir(parents=True, exist_ok=True)
        hero_frames = build_hero_parts(hero)
        add_look_variants(hero_frames, hero)
        atlas, pieces = pack_warrior_parts(hero_frames)
        atlas.save(hero_dir / f"{hero}_parts.png")
        (hero_dir / f"{hero}_parts.gd").write_text(
            build_parts_script(pieces, hero), encoding="utf-8"
        )
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
    build_jelly().save(items_dir / "jelly.png")
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
    build_crown().save(slime_dir / "crown.png")
    (slime_dir / "slime_frames.tres").write_text(
        build_slime_frames("res://assets/monsters/slime/slime.png"), encoding="utf-8"
    )
    shroom_dir = ASSETS / "monsters" / "shroom"
    shroom_dir.mkdir(parents=True, exist_ok=True)
    build_shroom_sheet().save(shroom_dir / "shroom.png")
    (shroom_dir / "shroom_frames.tres").write_text(
        build_slime_frames("res://assets/monsters/shroom/shroom.png", SHROOM_POSES), encoding="utf-8"
    )
    for name, (draw, poses) in FOREST_MONSTERS.items():
        folder = ASSETS / "monsters" / name
        folder.mkdir(parents=True, exist_ok=True)
        build_monster_sheet(draw, poses).save(folder / f"{name}.png")
        (folder / f"{name}_frames.tres").write_text(
            build_slime_frames(f"res://assets/monsters/{name}/{name}.png", poses), encoding="utf-8"
        )
    print("Assets written to", ASSETS)


if __name__ == "__main__":
    main()
