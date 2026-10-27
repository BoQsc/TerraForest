"""Compare actual pre-protection Git runtime against the working runtime without changing either checkout."""
import argparse
import datetime
import hashlib
import json
import os
import shutil
import subprocess
from pathlib import Path

from PIL import Image, ImageChops, ImageStat
from run import ROOT, parse_args
from run_godot_check import execute


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def git_digest(path):
    checksum = hashlib.sha1(("blob " + str(path.stat().st_size) + "\0").encode())
    with path.open("rb") as source:
        for block in iter(lambda: source.read(8 * 1024 * 1024), b""):
            checksum.update(block)
    return checksum.hexdigest()


def shared_import(source, destination):
    if Path(destination).exists():
        if not os.path.samefile(source, destination):
            raise ValueError("Existing derived import is not the expected shared file")
    else:
        os.link(source, destination)
    return destination


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--revision", default="ec05af0c")
    parser.add_argument("--directory", required=True, type=Path)
    options = parser.parse_args()
    directory = options.directory.resolve()
    directory.mkdir(parents=True, exist_ok=True)
    baseline = directory / "runtime-checkpoint/TerraForest"
    revision = subprocess.check_output(["git", "rev-parse", "--verify", options.revision + "^{commit}"], cwd=ROOT, text=True).strip()
    if not baseline.exists():
        listing = subprocess.check_output(["git", "ls-tree", "-r", revision, "--", "TerraForest/project.godot", "TerraForest/addons", "TerraForest/demo", "TerraForest/vehicle_demo"], cwd=ROOT.parent, text=True)
        shared = []
        for line in listing.splitlines():
            metadata, name = line.split("\t", 1)
            mode, kind, identity = metadata.split()
            relative = Path(name).relative_to("TerraForest")
            if "/authoring/" in name or "/ZombieLab/" in name or "/native/" in name or "/tests/" in name:
                continue
            if ".." in relative.parts or relative.is_absolute() or mode not in {"100644", "100755"} or kind != "blob":
                raise ValueError("Unexpected checkpoint entry: " + name)
            source = ROOT / relative
            target = baseline / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            if source.is_file() and source.suffix.lower() not in {".gd", ".gdshader", ".gdshaderinc", ".tres", ".json", ".cfg", ".godot", ".import", ".uid"} and git_digest(source) == identity:
                os.link(source, target)
                shared.append(dict(path=relative.as_posix(), git_blob=identity))
            else:
                target.write_bytes(subprocess.check_output(["git", "cat-file", "blob", identity], cwd=ROOT))
        (directory / "verified-shared-assets.json").write_text(json.dumps(shared, indent=2) + "\n")
        (directory / "runtime-checkpoint-revision.txt").write_text(revision + "\n")
    elif (directory / "runtime-checkpoint-revision.txt").read_text().strip() != revision:
        raise ValueError("Existing checkpoint belongs to a different revision")
    if (baseline / "addons/player_runtime/first_person_view.gd").exists():
        raise ValueError("Baseline already contains the clipping system")
    current_native = {str(path.relative_to(ROOT)): digest(path) for path in (ROOT / "addons").glob("*/bin/*.dll")}
    old_native = {str(path.relative_to(baseline)): digest(path) for path in (baseline / "addons").glob("*/bin/*.dll")}
    if current_native != old_native:
        raise ValueError("Native libraries differ; independently qualify the historical build before comparing")
    print("Checkpoint extracted; reusing unchanged derived imports in a separate copy", flush=True)
    shutil.copytree(ROOT / ".godot/imported", baseline / ".godot/imported", copy_function=shared_import, dirs_exist_ok=True)
    for name in ["extension_list.cfg", "global_script_class_cache.cfg"]:
        shutil.copy2(ROOT / ".godot" / name, baseline / ".godot" / name)
    driver = directory / "checkpoint_driver.gd"
    driver.write_bytes((ROOT / "tests/first_person_checkpoint.gd").read_bytes())
    settings, _ = parse_args([])
    runs = {}
    for label, project in [("before", baseline), ("after", ROOT)]:
        output = directory / label
        output.mkdir(exist_ok=True)
        command = [str(settings.godot), "--path", str(project), "--windowed", "--resolution", "1920x1080", "--max-fps", "60",
                   "--log-file", str(output / "engine.log"), "--script", str(driver), "--", "--temporary", "--checkpoint-evidence=" + str(output)]
        runs[label] = execute(command, output, 180, "FIRST_PERSON_CHECKPOINT captures=")
        print(label, runs[label]["passed"], flush=True)
        if not runs[label]["passed"]:
            (directory / "failed-run.json").write_text(json.dumps(runs, indent=2) + "\n")
            return 1
    comparisons = []
    historical = json.loads((directory / "before/result.json").read_text())
    current = json.loads((directory / "after/result.json").read_text())
    if not historical["historical_runtime"] or current["historical_runtime"]:
        raise ValueError("Comparison did not exercise the expected old and new runtimes")
    for path, actual in historical["source_sha256"].items():
        original = subprocess.check_output(["git", "show", revision + ":TerraForest/" + path[6:]], cwd=ROOT)
        if hashlib.sha256(original).hexdigest() != actual:
            raise ValueError("Historical runtime did not load checkpoint source: " + path)
    for label in historical["captures"]:
        old = directory / "before" / (label + ".png")
        new = directory / "after" / (label + ".png")
        difference = ImageChops.difference(Image.open(old).convert("RGB"), Image.open(new).convert("RGB"))
        mean = max(ImageStat.Stat(difference).mean) / 255
        hands = max(ImageStat.Stat(difference.crop((960, 700, 1600, 1080))).mean) / 255
        comparisons.append(dict(scene=label, mean_rgb_error=mean, hands_rgb_error=hands, before_sha256=digest(old), after_sha256=digest(new), passed=mean < .0005 and hands < .0005))
    record = dict(utc=datetime.datetime.now(datetime.timezone.utc).isoformat(), baseline_revision=revision, actual_historical_runtime=True,
                  baseline_project=str(baseline), current_project=str(ROOT), driver_sha256=digest(driver), native_sha256=current_native,
                  historical=historical, current=current,
                  current_runtime_sha256={name: digest(ROOT / name) for name in ["addons/player_runtime/first_person_view.gd", "addons/player_runtime/first_person_meshes.gd", "addons/player_runtime/first_person_depth.gd", "addons/characters/runtime/torch_flame.gdshader", "addons/characters/runtime/torch_motes.gdshader"]},
                  runs=runs, comparisons=comparisons, passed=all(item["passed"] for item in comparisons),
                  scope="Same Godot binary, native libraries, driver, poses, cameras, frozen torch clocks and production assets. Actual Git checkpoint runtime versus current protected default. Current SSAO/SSR are disabled; not an exhaustive renderer qualification.")
    (directory / "comparison.json").write_text(json.dumps(record, indent=2) + "\n")
    print("PASS" if record["passed"] else "FAIL", len(comparisons), "historical comparisons", directory, flush=True)
    return 0 if record["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
