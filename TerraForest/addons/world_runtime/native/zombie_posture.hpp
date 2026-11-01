// SPDX-License-Identifier: 0BSD
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/character_body3d.hpp>
#include <godot_cpp/classes/collision_shape3d.hpp>
#include <godot_cpp/classes/box_shape3d.hpp>
#include <godot_cpp/classes/capsule_shape3d.hpp>
#include <godot_cpp/classes/physics_shape_query_parameters3d.hpp>
#include <godot_cpp/variant/aabb.hpp>
#include <godot_cpp/variant/dictionary.hpp>
namespace terraforest {
class NativeZombiePosture : public godot::RefCounted {
    GDCLASS(NativeZombiePosture,godot::RefCounted)
    godot::Ref<godot::BoxShape3D> probe_,proxy_;
    godot::Ref<godot::PhysicsShapeQueryParameters3D> query_;
    int queries_=0,blocked_=0;
    bool clear(godot::CharacterBody3D *body,const godot::Ref<godot::Shape3D> &shape,const godot::Transform3D &local);
protected:
    static void _bind_methods();
public:
    NativeZombiePosture();
    bool apply_bounds(godot::CharacterBody3D *body,godot::CollisionShape3D *collider,const godot::AABB &bounds);
    bool restore_capsule(godot::CharacterBody3D *body,godot::CollisionShape3D *collider,const godot::Ref<godot::CapsuleShape3D> &shape,const godot::Transform3D &local);
    godot::Dictionary statistics()const;
    bool validate_snapshot(const godot::PackedByteArray &bytes)const;
};
}
