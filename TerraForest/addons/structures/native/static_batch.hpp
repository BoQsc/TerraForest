#pragma once
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/classes/multi_mesh_instance3d.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <vector>
namespace terraforest {
using namespace godot;
// One shared model per collection. Native spatial partitioning makes culling
// local; authoring does not create a node for every fence, rung, or prop.
class NativeStaticBatch : public Node3D {
    GDCLASS(NativeStaticBatch,Node3D)
    std::vector<MultiMeshInstance3D*> batches;
    int count=0;
protected:
    static void _bind_methods();
public:
    bool set_instances(const Ref<Mesh> &mesh,const PackedFloat32Array &transforms);
    Dictionary stats() const;
};
}
