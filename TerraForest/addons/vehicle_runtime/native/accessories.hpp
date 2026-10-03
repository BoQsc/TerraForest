// SPDX-License-Identifier: 0BSD
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <vector>
namespace terraforest {
class NativeVehicleAccessories : public godot::RefCounted {
    GDCLASS(NativeVehicleAccessories,godot::RefCounted)
    struct Mount { uint64_t id; godot::Transform3D base; godot::Vector3 p,pv,r,rv; double profile,pk,pd,rk,rd; };
    std::vector<Mount> mounts;
    godot::Vector3 previous_v,previous_w;
    bool initialized=false,disabled=false;
protected:
    static void _bind_methods();
public:
    bool configure(godot::TypedArray<godot::Node3D> nodes,godot::PackedFloat32Array profiles);
    void reset(godot::Vector3 velocity,godot::Vector3 angular);
    void step(godot::Basis basis,godot::Vector3 velocity,godot::Vector3 angular,double delta,bool enabled,double strength);
};
}
