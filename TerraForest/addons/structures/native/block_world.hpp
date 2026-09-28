#pragma once
#include "block_prefab.hpp"
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/classes/mesh_instance3d.hpp>
#include <godot_cpp/classes/static_body3d.hpp>
#include <godot_cpp/classes/shader_material.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <array>
#include <map>
#include <set>
#include <thread>
#include <mutex>
#include <condition_variable>
#include <vector>
#include <deque>

namespace terraforest {
using namespace godot;
struct BlockKey {
    int x=0,y=0,z=0;
    bool operator<(const BlockKey &b) const { return std::tie(x,y,z)<std::tie(b.x,b.y,b.z); }
};
struct BlockChunk { std::array<uint16_t,4096> cells{}; std::array<uint16_t,256> columns{}; int count=0; };
struct BlockVertex { float x,y,z,nx,ny,nz,u,v,material; };
struct BlockBake { BlockKey key; uint64_t revision=0; std::vector<BlockVertex> vertices; std::vector<int32_t> indices; int lattice_width=0; };
struct BlockVisual {
    MeshInstance3D *mesh=nullptr; StaticBody3D *body=nullptr;
    int triangles=0; uint64_t payload_bytes=0; int lattice_width=0;
    PackedVector3Array collision_vertices;
    PackedInt32Array collision_indices;
    int collision_at=0;
    bool collision_ready=false;
};
struct CachedBlockBake { BlockBake bake; uint64_t used=0; };
struct BlockChange { int32_t x,y,z; uint16_t before,after; };
static_assert(sizeof(BlockChange)==16,"History cell accounting must match allocated records");

// Main-thread authoring/publication, one immutable native worker snapshot at a time.
// No SceneTree or Godot resources are touched by the bake worker.
class NativeBlockWorld : public Node3D {
    GDCLASS(NativeBlockWorld,Node3D)
    friend class NativeStructuresSnapshot;
    std::map<BlockKey,BlockChunk> chunks;
    std::set<BlockKey> dirty;
    std::map<BlockKey,uint64_t> tickets;
    std::map<BlockKey,BlockVisual> visuals;
    // Exactly one main-thread submission may be outstanding, including a ready
    // result. The sleeping worker never accesses authoring or scene state.
    std::thread worker_thread;
    std::mutex worker_mutex;
    std::condition_variable worker_wake;
    bool worker_active=false;
    bool worker_stopping=false,worker_pending=false,worker_ready=false;
    BlockKey submitted_key;
    uint64_t submitted_ticket=0;
    std::array<uint16_t,5832> submitted_halo{};
    BlockBake worker_result;
    uint64_t worker_starts=0,worker_submissions=0,worker_consumed=0;
    void worker_loop();
    void submit_bake(BlockKey key,uint64_t ticket,const std::array<uint16_t,5832> &halo);
    bool take_bake(BlockBake &result,bool wait);
    BlockKey worker_key;
    uint64_t revision=0, rejected=0, published=0;
    Ref<ShaderMaterial> material;
    Vector3 focus;
    double collision_radius=48.0;
    bool collisions=true;
    std::deque<StaticBody3D *> retired_collision;
    uint64_t collision_ticks=0,collision_pieces_built=0,collision_pieces_retired=0;
    double collision_last_ms=0,collision_max_ms=0;
    double collision_cook_max_ms=0,collision_attach_max_ms=0,collision_activate_max_ms=0,collision_retire_max_ms=0;
    static constexpr int COLLISION_PIECE_TRIANGLES=1024, COLLISION_RETIRE_PER_TICK=4;
    bool collision_near(BlockKey key) const;
    void retire_collision(BlockVisual &visual);
    bool streaming=false,residency_dirty=false;
    double render_radius=384;
    int render_limit=256;
    uint64_t mesh_budget=64*1024*1024,cache_budget=32*1024*1024,mesh_bytes=0,cache_bytes=0;
    uint64_t cache_clock=0,cache_hits=0,cache_misses=0,mesh_evictions=0,cache_evictions=0,residency_checks=0;
    Vector3 residency_focus;
    std::set<BlockKey> wanted,settled,budget_blocked;
    std::map<BlockKey,CachedBlockBake> bake_cache;
    void refresh_residency();
    void release_visual(BlockKey key);
    void erase_cached(BlockKey key);
    void cache_bake(BlockBake &&bake);
    void trim_cache();
    bool admit_mesh(BlockKey key,uint64_t bytes);
    double distance_to_focus(BlockKey key) const;
    std::deque<std::vector<BlockChange>> undo_edits,redo_edits;
    uint64_t history_bytes=0,history_budget=0,unrecorded_edits=0;
    int history_steps=0;
    bool apply_cells(const PackedInt32Array &records,bool record_history,bool &changed);
    void remember_edit(std::vector<BlockChange> &&changes);
    void trim_history();
    bool replay_edit(bool backwards,const AABB &protected_bounds);
    static int div16(int v) { return v>=0?v/16:(v-15)/16; }
    static BlockKey key_for(int x,int y,int z) { return {div16(x),div16(y),div16(z)}; }
    static int index(int x,int y,int z) { return (x&15)+16*((y&15)+16*(z&15)); }
    uint16_t cell(int x,int y,int z) const;
    bool occupied(const AABB &bounds) const;
    bool prefab_records(const Ref<NativeBlockPrefab> &prefab,Vector3i origin,int turns,bool replace,PackedInt32Array *out) const;
    void invalidate(BlockKey key);
    void launch(bool allow_cached_upload=true);
    bool publish(BlockBake &&bake);
    bool update_collisions();
    void ensure_material();
    static BlockBake bake(BlockKey key,uint64_t ticket,std::array<uint16_t,5832> halo);
    static bool parse(const PackedByteArray &bytes,std::map<BlockKey,BlockChunk> *out);
protected:
    static void _bind_methods();
public:
    Dictionary raycast_cells(Vector3 from,Vector3 to) const;
    Dictionary raycast_scene(Vector3 from,Vector3 to,int64_t mask,const TypedArray<RID> &exclude) const;
    ~NativeBlockWorld();
    void _process(double delta) override;
    bool set_cells(const PackedInt32Array &records);
    bool configure_history(int64_t byte_limit,int step_limit);
    void clear_history();
    Dictionary history_stats() const;
    bool can_undo() const { return !undo_edits.empty(); }
    bool can_redo() const { return !redo_edits.empty(); }
    bool undo(const AABB &protected_bounds=AABB()) { return replay_edit(true,protected_bounds); }
    bool redo(const AABB &protected_bounds=AABB()) { return replay_edit(false,protected_bounds); }
    bool can_place_prefab(const Ref<NativeBlockPrefab> &prefab,Vector3i origin,int quarter_turns,bool replace=false) const;
    bool place_prefab(const Ref<NativeBlockPrefab> &prefab,Vector3i origin,int quarter_turns,bool replace=false);
    Ref<NativeBlockPrefab> capture_prefab(Vector3i origin,Vector3i size) const;
    PackedByteArray overlap_mask(const TypedArray<Transform3D> &transforms, const AABB &prototype_bounds) const;
    int get_cell(Vector3i p) const { return cell(p.x,p.y,p.z); }
    Dictionary stats() const;
    Dictionary collision_stats() const;
    void set_focus(Vector3 p);
    bool configure_streaming(bool enabled,double radius,int64_t chunk_limit,int64_t mesh_byte_limit,int64_t cache_byte_limit);
    Dictionary streaming_stats() const;
    void set_collision_radius(double radius);
    bool is_idle() const { return !residency_dirty&&dirty.empty()&&!worker_active; }
    void flush_bakes(); // Explicit offline baking/test operation; never called each frame.
    PackedByteArray capture_snapshot() const;
    bool validate_snapshot(const PackedByteArray &bytes) const { return parse(bytes,nullptr); }
    bool restore_snapshot(const PackedByteArray &bytes);
    void create_showcase();
};
}
