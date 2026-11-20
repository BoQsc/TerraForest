# SPDX-License-Identifier: 0BSD
"""Launch independent authority and gameplay processes against an owned temporary world."""
import argparse
from datetime import datetime, timezone
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
from play_checkpoint import revision_metadata
from retained_artifacts import digest
from windows_process_metrics import ProcessMetrics

POINTS = [(239, 31, 224), (241, 31, 224), (256, 32, 224)]


def samples():
    return ["sample %d %d %d" % point for point in POINTS]


def run(engine, packaged, report):
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
                    owner.stdin.write("v1 1 excavate 240 31 224 3 0\n")
                    owner.stdin.flush()
                    assert lines.get(timeout=90)["ok"]
                    report["edit_round_trip_ms"] = (time.perf_counter()-started)*1000
                    report["idle_working_set_bytes"] = idle_metrics["working_set_bytes"]
                    report["peak_working_set_after_edit_bytes"] = with_metrics.sample()["peak_working_set_bytes"]
                    # Windows permits reading and copying the canonical archive
                    # through this handle but denies the final replacement.
                    with archive.open("rb") as pinned:
                        owner.stdin.write("save\n")
                        owner.stdin.flush()
                        assert not lines.get(timeout=90)["ok"]
                        assert hashlib.sha256(pinned.read()).digest() == original_digest
                    assert not list(archive.parent.glob(archive.name + ".pending.*"))
                finally:
                    with_metrics.close()
            finally:
                owner.kill()
                owner.wait(timeout=10)
        assert hashlib.sha256(archive.read_bytes()).digest()==original_digest
        first = "v1 1 excavate 240 31 224 3 0"
        invalid = ["v2 1 excavate 240 31 224 3 0", "v1 0 excavate 240 31 224 3 0",
                   "v1 3 excavate 240 31 224 3 1", "v1 1 excavate 240 31 224 4 0",
                   "v1 2 excavate 240 31 224 3 0", "excavate 240 31 224 3 0"]
        results = invoke(host, [first,first]+invalid+samples()+["save","quit"], "AUTHORITY ")
        assert results[0]["last_request_id"] == 0  # crashed unsaved receipt is gone
        ack = {"ok":True,"version":1,"request_id":1,"changed":True,"revision":1}
        assert results[1] == results[2] == ack and results[-1]["ok"]
        assert all(not row["ok"] for row in results[3:3+len(invalid)])
        changed = results[3+len(invalid):-1]
        restarted = invoke(host, [first]+samples()+["excavate 240 31 224 4 1",first,
                               "v1 2 excavate 240 31 224 5 2",first,"quit"], "AUTHORITY ")
        assert restarted[0]["last_request_id"] == 1 and restarted[1] == ack
        assert restarted[-4]["revision"] == 2 and restarted[-3] == ack
        assert restarted[-2]["ok"] and restarted[-2]["request_id"] == 2 and not restarted[-1]["ok"]
        reloaded = restarted[2:-4]
        report["operator_retry"] = {"reply":ack,"rejected_commands":invalid,
                                    "restored_reply":restarted[1],"older_id_rejected":True}
        assert hashlib.sha256(archive.with_suffix(".trw.bak").read_bytes()).digest()==original_digest
        for i,(before, after, restored) in enumerate(zip(original[1:4], changed, reloaded, strict=True)):
            assert after["revision"] == before["revision"] + 1
            for key in ("density","depth","water_ml","revision"):
                assert restored[key]==after[key], (key,after,restored)
            assert before["water_ml"]==after["water_ml"]
            if i==2:
                assert before["density"]==after["density"] and before["height"]==after["height"]
            else:
                assert after["density"]>before["density"] and after["depth"]>0
        script = ROOT/"tests/authority_gameplay.gd"
        game, = invoke(base+["--script",str(script)], [], "GAME_AUTHORITY ")
        for i,sample in enumerate(changed):
            assert game["revision"]==sample["revision"]
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
        report.update(before=original[1:4], after=changed, reloaded=reloaded, gameplay=game,
                      initial_archive_sha256=original_digest.hex(), passed=True)


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True,type=Path)
    parser.add_argument("--pack",action="store_true")
    args=parser.parse_args()
    admit(ROOT, report_bytes=65536, scratch_bytes=16 << 20, world_bytes=160 << 20)
    engine = args.godot.resolve()
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    folder = ROOT/"reports/checks"/stamp
    folder.mkdir()
    report = dict(test="dedicated_world", passed=False, utc=stamp, engine=str(engine),
                  points=POINTS, seed=1703, generator=17, brush=[240,31,224,3],
                  processor=os.environ.get("PROCESSOR_IDENTIFIER"), **revision_metadata())
    try:
        report["engine_sha256"] = digest(engine)
        if args.pack:
            report["pack_sha256"] = digest(ROOT/"dist/TerraForest.pck")
        libraries = (ROOT/"dist" if args.pack else ROOT)/"addons"
        report["native_sha256"] = {p.name:digest(p) for p in sorted(libraries.glob("*/bin/*.dll"))}
        run(engine,args.pack,report)
    except Exception as error:
        report["error"] = repr(error)
        raise
    finally:
        evidence = folder/"dedicated_world.json"
        evidence.write_text(json.dumps(report,indent=2),encoding="utf-8")
        print("PASS" if report["passed"] else "FAIL", evidence)
