# SPDX-License-Identifier: 0BSD
"""Check source playback and exported audio using existing export filters."""
import argparse
from pathlib import Path
import shutil
import subprocess
import re

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True)
    args = parser.parse_args()
    folder = ROOT / "reports/audio_export"
    folder.mkdir(parents=True, exist_ok=True)

    def run(label, arguments, cwd=ROOT):
        result = subprocess.run([args.godot, *arguments], cwd=cwd, capture_output=True, text=True, timeout=90)
        log = result.stdout + "\n" + result.stderr
        (ROOT / f"reports/audio_{label}.log").write_text(log, encoding="utf-8")
        errors = re.search(r"(?m)^(?:SCRIPT ERROR|ERROR:|FAIL |WARNING:.*ObjectDB.*leak)", log)
        if result.returncode or errors:
            raise RuntimeError(f"{label} failed ({result.returncode}):\n{log[-5000:]}")
        print(f"PASS {label}")
        return log

    log = run("runtime", ["--headless", "--path", str(ROOT), "--script", "res://tests/audio_runtime.gd"])
    if "AUDIO_RUNTIME checks=" not in log:
        raise RuntimeError("Source checks did not finish")
    for name in ["addons/audio_runtime/catalog.gd", "addons/audio_runtime/audio_runtime.gd"]:
        target = folder / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / name, target)
        uid = ROOT / (name + ".uid")
        if uid.exists(): shutil.copyfile(uid, Path(str(target) + ".uid"))
    for name in ["addons/audio_runtime/packs/nox", "mods/example_audio"]:
        shutil.copytree(ROOT / name, folder / name, dirs_exist_ok=True)
    shutil.copyfile(ROOT / "tests/audio_runtime.gd", folder / "probe.gd")
    (folder / "project.godot").write_text('config_version=5\n[application]\nconfig/name="AudioExportCheck"\nconfig/features=PackedStringArray("4.7")\n')
    shutil.copyfile(ROOT / "export_presets.cfg", folder / "export_presets.cfg")
    run("import", ["--headless", "--editor", "--path", str(folder), "--import"])
    pack = folder / "audio.pck"
    run("export", ["--headless", "--path", str(folder), "--export-pack", "Windows Desktop", str(pack)])
    log = run("packed", ["--headless", "--main-pack", str(pack), "--script", "res://probe.gd"], folder)
    if "AUDIO_RUNTIME checks=" not in log:
        raise RuntimeError("Packed checks did not finish")
    print("AUDIO_CHECK source and isolated PCK passed")


if __name__ == "__main__":
    main()
