# SPDX-License-Identifier: 0BSD
"""Run a repository check with a fresh derived-cache path and retained provenance.

This is cache isolation, not a filesystem sandbox. Tests must still protect saves.
"""
import argparse
import datetime
import hashlib
import json
import re
import subprocess
import time
import uuid
from pathlib import Path

from play_checkpoint import revision_metadata
from run import ROOT, parse_args
from cache_retention import finalize_cache
from resource_limits import ResourceMonitor, require_free_space


def verify_pack_native(root=ROOT):
    def hashes(folder):
        return {str(path.relative_to(folder)): hashlib.sha256(path.read_bytes()).hexdigest()
                for path in sorted((folder / "addons").glob("*/bin/*.dll"))}
    source = hashes(root)
    if not source or source != hashes(root / "dist"):
        raise ValueError("External test scripts resolve native libraries from the project; re-export matching dist libraries before packaged validation")
    return source


def command_for(engine, test, folder, extra, headless=False, persistent=False):
    if not re.fullmatch(r"[a-z][a-z0-9_]{0,63}", test):
        raise ValueError("Test must be a simple repository test name")
    if not (ROOT / "tests" / (test + ".gd")).is_file():
        raise ValueError("Repository test does not exist")
    reserved = {"--derived-cache", "--no-derived-cache", "--temporary",
                "--snapshot-readonly", "--world-slot"}
    if any(arg.split("=", 1)[0] in reserved or arg == "--" for arg in extra):
        raise ValueError("Cache and temporary-world options belong to this launcher")
    if persistent and test != "water_static_compound":
        raise ValueError("Persistent mode is restricted to the isolated water compound-save check")
    token = uuid.uuid4().hex
    cache = f"user://{test}_{token}"
    command = [str(engine), "--path", str(ROOT), "--log-file", str(folder / "engine.log"),
               *(["--headless"] if headless else ["--fullscreen", "--resolution", "1920x1080"]),
               "--max-fps", "60", "--script", f"res://tests/{test}.gd", "--",
               *([f"--world-slot=water_compound_check_{token}"] if persistent else ["--temporary", f"--world-slot=check_{token}"]), f"--derived-cache={cache}", *extra]
    return command, cache


def execute(command, folder, timeout, required_text, cancel_requested=None, require_resource_budget=False):
    started = time.monotonic()
    result = {"timed_out": False, "launch_error": None, "cancelled": False}
    log_path = folder / "console.log"
    monitor = None
    game_process = any(name in Path(str(command[0])).name.lower() for name in ("godot", "terraforest"))
    with log_path.open("w", encoding="utf-8") as output:
        try:
            if game_process:
                require_free_space(ROOT)
            process = subprocess.Popen(command, cwd=ROOT, stdout=output, stderr=subprocess.STDOUT,
                                       creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
            result["pid"] = process.pid
            try:
                if game_process:
                    monitor = ResourceMonitor(process.pid)
                deadline = started + timeout
                while process.poll() is None:
                    if cancel_requested is not None and cancel_requested():
                        result["cancelled"] = True
                        process.kill()
                        break
                    if monitor:
                        monitor.sample()
                    remaining = deadline - time.monotonic()
                    if remaining <= 0: raise subprocess.TimeoutExpired(command, timeout)
                    try: process.wait(timeout=min(0.2, remaining))
                    except subprocess.TimeoutExpired: pass
                result["exit_code"] = process.wait()
            except subprocess.TimeoutExpired:
                process.kill()
                result["exit_code"] = process.wait()
                result["timed_out"] = True
            finally:
                # Only the child represented by this owned Popen handle is stopped.
                if process.poll() is None:
                    process.kill()
                    process.wait()
                if monitor:
                    result["resources"] = monitor.report()
                    monitor.close()
        except OSError as error:
            result.update(exit_code=None, launch_error=str(error))
    log = log_path.read_text(encoding="utf-8", errors="replace")
    engine_log = folder / "engine.log"
    diagnostic_text = log + ("\n" + engine_log.read_text(encoding="utf-8", errors="replace")
                             if engine_log.exists() else "")
    result["diagnostics"] = sorted(set(re.findall(
        r"(?m)^\s*(?:SCRIPT ERROR:|ERROR:|FAIL\b|WARNING: (?:[0-9]+ )?ObjectDB instances? (?:(?:was|were) )?leaked)[^\r\n]*",
        diagnostic_text)))
    result["required_text_found"] = required_text in log
    result["elapsed_seconds"] = time.monotonic() - started
    for name, check in result.get("resources", {}).get("checks", {}).items():
        if check["status"] in ("warning", "exceeded"):
            print(f"RESOURCE_BUDGET {name}: {check['status']} ({check['bytes'] / 2**30:.2f} GiB)", flush=True)
    result["passed"] = (result["exit_code"] == 0 and not result["timed_out"]
                        and not result["cancelled"] and not result["diagnostics"] and result["required_text_found"]
                        and not result.get("resources", {}).get("exceeded", False))
    if require_resource_budget and not result.get("resources", {}).get("within_sampled_limits", False):
        result["passed"] = False
        result["resource_gate"] = "Complete process RAM/VRAM telemetry within limits was required"
    try:
        result["cache_retention"] = finalize_cache(command, result["passed"])
    except (OSError, ValueError) as error:
        result["cache_retention"] = {"error": str(error), "retained": True}
    return result


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("test", help="tests/<name>.gd")
    parser.add_argument("--godot")
    parser.add_argument("--headless", action="store_true")
    parser.add_argument("--persistent", action="store_true", help="Unique disposable save slot; water_static_compound only")
    parser.add_argument("--timeout", type=float, default=90)
    parser.add_argument("--require", required=True, help="Successful completion text in console output")
    parser.add_argument("--dry-run", action="store_true")
    # Test-specific arguments must follow the explicit separator.
    import sys
    values = list(sys.argv[1:] if argv is None else argv)
    split = values.index("--") if "--" in values else len(values)
    args = parser.parse_args(values[:split])
    if not 0 < args.timeout <= 600 or not args.require.strip():
        parser.error("Use a positive timeout up to 600 seconds and nonempty completion text")
    config, _ = parse_args(["--godot", args.godot] if args.godot else [])
    engine = Path(config.godot).resolve()
    if not engine.is_file():
        parser.error("Godot executable does not exist")
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    folder = ROOT / "reports" / "checks" / stamp
    try:
        command, cache = command_for(engine, args.test, folder, values[split+1:], args.headless, args.persistent)
    except ValueError as error:
        parser.error(str(error))
    details = dict(command=command, cache=cache, utc=stamp, timeout=args.timeout,
                   required_text=args.require, headless=args.headless, persistent=args.persistent,
                   scope="Fresh derived-cache argument; test code must honor it. Not save isolation or a sandbox.",
                   cache_retained=None, **revision_metadata())
    details["engine_sha256"] = hashlib.sha256(engine.read_bytes()).hexdigest()
    details["test_sha256"] = hashlib.sha256((ROOT / "tests" / (args.test+".gd")).read_bytes()).hexdigest()
    details["native_sha256"] = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest()
                               for p in sorted((ROOT / "addons").glob("*/bin/*.dll"))}
    if args.dry_run:
        print(json.dumps(details, indent=2))
        return 0
    folder.mkdir(parents=True)
    manifest = folder / "run.json"
    manifest.write_text(json.dumps(details, indent=2)+"\n", encoding="utf-8")
    details["result"] = execute(command, folder, args.timeout, args.require)
    retention = details["result"].get("cache_retention", {})
    details["cache_retained"] = retention.get("retained", retention.get("retained_bytes", 0) > 0) if retention.get("managed") or retention.get("error") else None
    manifest.write_text(json.dumps(details, indent=2)+"\n", encoding="utf-8")
    print(("PASS " if details["result"]["passed"] else "FAIL ") + str(folder), flush=True)
    return 0 if details["result"]["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
