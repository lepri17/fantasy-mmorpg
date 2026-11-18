"""The game data, shared with the client: the JSON tables in client/data, plus
the trees, rocks and monsters placed in scene-built maps (the meadow is a Godot
scene, field.tscn, not JSON). Set MMO_CLIENT_DIR to use another client folder."""

from __future__ import annotations

import json
import math
import os
import re
from functools import lru_cache
from pathlib import Path

CLIENT = Path(os.environ.get("MMO_CLIENT_DIR", Path(__file__).resolve().parents[1] / "client"))
DATA = CLIENT / "data"

# Scene file -> what it is on the server: an obstacle or a monster spawn.
SCENE_KINDS = {
    "scenes/maps/tree.tscn": "tree",
    "scenes/maps/rock.tscn": "rock",
    "scenes/enemies/slime.tscn": "monster",
}
# Trunk or stone circle, from tree.tscn / rock.tscn: (offset y, radius).
OBSTACLES = {"tree": (-6.0, 18.0), "rock": (-10.0, 22.0)}


@lru_cache(maxsize=None)
def table(name: str) -> dict:
    """One file of client/data, such as table("items")."""
    with open(DATA / f"{name}.json", encoding="utf-8") as file:
        return json.load(file)


def roundi(value: float) -> int:
    """Godot's roundi(): halves round away from zero (Python's round() does not)."""
    return int(math.floor(value + 0.5)) if value >= 0 else -int(math.floor(-value + 0.5))


def snapped(value: float, step: float) -> float:
    """Godot's snappedf()."""
    return math.floor(value / step + 0.5) * step


@lru_cache(maxsize=None)
def scene_objects(scene_path: str) -> tuple:
    """Trees, rocks and monsters placed at the top level of a map scene, as
    ({"type", "pos", "id"?}, ...). Only what the server needs is read."""
    text = (CLIENT / scene_path.removeprefix("res://")).read_text(encoding="utf-8")
    resources = {
        rid: path
        for path, rid in re.findall(
            r'^\[ext_resource type="PackedScene" path="res://([^"]+)" id="([^"]+)"\]', text, re.M
        )
    }
    found = []
    for block in text.split("\n[node ")[1:]:
        header = re.match(r'name="[^"]+" parent="\." instance=ExtResource\("([^"]+)"\)\]', block)
        if header is None:
            continue
        kind = SCENE_KINDS.get(resources.get(header.group(1), ""))
        position = re.search(r"^position = Vector2\(([-\d.]+), ([-\d.]+)\)", block, re.M)
        if kind is None or position is None:
            continue
        thing = {"type": kind, "pos": [float(position.group(1)), float(position.group(2))]}
        if kind == "monster":
            monster = re.search(r'^monster_id = "([^"]+)"', block, re.M)
            thing["id"] = monster.group(1) if monster else "green_slime"
        found.append(thing)
    return tuple(found)
