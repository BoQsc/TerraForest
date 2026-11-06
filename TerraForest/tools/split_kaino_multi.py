"""Split multi-take Kaino WAVs into single hits.

Each source file keeps its original; the cut hits go to a "split" folder next
to it. Detection matches the audition analysis: 10 ms RMS windows, threshold at
6 % of the loudest window, gaps shorter than 60 ms bridged. Each hit gets 10 ms
of head room, 30 ms of tail and 5 ms fades so cuts do not click.

Usage: python tools/split_kaino_multi.py [--dry]
"""
from __future__ import annotations

import json
import sys
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PACKS = ROOT / "addons" / "audio_runtime" / "packs" / "Kaino"
SELECTION = ROOT / "addons" / "audio_runtime" / "kaino_audition_selection.json"

WINDOW_SECONDS = 0.010
GAP_MERGE_SECONDS = 0.060
HEAD_SECONDS = 0.010
TAIL_SECONDS = 0.030
FADE_SECONDS = 0.005


def decode(raw: bytes, width: int) -> list[int]:
    if width == 2:
        return list(memoryview(raw).cast("h"))
    if width == 3:
        out = []
        for i in range(0, len(raw) - 2, 3):
            value = raw[i] | (raw[i + 1] << 8) | (raw[i + 2] << 16)
            if value & 0x800000:
                value -= 0x1000000
            out.append(value)
        return out
    if width == 4:
        return list(memoryview(raw).cast("i"))
    raise ValueError(f"unsupported sample width {width}")


def encode(values: list[int], width: int) -> bytes:
    if width == 2:
        return b"".join(int(v).to_bytes(2, "little", signed=True) for v in values)
    if width == 3:
        out = bytearray()
        for v in values:
            v &= 0xFFFFFF
            out += bytes((v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF))
        return bytes(out)
    if width == 4:
        return b"".join(int(v).to_bytes(4, "little", signed=True) for v in values)
    raise ValueError(f"unsupported sample width {width}")


def segments(samples: list[int], rate: int) -> list[tuple[int, int]]:
    window = max(1, int(rate * WINDOW_SECONDS))
    rms = []
    for start in range(0, len(samples), window):
        chunk = samples[start:start + window]
        if not chunk:
            break
        rms.append((sum(v * v for v in chunk) / len(chunk)) ** 0.5)
    if not rms:
        return []
    threshold = max(max(rms) * 0.06, 60.0)
    merge = max(1, int(GAP_MERGE_SECONDS / WINDOW_SECONDS))
    found, start, quiet = [], None, 0
    for index, value in enumerate(rms):
        if value > threshold:
            if start is None:
                start = index
            quiet = 0
        elif start is not None:
            quiet += 1
            if quiet >= merge:
                found.append((start * window, (index - quiet + 1) * window))
                start, quiet = None, 0
    if start is not None:
        found.append((start * window, len(samples)))
    return found


def faded(values: list[int], rate: int) -> list[int]:
    ramp = max(1, int(rate * FADE_SECONDS))
    if len(values) <= ramp * 2:
        ramp = max(1, len(values) // 4)
    out = list(values)
    for i in range(min(ramp, len(out))):
        out[i] = int(out[i] * i / ramp)
        out[-1 - i] = int(out[-1 - i] * i / ramp)
    return out


def noted_paths() -> list[Path]:
    with open(SELECTION, encoding="utf-8") as handle:
        data = json.load(handle)
    keys = list(data.get("notes", {}).keys()) + list(data.get("selection", {}).values())
    paths = []
    for key in keys:
        path = ROOT / key.replace("res://", "")
        if path.suffix.lower() == ".wav" and path.exists() and path not in paths:
            paths.append(path)
    return paths


def main(dry: bool) -> None:
    manifest = {}
    total_hits = 0
    for path in sorted(noted_paths()):
        with wave.open(str(path), "rb") as w:
            channels, width, rate, frames = w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()
            raw = w.readframes(frames)
        samples = decode(raw, width)
        if channels > 1:
            samples = [sum(samples[i:i + channels]) // channels for i in range(0, len(samples) - channels + 1, channels)]
        found = segments(samples, rate)
        if len(found) <= 1:
            continue
        folder = path.parent / "split"
        head = int(rate * HEAD_SECONDS)
        tail = int(rate * TAIL_SECONDS)
        entries = []
        for number, (start, end) in enumerate(found, 1):
            a = max(0, start - head)
            b = min(len(samples), end + tail)
            target = folder / f"{path.stem}_hit{number}.wav"
            entries.append({"file": target.relative_to(ROOT).as_posix(), "start": round(start / rate, 3), "end": round(end / rate, 3)})
            if dry:
                continue
            folder.mkdir(parents=True, exist_ok=True)
            with wave.open(str(target), "wb") as out:
                out.setnchannels(1)
                out.setsampwidth(width)
                out.setframerate(rate)
                out.writeframes(encode(faded(samples[a:b], rate), width))
        total_hits += len(entries)
        manifest[path.relative_to(ROOT).as_posix()] = entries
        print(f"{path.name}: {len(entries)} hits")
    if not dry:
        folder = PACKS / "1" / "split"
        folder.mkdir(parents=True, exist_ok=True)
        (folder / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(f"{'would write' if dry else 'wrote'} {total_hits} hits from {len(manifest)} files")


if __name__ == "__main__":
    main("--dry" in sys.argv[1:])
