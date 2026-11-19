"""What the server knows of each map (client/data/maps.json, plus the meadow
scene): size, spawn points, portals, townspeople, obstacles, monster spawns,
the PvP zone and the teleport price."""

from __future__ import annotations

from dataclasses import dataclass, field
from functools import lru_cache

from ..data import OBSTACLES, scene_objects, table

# A monster's body radius, added to obstacle radii for walking around them.
MONSTER_RADIUS = 16.0


@dataclass
class MapInfo:
    id: str
    name: str
    width: float
    height: float
    safe: bool
    spawns: dict
    portals: list = field(default_factory=list)  # {"pos": (x, y), "to", "spawn"}
    npcs: dict = field(default_factory=dict)  # npc id -> (x, y)
    obstacles: list = field(default_factory=list)  # (x, y, radius)
    monsters: list = field(default_factory=list)  # (monster id, x, y)
    pvp_zone: tuple | None = None  # (left, top, right, bottom)
    dungeon: dict | None = None
    teleport_price: int = 0

    def spawn(self, name: str = "default") -> tuple[float, float]:
        point = self.spawns.get(name) or self.spawns["default"]
        return float(point[0]), float(point[1])

    def clamp(self, x: float, y: float) -> tuple[float, float]:
        return min(max(x, 0.0), self.width), min(max(y, 0.0), self.height)

    def in_pvp_zone(self, x: float, y: float) -> bool:
        if self.pvp_zone is None:
            return False
        left, top, right, bottom = self.pvp_zone
        return left <= x <= right and top <= y <= bottom


@lru_cache(maxsize=None)
def maps() -> dict:
    data = table("maps")
    tile = float(data["tile_size"])
    found = {}
    for map_id, info in data["maps"].items():
        if "size" in info:
            width, height = (float(v) for v in info["size"])
        else:
            width, height = len(info["ground"][0]) * tile, len(info["ground"]) * tile
        things = list(info.get("objects", []))
        if "scene" in info:
            things += list(scene_objects(info["scene"]))
        place = MapInfo(
            id=map_id,
            name=info["name"],
            width=width,
            height=height,
            safe=bool(info.get("safe", False)),
            spawns=dict(info["spawns"]),
            pvp_zone=tuple(info["pvp_zone"]) if "pvp_zone" in info else None,
            dungeon=info.get("dungeon"),
            teleport_price=int(info.get("teleport_price", 0)),
        )
        for thing in things:
            kind = thing["type"]
            if kind == "exit":  # a road at the edge into the next map (edge_exit.gd spot)
                x, y = _exit_spot(thing["side"], thing["span"], width, height)
                place.portals.append({"pos": (x, y), "to": thing["to"], "spawn": thing.get("spawn", "default")})
                continue
            if kind in ("water", "cliff", "icefall", "house"):  # the paused online rules do not know these yet
                continue
            x, y = float(thing["pos"][0]), float(thing["pos"][1])
            if kind in OBSTACLES:
                offset, radius = OBSTACLES[kind]
                scale = float(thing.get("scale", 1.0))  # the deep forest's bigger trees
                place.obstacles.append((x, y + offset * scale, radius * scale + MONSTER_RADIUS))
            elif kind == "portal":
                place.portals.append({"pos": (x, y), "to": thing["to"], "spawn": thing.get("spawn", "default")})
            elif kind == "npc":
                place.npcs[thing["id"]] = (x, y)
            elif kind == "monster":
                place.monsters.append((thing.get("id", "green_slime"), x, y))
        found[map_id] = place
    return found


def _exit_spot(side: str, span, width: float, height: float) -> tuple:
    """The middle of an edge road's trigger (client/scripts/maps/edge_exit.gd spot)."""
    middle = (float(span[0]) + float(span[1])) / 2.0
    depth, walls = 64.0, (24.0, 80.0, 24.0, 20.0)
    if side == "west":
        return walls[0] + depth / 2.0, middle
    if side == "east":
        return width - walls[2] - depth / 2.0, middle
    if side == "north":
        return middle, walls[1] + depth / 2.0
    return middle, height - walls[3] - depth / 2.0


def town() -> str:
    return table("maps")["town"]


def start() -> str:
    return table("maps")["start"]
