# SPDX-License-Identifier: 0BSD
"""Exercise automatic icon invalidation and rebaking; restore authored inputs."""
from pathlib import Path
import datetime
import hashlib
import json
import os
import subprocess
import time

from run import ROOT, parse_args


def main():
    config, _ = parse_args([])
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    folder = ROOT / "reports/checks" / (stamp + "_item_icon_refresh")
    folder.mkdir(parents=True)
    command = [config.godot, "--headless", "--path", str(ROOT),
               "--script", "res://tools/ensure_item_icons.gd"]
    atlas = ROOT / "addons/player_runtime/art/item_icons.trtex"
    receipt = atlas.with_name("item_icons.bake.json")
    scene = ROOT / "vehicle_demo/scenes/car.tscn"
    material_import = ROOT / "vehicle_demo/assets/Vehicle_Rebuilt_BaseColor.png.import"
    hashes = lambda: (hashlib.sha256(atlas.read_bytes()).hexdigest(),
                      hashlib.sha256(receipt.read_bytes()).hexdigest())
    runs = []
    checks = 0

    def run(label, check_only=False, expected=0):
        started = time.monotonic()
        args = command + (["--", "--check-only"] if check_only else [])
        result = subprocess.run(args, cwd=ROOT, capture_output=True, encoding="utf-8",
                                errors="replace", timeout=90,
                                creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        output = result.stdout + result.stderr
        (folder / (label + ".log")).write_text(output, encoding="utf-8")
        runs.append(dict(label=label, command=args, exit_code=result.returncode,
                         elapsed_seconds=time.monotonic()-started))
        assert result.returncode == expected and "ERROR:" not in output, output
        return output

    def passed(label):
        nonlocal checks
        checks += 1
        print("PASS " + label, flush=True)

    try:
        run("initialize")
        original_hashes = hashes()
        original_times = (atlas.stat().st_mtime_ns, receipt.stat().st_mtime_ns)
        assert "bake skipped" in run("warm") and hashes() == original_hashes
        assert (atlas.stat().st_mtime_ns, receipt.stat().st_mtime_ns) == original_times
        passed("unchanged launch skips rendering and writes")

        scene_times = scene.stat()
        try:
            os.utime(scene, ns=(scene_times.st_atime_ns, scene_times.st_mtime_ns + 1000000000))
            assert "bake skipped" in run("timestamp_only", True)
            passed("timestamp-only changes do not rebake identical content")
        finally:
            os.utime(scene, ns=(scene_times.st_atime_ns, scene_times.st_mtime_ns))

        original_import = material_import.read_bytes()
        changed_import = original_import.replace(b"mipmaps/generate=true", b"mipmaps/generate=false")
        assert changed_import != original_import
        material_import.write_bytes(changed_import)
        try:
            assert '["501"]' in run("external_texture_settings", True, 2)
            passed("transitive texture import settings invalidate only the vehicle")
        finally:
            assert material_import.read_bytes() == changed_import, "Input edited concurrently"
            material_import.write_bytes(original_import)

        original_receipt = receipt.read_bytes()
        receipt.unlink()
        try:
            assert '["1", "2", "3", "5", "501"]' in run("missing_receipt", True, 2)
            passed("missing dependency receipt requests a refresh")
        finally:
            assert not receipt.exists(), "Receipt changed concurrently"
            receipt.write_bytes(original_receipt)

        original_scene = scene.read_bytes()
        changed_scene = original_scene.replace(b"rotation = Vector3(0, -1.570796327, 0)",
                                              b"rotation = Vector3(0, -1.470796327, 0)", 1)
        assert changed_scene != original_scene
        scene.write_bytes(changed_scene)
        try:
            assert '["501"]' in run("changed_model")
            bake = (ROOT / "reports/item_icon_refresh/bake.log").read_text(encoding="utf-8")
            (folder / "changed_model_bake.log").write_text(bake, encoding="utf-8")
            assert "CURRENT_ICON 501 " in bake and "CURRENT_ICON 1 " not in bake and "CURRENT_ICON 2 " not in bake
            assert hashes()[0] != original_hashes[0]
            passed("changed model automatically renders only its thumbnail")
        finally:
            assert scene.read_bytes() == changed_scene, "Input edited concurrently"
            scene.write_bytes(original_scene)
            run("restore_model")
            restore_bake = (ROOT / "reports/item_icon_refresh/bake.log").read_text(encoding="utf-8")
            (folder / "restore_model_bake.log").write_text(restore_bake, encoding="utf-8")
        assert hashes() == original_hashes
        passed("restoring the model automatically restores the original images and receipt")
        assert "bake skipped" in run("final_warm", True)
        passed("subsequent launch remains current")
    finally:
        (folder / "run.json").write_text(json.dumps(dict(
            checks=checks, runs=runs, engine_sha256=hashlib.sha256(Path(config.godot).read_bytes()).hexdigest(),
            atlas_sha256=hashlib.sha256(atlas.read_bytes()).hexdigest()), indent=2)+"\n", encoding="utf-8")
    print(f"ITEM_ICON_REFRESH checks={checks} failures=0 {folder}", flush=True)


if __name__ == "__main__":
    main()
