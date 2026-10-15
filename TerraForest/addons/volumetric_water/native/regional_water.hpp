// SPDX-License-Identifier: 0BSD
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
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
#include <unordered_map>
#include <unordered_set>
#include "water_cell_profile.hpp"

namespace terraforest {
struct TerrainWaterContacts {uint64_t bytes=0;std::array<std::vector<WaterCellProfile::Triangle>,512> floors;};
struct StructureWaterContacts {uint64_t bytes=sizeof(std::shared_ptr<const WaterSolidProfile>)*512;std::array<std::shared_ptr<const WaterSolidProfile>,512> cells;};
// Immutable hand-off: only the terrain worker writes this object. No scene,
// inventory or live water state is touched by the worker.
class NativeWaterTerrainPatch : public godot::RefCounted {
    GDCLASS(NativeWaterTerrainPatch,godot::RefCounted)
    friend class NativeRegionalWater;
    godot::Vector3i coord;
    godot::PackedByteArray boundary;
    std::shared_ptr<const TerrainWaterContacts> contacts;
    std::array<float,729> density{};
    std::array<uint16_t,512> floor{},ceiling{};
    std::vector<std::vector<WaterSolidClip::Plane>> structure_hulls;
    std::shared_ptr<StructureWaterContacts> structures;
    std::atomic<bool> cached_cancelled{false};
    uint64_t cached_started_us=0,cached_worker_us=0;
    bool terrain_prepared=false,structure_only=false;
    godot::AABB structure_edit_bounds;
    int structure_cursor=0;
    int64_t prepare_structures();
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

// Sparse 0.5 m finite volumes in 4 m regions. Amounts are integer millilitres.
// Terrain-derived floor/ceiling intervals are cached, not re-solved per frame.
// Only the main thread owns this store; all loops have explicit work bounds.
class NativeRegionalWater : public godot::RefCounted {
    GDCLASS(NativeRegionalWater,godot::RefCounted)
    using Key=uint64_t;
    struct Region {
        std::array<uint16_t,512> floor{},ceiling{};
        std::array<uint64_t,512> water{};
        // Explicit scoop vacancies, allocated only in bucket-edited regions.
        // They store missing material, never simulated water or bucket identity.
        std::vector<uint32_t> vacancies;
        std::array<float,729> density{};
        std::shared_ptr<const TerrainWaterContacts> contacts;
        std::shared_ptr<const StructureWaterContacts> structures;
        bool valid=false,has_density=false,replace_water=false;
        bool limited_building_edit=false;
        godot::AABB building_edit_bounds;
    };
    static WaterCellProfile profile(const Region &r,int i) {
        if(r.floor[i]==r.ceiling[i])return WaterCellProfile::make(nullptr,false,r.floor[i],r.ceiling[i]);
        float d[8];int x=i%8,y=(i/8)%8,z=i/64;
        for(int c=0;c<8;++c)d[c]=r.density[x+(c&1)+9*(y+((c>>1)&1))+81*(z+((c>>2)&1))];
        auto result=WaterCellProfile::make(d,r.has_density,r.floor[i],r.ceiling[i]);
        if(r.contacts&&!r.contacts->floors[i].empty()){
            result.contact=&r.contacts->floors[i];result.cut=true;result.ceiling=500;result.open_bottom=result.minimum()<0;
            for(int n=0;n<4;++n)result.floor[n]=result.raw_bottom(n&1,n>>1);
        }
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
    static constexpr size_t MAX_REGIONS=4096;
    static constexpr uint64_t MAX_TOTAL=uint64_t(1)<<52;
    struct QuerySurface {
        godot::PackedVector3Array vertices;
        std::vector<godot::Vector3i> owners;
    };
    std::map<Key,QuerySurface> published_surfaces,staged_surfaces;
    bool publication_enabled=false,publish_pending=false;
    uint64_t published_batch=0,query_cache_bytes=0;
    mutable uint64_t query_builds=0,query_cache_hits=0;
    const QuerySurface *query_surface(Key k,QuerySurface &temporary) const;
    std::map<Key,Region> regions;
    std::map<Key,Region> mesh_snapshot;
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
    void changed(const godot::Vector3i &p);
    void request(Key k);
    void invalidate_regions(const godot::AABB &bounds,bool replace_water,bool buildings=false);
    using Placement=std::vector<std::pair<godot::Vector3i,uint64_t>>;
    bool plan_connected_scoop(Placement &cells,uint64_t amount,godot::Dictionary &out) const;
    bool bucket_footprint(godot::Vector3i target,const godot::Vector3 &aim,uint64_t amount,bool collect,int &x0,int &z0,godot::Dictionary &out);
    bool plan_vacancy_refill(godot::Vector3i target,const godot::Vector3 &aim,uint64_t amount,Placement &take) const;
    bool plan_local_refill(godot::Vector3i target,const godot::Vector3 &aim,uint64_t amount,Placement &take) const;
    bool plan_placement(godot::Vector3i target,const godot::Vector3 &aim,uint64_t amount,Placement &take,godot::Dictionary &out);
    void apply_placement(const Placement &take);
    void process_fill();
    struct SurfaceMesh {
        godot::PackedVector3Array vertices,normals;
        godot::PackedVector2Array uv;
        std::vector<godot::Vector3i> owners;
        godot::Dictionary faces;
    };
    bool surface_ready(Key owner,bool snapshot=false) const;
    SurfaceMesh build_surface(Key owner,bool snapshot=false,bool include_contacts=false) const;
    bool decode(const godot::PackedByteArray &data,bool install);
protected: static void _bind_methods();
public:
    godot::Dictionary next_request();
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
    bool overlaps_occupied(const godot::AABB &bounds) const;
    godot::Dictionary cell_geometry(const godot::Vector3 &point) const;
    godot::PackedByteArray placement_mask(const godot::TypedArray<godot::Transform3D> &transforms) const;
    godot::Dictionary raycast_vacancy(const godot::Vector3 &from,const godot::Vector3 &to) const;
    godot::Dictionary raycast_surface(const godot::Vector3 &from,const godot::Vector3 &to) const;
    bool commit_mesh_batch(int64_t id);
    godot::Dictionary next_mesh_batch();
    // Diagnostic contact flag audits the closed volume with the same builder.
    // Runtime publication and picking use the same closed material boundary.
    godot::Dictionary next_mesh(bool include_contacts=false);
    godot::Dictionary statistics() const;
    godot::PackedByteArray capture_snapshot(const godot::PackedByteArray &catalog) const;
    bool restore_snapshot(const godot::PackedByteArray &data);
    bool validate_snapshot(const godot::PackedByteArray &data) const;
    godot::PackedByteArray snapshot_catalog(const godot::PackedByteArray &data) const;
};
}
