// SPDX-License-Identifier: 0BSD
#pragma once
#include "entity_store.hpp"
#include <godot_cpp/classes/character_body3d.hpp>
namespace terraforest {
// One near-field collision proxy. Distant records remain in the store without bodies.
// Caller owns activation/readiness and calls tick once per physics step, never store.step.
class NativeEntityActor : public godot::CharacterBody3D {
    GDCLASS(NativeEntityActor,godot::CharacterBody3D)
    godot::Ref<NativeEntityStore> store_;
    int64_t handle_=0;
protected:
    static void _bind_methods();
public:
    bool profile_tick=false;
    uint64_t transform_us=0,motion_us=0,store_us=0;
    bool bind_entity(const godot::Ref<NativeEntityStore> &store,int64_t handle);
    bool tick(const godot::Vector3 &target,double delta,bool collision_ready);
};
}
