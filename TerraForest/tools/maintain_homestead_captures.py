# SPDX-License-Identifier: 0BSD
"""Cold-retain Homestead previews and required G-input UI captures, two ready per family."""
import argparse
import json
from pathlib import Path

from development_storage import admit
from maintain_performance_artifacts import ROOT, no_game_processes, owned_lease
from retained_artifacts import Store, archive, confined, digest, retire

FAMILIES = {
    "vegetation_reconstruction": (
        'vegetation_reconstruction.json',
        'driver.gd',
        'saved_view.png',
        'motion.webp',
        'route.webp',
        'analysis.json', 'grass_filtered.gd', 'grass_filtered.gdshader',
        'filtered_grass.gd', 'filtered_grass.gdshader',
        'source_enabled.png', 'baseline_route.frames', 'filtered_route.frames',
        'near_baseline.png', 'near_filtered.png',
        'filtered_still.png', 'filtered_end.png', 'filtered.frames',
        'early_opaque_still.png', 'early_opaque_end.png', 'early_opaque.frames',
        'attribution_baseline.png',
        'attribution_no_specular.png',
        'attribution_no_backlight.png',
        'attribution_no_white_flowers.png',
        'attribution_no_colored_flowers.png',
        'attribution_no_stones.png',
        'attribution_no_grass.png',
        'attribution_no_cover.png',
        'attribution_no_texture.png',
        'baseline_still.png',
        'baseline_end.png',
        'baseline.frames',
        'taa_msaa_still.png',
        'taa_msaa_end.png',
        'taa_msaa.frames',
        'taa_only_still.png',
        'taa_only_end.png',
        'taa_only.frames',
    ),
    "vegetation_causes": (
        'vegetation_causes.json', 'driver.gd', 'world_lod_tags.png',
        'world_far_lod_moderate.png', 'world_far_lod_moderate_end.png', 'world_far_lod_early.png',
        'world_far_lod_early_end.png', 'world_baseline.jpg', 'mask_low_0_0.png',
        'mask_low_0_15.png', 'mask_low_1_0.png', 'mask_low_1_15.png',
        'mask_low_3_0.png', 'mask_low_3_15.png', 'mask_near_0_0.png',
        'mask_near_0_15.png', 'mask_near_1_0.png', 'mask_near_1_15.png',
        'mask_near_3_0.png', 'mask_near_3_15.png', 'mask_eight_0_0.png',
        'mask_eight_0_15.png', 'mask_eight_1_0.png', 'mask_eight_1_15.png',
        'mask_eight_3_0.png', 'mask_eight_3_15.png', 'mask_three_0_0.png',
        'mask_three_0_15.png', 'mask_three_1_0.png', 'mask_three_1_15.png',
        'mask_three_3_0.png', 'mask_three_3_15.png', 'world_baseline_end.png',
        'world_no_grass.png', 'world_no_grass_end.png', 'world_no_fade.png',
        'world_no_fade_end.png', 'world_no_texture.png', 'world_no_texture_end.png',
        'world_no_shadow_reception.png', 'world_no_shadow_reception_end.png', 'world_flat_grass.png',
        'world_flat_grass_end.png', 'world_full_detail.png', 'world_full_detail_end.png',
    ),
    "grand_buildings": ("courtyard_flats.bin", "grand_cathedral.bin", "street_tower.bin", "grand_buildings.json",
                        "courtyard_flats_exterior.png", "courtyard_flats_interior.png", "courtyard_flats_plan.png",
                        "grand_cathedral_exterior.png", "grand_cathedral_interior.png", "grand_cathedral_basement.png",
                        "street_tower_exterior.png", "street_tower_interior.png", "street_tower_plan.png"),
    "vegetation_stability": ("vegetation_stability.json", "synthetic_before.frames", "synthetic_after.frames",
                             "world_before.frames", "world_after.frames", "synthetic_motion.webp", "world_motion.webp",
                             "synthetic_before.jpg", "synthetic_after.jpg", "world_before.jpg", "world_after.jpg",
                             "trial_shader.gdshader", "driver.gd"),
    "vegetation_shading": ("vegetation_shading.json", "baseline.png", "corrected.png", "baseline_repeat.png",
                           "motion_0_before.png", "motion_0_after.png", "motion_1_before.png", "motion_1_after.png",
                           "motion_2_before.png", "motion_2_after.png"),
    "startup_loading": ("ready.png", "result.json"),
    "full_launch": ("first_ui.png", "first_ui.json"),
    "world_browser_responsiveness": ("first_ui.png", "first_ui.json"),
    "homestead_pack": ("homestead_01.png",),
    "homestead_02_pack": ("homestead_02.png",),
    "homestead_03_pack": ("homestead_03.png",),
    "homestead_04_pack": ("homestead_04.png",),
    "homestead_05_pack": ("homestead_05.png",),
    "homestead_06_pack": ("homestead_06.png",),
    "homestead_07_pack": ("homestead_07.png",),
    "homestead_08_pack": ("homestead_08.png",),
    "homestead_09_pack": ("homestead_09.png",),
    "homestead_10_pack": ("homestead_10.png",),
    "outdoor_01_pack": ("outdoor_01.png",),
    "homestead_mansion": ("mansion_exterior.png", "mansion_plan.png", "mansion_salon.png", "mansion_dining.png", "mansion_bedroom.png", "mansion_workshop.png"),
    "homestead_generated_world": ("arrival.png", "house_interior.png", "cottage_interior.png", "outdoor_yard.png", "inspection.json"),
    "house_population_world": ("outdoors.png", "outdoor_publication.json"),
    "house_furnishings": ("cottage.png", "house.png", "apartments.png", "furnishings.bin", "house_furnishings.json"),
    "object_system_world": ("object_names.png", "outdoor_storage.png", "object_density.png", "object_state.bin", "object_performance.json"),
    "object_rendering_world": ("names_on_out.png", "names_on_return.png", "object_rendering.json"),
    "model_horizon": ("fixture.trw", "result.json"),
    "object_pack_render_mesh": ("source_materials.png", "combined_materials.png", "lod_source.png", "lod_render.png", "render_mesh.json"),
    "zombie_render_mesh": ("zombie_source.png", "zombie_combined.png", "zombie_render_mesh.json"),
    "drop_key_standard": ("backpack.png", "player_settings.png"),
}


def candidates(root=ROOT, keep_ready=2):
    ready = {family: [] for family in FAMILIES}
    for receipt in sorted((root / "reports/checks").glob("*/run.json")):
        run = json.loads(receipt.read_text(encoding="utf-8"))
        command = run.get("command", [])
        if run.get("result", {}).get("exit_code") is None or "--script" not in command or "--temporary" not in command:
            continue
        index = command.index("--script") + 1
        if index >= len(command):
            continue
        script = command[index]
        family = Path(script).stem
        if family not in FAMILIES or script != "res://tests/" + family + ".gd":
            continue
        folder = confined(receipt.parent, root / "reports/checks")
        if "--check-evidence-dir=" + str(folder) not in command:
            continue
        if any((folder / pin).exists() for pin in (".retain", "RETAIN_READY", "homestead.archive.json")):
            continue
        members = tuple(name for name in FAMILIES[family] if (folder / name).is_file())
        if members:
            ready[family].append((folder, members))
    for receipt in sorted((root / "reports/startup_optimization").glob("loading_*/run.json"), key=lambda p: p.parent.name.rsplit("_", 1)[-1]):
        run = json.loads(receipt.read_text(encoding="utf-8"))
        command = run.get("command", [])
        folder = confined(receipt.parent, root / "reports/startup_optimization")
        if (run.get("result", {}).get("exit_code") is None or
                "res://tests/startup_benchmark.gd" not in command or
                "--benchmark-output=" + str(folder) not in command or
                "--benchmark-profile" not in command or
                any(flag in command for flag in ("--benchmark-generate", "--benchmark-normal-load"))):
            continue
        if any((folder / pin).exists() for pin in (".retain", "RETAIN_READY", "homestead.archive.json")):
            continue
        members = tuple(name for name in FAMILIES["startup_loading"] if (folder / name).is_file())
        if members:ready["startup_loading"].append((folder, members))
    return [entry for entries in ready.values() for entry in entries[:-keep_ready]]


def maintain(apply=False, root=ROOT, keep_ready=2):
    if keep_ready not in (1, 2):
        raise ValueError("Keep one or two ready captures per family")
    selected = candidates(root, keep_ready)
    result = dict(keep_ready=keep_ready, candidates=[str(folder) for folder, _ in selected], reclaimed_bytes=0, manifests=[])
    if not apply or not selected:
        return result
    admit(root, report_bytes=1024 * 1024, world_bytes=0)
    no_game_processes()
    with owned_lease(root / "reports/retained_artifacts/writer", root):
        store = Store(root / "reports/retained_artifacts/chunks")
        for folder, members in selected:
            no_game_processes()
            if any((folder / pin).exists() for pin in (".retain", "RETAIN_READY")):
                continue
            record = archive(folder, list(members), folder / "homestead.archive.json", store,
                             dict(kind="completed-object-check-captures", run_sha256=digest(folder / "run.json")))
            result["reclaimed_bytes"] += retire(record, store, folder)
            result["manifests"].append(str(folder / "homestead.archive.json"))
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--keep-ready", type=int, choices=(1, 2), default=2)
    args = parser.parse_args()
    print(json.dumps(maintain(args.apply, keep_ready=args.keep_ready), indent=2))
