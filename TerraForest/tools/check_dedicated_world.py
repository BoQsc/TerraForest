# SPDX-License-Identifier: 0BSD
"""Launch independent authority and gameplay processes against an owned temporary world."""
import argparse
import hashlib
import json
from queue import Queue
from threading import Thread
import math
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

from development_storage import ROOT, admit
from windows_process_metrics import ProcessMetrics

POINTS = [(239, 31, 224), (241, 31, 224), (256, 32, 224)]


def samples():
    return ["sample %d %d %d" % point for point in POINTS]


def run(engine, packaged):
    admit(ROOT, report_bytes=65536, scratch_bytes=16 << 20, world_bytes=160 << 20)
    with tempfile.TemporaryDirectory(prefix="terraforest-authority-") as temp:
        env = dict(os.environ, APPDATA=temp)
        base = [str(engine), "--headless", "--path", str(ROOT / "dist" if packaged else ROOT)]
        if packaged:
            base += ["--main-pack", str(ROOT / "dist/TerraForest.pck")]
        host = base + ["--script", "res://addons/world_runtime/dedicated_main.gd", "--", "--authority-slot=AuthorityCheck"]

        def invoke(command, lines, prefix):
            child = subprocess.run(command, cwd=ROOT, input="\n".join(lines)+"\n", env=env,
                                   capture_output=True, text=True, timeout=240,
                                   creationflags=subprocess.CREATE_NO_WINDOW)
            if child.returncode or "ERROR:" in child.stderr:
                raise RuntimeError((child.stdout+"\n"+child.stderr)[-4000:])
            return [json.loads(row[len(prefix):]) for row in child.stdout.splitlines() if row.startswith(prefix)]

        original = invoke(host, samples()+["save", "quit"], "AUTHORITY ")
        assert original[-1]["ok"] and original[0]["ready"]
        archive, = Path(temp).rglob("AuthorityCheck.trw")
        game_input = archive.parent.parent / "worlds" / archive.name
        game_input.parent.mkdir(exist_ok=True)
        shutil.copyfile(archive, game_input)
        # A live owner holds the archive until process exit. Kill only this
        # test-owned child after an unsaved edit, then check canonical bytes.
        original_digest = hashlib.sha256(archive.read_bytes()).digest()
        with subprocess.Popen(host, cwd=ROOT, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE, text=True, env=env,
                              creationflags=subprocess.CREATE_NO_WINDOW) as owner:
            try:
                lines = Queue()
                def collect():
                    for line in owner.stdout:
                        if line.startswith("AUTHORITY "):
                            lines.put(json.loads(line.removeprefix("AUTHORITY ")))
                reader = Thread(target=collect, daemon=True)
                reader.start()
                assert lines.get(timeout=90)["ready"]
                with_metrics = ProcessMetrics(owner.pid)
                try:
                    idle_metrics = with_metrics.sample()
                    rival = subprocess.run(host, cwd=ROOT, input="quit\n", env=env,
                                           capture_output=True, text=True, timeout=30,
                                           creationflags=subprocess.CREATE_NO_WINDOW)
                    assert rival.returncode and "could not acquire" in rival.stderr
                    started = time.perf_counter()
                    owner.stdin.write("excavate 240 31 224 3 0\n")
                    owner.stdin.flush()
                    assert lines.get(timeout=90)["ok"]
                    print("Operator edit round trip ms", round((time.perf_counter()-started)*1000,2),
                          "idle working set", idle_metrics["working_set_bytes"],
                          "peak working set", with_metrics.sample()["peak_working_set_bytes"])
                finally:
                    with_metrics.close()
            finally:
                owner.kill()
                owner.wait(timeout=10)
        assert hashlib.sha256(archive.read_bytes()).digest()==original_digest
        results = invoke(host, ["excavate 240 31 224 3 0", "excavate 240 31 224 3 0"]+samples()+["save","quit"], "AUTHORITY ")
        assert results[1]["ok"] and not results[2]["ok"] and results[-1]["ok"]
        changed = results[3:6]
        reloaded = invoke(host, samples()+["quit"], "AUTHORITY ")[1:]
        assert hashlib.sha256(archive.with_suffix(".trw.bak").read_bytes()).digest()==original_digest
        for i,(before, after, restored) in enumerate(zip(original[1:4], changed, reloaded, strict=True)):
            for key in ("density","depth","water_ml"):
                assert restored[key]==after[key], (key,after,restored)
            assert before["water_ml"]==after["water_ml"]
            if i==2:
                assert before["density"]==after["density"]
            else:
                assert after["density"]>before["density"] and after["depth"]>0
        script = ROOT/"tests/authority_gameplay.gd"
        game, = invoke(base+["--script",str(script)], [], "GAME_AUTHORITY ")
        for i,sample in enumerate(changed):
            assert game["water_ml"]==sample["water_ml"]
            for key in ("density","depth"):
                assert math.isclose(game[key][i],sample[key],abs_tol=1e-4), (i,key,game[key][i],sample[key])
        # Corrupt only our disposable canonical file. Failure must preserve the
        # input for recovery and leave its verified backup intact.
        corrupt = archive.read_bytes()[:64]
        archive.write_bytes(corrupt)
        rejected = subprocess.run(host, cwd=ROOT, input="save\nquit\n", env=env,
                                  capture_output=True, text=True, timeout=30,
                                  creationflags=subprocess.CREATE_NO_WINDOW)
        assert rejected.returncode and archive.read_bytes()==corrupt
        assert hashlib.sha256(archive.with_suffix(".trw.bak").read_bytes()).digest()==original_digest
        print("PASS dedicated restart, stale revision, local-game density, depth and water conservation", changed)


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True,type=Path)
    parser.add_argument("--pack",action="store_true")
    args=parser.parse_args()
    run(args.godot.resolve(),args.pack)
