"""Draws the prototype art and writes it into the Godot project.

Everything here is drawn from code, so the art is original and fully owned.

Outputs (under client/assets):
  characters/warrior/warrior.png          sprite sheet, 4 rows x 6 columns
  characters/warrior/warrior_frames.tres  Godot SpriteFrames using that sheet
  environment/grass.png                   seamless grass tile
  monsters/slime/slime.png                slime sheet, 2 idle frames
  monsters/slime/slime_frames.tres        Godot SpriteFrames for the slime

Sheet layout: rows = down, left, right, up. Columns 0-1 = idle, 2-5 = walk, 6-8 = attack.
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

FRAME = 96  # final frame size in pixels
SCALE = 4  # draw 4x bigger, then shrink: gives smooth edges
FEET_Y = 86  # where the feet touch the ground inside a frame

DIRECTIONS = ["down", "left", "right", "up"]
IDLE_FPS = 2.0
WALK_FPS = 8.0
ATTACK_FPS = 14.0

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

SLIME_FRAME = 64
SLIME_FEET_Y = 56


@dataclass
class Pose:
    bob: float = 0.0  # body moves down by this many pixels
    step: int = 0  # -1 / 0 / 1: which leg is forward (or lifted)
    swing: int = 0  # 0 = sword at rest, 1-3 = frames of the sword swing


IDLE_POSES = [Pose(bob=0), Pose(bob=1)]
WALK_POSES = [Pose(0, 1), Pose(-1, 0), Pose(0, -1), Pose(-1, 0)]
ATTACK_POSES = [Pose(0, 0, 1), Pose(1, 0, 2), Pose(1, 0, 3)]

# Sword (hand, tip, drawn on top of the body?) for each swing frame.
SWING = {
    "down": [((30, 66), (12, 42), False), ((34, 72), (30, 94), True), ((40, 72), (62, 92), True)],
    "up": [((66, 66), (84, 42), False), ((62, 58), (72, 22), False), ((40, 58), (18, 40), False)],
    "left": [((42, 64), (20, 38), False), ((38, 70), (8, 66), True), ((38, 74), (14, 90), True)],
}


def sword_placement(direction: str, pose: Pose):
    """Where the sword is for this pose: (hand, tip, on_top)."""
    b = pose.bob
    if pose.swing:
        return SWING[direction][pose.swing - 1]
    if direction == "down":
        return (31, 72 + b - pose.step * 2), (17, 44 + b - pose.step * 2), False
    if direction == "up":
        return (65, 72 + b - pose.step * 2), (79, 44 + b - pose.step * 2), False
    return (40 + pose.step * 2, 71 + b), (13 + pose.step * 2, 53 + b), False


class Canvas:
    """Thin wrapper so the drawing code can use final-pixel coordinates."""

    def __init__(self, size: int = FRAME) -> None:
        self.size = size
        self.image = Image.new("RGBA", (size * SCALE, size * SCALE), (0, 0, 0, 0))
        self.draw = ImageDraw.Draw(self.image)
        self.line_width = int(1.5 * SCALE)

    @staticmethod
    def _s(value: float) -> float:
        return value * SCALE

    def ellipse(self, cx, cy, rx, ry, fill, outline=True) -> None:
        box = [self._s(cx - rx), self._s(cy - ry), self._s(cx + rx), self._s(cy + ry)]
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

    def finish(self) -> Image.Image:
        return self.image.resize((self.size, self.size), Image.LANCZOS)


def arc_points(cx, cy, rx, ry, start_deg, end_deg, count=24):
    """Points along an ellipse. 0 = right, 90 = bottom, 180 = left, 270 = top."""
    points = []
    for i in range(count + 1):
        angle = math.radians(start_deg + (end_deg - start_deg) * i / count)
        points.append((cx + rx * math.cos(angle), cy + ry * math.sin(angle)))
    return points


def draw_shadow(c: Canvas) -> None:
    c.ellipse(48, FEET_Y + 1, 17, 5, SHADOW, outline=False)


def draw_sword(c: Canvas, hand, tip) -> None:
    """A simple straight sword from the hand towards the tip."""
    hx, hy = hand
    tx, ty = tip
    length = math.hypot(tx - hx, ty - hy)
    ux, uy = (tx - hx) / length, (ty - hy) / length  # along the blade
    nx, ny = -uy, ux  # across the blade

    def at(along, across):
        return (hx + ux * along + nx * across, hy + uy * along + ny * across)

    c.polygon([at(-5, -1.6), at(1, -1.6), at(1, 1.6), at(-5, 1.6)], GRIP)
    c.polygon(
        [at(4, -2.4), at(length - 5, -2.4), at(length, 0), at(length - 5, 2.4), at(4, 2.4)],
        STEEL,
    )
    c.polygon([at(1, -5), at(4, -5), at(4, 5), at(1, 5)], GOLD)


def draw_leg(c: Canvas, x, lift=0.0, far=False) -> None:
    pants = PANTS_DARK if far else PANTS
    boot = BOOT_DARK if far else BOOT
    bottom = FEET_Y - lift
    c.rect(x - 4.5, 68, x + 4.5, bottom - 5, pants, radius=2)
    c.rect(x - 5.5, bottom - 8, x + 5.5, bottom, boot, radius=3)


def draw_torso(c: Canvas, x0, x1, bob) -> None:
    c.rect(x0, 55 + bob, x1, 77 + bob, ARMOR, radius=8)
    c.ellipse((x0 + x1) / 2 - 3, 62 + bob, (x1 - x0) / 5, 3.5, ARMOR_LIGHT, outline=False)
    c.rect(x0 + 0.75, 70 + bob, x1 - 0.75, 74 + bob, GOLD, radius=1)


def draw_arm(c: Canvas, x, bob, swing_y=0.0, swing_x=0.0) -> None:
    top = 58 + bob
    c.rect(x - 4 + swing_x, top, x + 4 + swing_x, top + 13 + swing_y, ARMOR_DARK, radius=4)
    c.ellipse(x + swing_x, top + 14 + swing_y, 3.6, 3.6, SKIN)
    c.ellipse(x, top + 1, 6, 5, ARMOR)


def draw_face_front(c: Canvas, cx, cy) -> None:
    for side in (-1, 1):
        ex = cx + side * 8.5
        c.ellipse(ex, cy + 7, 3.2, 4.6, EYE, outline=False)
        c.ellipse(ex - 1, cy + 5, 1.4, 1.4, WHITE, outline=False)
        c.ellipse(ex + 1.1, cy + 8.6, 0.8, 0.8, WHITE, outline=False)
        c.ellipse(cx + side * 14, cy + 13, 3.2, 1.8, BLUSH, outline=False)
    c.line(arc_points(cx, cy + 13.5, 2.4, 1.8, 20, 160, 8), width=1.2)


def hair_tuft(c: Canvas, cx, cy) -> None:
    c.polygon([(cx - 3, cy - 18), (cx + 7, cy - 29), (cx + 5, cy - 17)], HAIR)


def draw_down(c: Canvas, pose: Pose) -> None:
    b = pose.bob
    cx, cy = 48, 35 + b
    draw_shadow(c)
    c.polygon([(34, 58 + b), (62, 58 + b), (66, 79 + b), (30, 79 + b)], CAPE_DARK)
    hand, tip, sword_on_top = sword_placement("down", pose)
    if not sword_on_top:
        draw_sword(c, hand, tip)
    draw_leg(c, 42, lift=3 if pose.step > 0 else 0)
    draw_leg(c, 54, lift=3 if pose.step < 0 else 0)
    draw_torso(c, 35, 61, b)
    draw_arm(c, 32, b, swing_y=-pose.step * 2)
    draw_arm(c, 64, b, swing_y=pose.step * 2)
    c.rect(38, 53 + b, 58, 59 + b, CAPE, radius=3)  # scarf
    hair_tuft(c, cx, cy)
    c.ellipse(cx, cy, 22, 20, SKIN)
    draw_face_front(c, cx, cy)
    fringe = [(70, cy), (66, cy + 7), (60, cy + 1), (54, cy + 8), (48, cy + 1),
              (42, cy + 8), (36, cy + 1), (30, cy + 7), (26, cy)]
    c.polygon(arc_points(cx, cy, 23, 21.5, 180, 360) + fringe, HAIR)
    if sword_on_top:
        draw_sword(c, hand, tip)


def draw_up(c: Canvas, pose: Pose) -> None:
    b = pose.bob
    cx, cy = 48, 35 + b
    draw_shadow(c)
    hand, tip, _ = sword_placement("up", pose)
    draw_sword(c, hand, tip)
    draw_leg(c, 42, lift=3 if pose.step < 0 else 0)
    draw_leg(c, 54, lift=3 if pose.step > 0 else 0)
    draw_torso(c, 35, 61, b)
    draw_arm(c, 32, b, swing_y=pose.step * 2)
    draw_arm(c, 64, b, swing_y=-pose.step * 2)
    sway = pose.step * 1.5
    c.polygon(
        [(37, 55 + b), (59, 55 + b), (65 + sway, 80 + b), (56 + sway, 77 + b),
         (48 + sway, 81 + b), (40 + sway, 77 + b), (31 + sway, 80 + b)],
        CAPE,
    )
    c.line([(48, 60 + b), (48 + sway, 76 + b)], fill=CAPE_DARK, width=1.2)
    hair_tuft(c, cx, cy)
    spikes = [(69, cy + 6), (64, cy + 19), (58, cy + 15), (53, cy + 23), (48, cy + 17),
              (43, cy + 23), (38, cy + 15), (32, cy + 19), (27, cy + 6)]
    c.polygon(arc_points(cx, cy, 23, 21.5, 165, 375) + spikes, HAIR)
    c.line(arc_points(cx, cy + 2, 14, 10, 30, 150, 10), fill=HAIR_DARK, width=1.4)


def draw_left(c: Canvas, pose: Pose) -> None:
    b = pose.bob
    cx, cy = 47, 35 + b
    stride = pose.step * 5
    draw_shadow(c)
    hand, tip, sword_on_top = sword_placement("left", pose)
    if not sword_on_top:
        draw_sword(c, hand, tip)
    sway = abs(pose.step) * 2
    c.polygon(
        [(52, 56 + b), (62, 58 + b), (70 + sway, 78 + b), (63 + sway, 75 + b),
         (58 + sway, 79 + b), (54, 70 + b)],
        CAPE,
    )
    draw_leg(c, 48 + stride, far=True)
    draw_leg(c, 48 - stride, lift=2 if pose.step == 0 and pose.bob < 0 else 0)
    draw_torso(c, 38, 58, b)
    draw_arm(c, 48, b, swing_x=pose.step * 3)
    c.rect(40, 53 + b, 57, 59 + b, CAPE, radius=3)  # scarf
    hair_tuft(c, cx + 2, cy)
    c.ellipse(cx, cy, 21, 20, SKIN)
    c.ellipse(cx - 11, cy + 7, 2.8, 4.6, EYE, outline=False)
    c.ellipse(cx - 12, cy + 5, 1.3, 1.3, WHITE, outline=False)
    c.ellipse(cx - 9, cy + 13, 3.0, 1.8, BLUSH, outline=False)
    c.line(arc_points(cx - 15, cy + 13.5, 1.6, 1.4, 20, 160, 6), width=1.2)
    inner = [(cx + 9, cy + 15), (cx + 3, cy + 9), (cx + 1, cy + 1), (cx - 5, cy + 8),
             (cx - 10, cy), (cx - 16, cy + 6)]
    c.polygon(arc_points(cx, cy, 22, 21.5, 188, 425) + inner, HAIR)
    if sword_on_top:
        draw_sword(c, hand, tip)


def draw_frame(direction: str, pose: Pose) -> Image.Image:
    canvas = Canvas()
    if direction == "down":
        draw_down(canvas, pose)
    elif direction == "up":
        draw_up(canvas, pose)
    else:
        draw_left(canvas, pose)
    frame = canvas.finish()
    if direction == "right":
        frame = ImageOps.mirror(frame)
    return frame


def build_warrior_sheet() -> Image.Image:
    poses = IDLE_POSES + WALK_POSES + ATTACK_POSES
    sheet = Image.new("RGBA", (FRAME * len(poses), FRAME * len(DIRECTIONS)), (0, 0, 0, 0))
    for row, direction in enumerate(DIRECTIONS):
        for col, pose in enumerate(poses):
            sheet.paste(draw_frame(direction, pose), (col * FRAME, row * FRAME))
    return sheet


def build_sprite_frames(sheet_res_path: str) -> str:
    """Text of a Godot 4 SpriteFrames resource that slices the sheet."""
    idle_end = len(IDLE_POSES)
    walk_end = idle_end + len(WALK_POSES)
    attack_end = walk_end + len(ATTACK_POSES)
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
                f"region = Rect2({col * FRAME}, {row * FRAME}, {FRAME}, {FRAME})",
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
    warrior = sheet.crop((0, 0, FRAME, FRAME)).resize((FRAME * 2, FRAME * 2), Image.LANCZOS)
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
