# SPDX-License-Identifier: 0BSD
"""Blender background encoder for actual Godot sleeper-animation review frames."""
import argparse
import hashlib
import json
import sys
from pathlib import Path

import bpy

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--frames", type=Path, required=True)
args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
folder = args.frames.resolve()
if not folder.is_relative_to(root / "reports/zombie_sleepers"):
    raise ValueError("Expected an owned sleeper-review frame directory")
frames = sorted(folder.glob("[0-9][0-9][0-9][0-9].png"))
if len(frames) != 480:
    raise ValueError(f"Expected all 480 normal-speed frames, found {len(frames)}")
scene = bpy.context.scene
scene.render.resolution_x, scene.render.resolution_y = 1280, 720
scene.render.resolution_percentage = 100
scene.render.fps = 30
scene.frame_start, scene.frame_end = 1, len(frames)
editor = scene.sequence_editor_create()
strip = editor.strips.new_image("Godot sleeper review", str(frames[0]), channel=1, frame_start=1)
for frame in frames[1:]:
    strip.elements.append(frame.name)
scene.view_settings.view_transform = "Standard"
scene.render.image_settings.media_type = "VIDEO"
scene.render.image_settings.file_format = "FFMPEG"
scene.render.ffmpeg.format = "MPEG4"
scene.render.ffmpeg.codec = "H264"
scene.render.ffmpeg.constant_rate_factor = "MEDIUM"
scene.render.ffmpeg.ffmpeg_preset = "GOOD"
output = folder.parent / "Zombie.sleepers.mp4"
scene.render.filepath = str(output)
bpy.ops.render.render(animation=True)
(folder.parent / "video.json").write_text(json.dumps({
    "encoder": "Blender " + bpy.app.version_string, "fps": 30, "frames": len(frames),
    "sha256": hashlib.sha256(output.read_bytes()).hexdigest(),
    "scope": "Actual Godot R4 skin, four original wake clips, front/side at normal speed. Studio pose review, not live AI, collision, POI or performance acceptance."
}, indent=2) + "\n", encoding="utf-8")
print("ZOMBIE_SLEEPERS_VIDEO", output)
