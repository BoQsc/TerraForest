# SPDX-License-Identifier: 0BSD
"""Render natural-hillside cave fixtures without activating/capturing the mouse."""
import datetime
import json
import subprocess
from run import ROOT, parse_args
from play_checkpoint import revision_metadata
from run_godot_check import execute


def main():
    config, _ = parse_args([])
    folder = ROOT / "reports/exploration_review" / datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    folder.mkdir(parents=True)
    command = [config.godot, "--path", str(ROOT), "--windowed", "--position", "-2400,-1600", "--resolution", "1600x900", "--max-fps", "60", "--log-file", str(folder / "engine.log"), "--script", "res://tests/exploration_review.gd", "--", "--temporary", "--review-output=" + folder.as_posix()]
    original = subprocess.Popen

    def nonactivating(*arguments, **keywords):
        startup = subprocess.STARTUPINFO()
        startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
        startup.wShowWindow = 4
        keywords["startupinfo"] = startup
        return original(*arguments, **keywords)

    subprocess.Popen = nonactivating
    try:
        result = execute(command, folder, 240, "EXPLORATION_REVIEW checks=", require_resource_budget=True)
    finally:
        subprocess.Popen = original
    (folder / "run.json").write_text(json.dumps(dict(command=command, result=result, **revision_metadata()), indent=2) + "\n")
    print(("PASS " if result["passed"] else "FAIL ") + str(folder), flush=True)
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
