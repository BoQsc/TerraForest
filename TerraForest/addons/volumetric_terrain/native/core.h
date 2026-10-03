// SPDX-License-Identifier: 0BSD
#pragma once
#include "platform.h"
constexpr int WORLD=2000, WORLD_Y=256, PAGE=16, PAGE_SAMPLES=4096, MAX_PAGES=16384;
constexpr float SDF_BAND=4.f, SDF_SCALE=1024.f;
constexpr u32 SAVE_MAGIC=0x32575254u, MESH_MAGIC=0x324d5254u, REPLY_MAGIC=0x32505254u;
// Identity of the immutable base field (height, caves and generated materials).
// Legacy format-1 worlds use generator 1. New generators must keep that reader.
constexpr u32 TERRAIN_GENERATOR_ID=1; // Default remains the legacy landscape.
struct Page {
 u32 key=0; i16 *d=nullptr;u8 *mat=nullptr;
 // Derived worker-owned digest; never serialized or used as authoritative data.
 mutable bool geometry_digest_valid=false;
 mutable u8 geometry_digest[32]{};
};
struct Cave {V3 a,b;float r;};
struct Basin {float x,z,level;};
struct SkyProbe {V3 p,n;float sky;};
// Stable owner storage outside World, so reset/load cannot reset cancellation.
struct BuildControl {u32 epoch=0;};
struct GeometryCache;
struct World {
 BuildControl *build_control=nullptr;
 Map pages_by_key,blocks; List<Page> pages; List<Cave> caves; List<List<u32>> block_columns;
 u32 *edit_columns=nullptr;
 int seed=1703, revision=0, edits=0;u64 changed_samples=0;
 u32 generator_id=TERRAIN_GENERATOR_ID;
 Basin basins[4]{};int basin_count=0;
 // Derived only: never serialized. Owned by the terrain worker, not renderer.
 int surface_style=0;
 // Optional diagnostics, worker-owned and never serialized.
 bool profile_mesh=false;
 mutable float mesh_stage_ms[4]={}; // extraction, simplification, blocks, shading
 mutable GeometryCache *geometry_cache=nullptr;
 // Worker-owned immutable generator samples for the current reconstruction column.
 mutable List<float> owned_heights;
 mutable int owned_height_x=-1,owned_height_z=-1,owned_height_size=0,owned_height_seed=0;
 mutable int lighting_revision=-1;
 mutable Map light_roofs,light_samples,light_probe_ids;
 mutable List<float> light_tops;
 mutable List<SkyProbe> light_probes;
 mutable u64 light_rays=0,light_steps=0,light_unresolved=0,light_probe_hits=0;
 void init(int p_seed=1703,u32 generator=1);void release();
 bool set_block(u32 key,int material);void erase_block(u32 key);
 float height(float x,float z)const;
 float base(V3 p,float h)const;
 float sample(int x,int y,int z,u8*mat=nullptr)const;
 Page *ensure(int px,int py,int pz);
 bool edit(V3 a,V3 b,float radius,int shape,bool add,u8 material,V3 &lo,V3 &hi,int &changes,float depth=1.f,float clearance=0.f);
 void serialize(Bytes &out)const;bool deserialize(const u8*p,int n);
};
struct Vertex {V3 p,n;float material=0; i32 cx=0,cy=0,cz=0;u32 mask=0; V3 blend{};float substrate=0,sky=1,sun=1,ore=0,asphalt=0;};
struct Mesh {List<Vertex> v; List<u32> i;void release(){v.release();i.release();}};
// Cancellation state is outside World: save/load cannot race a main-thread request.
u32 terrain_build_epoch(const World *world=nullptr);
u32 terrain_cancel_builds(const World *world=nullptr);
bool build_patch(const World&w,int ox,int oz,int size,int step,Mesh&m,u32 expected_epoch=0xffffffffu,bool region_cache=false);
bool build_owned_region(const World&w,int ox,int oz,int size,int step,int y_begin,int y_end,Mesh&m,u32 epoch);
void release_geometry_cache(const World&w);
void invalidate_geometry_cache(const World&w,V3 lo,V3 hi);
void geometry_cache_stats(const World&w,Bytes&out);
void shade_visibility(const World&w,Mesh&m,u32 expected_epoch=0xffffffffu);
bool terrain_occluded(const World&w,V3 origin,V3 direction);
// 0 visible, 1 occluded, 2 unresolved (budget); conservative bool wrapper above.
int terrain_visibility(const World&w,V3 origin,V3 direction,int budget=1400);
void shade_mesh(const World&w,Mesh&m,u32 expected_epoch=0xffffffffu);
void add_blocks(const World&w,int ox,int oz,int size,Mesh&m,int y_begin=0,int y_end=WORLD_Y);
void encode_mesh(const Mesh&m,int ox,int oz,int size,int step,Bytes&out);
void process_request(World&w,const u8*data,int length,Bytes&out);
