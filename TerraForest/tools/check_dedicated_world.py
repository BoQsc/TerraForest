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
from statistics import median
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


def check_query_burst(owner, lines):
    # Compare equal point workloads on one settled revision, including IPC,
    # JSON decoding and client receipt. Send each eight-point set in one flush.
    points = (POINTS * 3)[:8]
    triples = ["%d %d %d" % p for p in points]
    singles = "\n".join("sample " + triple for triple in triples)
    batch = "v1 sample " + " ".join(triples)
    timings = {"single_requests": [], "batch_request": []}
    for iteration in range(33):
        reference = {}
        order = list(timings) if iteration % 2 == 0 else list(reversed(timings))
        for mode in order:
            single = mode == "single_requests"
            start = time.perf_counter_ns()
            owner.stdin.write((singles if single else batch) + "\n")
            owner.stdin.flush()
            replies = [lines.get(timeout=10) for _ in range(8 if single else 1)]
            elapsed_us = (time.perf_counter_ns() - start) / 1000
            assert all(reply["ok"] and reply["revision"] == 1 for reply in replies)
            if single:
                assert all(reply["water_ml"] == replies[0]["water_ml"] for reply in replies)
                rows = [{key: reply[key] for key in ("height", "density", "depth")} for reply in replies]
            else:
                assert replies[0]["version"] == 1 and len(replies[0]["samples"]) == 8
                rows = replies[0]["samples"]
            reference[mode] = (replies[0]["water_ml"], rows)
            if iteration:
                timings[mode].append(elapsed_us)
        assert reference["single_requests"] == reference["batch_request"]
    for invalid in ("v1 sample", "v1 sample 1 2", "v1 sample " + "1 2 3 " * 9,
                    "v1 sample 239 31 224 bad 0 0", "v1 sample 239 31 224 -1 0 0"):
        owner.stdin.write(invalid + "\n")
        owner.stdin.flush()
        reply = lines.get(timeout=10)
        assert not reply["ok"] and "samples" not in reply
    return {"points_per_set": len(points), "measured_sets_per_mode": len(timings["batch_request"]),
            "round_trip_us": {mode: {"median": median(times), "max": max(times)}
                              for mode, times in timings.items()}}


def measure_bucket_transfers(owner, lines):
    def request(command):
        owner.stdin.write(command+"\n")
        owner.stdin.flush()
        return lines.get(timeout=10)

    inventory = request("v1 inventory")
    slot = next(i for i,row in enumerate(inventory["slots"]) if row["item"]==401)
    before = request(samples()[2])
    digest_before = inventory["digest"]
    timings = {"scoop": [], "pour": []}
    request_id = 2
    for _ in range(32):
        for action in timings:
            command = f"v1 {request_id} {action} 256.25 38 224.25 256.25 33 224.25 {slot} 1 {digest_before}"
            started = time.perf_counter_ns()
            ack = request(command)
            timings[action].append((time.perf_counter_ns()-started)/1000)
            assert ack.get("water_ml")==1_000_000 and ack["request_id"]==request_id, ack
            state = request("v1 inventory")
            assert state["slots"][slot]["water_ml"]==(1_000_000 if action=="scoop" else 0)
            digest_before = state["digest"]
            request_id += 1
    assert digest_before==inventory["digest"] and request(samples()[2])["water_ml"]==before["water_ml"]
    return {"samples_per_action":32, "operator_round_trip_us":{
        action:{"first":values[0],"median":median(values),"maximum":max(values)} for action,values in timings.items()}}


def run(engine, packaged, report, expected_archive=None):
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

        original = invoke(host, samples()+["v1 inventory", "save", "quit"], "AUTHORITY ")
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
                    edit_reply = lines.get(timeout=90)
                    assert edit_reply["ok"]
                    report["edit_round_trip_ms"] = (time.perf_counter()-started)*1000
                    owner.stdin.write("edit-profile\n")
                    owner.stdin.flush()
                    report["edit_profile"] = lines.get(timeout=10)["profile"]
                    assert report["edit_profile"]["solves"] > 0
                    report["query_burst"] = check_query_burst(owner, lines)
                    owner.stdin.write("v1 1 excavate 240 31 224 3 0\n")
                    owner.stdin.flush()
                    assert lines.get(timeout=10) == edit_reply
                    report["idle_working_set_bytes"] = idle_metrics["working_set_bytes"]
                    report["peak_working_set_after_edit_bytes"] = with_metrics.sample()["peak_working_set_bytes"]
                    report["resident_bucket_transfers"] = measure_bucket_transfers(owner,lines)
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
                   "v1 2 excavate 240 31 224 3 0", "excavate 240 31 224 3 0",
                   "v1 2 excavate 240 31 224 0.25 1", "v1 2 deposit 240 31 224 0.25 2 1"]
        results = invoke(host, [first,first]+invalid+samples()+["save","quit"], "AUTHORITY ")
        assert results[0]["last_request_id"] == 0  # crashed unsaved receipt is gone
        ack = {"ok":True,"version":1,"request_id":1,"changed":True,"revision":1}
        assert results[1] == results[2] == ack and results[-1]["ok"]
        assert all(not row["ok"] for row in results[3:3+len(invalid)])
        changed = results[3+len(invalid):-1]
        report["edited_archive_sha256"] = digest(archive)
        if expected_archive and report["edited_archive_sha256"] != expected_archive:
            raise AssertionError("Edited terrain/water archive differs from the reference run")
        restarted = invoke(host, [first]+samples()+["excavate 240 31 224 4 1",first,
                               "v1 2 excavate 240 31 224 5 2",first,"quit"], "AUTHORITY ")
        assert restarted[0]["last_request_id"] == 1 and restarted[1] == ack
        assert restarted[-4]["revision"] == 2 and restarted[-3] == ack
        assert restarted[-2]["ok"] and restarted[-2]["request_id"] == 2 and restarted[-1] == ack
        reloaded = restarted[2:-4]
        report["operator_retry"] = {"reply":ack,"rejected_commands":invalid,
                                    "restored_reply":restarted[1],"delayed_duplicate":restarted[-1]}
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
        game, deposited_game = invoke(base+["--script",str(script)], [], "GAME_AUTHORITY ")
        for i,sample in enumerate(changed):
            assert game["revision"]==sample["revision"]
            assert game["water_ml"]==sample["water_ml"]
            for key in ("density","depth"):
                assert math.isclose(game[key][i],sample[key],abs_tol=1e-4), (i,key,game[key][i],sample[key])
        # Fill the reply window with no-op excavations, then retry through
        # a fresh process. Only the explicit save publishes the new history.
        def noop(request_id):
            return f"v1 {request_id} excavate 240 230 224 1 1"
        batch = invoke(host, [noop(i) for i in range(2,35)]+["save","quit"], "AUTHORITY ")
        for i, row in enumerate(batch[1:-1], 2):
            assert row == dict(ok=True, version=1, request_id=i, revision=1, changed=False), row
        assert batch[-1]["ok"]
        restored = invoke(host, [noop(3), noop(34), noop(2), first,
                                "v1 3 excavate 241 230 224 1 1", *samples(), "quit"], "AUTHORITY ")
        assert restored[0]["last_request_id"] == 34 and restored[1:3] == [batch[2], batch[-2]]
        for row in restored[3:5]:
            assert row == dict(ok=False, reason="Receipt expired", last_request_id=34), row
        assert not restored[5]["ok"] and restored[6:] == changed
        backup_digest = bytes.fromhex(report["edited_archive_sha256"])
        assert hashlib.sha256(archive.with_suffix(".trw.bak").read_bytes()).digest()==backup_digest
        report["receipt_window"] = dict(size=32, first_retained=3, last_retained=34, restored=True)
        backup_digest = bytes.fromhex(digest(archive))
        place = "v1 35 deposit 240 31 224 2 2 1"
        place_ack = dict(ok=True, version=1, request_id=35, changed=True, revision=2)
        deposited = invoke(host, [place.replace("2 2 1","2 0 1"),place,place,*samples(),"edit-profile","save","quit"], "AUTHORITY ")
        assert not deposited[1]["ok"] and deposited[2] == deposited[3] == place_ack and deposited[-1]["ok"]
        deposited_samples = deposited[4:-2]
        assert len(deposited_samples) == len(POINTS)
        profile = deposited[-2]["profile"]
        assert 0 < profile["displacement_searches"] <= profile["displacement_visits"]
        assert deposited_game["revision"] == 2 and deposited_game["water_ml"] == game["water_ml"]
        for i, sample in enumerate(deposited_samples):
            assert sample["revision"] == 2 and sample["water_ml"] == changed[i]["water_ml"]
            for key in ("density","depth"):
                assert math.isclose(deposited_game[key][i],sample[key],abs_tol=1e-4), (i,key,deposited_game,sample)
            if i<2:
                assert sample["density"]<0 and sample["depth"]==0
            else:
                assert sample["density"]==changed[i]["density"]
        ray = "v1 water-surface 256.25 38 224.25 256.25 33 224.25"
        persisted = invoke(host, [place,place.replace("2 2 1","2 3 1"),"v1 35 excavate 240 31 224 2 1",*samples(),ray,
                                  ray.replace(" 33 ", " 30 "),ray.replace(" 33 ", " 38 "),
                                  "v1 water-surface 256.25 50 224.25 256.25 46 224.25","v1 inventory","quit"], "AUTHORITY ")
        assert persisted[1]==place_ack and not persisted[2]["ok"] and not persisted[3]["ok"]
        assert persisted[4:-5]==deposited_samples
        hit, too_far, empty_ray, miss, inventory = persisted[-5:]
        assert inventory["slots"] == deposited_game["inventory"] == original[-2]["slots"]
        assert any(slot["item"]==401 and slot["count"]==1 and slot["water_ml"]==0 for slot in inventory["slots"])
        assert hit["ok"] and hit["hit"] and hit["revision"] == 2 and hit["cell"] == deposited_game["surface_cell"]
        assert math.isclose(hit["point"][1], deposited_game["surface_y"], abs_tol=1e-4)
        assert hit["point"][0::2] == [256.25, 224.25]
        assert all(math.isclose(a,b,abs_tol=1e-4) for a,b in zip(hit["normal"],deposited_game["surface_normal"],strict=True))
        assert not too_far["ok"] and not empty_ray["ok"] and miss["ok"] and not miss["hit"]
        report["water_surface"] = hit
        report["deposition"] = dict(ack=place_ack, authority=deposited_samples, gameplay=deposited_game, profile=profile)
        # Open the authority's actual edited checkpoint in a fresh game process.
        # The earlier local comparison applied both edits in memory.
        checkpoint = game_input.with_name("AuthorityReload.trw")
        live_bytes = sum(p.stat().st_size for p in Path(temp).rglob("*") if p.is_file())
        admit(ROOT, report_bytes=65536, scratch_bytes=16 << 20, world_bytes=live_bytes+archive.stat().st_size)
        shutil.copyfile(archive, checkpoint)
        loaded_game, = invoke(base+["--script",str(script),"--","--inspect-authority-save"], [], "GAME_AUTHORITY ")
        for key in ("revision", "water_ml", "inventory", "surface_cell"):
            assert loaded_game[key] == deposited_game[key], key
        for key in ("density", "depth", "surface_normal"):
            for actual, expected in zip(loaded_game[key], deposited_game[key], strict=True):
                assert math.isclose(actual, expected, abs_tol=1e-4), (key, actual, expected)
        assert math.isclose(loaded_game["surface_y"], deposited_game["surface_y"], abs_tol=1e-4)
        report["authority_checkpoint_in_gameplay"] = dict(sha256=digest(checkpoint), samples=loaded_game)
        checkpoint.unlink()
        # Corrupt only our disposable canonical file. Failure must preserve the
        # input for recovery and leave its verified backup intact.
        corrupt = archive.read_bytes()[:64]
        archive.write_bytes(corrupt)
        rejected = subprocess.run(host, cwd=ROOT, input="save\nquit\n", env=env,
                                  capture_output=True, text=True, timeout=30,
                                  creationflags=subprocess.CREATE_NO_WINDOW)
        assert rejected.returncode and archive.read_bytes()==corrupt
        assert hashlib.sha256(archive.with_suffix(".trw.bak").read_bytes()).digest()==backup_digest
        # Size the import from this generated fixture. One native publication
        # can hold the canonical, its staged successor and a backup copy.
        checkpoint_limit = game_input.stat().st_size + (8 << 20)
        live_bytes = sum(p.stat().st_size for p in Path(temp).rglob("*") if p.is_file())
        admit(ROOT, report_bytes=65536, scratch_bytes=16 << 20, world_bytes=live_bytes+checkpoint_limit)
        bucket, = invoke(base+["--script",str(script),"--","--bucket-checkpoint",
                               f"--checkpoint-limit={checkpoint_limit}"], [], "GAME_BUCKET ")
        checkpoint_path = archive.with_name("BucketCheck.trw")
        live_bytes = sum(p.stat().st_size for p in Path(temp).rglob("*") if p.is_file())
        admit(ROOT, report_bytes=65536, scratch_bytes=16 << 20, world_bytes=live_bytes+2*checkpoint_path.stat().st_size)
        bucket_host = host[:-1]+["--authority-slot=BucketCheck"]
        imported = invoke(bucket_host, ["v1 inventory",samples()[0],"quit"], "AUTHORITY ")
        slot = bucket["slot"]
        assert imported[1]["slots"][slot]["water_ml"] == 1_000_000
        assert imported[2]["water_ml"] == bucket["water_ml"] == original[1]["water_ml"]-1_000_000
        segment = "256.25 38 224.25 256.25 33 224.25"
        full = imported[1]["digest"]
        empty = original[-2]["digest"]
        pour = f"v1 1 pour {segment} {slot} 0 {full}"
        scoop = f"v1 2 scoop {segment} {slot} 0 {empty}"
        noop = "v1 3 excavate 240 230 224 1 0"
        transfers = invoke(bucket_host, [
            pour.replace(full,empty),pour,pour,"v1 inventory",samples()[0],
            "v1 water-surface "+segment,scoop.replace(empty,full),scoop,scoop,noop,"v1 inventory",samples()[0],"save","quit"], "AUTHORITY ")
        (_, stale_pour, poured, pour_retry, empty_inventory, full_lake, poured_surface,
         stale_scoop, scooped, scoop_retry, following_edit, full_inventory, scooped_lake, saved) = transfers
        assert not stale_pour["ok"] and not stale_scoop["ok"]
        assert poured==pour_retry and poured.get("water_ml")==1_000_000, poured
        assert empty_inventory["digest"]==empty and full_lake["water_ml"]==original[1]["water_ml"]
        assert poured_surface["cell"]==bucket["poured_cell"] and math.isclose(poured_surface["point"][1],bucket["poured_y"],abs_tol=1e-4), (poured_surface,bucket)
        assert scooped==scoop_retry and scooped.get("water_ml")==1_000_000 and following_edit["ok"], scooped
        assert full_inventory["digest"]==full and scooped_lake["water_ml"]==bucket["water_ml"] and saved["ok"]
        reopened = invoke(bucket_host,[pour,scoop,noop,pour.replace(" pour "," scoop "),"v1 inventory",samples()[0],"quit"], "AUTHORITY ")
        assert reopened[0]["last_request_id"]==3 and reopened[1:4]==[poured,scooped,following_edit]
        assert not reopened[4]["ok"] and reopened[5]["slots"]==imported[1]["slots"] and reopened[6]==imported[2]
        report["bucket_commands"] = dict(pour=poured,scoop=scooped,poured_surface=poured_surface,reloaded=True)
        dry, = invoke(bucket_host,["sample 1030.25 80 1030.25","quit"],"AUTHORITY ")[1:]
        y = dry["height"] + 0.5
        cold = f"v1 4 pour 1030.25 {y+3} 1030.25 1030.25 {y} 1030.25 {slot} 0 {full}"
        cold_run = invoke(bucket_host,[cold,"v1 inventory",samples()[0],*([cold]*256),"v1 inventory",samples()[0],"quit"],"AUTHORITY ")
        assert cold_run[1].get("pending") and cold_run[2]["digest"]==full and cold_run[3]["water_ml"]==bucket["water_ml"]
        attempts = cold_run[4:-2]
        success = next(i for i,row in enumerate(attempts) if row["ok"])
        assert all(row.get("pending") for row in attempts[:success]) and all(row==attempts[success] for row in attempts[success:])
        assert cold_run[-2]["digest"]==empty and cold_run[-1]["water_ml"]==original[1]["water_ml"]
        report["cold_bucket"] = dict(pending_replies=success+1, transferred_ml=attempts[success]["water_ml"])
        destination = bucket["move_destination"]
        move = f"v1 4 move-stack {slot} {destination} 1 {full}"
        conflict = move.replace(f" {destination} 1 ", f" {destination} 2 ")
        rows = invoke(bucket_host, [move.replace(full,empty), conflict, "v1 inventory",
                                    move, move, conflict, "v1 inventory", "save", "quit"], "AUTHORITY ")
        assert not rows[1]["ok"] and not rows[2]["ok"] and rows[3]["digest"] == full
        assert rows[4]["ok"] and rows[4]["changed"] and rows[4] == rows[5] and not rows[6]["ok"]
        assert rows[7]["slots"] == bucket["moved_slots"] and rows[8]["ok"]
        restored = invoke(bucket_host, [move, "v1 inventory", samples()[0], "quit"], "AUTHORITY ")
        assert restored[0]["last_request_id"] == 4 and restored[1] == rows[4]
        assert restored[2]["digest"] == rows[7]["digest"] and restored[3] == imported[2]
        report["inventory_move"] = dict(source=slot, destination=destination, reloaded=True,
                                        matches_gameplay=True, digest=restored[2]["digest"])
        report["bucket_save_reload"] = bucket
        report.update(before=original[1:4], after=changed, reloaded=reloaded, gameplay=game,
                      initial_archive_sha256=original_digest.hex(), passed=True)


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True,type=Path)
    parser.add_argument("--pack",action="store_true")
    parser.add_argument("--expect-edited-sha256", help="Compare the complete edited archive with a matched build")
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
        run(engine,args.pack,report,args.expect_edited_sha256)
    except Exception as error:
        report["error"] = repr(error)
        raise
    finally:
        evidence = folder/"dedicated_world.json"
        evidence.write_text(json.dumps(report,indent=2),encoding="utf-8")
        print("PASS" if report["passed"] else "FAIL", evidence)
