# SPDX-License-Identifier: 0BSD
"""Exercise commodity trading and its native save against release DLLs."""
import json
import shutil
import subprocess
from pathlib import Path
from run import ROOT, parse_args


def main():
    options, _ = parse_args()
    destination = ROOT / "reports" / "trader_release"
    destination.mkdir(parents=True, exist_ok=True)
    (destination / "project.godot").write_text('[application]\nconfig/name="Trader release check"\n', encoding="utf-8")
    for addon in ("player_runtime", "world_runtime"):
        source = ROOT / "addons" / addon
        target = destination / "addons" / addon
        (target / "bin").mkdir(parents=True, exist_ok=True)
        library = addon + ".windows.template_release.x86_64.dll"
        shutil.copy2(source / "bin" / library, target / "bin" / library)
        descriptor = (source / (addon + ".gdextension")).read_text().replace("template_debug", "template_release")
        (target / (addon + ".gdextension")).write_text(descriptor, encoding="utf-8")
    shutil.copy2(ROOT / "addons/player_runtime/trader_inventory.gd", destination / "addons/player_runtime/trader_inventory.gd")
    (destination / "tests").mkdir(exist_ok=True)
    for name in ("trader_inventory", "player_inventory"):
        source = (ROOT / "tests" / (name + ".gd")).read_text()
        if name == "trader_inventory":
            source = source.replace('func _initialize() -> void: run.call_deferred()', 'func _initialize() -> void:\n\tGDExtensionManager.load_extension("res://addons/player_runtime/player_runtime.gdextension")\n\tGDExtensionManager.load_extension("res://addons/world_runtime/world_runtime.gdextension")\n\trun.call_deferred()')
        (destination / "tests" / (name + ".gd")).write_text(source, encoding="utf-8")
    results = []
    for name, extra in (("trader_inventory", []), ("trader_inventory", ["--", "--restore"]), ("player_inventory", [])):
        label = name + ("_restore" if extra else "")
        log = destination / (label + ".log")
        command = [options.godot, "--headless", "--path", str(destination), "--log-file", str(log), "--script", "res://tests/" + name + ".gd", *extra]
        result = subprocess.run(command, capture_output=True, timeout=60)
        text = log.read_text(encoding="utf-8") if log.exists() else ""
        passed = result.returncode == 0 and name.upper() in text and not any(token in text for token in ("SCRIPT ERROR", "ERROR:", "FAIL ", "instances leaked"))
        results.append({"test":label, "passed":passed, "exit_code":result.returncode})
    (destination / "result.json").write_text(json.dumps(results, indent=2), encoding="utf-8")
    print(json.dumps(results, indent=2))
    return 0 if all(row["passed"] for row in results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
