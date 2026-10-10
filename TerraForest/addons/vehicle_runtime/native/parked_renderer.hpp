// SPDX-License-Identifier: 0BSD
#pragma once
#include "fleet.hpp"
#include <godot_cpp/classes/multi_mesh_instance3d.hpp>
#include <godot_cpp/classes/multi_mesh.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <vector>
#include <godot_cpp/classes/shape3d.hpp>
namespace terraforest {
class NativeParkedVehicleRenderer : public godot::Node3D {
 GDCLASS(NativeParkedVehicleRenderer,godot::Node3D)
 struct Part {uint64_t node;godot::Ref<godot::MultiMesh> mesh;godot::Transform3D local;godot::PackedFloat32Array buffer;};
 godot::Ref<NativeVehicleFleet> fleet_;
 std::vector<Part> parts_;
 int capacity_=0;
 godot::Ref<godot::Shape3D> collision_shape_;
 godot::Transform3D collision_local_;
 std::vector<godot::RID> bodies_;
 std::vector<godot::Transform3D> body_poses_;
 std::vector<bool> body_enabled_;
 void hide_all();
protected: static void _bind_methods();
 void _notification(int what);
public:
 ~NativeParkedVehicleRenderer();
 bool configure_collision(const godot::Ref<godot::Shape3D> &shape,const godot::Transform3D &local);
 bool configure(const godot::Ref<NativeVehicleFleet> &fleet,const godot::Array &parts,int capacity);
 godot::Dictionary refresh(const godot::Vector3 &center,double radius,const godot::PackedInt64Array &excluded,int budget);
};
}
