// SPDX-License-Identifier: 0BSD
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/variant/array.hpp>
#include <vector>

namespace terraforest {
// Immutable, bounded input. No live water store or scene node enters the worker.
class NativeWaterRenderPages : public godot::RefCounted {
    GDCLASS(NativeWaterRenderPages,godot::RefCounted)
    struct Owner {
        godot::Vector3 offset;
        godot::PackedVector3Array vertices,normals;
        godot::PackedVector2Array uv;
        godot::PackedColorArray colors;
        godot::PackedInt32Array indices;
    };
    std::vector<std::vector<Owner>> pages;
    godot::Array meshes;
    bool configured=false,prepared=false;
    int64_t bytes=0,vertices=0,indices=0,worker_us=0;
protected:
    static void _bind_methods();
public:
    bool configure(const godot::Array &input);
    void prepare();
    godot::Array result() const {return meshes;}
    godot::Dictionary statistics() const;
};
}
