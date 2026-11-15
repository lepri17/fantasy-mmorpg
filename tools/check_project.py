"""Quick consistency check of the Godot project, without needing Godot.

It does NOT run the game. It only catches broken wiring between files:
  - every res:// path used by a scene / resource exists
  - every ExtResource / SubResource id that is used is also declared
  - the main scene exists
  - input actions used in scripts are defined in project.godot
  - $Node paths used by a script exist in the scene that uses the script
  - the animations the player script asks for exist in its SpriteFrames
  - GDScript files parse and pass gdlint (if gdtoolkit is installed)

Run:  python tools/check_project.py
"""

from __future__ import annotations

import re
import shutil
import subprocess
import sys
from pathlib import Path

CLIENT = Path(__file__).resolve().parent.parent / "client"
errors: list[str] = []


def res_to_path(res_path: str) -> Path:
    return CLIENT / res_path.removeprefix("res://")


def check_resource_file(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    name = path.relative_to(CLIENT)

    for res_path in re.findall(r'path="(res://[^"]+)"', text):
        if not res_to_path(res_path).exists():
            errors.append(f"{name}: missing file {res_path}")

    declared_ext = set(re.findall(r'\[ext_resource[^\]]*\bid="([^"]+)"', text))
    declared_sub = set(re.findall(r'\[sub_resource[^\]]*\bid="([^"]+)"', text))
    for used in set(re.findall(r'ExtResource\("([^"]+)"\)', text)) - declared_ext:
        errors.append(f"{name}: ExtResource id '{used}' is not declared")
    for used in set(re.findall(r'SubResource\("([^"]+)"\)', text)) - declared_sub:
        errors.append(f"{name}: SubResource id '{used}' is not declared")


def check_project_file() -> set[str]:
    text = (CLIENT / "project.godot").read_text(encoding="utf-8")
    main_scene = re.search(r'run/main_scene="(res://[^"]+)"', text)
    if not main_scene:
        errors.append("project.godot: no main scene set")
    elif not res_to_path(main_scene.group(1)).exists():
        errors.append(f"project.godot: main scene {main_scene.group(1)} is missing")

    input_section = text.split("[input]", 1)[1].split("\n[", 1)[0] if "[input]" in text else ""
    return set(re.findall(r"^(\w+)=\{", input_section, flags=re.MULTILINE))


def check_script(script: Path, actions: set[str]) -> None:
    text = script.read_text(encoding="utf-8")
    name = script.relative_to(CLIENT)
    res_path = "res://" + name.as_posix()

    for action in set(re.findall(r'"(move_\w+|attack|skill|use_potion)"', text)) - actions:
        errors.append(f"{name}: input action '{action}' is not in project.godot")

    scenes = [s for s in CLIENT.rglob("*.tscn") if res_path in s.read_text(encoding="utf-8")]
    for scene in scenes:
        scene_text = scene.read_text(encoding="utf-8")
        node_names = set(re.findall(r'\[node name="([^"]+)"', scene_text))
        for node in set(re.findall(r"\$(\w+)", text)) - node_names:
            errors.append(f"{name}: ${node} not found in {scene.relative_to(CLIENT)}")

        prefixes = set(re.findall(r'play\("(\w+_)" \+ facing\)', text))
        facings = set(re.findall(r'return "(\w+)"', text))
        for frames_path in re.findall(r'type="SpriteFrames" path="(res://[^"]+)"', scene_text):
            frames_file = res_to_path(frames_path)
            if not frames_file.exists():
                continue
            animations = set(re.findall(r'"name": &"(\w+)"', frames_file.read_text("utf-8")))
            for wanted in {p + f for p in prefixes for f in facings} - animations:
                errors.append(f"{name}: animation '{wanted}' missing in {frames_path}")


def check_gdscript(scripts: list[Path]) -> None:
    if not scripts:
        return
    for tool in ("gdparse", "gdlint"):
        if shutil.which(tool) is None:
            print(f"(skipped {tool}: pip install gdtoolkit to enable it)")
            continue
        result = subprocess.run([tool, *map(str, scripts)], capture_output=True, text=True)
        if result.returncode != 0:
            errors.append(f"{tool} failed:\n{result.stdout}{result.stderr}")


def main() -> int:
    actions = check_project_file()
    for pattern in ("*.tscn", "*.tres"):
        for path in CLIENT.rglob(pattern):
            check_resource_file(path)
    scripts = sorted(CLIENT.rglob("*.gd"))
    for script in scripts:
        check_script(script, actions)
    check_gdscript(scripts)

    if errors:
        print("PROBLEMS FOUND:")
        for error in errors:
            print(" -", error)
        return 1
    print(f"OK: {len(scripts)} script(s), input actions: {', '.join(sorted(actions))}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
