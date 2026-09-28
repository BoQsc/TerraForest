#pragma once
#include "block_prefab.hpp"
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/classes/mesh_instance3d.hpp>
#include <godot_cpp/classes/static_body3d.hpp>
#include <godot_cpp/classes/shader_material.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <array>
#include <map>
#include <set>
#include <future>
#include <vector>

namespace terraforest {
using namespace godot;
struct BlockKey {
    int x=0,y=0,z=0;
    bool operator<(const BlockKey &b) const { return std::tie(x,y,z)<std::tie(b.x,b.y,b.z); }
};
struct BlockChunk { std::array<uint16_t,4096> cells{}; std::array<uint16_t,256> columns{}; int count=0; };
struct BlockVertex { float x,y,z,nx,ny,nz,u,v,material; };
struct BlockBake { BlockKey key; uint64_t revision=0; std::vector<BlockVertex> vertices; std::vector<int32_t> indices; };
struct BlockVisual { MeshInstance3D *mesh=nullptr; StaticBody3D *body=nullptr; int triangles=0; };

// Main-thread authoring/publication, one immutable native worker snapshot at a time.
// No SceneTree or Godot resources are touched by the bake worker.
class NativeBlockWorld : public Node3D {
    GDCLASS(NativeBlockWorld,Node3D)
    friend class NativeStructuresSnapshot;
    std::map<BlockKey,BlockChunk> chunks;
    std::set<BlockKey> dirty;
    std::map<BlockKey,uint64_t> tickets;
    std::map<BlockKey,BlockVisual> visuals;
    std::future<BlockBake> worker;
    BlockKey worker_key;
    uint64_t revision=0, rejected=0, published=0;
    Ref<ShaderMaterial> material;
    Vector3 focus;
    double collision_radius=48.0;
    bool collisions=true;
    static int div16(int v) { return v>=0?v/16:(v-15)/16; }
    static BlockKey key_for(int x,int y,int z) { return {div16(x),div16(y),div16(z)}; }
    static int index(int x,int y,int z) { return (x&15)+16*((y&15)+16*(z&15)); }
    uint16_t cell(int x,int y,int z) const;
    bool occupied(const AABB &bounds) const;
    bool prefab_records(const Ref<NativeBlockPrefab> &prefab,Vector3i origin,int turns,bool replace,PackedInt32Array *out) const;
    void invalidate(BlockKey key);
    void launch();
    void publish(BlockBake &&bake);
    void update_collisions();
    void ensure_material();
    static BlockBake bake(BlockKey key,uint64_t ticket,std::array<uint16_t,5832> halo);
    static bool parse(const PackedByteArray &bytes,std::map<BlockKey,BlockChunk> *out);
protected:
    static void _bind_methods();
public:
    ~NativeBlockWorld();
    void _process(double delta) override;
    bool set_cells(const PackedInt32Array &records);
    bool can_place_prefab(const Ref<NativeBlockPrefab> &prefab,Vector3i origin,int quarter_turns,bool replace=false) const;
    bool place_prefab(const Ref<NativeBlockPrefab> &prefab,Vector3i origin,int quarter_turns,bool replace=false);
    Ref<NativeBlockPrefab> capture_prefab(Vector3i origin,Vector3i size) const;
    PackedByteArray overlap_mask(const TypedArray<Transform3D> &transforms, const AABB &prototype_bounds) const;
    int get_cell(Vector3i p) const { return cell(p.x,p.y,p.z); }
    Dictionary stats() const;
    void set_focus(Vector3 p) { focus=p; }
    void set_collision_radius(double radius);
    bool is_idle() const { return dirty.empty()&&!worker.valid(); }
    void flush_bakes(); // Explicit offline baking/test operation; never called each frame.
    PackedByteArray capture_snapshot() const;
    bool validate_snapshot(const PackedByteArray &bytes) const { return parse(bytes,nullptr); }
    bool restore_snapshot(const PackedByteArray &bytes);
    void create_showcase();
};
}
