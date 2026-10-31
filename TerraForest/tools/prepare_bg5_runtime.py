# SPDX-License-Identifier: 0BSD
"""Bake the preserved BG5 masters into native shared meshes and portable GLBs."""
import argparse
import hashlib
import json
import re
import subprocess
import time

from run import ROOT, parse_args


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify_masters():
    master = ROOT / "authoring/bg5"
    provenance = json.loads((master / "provenance.json").read_text())
    for entry in provenance["files"]:
        if sha(master / entry["path"]) != entry["sha256"]:
            raise ValueError("Master hash changed: " + entry["path"])


def verify():
    verify_masters()
    receipt = json.loads((ROOT / "mods/bg5_runtime/bake.json").read_text())
    checks = {**receipt["sources"],
              "res://authoring/bg5/runtime_recipe.json": receipt["recipe_sha256"],
              "res://tools/bake_bg5_runtime.gd": receipt["tool_sha256"]}
    for asset in receipt["assets"].values():
        checks[asset["glb"]] = asset["glb_sha256"]
        config = ROOT / (asset["glb"].removeprefix("res://") + ".import")
        if config.read_text().strip() != '[remap]\n\nimporter="keep"':
            raise ValueError("Portable GLB must be exported as-is: " + asset["glb"])
        if "prefab" in asset:
            checks[asset["prefab"]] = asset["prefab_sha256"]
    for path, digest in checks.items():
        if sha(ROOT / path.removeprefix("res://")) != digest:
            raise ValueError("Stale bake: " + path)
    for path, entry in receipt["textures"].items():
        if sha(ROOT / path.removeprefix("res://")) != entry["sha256"]:
            raise ValueError("Texture changed: " + path)
        if sha(ROOT / (path.removeprefix("res://") + ".import")) != entry["import_sha256"]:
            raise ValueError("Texture import settings changed: " + path)
    print("PASS BG5 masters, recipe, tool, textures and runtime outputs match")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    if args.check:
        verify()
        return
    engine = args.godot or parse_args([])[0].godot
    verify_masters()
    report = ROOT / "reports/bg5_runtime"
    report.mkdir(parents=True, exist_ok=True)

    def run(label, options):
        result = subprocess.run([str(engine), "--headless", "--path", str(ROOT), *options],
                                capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=120)
        log = result.stdout + "\n" + result.stderr
        (report / (label + ".log")).write_text(log, encoding="utf-8")
        if result.returncode or "SCRIPT ERROR:" in log or "ERROR:" in log:
            raise RuntimeError(label + " failed:\n" + log[-6000:])
        print(label, "PASS", flush=True)

    run("extract_textures", ["--script", "res://tools/bake_bg5_runtime.gd", "--", "--textures"])
    run("initial_import", ["--editor", "--import"])
    textures = json.loads((ROOT / "addons/structures/textures/bg5/textures.json").read_text())["textures"]
    for path, entry in textures.items():
        config = ROOT / (path.removeprefix("res://") + ".import")
        text = config.read_text()
        for key, value in {"compress/mode":"2", "compress/high_quality":"true",
                           "compress/normal_map":"1" if entry["normal"] else "2",
                           "mipmaps/generate":"true"}.items():
            text, count = re.subn(r"(?m)^" + re.escape(key) + r"=.*$", key + "=" + value, text)
            if count != 1:
                raise ValueError("Missing import option: " + key)
        config.write_text(text, encoding="utf-8")
    run("compressed_texture_import", ["--editor", "--import"])
    run("mesh_bake", ["--script", "res://tools/bake_bg5_runtime.gd"])
    staged = report / "staged"
    receipt = json.loads((staged / "bake.json").read_text())
    for entry in receipt["assets"].values():
        for key in ("prefab", "glb"):
            if key not in entry:
                continue
            destination = ROOT / entry[key].removeprefix("res://")
            source = staged / destination.name
            for attempt in range(10):
                try:
                    source.replace(destination)
                    break
                except PermissionError:
                    if attempt == 9:
                        raise
                    time.sleep(0.2)
        # FileAccess/GLTFDocument consume these bytes directly, including in PCKs.
        # A scene import replaces the GLB with a PackedScene during export.
        config = ROOT / (entry["glb"].removeprefix("res://") + ".import")
        config.write_text('[remap]\n\nimporter="keep"\n', encoding="utf-8")
    run("runtime_import", ["--editor", "--import"])
    receipt_path = ROOT / "mods/bg5_runtime/bake.json"
    for path, entry in receipt["textures"].items():
        entry["sha256"] = sha(ROOT / path.removeprefix("res://"))
        entry["import_sha256"] = sha(ROOT / (path.removeprefix("res://") + ".import"))
    receipt_path.write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    verify()


if __name__ == "__main__":
    main()
