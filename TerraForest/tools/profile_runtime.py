"""Capture offscreen gameplay, walking or speed-sweep profiles without modifying saves."""
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
    for phase in dict.fromkeys(row["phase"] for row in frames):
        rows = [row for row in frames if row["phase"] == phase]
        if not rows:
            continue
        metrics = {key: distribution([row[key] for row in rows]) for key in
                   ("frame_ms", "process_ms", "gpu_ms", "render_cpu_ms", "ecosystem_us", "cover_us")}
        for key in ("draw_calls", "ground_render_us", "ground_upload_us", "ground_selection_us", "ground_cleanup_us"):
            values = [row[key] for row in rows if key in row]
            if values:
                metrics[key] = distribution(values)
        metrics["stages_ms"] = {stage: distribution([row["stages"][stage] for row in rows
                                                    if stage in row["stages"]])
                               for stage in sorted({stage for row in rows for stage in row["stages"]})}
        result[phase] = metrics
    return result


def gameplay_gates(gameplay, frames):
    contacts = gameplay.get("contacts", [])
    changed = [contact for contact in contacts if contact.get("changed", False)]
    gates = {"all_24_contacts_changed": len(contacts) == 24 and len(changed) == 24,
             "physical_jumps": gameplay.get("jumps", 0) >= 3,
             "contact_to_draw_max_150ms": len(changed) == 24 and all(
                 0 <= contact.get("contact_to_draw_ms", float("inf")) <= 150 for contact in changed)}
    for phase in ("idle", "walking", "sprinting", "jumping", "mining_idle", "mining_after_run", "mining_after_jump", "recovery"):
        values = sorted(row["frame_ms"] for row in frames if row["phase"] == phase)
        gates[phase + "_frame_p99_20ms_max_50ms"] = bool(values) and (
            values[min(len(values) - 1, int(len(values) * .99))] <= 20 and values[-1] <= 50)
    return gates


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--slot", required=True)
    parser.add_argument("--pack", action="store_true")
    parser.add_argument("--gameplay", action="store_true", help="Measure pickaxe contact-to-draw, walking, sprinting and physical jumping")
    parser.add_argument("--require-gameplay-performance", action="store_true", help="Fail the command if any gameplay timing gate fails")
    parser.add_argument("--label", default="profile")
    parser.add_argument("--require-resource-budget", action="store_true")
    parser.add_argument("--speed-sweep", "--driving", dest="driving", action="store_true", help="Controlled road-camera speed sweep, not a vehicle handling qualification")
    parser.add_argument("--speed-kph", type=float, default=100)
    parser.add_argument("--ground-upload-kib", type=int, choices=[0, 8, 16, 32, 64], default=0, help="Controlled speed-sweep renderer experiment; zero uses production settings")
    args = parser.parse_args()
    if args.gameplay and args.driving:
        parser.error("Gameplay and speed-sweep workloads are separate")
    if args.require_gameplay_performance and not args.gameplay:
        parser.error("Gameplay performance gates require --gameplay")
    if not args.label.isidentifier():
        parser.error("Label must be an identifier")
    config, _ = parse_args([])
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    folder = ROOT / "reports/runtime_performance" / (stamp + "_" + args.label)
    folder.mkdir(parents=True)
    test = "gameplay_performance" if args.gameplay else ("vegetation_driving_profile" if args.driving else "runtime_travel_profile")
    source = ROOT / "tests" / (test + ".gd")
    extra = ["--profile-slot=" + args.slot, "--profile-dir=" + folder.as_posix()]
    if args.driving:
        extra.append("--drive-kph=" + str(args.speed_kph))
        extra.append("--ground-upload-kib=" + str(args.ground_upload_kib))
    command, cache = command_for(config.godot, test, folder, extra)
    command.remove("--fullscreen")
    command[1:1] = ["--windowed", "--position", "-2400,-1600"]
    record = dict(command=command, cache=cache, mode="gameplay" if args.gameplay else ("controlled_speed_sweep" if args.driving else "walking"), source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
                  native_sha256={str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
                                 for path in (ROOT / "addons").glob("*/bin/*.dll")}, **revision_metadata())
    if args.pack:
        verify_pack_native()
        command[1:1] = ["--main-pack", str(ROOT / "dist/TerraForest.pck")]
        command[command.index("--path") + 1] = str(ROOT / "dist")
        driver = folder / "profile.gd"
        driver_text = source.read_text(encoding="utf-8")
        if args.driving or args.gameplay:
            base = folder / "runtime_travel_profile.gd"
            base.write_bytes((ROOT / "tests/runtime_travel_profile.gd").read_bytes())
            record["base_source_sha256"] = hashlib.sha256(base.read_bytes()).hexdigest()
            driver_text = driver_text.replace("res://tests/runtime_travel_profile.gd", base.as_posix())
        driver.write_text(driver_text, encoding="utf-8")
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
    gameplay_path = folder / "gameplay.json"
    if args.gameplay and gameplay_path.exists() and samples.exists():
        gameplay = json.loads(gameplay_path.read_text(encoding="utf-8"))
        record["gameplay_gates"] = gameplay_gates(gameplay, data["frames"])
        record["performance_passed"] = all(record["gameplay_gates"].values())
    manifest.write_text(json.dumps(record, indent=2), encoding="utf-8")
    print(("FUNCTIONAL " if args.gameplay else "") + ("PASS " if record["result"]["passed"] else "FAIL ") + str(folder))
    if args.gameplay:
        print("GAMEPLAY PERFORMANCE " + ("PASS" if record.get("performance_passed", False) else "FAIL / inspect retained timings"))
    return 0 if record["result"]["passed"] and (not args.require_gameplay_performance or record.get("performance_passed", False)) else 1


if __name__ == "__main__":
    raise SystemExit(main())
