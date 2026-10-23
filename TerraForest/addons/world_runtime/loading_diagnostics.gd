# SPDX-License-Identifier: 0BSD
extends RefCounted
# Observe main-thread state and worker-published counters; never acquire the
# native terrain-world mutex while generation owns it for a long bake.
static func snapshot(game:Node)->Dictionary:
 var terrain:Node=game.terrain
 var backend:RefCounted=terrain.backend
 return {
  "readiness":terrain.loading_state(game.player.position,game.fly),
  "world":{"slot":terrain.save_slot,"seed":backend.world_seed,"generator":backend.world_generator,"ready":terrain.world_ready,"snapshot_restore_ok":terrain.snapshot_restore_ok,"waiting_spawn":game.waiting_spawn,"read_only":backend.readonly_snapshot,"temporary":game.temporary_world,"save_path":ProjectSettings.globalize_path(backend.save_path),"derived_cache_path":ProjectSettings.globalize_path(backend.cache_path),"error":terrain.latest_error},
  "terrain_stream":{"tiles":terrain.tiles.size(),"active_leaves":terrain.active_leaves.size(),"in_flight":terrain.in_flight.size(),"staging":terrain.staging.size(),"batch_remaining":terrain.batch_remaining,"pending_edit":terrain.pending_edit,"worker_builds":terrain.worker_builds,"triangles":terrain.total_triangles,"mesh_cache_bytes":terrain.cache_bytes,"sdf_pages":terrain.sdf_pages,"revision":terrain.native_revision,"collision_pieces_reused":terrain.collision_pieces_reused,"collision_pieces_built":terrain.collision_pieces_built},
  "derived_cache_last_published":terrain.derived_metrics,
  "addons":game._additional_loading_diagnostics(),
  "terrain_worker":backend.startup_diagnostics()
 }
