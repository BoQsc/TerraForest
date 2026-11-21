// SPDX-License-Identifier: 0BSD
#pragma once
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/aabb.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <vector>
#include <atomic>
#include <array>
#include <deque>
#include <map>
#include <memory>
#include <mutex>
#include <unordered_map>
#include <unordered_set>
#include "water_cell_profile.hpp"
#include "water_terrain_contacts.hpp"
#include "snapshot_array.hpp"

namespace terraforest {
struct WaterSurfaceProfileCache;
class NativeWaterRegionReceipt : public godot::RefCounted {
 GDCLASS(NativeWaterRegionReceipt,godot::RefCounted)
 friend class NativeWaterRegionStore;
 friend class NativeRegionalWater;
 godot::Vector3i coordinate;
 godot::PackedByteArray packet,digest;
protected: static void _bind_methods() {}
};
class NativeRegionalWater;
class NativeWaterMapIdentity : public godot::RefCounted {
 GDCLASS(NativeWaterMapIdentity,godot::RefCounted)
 friend class NativeRegionalWater;
 godot::PackedByteArray bytes;
 godot::String identity;
 godot::Ref<NativeRegionalWater> decoded;
 godot::PackedByteArray catalog;
 bool consumed=false;
 uint64_t hash_us=0;
protected: static void _bind_methods();
public:
 godot::Ref<NativeWaterMapIdentity> prepare(const godot::PackedByteArray &data) const;
 godot::PackedByteArray get_bytes() const{return bytes;}
 godot::PackedByteArray get_catalog() const{return catalog;}
 void retire();
};
class NativeWaterSnapshot;
class NativeWaterMeshJob;
class NativeWaterEquilibriumJob;
class NativeWaterLocalEdit;
struct EquilibriumCaptureState;
enum class WaterBrickGeometry : uint8_t { mixed,air,solid };
struct StructureWaterContacts {uint64_t bytes=sizeof(std::shared_ptr<const WaterSolidProfile>)*512;std::array<std::shared_ptr<const WaterSolidProfile>,512> cells;};
// Immutable hand-off: only the terrain worker writes this object. No scene,
// inventory or live water state is touched by the worker.
class NativeWaterTerrainPatch : public godot::RefCounted {
    GDCLASS(NativeWaterTerrainPatch,godot::RefCounted)
    friend class NativeRegionalWater;
    friend class NativeWaterEquilibriumJob;
    friend class NativeWaterLocalEdit;
    godot::Vector3i coord;
    godot::PackedByteArray boundary;
    std::shared_ptr<const TerrainWaterContacts> contacts;
    std::array<float,729> density{};
    std::array<uint16_t,512> floor{},ceiling{};
    std::vector<std::vector<WaterSolidClip::Plane>> structure_hulls;
    std::shared_ptr<StructureWaterContacts> structures;
    std::atomic<bool> cached_cancelled{false};
    uint64_t cached_started_us=0,cached_worker_us=0;
    bool terrain_prepared=false,structure_only=false,general_terrain=false;
    WaterBrickGeometry brick_geometry=WaterBrickGeometry::mixed;
    void classify_uniform_terrain();
    godot::AABB structure_edit_bounds;
    // Exact cell-local density samples identify identical terrain-only hulls.
    std::map<std::array<uint32_t,8>,std::shared_ptr<const WaterSolidProfile>> density_profiles;
    int structure_cursor=0;
    int64_t prepare_structures();
    int64_t sample_boundary(godot::Object *core,int64_t budget,int64_t rev,int64_t cancel,const godot::PackedByteArray *packet);
    int cursor=0,status=-1;
    int64_t revision=-1,epoch=-1;
protected: static void _bind_methods();
public:
    bool configure(const godot::Vector3i &coordinate);
    bool set_structure_hulls(const godot::Array &hulls);
    int64_t sample_terrain(godot::Object *core,int64_t budget,int64_t rev,int64_t cancel);
    void prepare_cached();
    void cancel_cached();
    godot::Dictionary statistics() const;
};

// A bounded worker handoff; each patch retains the existing sampling algorithm.
class NativeWaterTerrainBatch : public godot::RefCounted {
    GDCLASS(NativeWaterTerrainBatch,godot::RefCounted)
    std::vector<godot::Ref<NativeWaterTerrainPatch>> patches;
    size_t cursor=0;
    int64_t revision=-1,epoch=-1;
protected: static void _bind_methods();
public:
    bool configure(const godot::Array &input);
    int64_t sample_terrain(godot::Object *core,int64_t budget,int64_t rev,int64_t cancel);
};

// Sparse 0.5 m finite volumes in 4 m regions. Amounts are integer millilitres.
// Terrain-derived floor/ceiling intervals are cached, not re-solved per frame.
// Live stores belong to the main thread; private load stores may be decoded
// on the loading worker and handed off only after that worker has completed.
class NativeRegionalWater : public godot::RefCounted {
    GDCLASS(NativeRegionalWater,godot::RefCounted)
    friend class NativeWaterSnapshot;
    friend class NativeWaterMeshJob;
    friend class NativeWaterEquilibriumJob;
    friend class NativeWaterLocalEdit;
    friend class NativeWaterMapIdentity;
    friend class NativeWaterRegionStore;
    friend class NativeGeneratedLakeBake;
    using Key=uint64_t;
    struct Region {
        SnapshotArray<uint16_t,512> floor,ceiling;
        SnapshotArray<uint64_t,512> water;
        // Explicit scoop vacancies, allocated only in bucket-edited regions.
        // They store missing material, never simulated water or bucket identity.
        std::vector<uint32_t> vacancies;
        SnapshotArray<float,729> density;
        std::shared_ptr<const TerrainWaterContacts> contacts;
        std::shared_ptr<const StructureWaterContacts> structures;
        bool valid=false,has_density=false,replace_water=false;
        WaterBrickGeometry brick_geometry=WaterBrickGeometry::mixed;
        // Event-driven settling; the pending flag survives snapshots. The
        // cursor is disposable: replaying a scan never replays a transfer.
        bool settle_pending=false;
        // Five outgoing faces per cell; fixed storage, no per-cell heap queue.
        std::array<uint64_t,40> settle_mask{};
        uint16_t settle_cursor=0;
        // 0 ordinary, 1 regenerable ocean, 2 ocean touched by gameplay/terrain.
        uint8_t ocean_state=0;
        uint8_t occupancy_version=13;
        bool limited_building_edit=false;
        godot::AABB building_edit_bounds;
        // Conservative charge per retained owner, even when payload is shared.
        static constexpr uint64_t payload_bytes=2*SnapshotArray<uint16_t,512>::retained_bytes+
            SnapshotArray<uint64_t,512>::retained_bytes+SnapshotArray<float,729>::retained_bytes;
        uint64_t encoded_contacts_bytes() const;
        uint32_t encoded_vacancies() const;
    };
    static WaterCellProfile profile(const Region &r,int i) {
        if(r.brick_geometry==WaterBrickGeometry::air){WaterCellProfile clear;clear.cut=true;return clear;}
        if(r.floor[i]==r.ceiling[i])return WaterCellProfile::make(nullptr,false,r.floor[i],r.ceiling[i]);
        float d[8];int x=i%8,y=(i/8)%8,z=i/64;
        for(int c=0;c<8;++c)d[c]=r.density[x+(c&1)+9*(y+((c>>1)&1))+81*(z+((c>>2)&1))];
        auto result=WaterCellProfile::make(d,r.has_density,r.floor[i],r.ceiling[i]);
        if(r.contacts)r.contacts->attach(result,i);
        if(r.structures&&r.structures->cells[i])result.solid=r.structures->cells[i].get();
        return result;
    }
    WaterCellProfile surface_profile(const godot::Vector3i &p,bool snapshot=false) const;
    static bool joined(const WaterCellProfile &a,uint64_t av,const WaterCellProfile &b,uint64_t bv,int axis,int side) {
        return av&&bv&&WaterCellProfile::face_overlap(a,a.head(av),b,b.head(bv),axis,side);
    }
    static bool joined_vertical(const WaterCellProfile &a,uint64_t av,const WaterCellProfile &b,uint64_t bv){
        return av&&bv&&a.ceiling==500&&b.open_bottom&&WaterCellProfile::vertical_overlap(a,a.head(av),b,b.head(bv));
    }
    // The saved ocean, local settlement and remote excavations share this store.
    static constexpr size_t MAX_REGIONS=8192;
    static constexpr uint32_t MAGIC=0x31575256;
    // Expanded worker data, including region records and serialized contacts.
    // The compound archive stores the small content-addressed pack index.
    static constexpr int64_t MAX_EXPANDED_BYTES=160*1024*1024;
    static constexpr uint64_t MAX_FROZEN_BYTES=256*1024*1024;
    static constexpr uint64_t MAX_TOTAL=uint64_t(1)<<52;
    struct ReconstructedCell {uint16_t index;std::array<double,4> heights;};
    struct QuerySurface {
        // Identical triangles with position-only welding and region-local
        // ownership. Shading duplicates and absolute owner coordinates are not
        // retained in the CPU query cache.
        godot::PackedVector3Array vertices;
        godot::PackedInt32Array indices;
        std::vector<uint16_t> owners;
        std::vector<ReconstructedCell> reconstructed;
        godot::PackedByteArray render_digest;
        uint64_t bytes() const {return uint64_t(vertices.size())*sizeof(godot::Vector3)+uint64_t(indices.size())*sizeof(int32_t)+owners.size()*sizeof(uint16_t)+reconstructed.size()*sizeof(ReconstructedCell)+render_digest.size();}
        godot::Vector3 vertex(int index) const {return vertices[indices[index]];}
        // While the ocean proxy is visible, only a resident free surface
        // coincident with that plane can supply a visible interaction owner.
        bool on_ocean_proxy(int i,int region_y) const {
            if(owners[i/3]&0x8000)return false;
            const float level=40-region_y*4;
            const auto a=vertex(i),b=vertex(i+1),c=vertex(i+2);
            return a.y==level&&b.y==level&&c.y==level&&(c-a).cross(b-a).y>0;
        }
    };
    std::map<Key,QuerySurface> published_surfaces,staged_surfaces;
    uint64_t staged_surface_bytes=0;
    int64_t staged_surface_delta=0;
    static constexpr uint64_t MAX_SURFACE_CACHE_BYTES=64*1024*1024;
    bool publication_enabled=false,publish_pending=false;
    std::unordered_set<Key> equilibrium_dependencies;
    std::unordered_set<Key> local_edit_regions;
    std::unordered_set<Key> local_occupancy_regions;
    std::unordered_set<Key> local_receiver_regions;
    // Inclusive 4 m region coordinates for edits that use connected receiver discovery.
    // One proven, outward-facing cell per unresolved region. Hints only
    // discover dependencies. The final solve still certifies the whole body.
    struct WetFrontier {
        double head=-1;
        std::unordered_map<Key,std::pair<godot::Vector3i,int>> entries;
    };
    WetFrontier wet_frontier;
    using EditRegionBox=std::pair<godot::Vector3i,godot::Vector3i>;
    std::vector<EditRegionBox> wide_edit_bounds;
    // Unpublished relaxation is speculative. A new player edit can discard it
    // without discarding that edit or waiting for a lake-wide mesh rebuild.
    struct RelaxationBefore {SnapshotArray<uint64_t,512> water;std::vector<uint32_t> vacancies;uint8_t ocean_state;};
    std::map<Key,RelaxationBefore> relaxation_before;
    std::unordered_set<Key> relaxation_dirty_before,urgent_meshes;
    bool background_change=false,batch_urgent=false;
    bool western_ocean=false,surrounding_ocean=false;
    std::unordered_set<Key> published_regions,staged_ready;
    bool ocean_column_published(int x,int z) const;
    bool generating_ocean=false;
    uint64_t published_batch=0,query_cache_bytes=0;
    mutable uint64_t query_builds=0,query_cache_hits=0;
    const QuerySurface *query_surface(Key k,QuerySurface &temporary) const;
    std::map<Key,Region> regions;
    std::map<Key,godot::PackedByteArray> deferred_regions;
    struct OceanCached {Region region;uint64_t bytes=0,stamp=0;};
    std::map<Key,OceanCached> ocean_cache;
    uint64_t ocean_cache_bytes=0,ocean_cache_clock=0,ocean_cache_hits=0;
    std::unordered_map<Key,uint64_t> ocean_edit_interests;
    std::unordered_map<Key,uint64_t> ocean_settlement_interests;
    uint64_t ocean_edit_retry_until=0;
    int prepare_ocean_regions(const godot::AABB &bounds,bool background);
    void trim_ocean_cache(uint64_t incoming=0);
    bool restore_ocean_cache(Key k);
    void retire_pristine_ocean(Key k);

    // Main-thread snapshot cache. PackedByteArray copy-on-write keeps an older
    // worker-owned save immutable when the live store changes. Never retain more
    // than 64 MiB here; larger captures remain uncached.
    mutable godot::PackedByteArray saved_snapshot,saved_catalog,frozen_catalog;
    mutable godot::Ref<godot::RefCounted> saved_frozen;
    mutable bool snapshot_cached=false;
    mutable uint64_t snapshot_builds=0,snapshot_hits=0;
    void invalidate_snapshot(bool map_changed=true) const;
    mutable uint64_t map_revision=0;
    mutable uint64_t survey_revision=0;
    mutable uint64_t usage_revision=UINT64_MAX;
    mutable int64_t packed_region_bytes=0, packed_region_count=0;
    mutable godot::String survey_saved_identity;
    uint64_t survey_identity_hash_us=0,survey_identity_scene_hash_us=0;

    std::map<Key,Region> mesh_snapshot;
    // Immersion uses the same occupied state as the displayed/query batch.
    std::map<Key,Region> published_occupancy,staged_occupancy;
    std::unordered_set<Key> mesh_snapshot_absent,mesh_snapshot_dependencies;
    std::deque<Key> batch_queue;
    std::vector<Key> batch_owners;
    bool batch_active=false;
    uint64_t batch_id=0;
    void preserve_mesh_region(Key k);
    void cancel_mesh_batch();
    void prioritize_mesh(Key k);
    const Region *surface_region(Key k,bool snapshot) const;

    std::deque<Key> requests,meshes;
    std::unordered_set<Key> request_set,mesh_set,restored_cache;
    uint64_t cache_rebuilds=0;
    uint64_t solid_cache_bytes=0;
    uint64_t total=0,sampled=0,cache_hits=0,changes=0;
    uint64_t last_us=0,max_us=0,mesh_us=0,max_mesh_us=0;
    bool limit=false;
    struct Fill {
        bool running=false;
        Key seed=0;
        godot::Vector3i low,high;
        int level=0;
        int64_t remaining=-1;
        std::deque<Key> queue;
        std::unordered_set<Key> seen;
    } fill;
    static Key key(const godot::Vector3i &p);
    static godot::Vector3i position(Key k);
    static godot::Vector3i cell(const godot::Vector3 &p);
    static Key region_key(const godot::Vector3i &p);
    static int index(const godot::Vector3i &p);
    static bool in_domain(const godot::Vector3i &p);
    Region *get(const godot::Vector3i &p,bool request);
    const Region *get(const godot::Vector3i &p) const;
    static uint32_t mesh_owner_mask(int cell_index);
    void changed_owners(Key region, uint32_t owners);
    void changed(const godot::Vector3i &p);
    void request(Key k);
    void invalidate_regions(const godot::AABB &bounds,bool replace_water,bool buildings=false);
    std::deque<Key> settling;
    std::unordered_set<Key> settling_set;
    uint64_t settle_steps=0,settle_transfers=0,settle_us=0;
    bool settle_profiling=false;
    uint64_t settle_face_us=0,settle_profiled_faces=0,settle_max_face_us=0;
    godot::Vector3i settle_slowest_cell;
    int settle_slowest_direction=0;
    void wake_settling(Key k,int cell_index=-1);
    void settle_cell(const godot::Vector3i &p,int direction);
    using Placement=std::vector<std::pair<godot::Vector3i,uint64_t>>;
    bool plan_connected_scoop(Placement &cells,uint64_t amount,godot::Dictionary &out,double floor_level=-1e30) const;
    bool bucket_footprint(godot::Vector3i target,const godot::Vector3 &aim,uint64_t amount,bool collect,int &x0,int &z0,godot::Dictionary &out);
    bool plan_vacancy_refill(godot::Vector3i target,const godot::Vector3 &aim,uint64_t amount,Placement &take) const;
    bool plan_local_refill(godot::Vector3i target,const godot::Vector3 &aim,uint64_t amount,Placement &take) const;
    bool plan_placement(godot::Vector3i target,const godot::Vector3 &aim,uint64_t amount,Placement &take,godot::Dictionary &out,bool allow_refill=true);
    void apply_placement(const Placement &take);
    void process_fill();
    struct SurfaceMesh {
        bool valid=true;
        godot::PackedVector3Array vertices,normals;
        godot::PackedVector2Array uv;
        godot::PackedColorArray colors;
        godot::PackedVector3Array render_vertices,render_normals;
        godot::PackedVector2Array render_uv;
        godot::PackedColorArray render_colors;
        godot::PackedInt32Array render_indices;
        godot::PackedVector3Array query_vertices;
        godot::PackedInt32Array query_indices;
        std::vector<uint16_t> owners;
        std::vector<ReconstructedCell> reconstructed;
        godot::Dictionary faces;
    };
    bool surface_budget_failed=false;
    godot::Ref<NativeWaterMeshJob> pending_mesh_job;
    godot::Ref<NativeWaterEquilibriumJob> equilibrium_capture;
    godot::Ref<NativeWaterEquilibriumJob> continue_equilibrium_capture(uint64_t deadline);
    uint64_t mesh_worker_us=0,max_mesh_worker_us=0;
    bool surface_ready(Key owner,bool snapshot=false) const;
    bool dry_surface_owner(Key owner,bool snapshot) const;
    enum class SurfaceStreams { All, Indexed, Query };
    bool build_level_surface(Key owner,const std::array<const Region*,27> &halo,SurfaceMesh &output) const;
    static void identify_render_surface(SurfaceMesh &surface);
    bool build_open_sheet(Key owner,const std::array<const Region*,27> &halo,SurfaceMesh &surface) const;
    SurfaceMesh build_surface(Key owner,bool snapshot=false,bool include_contacts=false,const std::atomic<bool> *cancel=nullptr,WaterSurfaceProfileCache *profiles=nullptr,SurfaceStreams streams=SurfaceStreams::All) const;
    bool decode(const godot::PackedByteArray &data,bool install,bool prepare_render=true);
protected: static void _bind_methods();
public:
    godot::Array pending_edit_patches() const;
    godot::Ref<NativeWaterLocalEdit> capture_local_edit(bool wide=false) const;
    godot::Dictionary accept_local_edit(const godot::Ref<NativeWaterLocalEdit> &edit);
    int64_t interrupt_relaxation();
    void settle_after_edit(const godot::AABB &bounds);
    godot::Ref<NativeWaterEquilibriumJob> begin_equilibrium(int64_t budget_usec=0,bool local_response=false);
    godot::Dictionary finish_equilibrium(const godot::Ref<NativeWaterEquilibriumJob> &job);
    int64_t advance_settling(int64_t budget=256);
    void configure_settling_profile(bool enabled){settle_profiling=enabled;settle_face_us=settle_profiled_faces=settle_max_face_us=0;}
    void set_western_ocean(bool enabled){if(western_ocean!=enabled){western_ocean=enabled;invalidate_snapshot();}}
    void set_surrounding_ocean(bool enabled){if(surrounding_ocean!=enabled){surrounding_ocean=enabled;invalidate_snapshot();}}
    godot::Dictionary water_patch_state() const;
    godot::PackedByteArray capture_water_patch(const godot::Vector3i &origin,const godot::Vector3i &size,int64_t revision,int64_t owner) const;
    bool validate_water_patch(const godot::PackedByteArray &data) const;
    godot::Dictionary restore_water_patch(const godot::PackedByteArray &data,int64_t revision,int64_t owner);
    godot::Dictionary survey_ocean(int64_t cursor,int64_t expected_revision) const;
    // Single-region transfer primitive; the caller must establish checkpoint and
    // terrain identity before reusing occupancy. It never retires live data.
    bool retire_region(const godot::Ref<NativeWaterRegionReceipt> &receipt,int64_t expected_revision);
    bool register_deferred_regions(const godot::PackedInt32Array &coordinates,const godot::PackedByteArray &digests);
    godot::Dictionary deferred_region_page(int64_t cursor,int64_t limit) const;
    godot::PackedInt32Array edited_region_coordinates() const;
    godot::PackedByteArray capture_unarchived_snapshot(const godot::PackedByteArray &catalog) const;
    godot::PackedByteArray capture_region_snapshot(const godot::Vector3i &coordinate) const;
    bool restore_region_snapshot(const godot::Vector3i &coordinate,const godot::PackedByteArray &packet,int64_t expected_revision,bool reuse_occupancy);
    godot::PackedByteArray ocean_publication_mask() const;
    godot::Dictionary update_ocean_residency(const godot::Vector3 &center,int64_t budget);
    bool prepare_ocean_edit(const godot::AABB &bounds);
    int prepare_ocean_edit_status(const godot::AABB &bounds);
    int ocean_edit_remaining = 0;
    int get_ocean_edit_remaining() const { return ocean_edit_remaining; }
    // Conservative occupied-cell column envelope for cartography, not a mesh surface.
    godot::Dictionary survey_columns(int64_t cursor,int64_t expected_revision,int64_t region_budget) const;
    godot::String survey_cache_identity() const{return survey_saved_identity;}
    int64_t survey_revision_id() const {return int64_t(map_revision);}
    int64_t total_water_ml() const {return int64_t(total);}
    godot::Dictionary survey_surfaces(int64_t cursor,int64_t expected_revision,int64_t region_budget) const;
    godot::Dictionary next_request();
    godot::Array next_requests(int64_t limit,bool ocean_only=true);
    bool accept_patch(const godot::Ref<NativeWaterTerrainPatch> &patch);
    void invalidate(const godot::AABB &bounds,bool replace_water=false);
    void invalidate_buildings(const godot::AABB &bounds);
    bool reuse_building_occupancy(const godot::Ref<NativeWaterTerrainPatch> &patch);
    void advance(int64_t budget,double seconds=1.0/60.0);
    bool begin_fill(const godot::AABB &bounds,double level,const godot::Vector3 &seed,int64_t amount);
    int64_t remove_bounds(const godot::AABB &bounds);
    godot::Dictionary place_water(const godot::Vector3 &point,int64_t amount);
    int64_t brush(const godot::Vector3 &point,double radius,int64_t amount);
    godot::Dictionary transfer_water(const godot::Vector3 &from,const godot::Vector3 &to,bool pour,godot::Object *inventory,int64_t slot,int64_t revision);
    godot::Vector3 surface_near(const godot::Vector3 &point,double radius) const;
    double depth_at(const godot::Vector3 &point) const;
    godot::PackedByteArray capture_local_snapshot(const godot::AABB &bounds) const;
    bool dry_footprint(const godot::Vector3 &from,const godot::Vector3 &middle,const godot::Vector3 &to,double radius,double vertical_offset) const;
    bool overlaps_occupied(const godot::AABB &bounds) const;
    bool has_deferred_overlap(const godot::AABB &bounds) const;
    godot::Dictionary cell_geometry(const godot::Vector3 &point) const;
    godot::PackedByteArray placement_mask(const godot::TypedArray<godot::Transform3D> &transforms) const;
    godot::Dictionary raycast_vacancy(const godot::Vector3 &from,const godot::Vector3 &to) const;
    godot::Dictionary raycast_surface(const godot::Vector3 &from,const godot::Vector3 &to) const;
    bool commit_mesh_batch(int64_t id,const godot::Array &retiring=godot::Array(),const godot::Array &revealing=godot::Array());
    godot::Dictionary next_mesh_batch(bool background=false,bool indexed_only=false,bool prepared_only=false,bool joint_edit=false);
    // Diagnostic contact flag audits the closed volume with the same builder.
    // Runtime publication and picking use the same closed material boundary.
    godot::Dictionary next_mesh(bool include_contacts=false);
    godot::Dictionary runtime_state() const;
    godot::Dictionary capacity_usage(int64_t catalog_bytes,int64_t empty_catalog_bytes) const;
    godot::Dictionary statistics() const;
    godot::PackedByteArray capture_streaming_snapshot(const godot::PackedByteArray &catalog) const;
    godot::Dictionary inspect_streaming_snapshot(const godot::PackedByteArray &data) const;
    godot::Variant capture_storage_snapshot(const godot::PackedByteArray &catalog) const;
    godot::PackedByteArray capture_snapshot(const godot::PackedByteArray &catalog) const;
    bool restore_prepared(const godot::Ref<NativeWaterMapIdentity> &prepared);
    bool restore_snapshot(const godot::PackedByteArray &data);
    bool validate_snapshot(const godot::PackedByteArray &data) const;
    godot::PackedByteArray snapshot_catalog(const godot::PackedByteArray &data) const;
};

// Worker owns an immutable local halo, never the live water store or scene.
class NativeWaterEquilibriumJob : public godot::RefCounted {
    GDCLASS(NativeWaterEquilibriumJob,godot::RefCounted)
    friend class NativeRegionalWater;
    friend class NativeWaterLocalEdit;
    godot::Ref<NativeRegionalWater> frozen;
    uint64_t revision=0,elapsed_us=0,visited_cells=0,blocked_ml=0;
    uint64_t displacement_visits=0,displacement_searches=0;
    uint64_t closed_basins=0,closed_basin_ml=0;
    int64_t ocean_exchange_ml=0;
    std::array<uint64_t,8> phase_us{};
    uint64_t reserved_bytes=0;
    size_t cell_limit=131072;
    size_t hierarchy_cell_limit=131072;
    static std::atomic<uint64_t> pending_bytes;
    std::vector<uint64_t> required,changed_regions,capture_keys;
    std::unordered_set<uint64_t> local_donors;
    std::vector<NativeRegionalWater::EditRegionBox> wide_edit_bounds;
    // An immutable terrain reader and a known-empty structure bound let the
    // worker follow newly opened faces without round trips through the scene.
    struct FieldReader { godot::Rect2i bounds; godot::Ref<godot::RefCounted> core; };
    std::vector<FieldReader> field_readers;
    godot::AABB clear_structure_bounds;
    godot::Dictionary structure_hulls;
    int64_t field_revision=-1,field_epoch=-1;
    size_t receiver_slots=0;
    uint64_t receiver_bytes=0,receiver_solid_bytes=0,receiver_solid_limit=0,private_rounds=0;
    const char *receiver_fallback=nullptr;
    std::unordered_set<uint64_t> existing_outside;
    std::map<uint64_t,NativeRegionalWater::Region> receiver_neighbours;
    std::vector<uint64_t> prepared_receivers;
    // Identical region-local extraction inputs can share exact contact
    // geometry across receiver waves. Keys include the vertical domain edge.
    struct ReceiverTemplate { godot::PackedByteArray input; NativeRegionalWater::Region region; };
    std::mutex template_mutex;
    std::unordered_multimap<uint64_t,ReceiverTemplate> receiver_templates;
    size_t template_bytes=0,template_hits=0;
    std::array<NativeRegionalWater::Region,2> homogeneous_receivers;
    size_t classified_receivers=0;
    using LayerSignature=std::array<int16_t,9>;
    std::map<LayerSignature,NativeRegionalWater::Region> layered_receivers;
    size_t reused_layered_receivers=0;
    // Classification is private to one sealed edit. Only receivers reached
    // through an actual submerged opening enter the persisted region ledger.
    using ReceiverClass=std::array<uint8_t,17>;
    std::unordered_map<uint64_t,ReceiverClass> receiver_classes;
    bool survey_attempted=false;
    size_t air_frontier_receivers=0;
    void expand_air_frontier();
    bool prepare_receivers();
    size_t capture_cursor=0;
    std::shared_ptr<EquilibriumCaptureState> capture_selection;
    godot::String reason;
    bool success=false,consumed=false,local_response=false;
    enum class SpanResult { fallback, dependencies, settled };
    NativeRegionalWater::WetFrontier wet_frontier;
    bool advance_wet_frontier();
    SpanResult settle_wide_spans();
    SpanResult settle_wide_prisms();
    SpanResult settle_column_portals();
    size_t column_rooms=0,column_portals=0,column_tiers=0;
    uint64_t column_us=0;
    const char *column_fallback=nullptr;
    size_t prism_nodes=0,prism_edges=0;
    std::array<uint64_t,5> prism_us{};
    uint64_t receiver_us=0;
    const char *prism_fallback=nullptr;
    size_t wide_spans=0,wide_cells=0,wide_basin_leaves=0;
    const char *wide_fallback=nullptr;
    std::atomic<bool> started{false},ready{false},cancelled{false};
protected: static void _bind_methods();
public:
    ~NativeWaterEquilibriumJob();
    void prepare();
    bool set_edit_field(const godot::Array &groups,const godot::AABB &bounds,const godot::Dictionary &solids,int64_t revision,int64_t epoch);
    void cancel(){cancelled.store(true);}
    bool is_ready()const{return ready.load(std::memory_order_acquire);}
};

// One worker owns the occupancy update, equilibrium and detailed mesh for a
// resident edit. Its isolated store shares immutable region payloads with the
// authority. Only the main thread can adopt the finished delta and show it.
class NativeWaterLocalEdit : public godot::RefCounted {
    GDCLASS(NativeWaterLocalEdit,godot::RefCounted)
    friend class NativeRegionalWater;
    godot::Ref<NativeRegionalWater> store;
    uint64_t owner=0,revision=0,survey=0,publication=0;
    size_t receiver_slots=0;
    std::vector<uint64_t> new_receivers;
    godot::Array field_groups;
    godot::AABB field_bounds;
    godot::Dictionary solid_hulls;
    int64_t field_revision=-1,field_epoch=-1;
    bool sample_edit_occupancy(godot::Array &patches);
    std::vector<uint64_t> sampled_regions;
    std::unordered_set<uint64_t> changed_regions;
    godot::Array packets;
    godot::Dictionary result;
    std::atomic<bool> started{false},ready{false},cancelled{false};
    bool complete=false,consumed=false;
protected: static void _bind_methods();
public:
    bool set_field(const godot::Array &groups,const godot::AABB &bounds,const godot::Dictionary &solids,int64_t rev,int64_t epoch);
    void cancel(){cancelled.store(true);}
    void prepare(const godot::Array &patches,bool prepare_render=false);
};

// Worker owns an immutable local halo, never the live water store or scene.
class NativeWaterMeshJob : public godot::RefCounted {
    GDCLASS(NativeWaterMeshJob,godot::RefCounted)
    friend class NativeRegionalWater;
    godot::Ref<NativeRegionalWater> frozen;
    std::vector<NativeRegionalWater::SurfaceMesh> results;
    // Completed owners can be uploaded while other lanes clip their surfaces.
    std::mutex delivery_mutex;
    std::map<size_t,NativeRegionalWater::SurfaceMesh> deliverable;
    std::vector<uint64_t> owners;
    size_t consumed=0;
    bool indexed_only=false,foreground=false;
    uint64_t batch=0,elapsed_us=0,reserved_bytes=0;
    static std::atomic<uint64_t> pending_bytes;
    std::atomic<bool> started{false},ready{false},cancelled{false};
    void release_reservation();
protected: static void _bind_methods();
public:
    void prepare();
    void cancel(){cancelled.store(true);}
    bool is_ready()const{return ready.load(std::memory_order_acquire);}
    ~NativeWaterMeshJob();
};

// Single worker owns serialization; no live scene/runtime references escape.
class NativeWaterSnapshot : public godot::RefCounted {
    GDCLASS(NativeWaterSnapshot,godot::RefCounted)
    friend class NativeRegionalWater;
    godot::Ref<NativeRegionalWater> frozen;
    godot::PackedByteArray catalog,serialized;
    uint64_t reserved_bytes=0;
    static std::atomic<uint64_t> pending_bytes;
protected: static void _bind_methods();
public:
    godot::PackedByteArray serialize_snapshot();
    ~NativeWaterSnapshot();
};
}
