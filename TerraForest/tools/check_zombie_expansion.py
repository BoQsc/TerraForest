# SPDX-License-Identifier: 0BSD
"""Bounded native or nonactivating ordinary-world encounter expansion checks."""
import argparse
import datetime
import hashlib
import json
import shutil
import subprocess

from play_checkpoint import revision_metadata
from run import ROOT, parse_args
from run_godot_check import command_for, execute, verify_pack_native


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=["native", "world"])
    parser.add_argument("--release", action="store_true")
    parser.add_argument("--pack", action="store_true")
    args = parser.parse_args()
    if (args.release and args.mode != "native") or (args.pack and args.mode != "world"):
        parser.error("Use --release with native, or --pack with world")
    config, _ = parse_args([])
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    report = ROOT / "reports/zombie_expansion" / stamp
    report.mkdir(parents=True)
    record = dict(mode=args.mode, release=args.release, pack=args.pack, results=[], **revision_metadata())
    project = ROOT
    if args.release:
        project = ROOT / ".build/zombie_expansion_release"
        project.mkdir(parents=True, exist_ok=True)
        (project / "project.godot").write_text('config_version=5\n[application]\nconfig/name="Zombie Expansion Release Check"\n')
        addon = project / "addons/world_runtime"
        (addon / "bin").mkdir(parents=True, exist_ok=True)
        library = "world_runtime.windows.template_release.x86_64.dll"
        shutil.copy2(ROOT / "addons/world_runtime/bin" / library, addon / "bin" / library)
        source = ROOT / "addons/world_runtime/world_runtime.gdextension"
        (addon / source.name).write_text(source.read_text().replace("template_debug", "template_release"))
        record["release_sha256"] = hashlib.sha256((addon / "bin" / library).read_bytes()).hexdigest()
        for relative in ["addons/characters/runtime/assets/zombie.encounters.json", *[f"tests/{name}.gd" for name in ["zombie_expansion", "zombie_awareness", "zombie_population", "zombie_anatomy"]]]:
            target = project / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / relative, target)
    if args.mode == "native":
        for name in ["zombie_expansion", "zombie_awareness", "zombie_population", "zombie_anatomy"]:
            folder = report / name
            folder.mkdir()
            command = [config.godot, "--headless", "--path", str(project), "--log-file", str(folder / "engine.log"), "--script", f"res://tests/{name}.gd"]
            if name == "zombie_population":
                command += ["--", "--population-output=" + folder.as_posix()]
            result = execute(command, folder, 30, name.upper() + " checks=")
            record["results"].append(dict(test=name, command=command, result=result))
            print(("PASS " if result["passed"] else "FAIL ") + name, flush=True)
        folder = report / "fresh_population"
        folder.mkdir()
        command = [config.godot, "--headless", "--path", str(project), "--log-file", str(folder / "engine.log"), "--script", "res://tests/zombie_population.gd", "--", "--population-read=" + (report / "zombie_population/population_extended.bin").as_posix(), "--population-output=" + folder.as_posix()]
        record["results"].append(dict(test="fresh_population", command=command, result=execute(command, folder, 30, "ZOMBIE_POPULATION checks=")))
    else:
        command, cache = command_for(config.godot, "zombie_variety_world", report, ["--gameplay-construction", "--zombies", "--world-seed=1703", "--view-output=" + report.as_posix()])
        command.remove("--fullscreen")
        command[1:1] = ["--windowed", "--position", "-2400,-1600"]
        if args.pack:
            record["native_sha256"] = verify_pack_native()
            driver = report / "driver.gd"
            driver.write_bytes((ROOT / "tests/zombie_variety_world.gd").read_bytes())
            command[1:1] = ["--main-pack", str(ROOT / "dist/TerraForest.pck")]
            command[command.index("--path") + 1] = str(ROOT / "dist")
            command[command.index("--script") + 1] = str(driver)
            record["pack_sha256"] = hashlib.sha256((ROOT / "dist/TerraForest.pck").read_bytes()).hexdigest()
        original = subprocess.Popen

        def nonactivating(*arguments, **keywords):
            startup = subprocess.STARTUPINFO()
            startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
            startup.wShowWindow = 4
            keywords["startupinfo"] = startup
            return original(*arguments, **keywords)

        subprocess.Popen = nonactivating
        try:
            result = execute(command, report, 180, "ZOMBIE_VARIETY_WORLD checks=", require_resource_budget=True)
        finally:
            subprocess.Popen = original
        record["results"].append(dict(test="world", command=command, cache=cache, result=result))
    record["passed"] = all(row["result"]["passed"] for row in record["results"])
    (report / "run.json").write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
    print(("PASS " if record["passed"] else "FAIL ") + str(report), flush=True)
    return 0 if record["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
