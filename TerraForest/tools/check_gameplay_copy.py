# SPDX-License-Identifier: 0BSD
"""Verify copying, no-overwrite behavior and real startup on an isolated copied slot."""
import datetime
import hashlib
import json
import os
from pathlib import Path
import uuid
from clone_world import clone_once
from run import ROOT, parse_args, launch_details
from run_godot_check import execute
from play_checkpoint import revision_metadata

def digest_tree(path):
    return {str(p.relative_to(path)):hashlib.sha256(p.read_bytes()).hexdigest()
            for p in path.rglob("*") if p.is_file()}

def main():
    args, extra = parse_args()
    if extra:raise ValueError("No additional arguments supported")
    folder=ROOT/"reports/gameplay_copy"/datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    folder.mkdir(parents=True)
    fixture=folder/"fixture";fixture.mkdir()
    (fixture/"source.trw").write_bytes(b"canonical test root")
    for suffix in ("regions","models"):
        part=fixture/("source.trw."+suffix);part.mkdir();(part/"packet").write_bytes(suffix.encode())
    before=digest_tree(fixture)
    assert clone_once(fixture,"source","copy")["created"]
    for name,data in before.items():assert (fixture/name.replace("source.trw","copy.trw",1)).read_bytes()==(fixture/name).read_bytes()
    (fixture/"copy.trw").write_bytes(b"gameplay progress")
    assert not clone_once(fixture,"source","copy")["created"] and (fixture/"copy.trw").read_bytes()==b"gameplay progress"
    for bad in ("../outside","has space",""):
        try:clone_once(fixture,"source",bad)
        except ValueError:pass
        else:raise AssertionError("Invalid slot accepted")
    (fixture/"partial.trw.regions").mkdir()
    try:clone_once(fixture,"source","partial")
    except FileExistsError:pass
    else:raise AssertionError("Partial target overwritten")
    assert not (fixture/"partial.trw").exists()
    # Real copy: no changes to the player's canonical editor or gameplay saves.
    manifest=json.loads((ROOT/"docs/evidence/generated_furnished/manifest.json").read_text())
    worlds=Path(os.environ["APPDATA"])/"Godot/app_userdata/TerraForest/worlds"
    source=manifest["slot"];slot="gameplay_copy_"+uuid.uuid4().hex
    source_files=[worlds/(source+".trw")]
    for suffix in (".regions",".models"):
        source_files+=list((worlds/(source+".trw"+suffix)).rglob("*"))
    source_hash={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in source_files if p.is_file()}
    copied=clone_once(worlds,source,slot)
    for path,value in source_hash.items():
        destination=Path(path.replace(source+".trw",slot+".trw",1))
        assert hashlib.sha256(destination.read_bytes()).hexdigest()==value
    args.slot=slot
    details=launch_details(args,["--gameplay-construction","--ground-cover","--actors","--vehicle-fleet"])
    command=details["command"];index=command.index("res://demo/world.tscn")
    command[index:index+1]=["--script","res://tests/playtest_startup.gd"]
    command[1:1]=["--log-file",str(folder/"engine.log")]
    record=dict(command=command,copy=copied,copied_files=len(source_hash),**revision_metadata())
    record["result"]=execute(command,folder,90,"PASS PLAYTEST_STARTUP ")
    record["source_unchanged"]=all(hashlib.sha256(Path(p).read_bytes()).hexdigest()==h for p,h in source_hash.items())
    (folder/"run.json").write_text(json.dumps(record,indent=2),encoding="utf-8")
    assert record["source_unchanged"]
    print(("PASS " if record["result"]["passed"] else "FAIL ")+str(folder))
    return 0 if record["result"]["passed"] else 1
if __name__=="__main__":raise SystemExit(main())
