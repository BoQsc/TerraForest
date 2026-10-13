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
#include <array>
#include <deque>
#include <map>
#include <unordered_set>

namespace terraforest {
// Immutable hand-off: only the terrain worker writes this object. No scene,
// inventory or live water state is touched by the worker.
class NativeWaterTerrainPatch : public godot::RefCounted {
    GDCLASS(NativeWaterTerrainPatch,godot::RefCounted)
    friend class NativeRegionalWater;
    godot::Vector3i coord;
    std::array<float,729> density{};
    std::array<uint16_t,512> floor{},ceiling{};
    int cursor=0,status=-1;
    int64_t revision=-1,epoch=-1;
protected: static void _bind_methods();
public:
    bool configure(const godot::Vector3i &coordinate);
    int64_t sample_terrain(godot::Object *core,int64_t budget,int64_t rev,int64_t cancel);
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
        std::array<float,729> density{};
        bool valid=false,has_density=false;
    };
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

    std::deque<Key> active,requests,meshes;
    std::unordered_set<Key> active_set,request_set,mesh_set,restored_cache;
    std::deque<Key> vertical;
    std::unordered_set<Key> vertical_set;
    std::map<Key,uint32_t> vertical_regions;
    void queue_vertical(const godot::Vector3i &lower);
    void settle_vertical();
    uint64_t vertical_steps=0;
    uint64_t cache_rebuilds=0;
    uint64_t total=0,steps=0,sampled=0,cache_hits=0,changes=0;
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
    void wake(const godot::Vector3i &p);
    void changed(const godot::Vector3i &p);
    void request(Key k);
    void process_cell(const godot::Vector3i &p);
    void process_fill();
    void move(const godot::Vector3i &a,const godot::Vector3i &b,uint64_t amount);
    struct SurfaceMesh {
        godot::PackedVector3Array vertices,normals;
        godot::PackedVector2Array uv;
        std::vector<godot::Vector3i> owners;
        godot::Dictionary faces;
    };
    bool surface_ready(Key owner,bool snapshot=false) const;
    SurfaceMesh build_surface(Key owner,bool snapshot=false) const;
    bool decode(const godot::PackedByteArray &data,bool install);
protected: static void _bind_methods();
public:
    godot::Dictionary next_request();
    bool accept_patch(const godot::Ref<NativeWaterTerrainPatch> &patch);
    void invalidate(const godot::AABB &bounds);
    void advance(int64_t budget);
    bool begin_fill(const godot::AABB &bounds,double level,const godot::Vector3 &seed,int64_t amount);
    int64_t remove_bounds(const godot::AABB &bounds);
    int64_t brush(const godot::Vector3 &point,double radius,int64_t amount);
    godot::Dictionary transfer_water(const godot::Vector3 &from,const godot::Vector3 &to,bool pour,godot::Object *inventory,int64_t slot,int64_t revision,int64_t max_litres);
    godot::Vector3 surface_near(const godot::Vector3 &point,double radius) const;
    double depth_at(const godot::Vector3 &point) const;
    godot::PackedByteArray placement_mask(const godot::TypedArray<godot::Transform3D> &transforms) const;
    godot::Dictionary raycast_surface(const godot::Vector3 &from,const godot::Vector3 &to) const;
    bool commit_mesh_batch(int64_t id);
    godot::Dictionary next_mesh_batch();
    godot::Dictionary next_mesh();
    godot::Dictionary statistics() const;
    godot::PackedByteArray capture_snapshot(const godot::PackedByteArray &catalog) const;
    bool restore_snapshot(const godot::PackedByteArray &data);
    bool validate_snapshot(const godot::PackedByteArray &data) const;
    godot::PackedByteArray snapshot_catalog(const godot::PackedByteArray &data) const;
};
}
