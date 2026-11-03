# SPDX-License-Identifier: 0BSD
"""Build the curated CC0 runtime subset from the verified NOX archive.

External authoring dependency: ffmpeg (used under its own terms, not bundled).
The upstream README and source page must be reviewed before running intake.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
EXPECTED = "0df9a98cc8d0499787cb3c29f3e278fdacd75ca3e94106828ea8b5c115ae8d3d"
SOURCE = "https://nox-sound-design.itch.io/essentials-series-sfx-nox-sound"


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    args = parser.parse_args()
    with args.archive.open("rb") as source_file:
        digest = hashlib.file_digest(source_file, "sha256").hexdigest()
    if digest != EXPECTED:
        parser.error("Archive changed: review provenance and terms before upgrading")
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        parser.error("ffmpeg is required for offline asset preparation")
    destination = ROOT / "addons/audio_runtime/packs/nox"
    destination.mkdir(parents=True, exist_ok=True)
    sounds, records = [], []
    with zipfile.ZipFile(args.archive) as archive, tempfile.TemporaryDirectory() as staging:
        names = archive.namelist()

        def convert(member, output, ambient=False):
            data = archive.read(member)
            raw = Path(staging) / "source.wav"
            raw.write_bytes(data)
            target = destination / output
            command = [ffmpeg, "-v", "error", "-y", "-i", str(raw), "-map_metadata", "-1", "-ar", "48000"]
            command += ["-c:a", "libvorbis", "-q:a", "5", "-f", "ogg"] if ambient else ["-ac", "1", "-c:a", "pcm_s16le", "-f", "wav"]
            subprocess.run([*command, str(target)], check=True, capture_output=True)
            records.append(dict(source_member=member, source_sha256=sha(data), path=output,
                                sha256=sha(target.read_bytes()), conversion="48kHz Vorbis q5" if ambient else "48kHz mono PCM16",
                                bytes=target.stat().st_size))
            return output

        for surface, upstream in {"dirt": "DirtyGround", "grass": "Grass", "gravel": "Gravel", "leaves": "Leaves", "metal": "Metal", "rock": "Rock", "sand": "Sand", "snow": "Snow", "water": "Water", "wood": "Wood"}.items():
            for gait in ("walk", "run"):
                folder = f"/Footsteps_Essentials_NOX_SOUND/Footsteps_{upstream}/Footsteps_{upstream}_{gait.title()}/"
                selected = sorted(n for n in names if folder in n and n.endswith(".wav"))[:4]
                if len(selected) != 4:
                    raise ValueError(f"Missing four {surface}/{gait} variants")
                files = [convert(n, f"{surface}_{gait}_{i+1:02}.wav.bin") for i, n in enumerate(selected)]
                sounds.append(dict(id=f"nox.step.{surface}.{gait}", event="movement.footstep", match=dict(surface=surface, gait=gait), files=files, gain_db=-8, priority=80, limit=4, range=20))
        sounds.append(dict(id="nox.step.fallback", event="movement.footstep", files=["dirt_walk_01.wav.bin", "dirt_walk_02.wav.bin"], gain_db=-10, priority=80, limit=4, range=20))
        for event, filename, output, bus, gain, spatial_range in [
            ("ambience.forest", "Ambiance_Forest_Birds_Loop_Stereo.wav", "forest.ogg.bin", "Ambience", -18, 32),
            ("fire.burn", "Ambiance_Firecamp_Small_Loop_Mono.wav", "campfire.ogg.bin", "Effects", -12, 16),
        ]:
            member = next(n for n in names if n.endswith("/Nature_Essentials_NOX_SOUND/" + filename))
            convert(member, output, True)
            sounds.append(dict(id="nox." + event, event=event, files=[output], bus=bus, gain_db=gain, pitch=1, range=spatial_range, priority=40, limit=8 if event == "fire.burn" else 1, loop=True))
        readme = next(n for n in names if n.endswith("Essentials_Series_README.pdf"))
        provenance = dict(schema=1, creator="Nox_Sound_Design", source=SOURCE, retrieved="2026-11-03", license="CC0-1.0", archive_sha256=digest, archive_bytes=args.archive.stat().st_size,
                          authoring_tool=subprocess.check_output([ffmpeg, "-version"], text=True).splitlines()[0],
                          upstream_readme_sha256=sha(archive.read(readme)), evidence="README PDF: All these sounds are under CC0 license. Source page also declares all sounds CC0.",
                          scope="Selected sound recordings and runtime derivatives only; no upstream promotional images or branding imported.", files=records)
    (destination / "pack.audio.module.json").write_text(json.dumps(dict(schema=1, id="nox.essentials.v1", sounds=sounds), indent=2) + "\n")
    (destination / "provenance.json").write_text(json.dumps(provenance, indent=2) + "\n")
    example = ROOT / "mods/example_audio"
    example.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(destination / "grass_walk_01.wav.bin", example / "soft_grass.wav.bin")
    replacement = dict(sounds[2], replace=True, files=["soft_grass.wav.bin"], gain_db=-18)
    assert replacement["id"] == "nox.step.grass.walk"
    (example / "pack.audio.module.json").write_text(json.dumps(dict(schema=1, id="example.soft-grass.v1", requires=["nox.essentials.v1"], sounds=[replacement]), indent=2) + "\n")
    print(f"Prepared {len(records)} clips, {len(sounds)} definitions, {sum(r['bytes'] for r in records):,} bytes")


if __name__ == "__main__":
    main()
