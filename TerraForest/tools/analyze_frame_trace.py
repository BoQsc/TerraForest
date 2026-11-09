"""Summarize one rolling-trace session without counting overlapping frames twice."""
# SPDX-License-Identifier: 0BSD
import argparse
import hashlib
import json
from pathlib import Path


def distribution(values):
    values = sorted(values)
    n = len(values)
    if not n:
        return None
    return {"samples": n, "mean": sum(values) / n, "p50": values[n // 2],
            "p95": values[min(n - 1, int(n * .95))],
            "p99": values[min(n - 1, int(n * .99))], "maximum": values[-1]}


def summarize(captures):
    frames = {}
    for capture in captures:
        if capture.get("schema") != 1:
            raise ValueError("Unsupported trace schema")
        for row in capture["frames"]:
            identity = (row["frame"], row["at_us"])
            if identity in frames and frames[identity] != row:
                raise ValueError("Overlapping captures disagree about an immutable frame")
            frames[identity] = row
    rows = sorted(frames.values(), key=lambda r: r["at_us"])
    lookup = {r["frame"]: r for r in rows}
    phases = {}
    for phase in dict.fromkeys(r["phase"] for r in rows):
        selected = [r for r in rows if r["phase"] == phase]
        metrics = {key: distribution([r[key] for r in selected if key in r]) for key in
                   ("frame_ms", "process_ms", "draw_ms", "before_process_ms", "after_process_ms",
                    "physics_ms", "gpu_ms", "render_cpu_ms", "recorder_previous_us", "draw_calls", "primitives")}
        metrics["over_20ms_frames"] = sum(r["frame_ms"] > 20 for r in selected)
        phases[phase] = metrics
    worst = []
    for row in sorted(rows, key=lambda r: r["frame_ms"], reverse=True)[:20]:
        prior = lookup.get(row["frame"] - 1)
        record = dict(row)
        record["pipeline_deltas"] = {
            key: row[key] - prior[key] if prior is not None else None
            for key in ("pipeline_draw", "pipeline_specialization") if key in row}
        # Stages are nested. Preserve them; never add their maxima together.
        record["stages_ms"] = dict(sorted(row.get("stages_ms", {}).items(), key=lambda x: -x[1]))
        worst.append(record)
    return {"unique_frames": len(rows), "phases": phases, "slowest_frames": worst,
            "scope": "Triggered windows only, not an unbiased whole-session distribution. Overlapping frames deduplicated. Stages/physics overlap wall intervals. GPU timers may lag. Missing adjacent frames give unknown compilation deltas."}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("session", type=Path, help="One session directory or one trace JSON")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    files = sorted(args.session.glob("trace_*.json")) if args.session.is_dir() else [args.session]
    if not files:
        parser.error("No trace files found")
    captures = [json.loads(path.read_text(encoding="utf-8")) for path in files]
    result = summarize(captures)
    result["sources"] = [{"path": str(path.resolve()), "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                          "trigger": data["trigger"], "metadata": data["metadata"], "truncated": data["truncated"]}
                         for path, data in zip(files, captures)]
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    for phase, metrics in result["phases"].items():
        value = metrics["frame_ms"]
        print(f"{phase}: n={value['samples']} p99={value['p99']:.3f} ms max={value['maximum']:.3f} ms")
    print(f"{result['unique_frames']} unique frames in {len(files)} triggered windows")
    if args.output:
        print(args.output.resolve())


if __name__ == "__main__":
    main()
