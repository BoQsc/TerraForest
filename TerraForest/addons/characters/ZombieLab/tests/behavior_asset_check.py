"""Validate shipped GLB identities, original preservation, and R4 action tracks.

Python standard library only. Run from any directory; no asset is changed.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import struct

ROOT = Path(__file__).resolve().parents[1]
BASE_ACTIONS = ("Zombie_Idle", "Zombie_Walk", "Zombie_Attack", "Zombie_Hit")
ORIGINALS = {
    "assets/Zombie.glb": "8486a5b6441f8242cdac0dc96c411cbb763c46aa6b38ae1cd458d94db891f5a0",
    "source/Zombie.blend": "d9b207ee96672acc5cb12c9544d46914b736dfda784b91f049f49fae0d12656b",
    "assets/Zombie.r2.glb": "7ba891bc1c72cb31a9ec4d807ea81cc10dad37d767041048da464d1e0bb6028b",
    "source/Zombie.r2.blend": "56e28fb299197ce1d908879a7237563fc381a4acf9de83e46f3261cd270cdd82",
    "archive/r3/Zombie.r3.glb": "2ed8ee3d69b66a799479c75c5144aee84045e9aa647b6a2efa8ce3c737b892e2",
    "archive/r3/Zombie.r3.blend": "983623cee93a3651f784bc0f49378089e609ec011d03c180a5630d86de28d85f",
    "archive/r4.previous/Zombie.r4.glb": "f9f387e637bdaeea0bbdf7d00e842b2a52279c7e9381b1daddea2c2f4852d992",
    "archive/r4.previous/Zombie.r4.blend": "72386e6e30655e4de148879d4a46ccbd6176f8bf9146e5ecd594851e8a182847",
}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


class Glb:
    def __init__(self, path):
        self.path = path
        raw = path.read_bytes()
        magic, version, total = struct.unpack_from("<4sII", raw)
        assert magic == b"glTF" and version == 2 and total == len(raw)
        self.binary = b""
        at = 12
        while at < len(raw):
            length, kind = struct.unpack_from("<II", raw, at)
            chunk = raw[at + 8:at + 8 + length]
            if kind == 0x4E4F534A:
                self.data = json.loads(chunk)
            elif kind == 0x004E4942:
                self.binary = chunk
            at += 8 + length

    def accessor(self, index):
        acc = self.data["accessors"][index]
        n = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}[acc["type"]]
        fmt = {5120: "b", 5121: "B", 5122: "h", 5123: "H", 5125: "I", 5126: "f"}[acc["componentType"]]
        width = struct.calcsize("<" + fmt * n)
        view = self.data["bufferViews"][acc["bufferView"]]
        offset = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
        stride = view.get("byteStride", width)
        rows = [list(struct.unpack_from("<" + fmt * n, self.binary, offset + i * stride)) for i in range(acc["count"])]
        assert "sparse" not in acc, "Sparse accessor needs explicit decoding"
        return rows

    def animation(self, name, bones_only=False):
        anim = next(a for a in self.data.get("animations", []) if a.get("name") == name)
        result = {}
        for channel in anim["channels"]:
            target = channel["target"]
            if bones_only and target["path"] == "weights":
                continue
            sampler = anim["samplers"][channel["sampler"]]
            node = self.data["nodes"][target["node"]].get("name", str(target["node"]))
            result[node + "/" + target["path"]] = {
                "interpolation": sampler.get("interpolation", "LINEAR"),
                "times": self.accessor(sampler["input"]),
                "values": self.accessor(sampler["output"]),
            }
        return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=ROOT / "validation/asset.identity.json")
    args = parser.parse_args()
    checks = []
    def check(name, passed, details=None):
        checks.append({"name": name, "passed": bool(passed), "details": details or {}})
    manifest = json.loads((ROOT / "assets/zombie.revisions.json").read_text())
    check("F1 is startup; only F1 F2 F4 active", manifest["default_revision"] == "original"
          and set(manifest["revision_order"]) == {"original", "r2", "r4"})
    r3 = next(r for r in manifest["revisions"] if r["id"] == "r3")
    check("R3 is explicitly deprecated and archived", r3.get("status") == "deprecated"
          and not r3.get("selectable", True) and "archive/r3/" in r3["model_path"])
    hashes = {}
    for rel, expected in ORIGINALS.items():
        actual = sha(ROOT / rel)
        hashes[rel] = actual
        check("Preserved bytes: " + rel, actual == expected, {"expected": expected, "actual": actual})
    for profile in manifest["revisions"]:
        for field, digest in [("model_path", "model_sha256"), ("blend_path", "blend_sha256")]:
            rel = profile[field].removeprefix("res://")
            actual = sha(ROOT / rel)
            hashes[rel] = actual
            check("Catalog matches " + rel, actual == profile[digest], {"actual": actual, "catalog": profile[digest]})
    old = Glb(ROOT / "archive/r4.previous/Zombie.r4.glb")
    glb = Glb(ROOT / "assets/Zombie.r4.glb")
    data = glb.data
    triangles = sum((data["accessors"][p["indices"]]["count"] if "indices" in p else data["accessors"][p["attributes"]["POSITION"]]["count"]) // 3
                    for m in data["meshes"] for p in m["primitives"])
    check("Full R4 geometry below 15000 triangles including caps", triangles < 15000, {"triangles": triangles})
    check("R4 retains 59 skin joints", len(data["skins"]) == 1 and len(data["skins"][0]["joints"]) == 59)
    check("All GLB buffers and images are self-contained", all("uri" not in b for b in data.get("buffers", []))
          and all("bufferView" in im for im in data.get("images", [])))
    old_ibm = old.accessor(old.data["skins"][0]["inverseBindMatrices"])
    new_ibm = glb.accessor(data["skins"][0]["inverseBindMatrices"])
    check("R4 inverse bind matrices preserved exactly", old_ibm == new_ibm)
    base_comparison = {}
    for action in BASE_ACTIONS:
        before, after = old.animation(action, True), glb.animation(action, True)
        exact = before == after
        maximum = 0.0
        comparable = before.keys() == after.keys()
        if comparable:
            for key in before:
                a, b = before[key], after[key]
                comparable &= a["times"] == b["times"] and len(a["values"]) == len(b["values"])
                if len(a["values"]) == len(b["values"]):
                    for x, y in zip(a["values"], b["values"]):
                        maximum = max(maximum, *(abs(i-j) for i, j in zip(x, y)))
        base_comparison[action] = {"exact_decoded_channel_match": exact, "same_sampling": comparable,
                                   "maximum_component_difference": maximum}
        check("Preserved base action " + action, comparable and maximum < 1e-5, base_comparison[action])
    contract = json.loads((ROOT / "assets/Zombie.r4.behavior.json").read_text())
    for name in BASE_ACTIONS:
        weight_tracks = {k:v for k,v in glb.animation(name).items() if k.endswith('/weights')}
        largest = max((abs(v) for channel in weight_tracks.values() for row in channel['values'] for v in row), default=0.0)
        check('All new morphs are zero in preserved base clip: ' + name, largest < 1e-6,
              {'morph_tracks': len(weight_tracks), 'largest_absolute_weight': largest})
    animations = {a["name"]: a for a in data.get("animations", [])}
    check("All new actions are in the actual R4 GLB", all(k in animations for k in contract["actions"]),
          {"required": list(contract["actions"]), "actual": list(animations)})
    action_metrics = {}
    for name, spec in contract["actions"].items():
        tracks = glb.animation(name)
        end = max(row[0] for channel in tracks.values() for row in channel["times"])
        finite = all(math.isfinite(v) for channel in tracks.values() for row in channel["values"] for v in row)
        weight_tracks = {k:v for k,v in tracks.items() if k.endswith("/weights")}
        mouth_tracks = {k:v for k,v in weight_tracks.items() if k.startswith('Z_Head/')}
        jaw_max = max((v for channel in mouth_tracks.values() for row in channel["values"] for v in row), default=0.0)
        action_metrics[name] = {"duration_seconds": end, "channels": len(tracks), "finite": finite,
                                "morph_channels": len(weight_tracks), "maximum_mouth_weight": jaw_max,
                                "maximum_corrective_weight": max((v for k,c in weight_tracks.items() if k not in mouth_tracks for row in c['values'] for v in row),default=0.0)}
        check("Action tracks and duration: " + name, finite and abs(end-spec["duration_seconds"]) < 1e-5,
              action_metrics[name])
        if "Bite" in name:
            check("Bite contains visible animated mouth morph: " + name, jaw_max > .5 and bool(mouth_tracks))
        else:
            check("Non-bite action resets the mouth: " + name, bool(mouth_tracks) and abs(jaw_max) < 1e-6)
    report = {"passed": all(c["passed"] for c in checks), "checks": checks, "source_sha256": hashes,
              "triangles_including_caps": triangles, "base_action_comparison": base_comparison,
              "r4_actions": action_metrics, "limits": ["Static source and accessor checks do not replace runtime, contact, cloth or visual review."]}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"passed": report["passed"], "checks": len(checks), "failed": [c for c in checks if not c["passed"]], "report": str(args.output)}))
    raise SystemExit(0 if report["passed"] else 1)


if __name__ == "__main__":
    main()
