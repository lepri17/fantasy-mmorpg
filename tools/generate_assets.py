"""Draws the prototype art and writes it into the Godot project.

Everything here is drawn from code, so the art is original and fully owned.

Outputs (under client/assets):
  characters/warrior/warrior.png          sprite sheet, 4 rows x 15 columns, 128 px frames
  characters/warrior/warrior_frames.tres  Godot SpriteFrames using that sheet
  environment/grass.png                   seamless grass tile
  monsters/slime/slime.png                slime sheet, 2 idle frames
  monsters/slime/slime_frames.tres        Godot SpriteFrames for the slime

Sheet layout: rows = down, left, right, up. Columns 0-3 = idle, 4-9 = walk, 10-14 = attack.
Also writes environment/tree.png, environment/rock.png and the app icon (client/icon.png).

Run:  python tools/generate_assets.py
Needs: Pillow (pip install pillow)
"""

from __future__ import annotations

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
IDLE_FPS = 4.0
WALK_FPS = 12.0
ATTACK_FPS = 18.0

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
    "back" = behind the body, "body" = over the body but under the head, "front" = over all."""
    hand, tip, sword_layer_name = sword
    if sword_layer_name != layer:
        return
    if pose.trail:
        draw_trail(c, *pose.trail, center)
    draw_sword(c, hand, tip)
    if layer != "back":
        draw_fist(c, hand)  # the glove closes over the grip


# ---------------------------------------------------------------- body parts


def draw_fist(c: Canvas, hand) -> None:
    c.ellipse(hand[0], hand[1], 3.3, 3.3, GRIP)  # leather glove


def draw_arm(c: Canvas, shoulder, hand) -> None:
    """Armoured arm from shoulder to hand: dark sleeve, steel bracer, glove."""
    c.capsule(shoulder, hand, 3.8, ARMOR_DARK)
    c.capsule(lerp(shoulder, hand, 0.55), lerp(shoulder, hand, 0.85), 4.0, STEEL_DARK)
    draw_fist(c, hand)


def draw_pauldron(c: Canvas, x, y) -> None:
    c.ellipse(x, y, 6.8, 5.6, ARMOR)
    c.line(arc_points(x, y + 0.4, 5.8, 4.6, 25, 155, 10), fill=GOLD, width=1.5)
    c.ellipse(x - 2.2, y - 2.0, 2.2, 1.4, ARMOR_LIGHT, outline=False)


def draw_torso_front(c: Canvas, cx, oy, back=False) -> None:
    """Chest plate (or back plate), belt with buckle and two hip plates."""
    top, bottom = 54 + oy, 71 + oy
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
        c.capsule((x, 69 + oy), (x, foot_y - 6), 4.4, PANTS)
        draw_boot_front(c, x, foot_y)


def draw_leg_side(c: Canvas, x, oy, forward, lift, far: bool) -> None:
    fx, fy = x - forward * 2.2, FEET_Y - lift
    c.capsule((x, 69 + oy), (fx + 0.5, fy - 6), 4.3, PANTS_DARK if far else PANTS)
    c.rect(fx - 6.5, fy - 8, fx + 4.2, fy, BOOT_DARK if far else BOOT, radius=2.8)
    c.rect(fx - 4.8, fy - 9, fx + 4.8, fy - 5.6, BOOT if far else BOOT_LIGHT, radius=1.4)


def draw_cape_front(c: Canvas, cx, oy, sway) -> None:
    """From the front only the dark inside of the cape shows, flaring around the legs."""
    s = sway * 1.2
    c.polygon(
        [(cx - 12, 56 + oy), (cx + 12, 56 + oy), (cx + 18 + s, 79 + oy), (cx + 9 + s, 77.5 + oy),
         (cx + s, 80 + oy), (cx - 9 + s, 77.5 + oy), (cx - 18 + s, 79 + oy)],
        CAPE_DARK,
    )


def draw_cape_back(c: Canvas, cx, oy, sway) -> None:
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
    back = (cx + 17 + wind * 6 + sway * 1.5, 79 + oy - wind * 4)
    mid = (cx + 12 + wind * 4 + sway, 76.5 + oy - wind * 2)
    front = (cx + 8 + wind * 2 + sway * 0.5, 79 + oy - wind)
    c.polygon([(cx + 2, 55 + oy), (cx + 10, 56 + oy), back, mid, front, (cx + 3, 73 + oy)], CAPE)
    c.line([(cx + 7, 60 + oy), lerp(mid, back, 0.3)], fill=CAPE_DARK, width=1.2)


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


def draw_head_front(c: Canvas, cx, cy, sway) -> None:
    draw_tails(c, (cx + 17, cy - 5), 32, 14, sway)
    draw_tuft(c, cx, cy, sway)
    c.ellipse(cx, cy, 22, 20, SKIN)
    for side in (-1, 1):
        draw_eye(c, cx + side * 8.5, cy + 7.5)
        c.ellipse(cx + side * 14, cy + 13.5, 3.2, 1.8, BLUSH, outline=False)
    c.line(arc_points(cx, cy + 13.5, 2.4, 1.8, 20, 160, 8), width=1.2)
    fringe = [(cx + 22, cy), (cx + 18, cy + 7), (cx + 12, cy + 1), (cx + 6, cy + 8), (cx, cy + 1),
              (cx - 6, cy + 8), (cx - 12, cy + 1), (cx - 18, cy + 7), (cx - 22, cy)]
    c.polygon(arc_points(cx, cy, 23, 21.5, 180, 360) + fringe, HAIR)
    c.line(arc_points(cx, cy - 4, 16, 13, 215, 260, 8), fill=HAIR_LIGHT, width=2.2)
    draw_band(c, cx, cy, 21.8)
    c.rect(cx - 4.2, cy - 4.4, cx + 4.2, cy + 1.4, GOLD, radius=1.2)  # forehead plate
    c.ellipse(cx, cy - 1.5, 1.5, 1.5, GEM, outline=False)


def draw_head_back(c: Canvas, cx, cy, sway) -> None:
    draw_tuft(c, cx, cy, sway)
    spikes = [(cx + 21, cy + 6), (cx + 16, cy + 19), (cx + 10, cy + 15), (cx + 5, cy + 23),
              (cx, cy + 17), (cx - 5, cy + 23), (cx - 10, cy + 15), (cx - 16, cy + 19),
              (cx - 21, cy + 6)]
    c.polygon(arc_points(cx, cy, 23, 21.5, 165, 375) + spikes, HAIR)
    c.line(arc_points(cx, cy + 2, 14, 10, 30, 150, 10), fill=HAIR_DARK, width=1.4)
    c.line(arc_points(cx, cy - 4, 16, 13, 215, 260, 8), fill=HAIR_LIGHT, width=2.2)
    draw_band(c, cx, cy, 21.8)
    draw_tails(c, (cx, cy - 0.5), 90, 15, sway)
    c.ellipse(cx, cy - 1.3, 2.8, 2.3, CAPE)  # knot


def draw_head_side(c: Canvas, cx, cy, sway, wind) -> None:
    draw_tails(c, (cx + 19, cy - 6), 28 - wind * 18, 15 + wind * 2, sway)
    draw_tuft(c, cx + 2, cy, sway)
    c.ellipse(cx, cy, 21, 20, SKIN)
    draw_eye(c, cx - 11.5, cy + 7.5, rx=2.7)
    c.ellipse(cx - 8.5, cy + 13.5, 3.0, 1.8, BLUSH, outline=False)
    c.line(arc_points(cx - 15, cy + 13.5, 1.6, 1.4, 20, 160, 6), width=1.2)
    inner = [(cx + 9, cy + 15), (cx + 3, cy + 9), (cx + 1, cy + 1), (cx - 5, cy + 8),
             (cx - 10, cy), (cx - 16, cy + 6)]
    c.polygon(arc_points(cx, cy, 22, 21.5, 188, 425) + inner, HAIR)
    c.line(arc_points(cx + 1, cy - 4, 16, 13, 220, 265, 8), fill=HAIR_LIGHT, width=2.2)
    draw_band(c, cx, cy, 20.8)
    c.rect(cx - 21.8, cy - 8.6, cx - 18.4, cy - 3, GOLD, radius=1)  # edge of the forehead plate
    c.ellipse(cx + 19.3, cy - 6, 2.8, 2.3, CAPE)  # knot


# ---------------------------------------------------------------- whole frames


def draw_down(c: Canvas, pose: Pose) -> None:
    ox, oy = pose.lean[0], pose.bob + pose.lean[1]
    cx, center = 48 + ox, (48 + ox, 62 + oy)
    sword = sword_for(pose, (cx - 17, 70 + oy + pose.arm * 1.2), (-13, -27))
    draw_shadow(c)
    draw_cape_front(c, cx, oy, pose.sway)
    sword_layer(c, pose, sword, center, "back")
    draw_legs_front(c, 48 + ox * 0.3, oy, pose.legs, toward_camera=True)
    draw_torso_front(c, cx, oy)
    draw_arm(c, (cx - 14, 58 + oy), sword[0])
    draw_arm(c, (cx + 14, 58 + oy), (cx + 17, 70 + oy - pose.arm * 2.2))
    draw_pauldron(c, cx - 15, 57.5 + oy)
    draw_pauldron(c, cx + 15, 57.5 + oy)
    c.rect(cx - 10, 51.5 + oy, cx + 10, 57.5 + oy, CAPE, radius=3)  # scarf
    sword_layer(c, pose, sword, center, "body")
    draw_head_front(c, cx, 35 + oy, pose.sway)
    sword_layer(c, pose, sword, center, "front")


def draw_up(c: Canvas, pose: Pose) -> None:
    ox, oy = pose.lean[0], pose.bob + pose.lean[1]
    cx, center = 48 + ox, (48 + ox, 62 + oy)
    sword = sword_for(pose, (cx + 17, 70 + oy + pose.arm * 1.2), (13, -27))
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


def draw_side(c: Canvas, pose: Pose) -> None:
    """Facing left. The "right" frames are these, mirrored."""
    ox, oy = pose.lean[0], pose.bob + pose.lean[1]
    cx, center = 47 + ox, (47 + ox, 62 + oy)
    sword = sword_for(pose, (cx - 6 - pose.arm * 3.5, 70 + oy), (-26, -16))
    (near_forward, near_lift), (far_forward, far_lift) = pose.legs
    draw_shadow(c)
    draw_cape_side(c, cx, oy, pose.sway, pose.wind)
    draw_arm(c, (cx + 4, 58 + oy), (cx + 6 + pose.arm * 3.5, 69 + oy))  # far arm
    sword_layer(c, pose, sword, center, "back")
    base = 48 + ox * 0.3
    draw_leg_side(c, base, oy, far_forward, far_lift, far=True)
    draw_leg_side(c, base, oy, near_forward, near_lift, far=False)
    draw_torso_side(c, cx, oy)
    draw_arm(c, (cx + 1, 58 + oy), sword[0])
    draw_pauldron(c, cx + 1, 57.5 + oy)
    c.rect(cx - 8, 51.5 + oy, cx + 9, 57.5 + oy, CAPE, radius=3)  # scarf
    sword_layer(c, pose, sword, center, "body")
    draw_head_side(c, cx, 35 + oy, pose.sway, pose.wind)
    sword_layer(c, pose, sword, center, "front")


def warrior_poses(direction: str) -> list[Pose]:
    return idle_poses() + walk_poses() + attack_poses(direction)


def draw_frame(direction: str, pose: Pose) -> Image.Image:
    canvas = Canvas()
    if direction == "down":
        draw_down(canvas, pose)
    elif direction == "up":
        draw_up(canvas, pose)
    else:
        draw_side(canvas, pose)
    frame = canvas.finish(CELL)
    return ImageOps.mirror(frame) if direction == "right" else frame


def build_warrior_sheet() -> Image.Image:
    columns = IDLE_FRAMES + WALK_FRAMES + ATTACK_FRAMES
    sheet = Image.new("RGBA", (CELL * columns, CELL * len(DIRECTIONS)), (0, 0, 0, 0))
    for row, direction in enumerate(DIRECTIONS):
        for col, pose in enumerate(warrior_poses(direction)):
            sheet.paste(draw_frame(direction, pose), (col * CELL, row * CELL))
    return sheet


def build_sprite_frames(sheet_res_path: str) -> str:
    """Text of a Godot 4 SpriteFrames resource that slices the sheet."""
    idle_end = IDLE_FRAMES
    walk_end = idle_end + WALK_FRAMES
    attack_end = walk_end + ATTACK_FRAMES
    animations = []  # (name, fps, loop, [(row, column), ...])
    for kind, fps, loop, columns in (
        ("idle", IDLE_FPS, True, range(0, idle_end)),
        ("walk", WALK_FPS, True, range(idle_end, walk_end)),
        ("attack", ATTACK_FPS, False, range(walk_end, attack_end)),
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


def build_coin() -> Image.Image:
    c = Canvas(32)
    c.ellipse(16, 27, 9, 3, SHADOW, outline=False)
    c.ellipse(16, 15, 10, 10, GOLD)
    c.ellipse(16, 15, 6, 6, (255, 228, 140, 255), outline=False)
    c.ellipse(13.5, 12.5, 2, 2, WHITE, outline=False)
    return c.finish()


def build_potion() -> Image.Image:
    c = Canvas(32)
    c.ellipse(16, 28, 9, 3, SHADOW, outline=False)
    c.rect(13, 5, 19, 14, (214, 234, 244, 255), radius=1.5)
    c.rect(12, 3, 20, 7, GRIP, radius=1.5)
    c.ellipse(16, 19, 9, 8.5, (232, 70, 86, 255))
    c.ellipse(13, 16, 2.6, 2, (255, 170, 176, 255), outline=False)
    return c.finish()


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


def draw_slime(squash: float) -> Image.Image:
    """One slime frame. squash 0 = tall, 1 = flattened (for the idle bounce)."""
    c = Canvas(SLIME_FRAME)
    cx, cy = 32, 39 + 2 * squash
    rx, ry = 22 + 2 * squash, 17 - 2 * squash
    c.ellipse(cx, SLIME_FEET_Y + 1, 20, 4, SHADOW, outline=False)
    top = cy - ry
    c.line([(cx, top + 2), (cx, top - 6)], width=1.6)
    c.polygon([(cx, top - 5), (cx + 9, top - 11), (cx + 8, top - 3)], LEAF)
    c.polygon([(cx, top - 5), (cx - 8, top - 10), (cx - 7, top - 3)], LEAF)
    c.ellipse(cx, cy, rx, ry, SLIME)
    c.ellipse(cx - 9, cy - 8, 6, 3.5, SLIME_LIGHT, outline=False)
    for side in (-1, 1):
        ex = cx + side * 8
        c.ellipse(ex, cy - 1, 3.2, 4.6, EYE, outline=False)
        c.ellipse(ex - 1, cy - 3, 1.3, 1.3, WHITE, outline=False)
        c.ellipse(cx + side * 15, cy + 6, 3.0, 1.8, BLUSH, outline=False)
    c.line(arc_points(cx, cy + 5, 2.6, 1.8, 20, 160, 8), width=1.2)
    return c.finish()


def build_slime_sheet() -> Image.Image:
    sheet = Image.new("RGBA", (SLIME_FRAME * 2, SLIME_FRAME), (0, 0, 0, 0))
    for col, squash in enumerate((0.0, 1.0)):
        sheet.paste(draw_slime(squash), (col * SLIME_FRAME, 0))
    return sheet


def build_slime_frames(sheet_res_path: str) -> str:
    """SpriteFrames text with one looping animation: idle (2 frames)."""
    lines = [
        '[gd_resource type="SpriteFrames" load_steps=4 format=3]',
        "",
        f'[ext_resource type="Texture2D" path="{sheet_res_path}" id="1_sheet"]',
        "",
    ]
    for col in range(2):
        lines += [
            f'[sub_resource type="AtlasTexture" id="frame_{col}"]',
            'atlas = ExtResource("1_sheet")',
            f"region = Rect2({col * SLIME_FRAME}, 0, {SLIME_FRAME}, {SLIME_FRAME})",
            "",
        ]
    frames = ", ".join(
        '{\n"duration": 1.0,\n"texture": SubResource("frame_%d")\n}' % col for col in range(2)
    )
    lines += [
        "[resource]",
        'animations = [{\n"frames": [%s],\n"loop": true,\n"name": &"idle",\n"speed": 3.0\n}]'
        % frames,
        "",
    ]
    return "\n".join(lines)


def main() -> None:
    warrior_dir = ASSETS / "characters" / "warrior"
    environment_dir = ASSETS / "environment"
    warrior_dir.mkdir(parents=True, exist_ok=True)
    environment_dir.mkdir(parents=True, exist_ok=True)

    sheet = build_warrior_sheet()
    sheet.save(warrior_dir / "warrior.png")
    build_icon(sheet).save(ROOT / "client" / "icon.png")
    (warrior_dir / "warrior_frames.tres").write_text(
        build_sprite_frames("res://assets/characters/warrior/warrior.png"), encoding="utf-8"
    )
    build_grass_tile().save(environment_dir / "grass.png")
    build_tree().save(environment_dir / "tree.png")
    build_rock().save(environment_dir / "rock.png")

    items_dir = ASSETS / "items"
    items_dir.mkdir(parents=True, exist_ok=True)
    build_coin().save(items_dir / "coin.png")
    build_potion().save(items_dir / "potion.png")

    slime_dir = ASSETS / "monsters" / "slime"
    slime_dir.mkdir(parents=True, exist_ok=True)
    build_slime_sheet().save(slime_dir / "slime.png")
    (slime_dir / "slime_frames.tres").write_text(
        build_slime_frames("res://assets/monsters/slime/slime.png"), encoding="utf-8"
    )
    print("Assets written to", ASSETS)


if __name__ == "__main__":
    main()
