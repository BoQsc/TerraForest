"""Capture comparable offscreen walking profiles without modifying saved worlds."""
import argparse
import datetime
import hashlib
import json
import subprocess

from play_checkpoint import revision_metadata
from run import ROOT, parse_args
from run_godot_check import command_for, execute, verify_pack_native


def summarize(frames):
    def distribution(values):
        values = sorted(values)
        return dict(samples=len(values), mean=sum(values) / len(values),
                    p95=values[min(len(values) - 1, int(len(values) * .95))], maximum=values[-1])

    result = {}
    for phase in ("idle", "walking", "recovery"):
        rows = [row for row in frames if row["phase"] == phase]
        if not rows:
            continue
        metrics = {key: distribution([row[key] for row in rows]) for key in
                   ("frame_ms", "process_ms", "gpu_ms", "render_cpu_ms", "ecosystem_us", "cover_us")}
        metrics["stages_ms"] = {stage: distribution([row["stages"][stage] for row in rows
                                                    if stage in row["stages"]])
                               for stage in sorted({stage for row in rows for stage in row["stages"]})}
        result[phase] = metrics
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--slot", required=True)
    parser.add_argument("--pack", action="store_true")
    parser.add_argument("--label", default="profile")
    parser.add_argument("--require-resource-budget", action="store_true")
    args = parser.parse_args()
    if not args.label.isidentifier():
        parser.error("Label must be an identifier")
    config, _ = parse_args([])
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    folder = ROOT / "reports/runtime_performance" / (stamp + "_" + args.label)
    folder.mkdir(parents=True)
    source = ROOT / "tests/runtime_travel_profile.gd"
    command, cache = command_for(config.godot, "runtime_travel_profile", folder,
                                 ["--profile-slot=" + args.slot, "--profile-dir=" + folder.as_posix()])
    command.remove("--fullscreen")
    command[1:1] = ["--windowed", "--position", "-2400,-1600"]
    record = dict(command=command, cache=cache, source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
                  native_sha256={str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
                                 for path in (ROOT / "addons").glob("*/bin/*.dll")}, **revision_metadata())
    if args.pack:
        verify_pack_native()
        command[1:1] = ["--main-pack", str(ROOT / "dist/TerraForest.pck")]
        command[command.index("--path") + 1] = str(ROOT / "dist")
        driver = folder / "profile.gd"
        driver.write_bytes(source.read_bytes())
        command[command.index("--script") + 1] = str(driver)
        record["pack_sha256"] = hashlib.sha256((ROOT / "dist/TerraForest.pck").read_bytes()).hexdigest()
    manifest = folder / "run.json"
    manifest.write_text(json.dumps(record, indent=2), encoding="utf-8")
    original = subprocess.Popen

    def nonactivating(*arguments, **keywords):
        startup = subprocess.STARTUPINFO()
        startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        startup.wShowWindow = 4
        keywords["startupinfo"] = startup
        return original(*arguments, **keywords)

    subprocess.Popen = nonactivating
    try:
        record["result"] = execute(command, folder, 240, "TRAVEL_PROFILE PASS", require_resource_budget=args.require_resource_budget)
    finally:
        subprocess.Popen = original
    samples = folder / "frames.json"
    if samples.exists():
        data = json.loads(samples.read_text(encoding="utf-8"))
        record["summary"] = summarize(data["frames"])
    manifest.write_text(json.dumps(record, indent=2), encoding="utf-8")
    print(("PASS " if record["result"]["passed"] else "FAIL ") + str(folder))
    return 0 if record["result"]["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
