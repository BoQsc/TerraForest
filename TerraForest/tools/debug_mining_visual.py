# SPDX-License-Identifier: 0BSD
"""Run paired mining diagnostics and build a self-contained local HTML viewer.

python tools/debug_mining_visual.py [--godot PATH]
Exit 1 means the actual mining gates failed; inspect report.html, not just exit status.
Screenshot runs are intentionally excluded from performance acceptance.
"""
from __future__ import annotations
import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_GODOT = Path(r"C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe")

HTML = r'''<!doctype html><html lang="en"><meta charset="utf-8">
<title>Mining: input to visible change</title>
<style>
*{box-sizing:border-box}body{margin:24px;background:#101620;color:#e4edf5;font:15px system-ui}h1{font-size:26px;margin-bottom:8px}p{max-width:1100px;line-height:1.5}.muted{color:#a9b8c7}.bad{color:#ff9f95}button,select{background:#25374c;color:white;border:1px solid #52708c;padding:8px;border-radius:5px;margin:4px}input{width:100%}.grid{display:grid;grid-template-columns:minmax(600px,2fr) minmax(360px,1fr);gap:18px}.panel{background:#192332;padding:16px;border-radius:8px;margin:12px 0}img{width:100%;display:block}canvas{width:100%;background:#101620}table{border-collapse:collapse;width:100%;font-size:13px}th,td{text-align:left;padding:7px;border-bottom:1px solid #344354}pre{white-space:pre-wrap;font-size:12px;max-height:270px;overflow:auto}#milestones{display:flex;gap:24px;flex-wrap:wrap}.metric{font-size:22px}.small{font-size:12px}a{color:#95d5ff}summary{cursor:pointer} @media(max-width:1000px){.grid{display:block}}
</style><h1>Mining: input → target → terrain readiness → visible change</h1>
<p class="bad">This report diagnoses failures. Screenshot timing is intrusive and is not performance acceptance. Images show actual rendered frames; “draw” events alone do not prove the excavation was visible.</p>
<div id="baseline" class="panel"></div>
<label>Location <select id="phase"></select></label><button id="prev">Previous capture</button><button id="next">Next capture</button>
<div id="milestones" class="panel"></div>
<div class="panel"><canvas id="timeline" width="1500" height="160"></canvas><input id="scrub" type="range" min="0" value="0"><div id="time"></div></div>
<div class="grid"><div><div class="panel"><div id="caption"></div><img id="shot" alt="Actual Godot viewport capture"></div><div class="panel"><h3>Events near selected time</h3><pre id="events"></pre></div></div>
<div><div class="panel"><h3>Actual published terrain coverage</h3><canvas id="map" width="500" height="380"></canvas><p class="small">Blue: visible cut. Orange: requested activation dependencies. Red cross: scripted destination. Outlines are tile extents, not meshes.</p></div><div class="panel"><h3>Target and its coverage dependencies</h3><div id="hierarchy"></div></div><div class="panel"><h3>Worker and scene preparation</h3><pre id="queue"></pre></div></div></div>
<details class="panel"><summary>Scope, provenance and source hashes</summary><pre id="scope"></pre></details>
<script>const DATA=__DATA__;
const $=id=>document.getElementById(id);let p,index=0;
const pretty=v=>JSON.stringify(v,null,2), fmt=v=>v==null?'not observed':v.toFixed(1)+' ms';
const metric=(label,v)=>`<div><span class="muted">${label}</span><div class="metric">${fmt(v)}</div></div>`;
function first(pred){return p.samples.find(pred)?.ms}
function arrivalTarget(s){let k=s.hierarchy[0]?.key;return k&&p.destination[0]>=k[0]&&p.destination[0]<k[0]+k[2]&&p.destination[2]>=k[1]&&p.destination[2]<k[1]+k[2]}
function choose(){p=DATA.trace.phases[+$('phase').value];index=0;$('scrub').max=Math.max(0,p.samples.length-1);$('scrub').value=0;
$('milestones').innerHTML=metric('Arrival target cached',first(s=>arrivalTarget(s)&&s.query_cached))+metric('Arrival tile resident',first(s=>arrivalTarget(s)&&s.hierarchy[0].resident))+metric('Arrival target visible',first(s=>arrivalTarget(s)&&s.hierarchy.some(h=>h.active&&!h.dirty)))+metric('Edit pending',first(s=>s.pending_edit))+metric('First changed draw callback',p.first_draw_ms);render();}
function drawTimeline(){let c=$('timeline'),x=c.getContext('2d'),end=p.samples.at(-1)?.ms||3000;x.clearRect(0,0,c.width,c.height);let tracks=[['Target cached',s=>arrivalTarget(s)&&s.query_cached],['Visible owner',s=>arrivalTarget(s)&&s.hierarchy.some(h=>h.active&&!h.dirty)],['Ray hit',s=>s.hit],['Edit pending',s=>s.pending_edit],['Worker busy',s=>!!s.worker.active.kind]];tracks.forEach(([label,pred],j)=>{x.fillStyle='#d9e5f0';x.fillText(label,5,j*28+20);p.samples.forEach((s,i)=>{let next=p.samples[i+1]?.ms??end;x.fillStyle=pred(s)?'#52b99b':'#384455';x.fillRect(125+s.ms/end*(c.width-130),j*28+6,Math.max(1,(next-s.ms)/end*(c.width-130)),16)})});x.fillStyle='#fff';x.fillRect(125+p.samples[index].ms/end*(c.width-130),0,2,150);}
function map(s){let c=$('map'),x=c.getContext('2d'),cx=p.destination[0],cz=p.destination[2],scale=.72;x.clearRect(0,0,c.width,c.height);function tile(k,color,fill){let px=250+(k[0]-cx)*scale,py=190+(k[1]-cz)*scale;x.strokeStyle=color;x.fillStyle=fill;if(fill)x.fillRect(px,py,k[2]*scale,k[2]*scale);x.strokeRect(px,py,k[2]*scale,k[2]*scale)}s.visible.forEach(k=>tile(k,'#5686bd','#16324b'));s.activation.forEach(k=>tile(k,'#efb759',null));x.strokeStyle='#ff7970';x.beginPath();x.moveTo(240,190);x.lineTo(260,190);x.moveTo(250,180);x.lineTo(250,200);x.stroke();}
function state(h){return [h.active?'VISIBLE':null,h.dirty?'DIRTY':null,h.resident?'resident':null,h.preparing?'uploading':null,h.paused?'paused':null,h.staged?'staged':null,h.in_flight?'worker/queue':null,h.activation?'activation':null,h.requested?'requested':null].filter(Boolean).join(' · ')||'absent'}
function render(){if(!p.samples.length)return;index=+$('scrub').value;let s=p.samples[index];$('time').textContent=`State sample ${index+1}/${p.samples.length} at ${fmt(s.ms)} | focused=${s.focused}, held=${s.held} | observer ${fmt(s.observer_ms)}`;let captures=p.captures.filter(c=>c.ms<=s.ms),cap=captures.at(-1)||p.captures[0];if(cap){$('shot').src='visual/'+cap.file;$('caption').textContent=`Rendered capture: ${fmt(cap.ms)} — ${cap.reason}; ${cap.width}×${cap.height}; GPU readback ${fmt(cap.readback_ms)}. State cursor may be later.`}else{$('shot').removeAttribute('src');$('caption').textContent='No capture: run failed before render evidence.'}
$('hierarchy').innerHTML='<table><tr><th>Tile [x,z,size]</th><th>State</th></tr>'+s.hierarchy.map(h=>`<tr><td>${h.key.join(',')}</td><td>${state(h)}</td></tr>`+h.children.map(ch=>`<tr><td class="muted">↳ ${ch.key.join(',')}</td><td>${state(ch)}</td></tr>`).join('')).join('')+'</table>';
$('queue').textContent=pretty({target:s.target,worker:s.worker,preparation:s.preparation,paused:s.paused,staging:s.staging,batch_remaining:s.batch_remaining,revisions:[s.native_revision,s.published_revision],schedule_timer:s.schedule_timer});$('events').textContent=pretty(p.events.filter(e=>Math.abs(e.ms-s.ms)<120));drawTimeline();map(s);}
DATA.trace.phases.forEach((p,i)=>{let o=document.createElement('option');o.value=i;o.textContent=p.phase;$('phase').append(o)});
$('baseline').innerHTML='<h3>Timing run — no screenshot observer</h3>'+DATA.baseline.phases.map(p=>`<p><b>${p.phase}</b>: ${p.changed_draws} visible changed draws; longest visible gap <b>${fmt(p.visible_gaps.max_ms)}</b>; capture-to-draw p95 ${fmt(p.capture_to_draw.p95_ms)}; frame p99 ${fmt(p.frames.p99_ms)}, maximum ${fmt(p.frames.max_ms)}.</p>`).join('')+'<p class="bad">'+DATA.baseline.checks.filter(c=>!c.pass).map(c=>c.name).join(' • ')+'</p>';
$('scope').textContent=pretty({scope:DATA.trace.scope,provenance:DATA.provenance,save_errors:DATA.trace.save_errors});$('phase').onchange=choose;$('scrub').oninput=render;
function step(d){let t=p.samples[index]?.ms||0;let cap=d>0?p.captures.find(c=>c.ms>t+.1):p.captures.filter(c=>c.ms<t-.1).at(-1);if(cap){$('scrub').value=cap.sample_index;render()}}
$('prev').onclick=()=>step(-1);$('next').onclick=()=>step(1);choose();
</script></html>'''

def run(godot: Path, output: Path, visual: bool) -> tuple[dict, int]:
    label = "visual" if visual else "timing"
    destination = output / label
    destination.mkdir()
    # Timestamped output directories retain prior evidence; never reuse stale results.
    report = ROOT / "reports/held_mining_flight.json"
    before = report.stat().st_mtime_ns if report.exists() else None
    command = [str(godot), "--path", str(ROOT), "--script", "res://tests/held_mining_flight.gd", "--", "--region-terrain"]
    if visual:
        command.append("--visual-debug")
    print(f"Running {label}: two 3-second bursts after startup", flush=True)
    with (destination / "godot.log").open("w", encoding="utf-8") as log:
        result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=100)
    if not report.exists() or report.stat().st_mtime_ns == before:
        raise RuntimeError(f"{label} produced no fresh report; inspect {destination / 'godot.log'}")
    data = json.loads(report.read_text())
    if bool(data.get("visual_diagnostic")) != visual:
        raise RuntimeError("Report mode mismatch")
    shutil.copy2(report, destination / "results.json")
    shutil.copy2(ROOT / "reports/foundation_mining.frames.csv", destination / "frames.csv")
    if visual:
        trace_path = ROOT / "reports/mining_visual/trace.json"
        if not trace_path.exists() or trace_path.stat().st_mtime_ns < report.stat().st_mtime_ns:
            raise RuntimeError("Missing or stale visual trace")
        trace = json.loads(trace_path.read_text())
        if trace["save_errors"] or len(trace["phases"]) != 2:
            raise RuntimeError("Incomplete visual evidence")
        shutil.copy2(trace_path, destination / "trace.json")
        for phase in trace["phases"]:
            if len(phase["captures"]) < 6:
                raise RuntimeError("Missing capture milestones")
            for capture in phase["captures"]:
                if (capture["width"], capture["height"]) != (1920, 1080):
                    raise RuntimeError("Screenshot resolution is not 1920x1080")
                shutil.copy2(trace_path.parent / capture["file"], destination / capture["file"])
    return data, result.returncode

def build_viewer(output: Path) -> None:
    payload = {"baseline":json.loads((output / "timing/results.json").read_text()), "diagnostic":json.loads((output / "visual/results.json").read_text()), "trace":json.loads((output / "visual/trace.json").read_text()), "provenance":json.loads((output / "provenance.json").read_text())}
    (output / "report.html").write_text(HTML.replace("__DATA__", json.dumps(payload).replace("<", "\\u003c")), encoding="utf-8")

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, default=Path(os.environ.get("GODOT_EXE", str(DEFAULT_GODOT))))
    parser.add_argument("--report-only", type=Path, help="Rebuild viewer from an existing paired run; do not rerun Godot")
    args = parser.parse_args()
    if args.report_only:
        build_viewer(args.report_only)
        print(args.report_only / "report.html")
        return 0
    if not args.godot.is_file():
        parser.error("Godot executable not found; supply --godot")
    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
    output = ROOT / "reports/mining_diagnostic" / stamp
    output.mkdir(parents=True)
    baseline, code = run(args.godot, output, False)
    diagnostic, visual_code = run(args.godot, output, True)
    trace = json.loads((output / "visual/trace.json").read_text())
    sources = ["tests/held_mining_flight.gd", "tests/mining_visual_observer.gd", "tools/debug_mining_visual.py", "demo/controller.gd", "addons/volumetric_terrain/terrain_stream.gd", "addons/volumetric_terrain/terrain_backend.gd", "addons/volumetric_terrain/bin/terrain_core.windows.x86_64.dll"]
    provenance = {"utc":stamp, "head":subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(), "timing_exit":code, "visual_exit":visual_code, "source_sha256":{p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in sources}, "presentation":baseline["presentation"], "note":"Two independent temporary worlds; same scripted destinations and held input. Images are from the diagnostic run only; no human playtest."}
    (output / "provenance.json").write_text(json.dumps(provenance, indent=2), encoding="utf-8")
    build_viewer(output)
    print(f"REPORT: {output / 'report.html'}", flush=True)
    print("PERFORMANCE: " + ("PASS" if code==0 else "FAIL — preserved in report"), flush=True)
    return 0 if code==0 else 1

if __name__ == "__main__":
    raise SystemExit(main())
