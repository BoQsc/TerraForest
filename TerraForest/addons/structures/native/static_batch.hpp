#pragma once
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/classes/multi_mesh_instance3d.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include "block_world.hpp"
#include <map>
#include <set>
#include <vector>
namespace terraforest {
using namespace godot;
// One shared model per collection. Native spatial partitioning makes culling
// local; authoring does not create a node for every fence, rung, or prop.
class NativeStaticBatch : public Node3D {
    GDCLASS(NativeStaticBatch,Node3D)
    friend class NativeStructuresSnapshot;
    friend class NativeStaticHistory;
    using Placement = std::array<float,12>;
    std::map<int64_t,Placement> placements;
    std::map<BlockKey,std::set<int64_t>> groups;
    using RenderKey = std::pair<BlockKey,uint32_t>;
    std::map<RenderKey,MultiMeshInstance3D*> batches;
    std::map<int64_t,int> slots;
    std::map<RenderKey,std::vector<int64_t>> resident_ids;
    std::map<BlockKey,std::vector<int64_t>> render_ids;
    std::map<BlockKey,AABB> render_bounds;
    std::vector<RenderKey> render_pending;
    bool render_streaming=false,render_dirty=true;
    Vector3 render_focus,render_selection_focus;
    double render_radius=384;
    int render_batch_limit=128,render_upload_limit=2,render_candidates=0,render_blocked=0;
    uint64_t render_byte_limit=4*1024*1024,render_tick_bytes=256*1024;
    uint64_t render_bytes=0,render_evictions=0,render_queries=0,render_uploaded_bytes=0;
    uint32_t render_page_capacity() const;
    uint64_t render_page_size(RenderKey key) const;
    void release_batch(RenderKey key);
    void release_group(BlockKey key);
    void upload_batch(RenderKey key);
    void select_render_batches();
    Ref<Mesh> source_mesh;
    String asset_id;
    bool asset_locked=false;
    uint64_t uploads=0;
    uint64_t instance_updates=0;
    uint64_t edit_revision=0;
    bool defer_change_signal=false;
    void publish_change();
    bool placement_clear(const PackedFloat32Array &transform,const AABB &protection) const;
    struct ProxyBody { RID body; std::vector<RID> shapes; };
    std::map<int64_t,ProxyBody> collision_bodies;
    std::map<RID,int64_t> body_ids;
    std::map<BlockKey,AABB> collision_bounds;
    std::vector<int64_t> collision_pending;
    AABB proxy_box;
    std::vector<AABB> proxy_parts;
    int proxy_shape_limit=4096,proxy_shapes_per_tick=64;
    Vector3 collision_focus,selection_focus;
    Transform3D collision_transform;
    double proxy_radius=0;
    int proxy_limit=512,proxy_build_limit=8;
    bool collision_dirty=true,proxy_transform_valid=true;
    uint64_t proxy_builds=0,proxy_evictions=0,proxy_queries=0;
    int proxy_candidates=0,invalid_proxies=0;
    static Transform3D placement_transform(const Placement &p);
    void release_proxy(int64_t id);
    void clear_proxies();
    void invalidate_proxy(int64_t id);
    void refresh_collision_bounds(const std::set<BlockKey> &keys);
    void select_proxies();
    static bool valid_transform(const float *t);
    static BlockKey group_for(const Placement &p);
    static bool valid_asset(const String &id);
    static bool parse(const PackedByteArray &bytes,String &asset,std::map<int64_t,Placement> *out);
    void rebuild(const std::set<BlockKey> &keys);
protected:
    static void _bind_methods();
    void _notification(int what);
public:
    NativeStaticBatch();
    PackedByteArray overlap_mask(const TypedArray<Transform3D> &transforms,const AABB &bounds) const;
    bool can_insert_instance(const PackedFloat32Array &transform,const AABB &protected_bounds) const;
    int64_t insert_instance(const PackedFloat32Array &transform,const AABB &protected_bounds);
    ~NativeStaticBatch();
    void _physics_process(double delta) override;
    void _process(double delta) override;
    bool configure_render_streaming(bool enabled,double radius,int64_t batch_limit,int64_t byte_limit,int64_t uploads_per_tick,int64_t bytes_per_tick);
    void set_render_focus(Vector3 focus);
    Dictionary render_stats() const;
    bool configure_collision(const AABB &box,double radius,int64_t instance_limit,int64_t builds_per_tick);
    bool configure_compound_collision(const TypedArray<AABB> &boxes,double radius,int64_t instance_limit,int64_t builds_per_tick,int64_t shape_limit,int64_t shapes_per_tick);
    void set_collision_focus(Vector3 focus);
    Dictionary collision_stats() const;
    int64_t placement_for_body(RID body) const;
    bool set_instances(const Ref<Mesh> &mesh,const PackedFloat32Array &transforms);
    bool configure_asset(const String &id,const Ref<Mesh> &mesh);
    bool lock_asset_identity();
    bool upsert_instances(const PackedInt64Array &ids,const PackedFloat32Array &transforms);
    bool remove_instances(const PackedInt64Array &ids);
    PackedFloat32Array get_instance(int64_t id) const;
    PackedInt64Array get_ids() const;
    PackedByteArray capture_snapshot() const;
    bool validate_snapshot(const PackedByteArray &bytes) const;
    bool restore_snapshot(const PackedByteArray &bytes);
    Dictionary stats() const;
};
}
