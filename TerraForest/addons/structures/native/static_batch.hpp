#pragma once
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/classes/multi_mesh_instance3d.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include "block_world.hpp"
#include "model_bounds_index.hpp"
#include <map>
#include <set>
#include <vector>
#include <memory>
#include <godot_cpp/classes/hashing_context.hpp>
namespace terraforest {
using namespace godot;
// One shared model per collection. Native spatial partitioning makes culling
// local; authoring does not create a node for every fence, rung, or prop.
struct ModelCheckpointLease;
class NativeStaticBatch : public Node3D {
    GDCLASS(NativeStaticBatch,Node3D)
    friend class NativeModelMapRegion;
    friend class NativePrefabPlacement;
    friend class NativeStructureQueries;
    friend class NativeModelTransferScheduler;
    std::shared_ptr<ModelCheckpointLease> paging_checkpoint;
    uint64_t paging_owner=0;
    friend class NativeStructuresSnapshot;
    friend class NativeStaticHistory;
    friend class NativeBlockRegionStore;
    using Placement = std::array<float,12>;
    std::map<int64_t,Placement> placements;
    // Runtime ownership interlock (e.g. nonempty container contents). Rebuilt
    // by the owner on load; streaming retirement is not object destruction.
    std::set<int64_t> removal_protected;
    std::map<BlockKey,std::set<int64_t>> groups;
    struct UnloadedRegion { PackedByteArray checksum; AABB bounds; size_t count=0; };
    struct MetadataRegion { PackedByteArray checksum; std::array<float,9> basis_max{}; std::vector<int64_t> ids; };
    static bool parse_metadata(const PackedByteArray &bytes,String &asset,PackedByteArray &checkpoint,std::map<BlockKey,MetadataRegion> &regions,std::set<int64_t> &ids);
    std::map<BlockKey,UnloadedRegion> unloaded_regions;
    ModelBoundsIndex unloaded_bounds;
    std::set<int64_t> unloaded_ids;
    static PackedByteArray encode_placements(const String &asset,const std::map<int64_t,Placement> &values);
    static bool parse_region(const PackedByteArray &bytes,String &asset,BlockKey &region,std::map<int64_t,Placement> &values);
    static bool valid_model_region(BlockKey key);
    bool prepare_metadata(const PackedByteArray &bytes,std::map<BlockKey,UnloadedRegion> &staged,std::set<int64_t> &ids) const;
    void install_metadata(std::map<BlockKey,UnloadedRegion> &&staged,std::set<int64_t> &&ids,const String &identity=String());
    bool unload_region_impl(const PackedByteArray &packet);
    bool restore_region_impl(const PackedByteArray &packet);
    struct RegionAdmission {
        enum Phase { OUTER_HASH, INNER_HASH, RECORDS, ROLLBACK, RETIRE_RECORDS } phase=OUTER_HASH;
        BlockKey key;
        uint64_t history_owner=0,validated_records=0;
        bool retiring=false;
        PackedByteArray packet;
        Ref<HashingContext> hash;
        uint64_t offset=0,record_offset=0,count=0;
        int64_t previous=0;
        std::set<int64_t> ids;
        std::vector<int64_t> ordered;
        AABB collision,visual,prototype,mesh_bounds;
        String error;
    };
    std::unique_ptr<RegionAdmission> admission;
    String admission_result="idle",admission_error;
    uint64_t admission_step_records=0,admission_step_bytes=0;
    bool admission_busy=false,admission_retiring=false;
    bool begin_region_transfer(const PackedByteArray &bytes,bool retiring);
    bool retirement_locks(BlockKey key) const;
    uint64_t admission_ticket=0;
    bool admission_owned();
    Dictionary advance_region_admission_impl(int64_t max_records,int64_t max_hash_bytes,int64_t max_usec);
    size_t hidden_record_count() const { return admission?admission->ids.size():0; }
    void fail_admission(const String &error);
    using RenderKey = std::pair<BlockKey,uint32_t>;
    std::map<RenderKey,MultiMeshInstance3D*> batches;
    std::map<int64_t,int> slots;
    std::map<RenderKey,std::vector<int64_t>> resident_ids;
    std::map<BlockKey,std::vector<int64_t>> render_ids;
    std::map<BlockKey,AABB> render_bounds;
    std::vector<RenderKey> render_pending;
    bool render_streaming=false,render_dirty=true;
    bool collision_only=false;
    bool casts_shadows=true;
    double shadow_distance=0;
    bool page_casts_shadows(RenderKey key) const;
    bool appearance_fade=false;
    std::map<int64_t,float> appearance_birth;
    uint64_t render_stride_bytes() const { return appearance_fade?64:48; }
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
    String survey_saved_identity;
    bool defer_change_signal=false;
    void publish_change(bool storage_only=false);
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
    struct CollectionRetirement {
        decltype(placements) old_placements;
        decltype(groups) old_groups;
        decltype(batches) old_batches;
        decltype(slots) old_slots;
        decltype(appearance_birth) old_birth;
        decltype(resident_ids) old_resident;
        decltype(render_ids) old_render;
        decltype(render_bounds) old_bounds;
        decltype(collision_bounds) old_collision_bounds;
        uint64_t units=0,render_bytes=0,stride_bytes=48;
    };
    std::unique_ptr<CollectionRetirement> collection_retirement;
protected:
    static void _bind_methods();
    void _notification(int what);
public:
    String survey_cache_identity() const{return survey_saved_identity;}
    AABB survey_prototype_bounds() const{return source_mesh.is_valid()?source_mesh->get_aabb():AABB();}
    Dictionary survey_index() const;
    Dictionary survey_bounds(Vector3i region,int64_t after_id,int64_t expected_revision) const;
    int64_t survey_revision_id() const{return edit_revision;}
    bool set_removal_protected(int64_t id,bool enabled);
    bool is_removal_protected(int64_t id) const {return removal_protected.count(id)!=0;}
    bool begin_region_admission(const PackedByteArray &bytes);
    bool begin_region_retirement(const PackedByteArray &bytes);
    Dictionary advance_region_retirement(int64_t max_records,int64_t max_hash_bytes,int64_t max_usec);
    bool cancel_region_retirement();
    Dictionary advance_region_admission(int64_t max_records,int64_t max_hash_bytes,int64_t max_usec);
    bool cancel_region_admission();
    Dictionary region_admission_stats() const;
    bool validate_metadata(const PackedByteArray &bytes) const;
    bool restore_metadata(const PackedByteArray &bytes);
    Dictionary capture_storage_state() const;
    PackedByteArray capture_region(Vector3i region) const;
    bool validate_region_snapshot(const PackedByteArray &bytes) const;
    bool unload_region(const PackedByteArray &expected_snapshot);
    bool restore_region(const PackedByteArray &bytes);
    bool is_region_loaded(Vector3i region) const;
    Dictionary region_stats() const;
    bool configure_collision_only();
    bool upsert_transforms(const PackedInt64Array &ids,const TypedArray<Transform3D> &transforms);
    NativeStaticBatch();
    PackedByteArray overlap_mask(const TypedArray<Transform3D> &transforms,const AABB &bounds) const;
    bool can_insert_instance(const PackedFloat32Array &transform,const AABB &protected_bounds) const;
    int64_t insert_instance(const PackedFloat32Array &transform,const AABB &protected_bounds);
    ~NativeStaticBatch();
    void _physics_process(double delta) override;
    void _process(double delta) override;
    bool configure_render_streaming(bool enabled,double radius,int64_t batch_limit,int64_t byte_limit,int64_t uploads_per_tick,int64_t bytes_per_tick);
    void set_render_focus(Vector3 focus);
    bool set_render_radius(double radius);
    Dictionary render_stats() const;
    bool is_render_region_ready(const AABB &world_bounds) const;
    void set_casts_shadows(bool enabled);
    bool set_shadow_distance(double radius);
    bool configure_appearance_fade();
    bool configure_collision(const AABB &box,double radius,int64_t instance_limit,int64_t builds_per_tick);
    bool configure_compound_collision(const TypedArray<AABB> &boxes,double radius,int64_t instance_limit,int64_t builds_per_tick,int64_t shape_limit,int64_t shapes_per_tick);
    void set_collision_focus(Vector3 focus);
    Dictionary collision_stats() const;
    bool is_collision_region_ready(const AABB &world_bounds) const;
    int64_t placement_for_body(RID body) const;
    bool set_instances(const Ref<Mesh> &mesh,const PackedFloat32Array &transforms);
    bool configure_asset(const String &id,const Ref<Mesh> &mesh);
    bool lock_asset_identity();
    bool upsert_instances(const PackedInt64Array &ids,const PackedFloat32Array &transforms);
    bool remove_instances(const PackedInt64Array &ids);
    bool clear_instances();
    bool begin_transient_clear();
    Dictionary advance_transient_clear(int64_t max_records,int64_t max_usec);
    PackedFloat32Array get_instance(int64_t id) const;
    PackedInt64Array get_ids() const;
    PackedByteArray capture_snapshot() const;
    bool validate_snapshot(const PackedByteArray &bytes) const;
    bool restore_snapshot(const PackedByteArray &bytes);
    Dictionary stats() const;
};
}
