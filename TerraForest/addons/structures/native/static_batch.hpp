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
    using Placement = std::array<float,12>;
    std::map<int64_t,Placement> placements;
    std::map<BlockKey,std::set<int64_t>> groups;
    std::map<BlockKey,MultiMeshInstance3D*> batches;
    std::map<int64_t,int> slots;
    Ref<Mesh> source_mesh;
    String asset_id;
    uint64_t uploads=0;
    uint64_t instance_updates=0;
    static bool valid_transform(const float *t);
    static BlockKey group_for(const Placement &p);
    static bool valid_asset(const String &id);
    static bool parse(const PackedByteArray &bytes,String &asset,std::map<int64_t,Placement> *out);
    void rebuild(const std::set<BlockKey> &keys);
protected:
    static void _bind_methods();
public:
    bool set_instances(const Ref<Mesh> &mesh,const PackedFloat32Array &transforms);
    bool configure_asset(const String &id,const Ref<Mesh> &mesh);
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
