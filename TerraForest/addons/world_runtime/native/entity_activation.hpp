// SPDX-License-Identifier: 0BSD
#pragma once
#include "entity_actor.hpp"
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <vector>
namespace terraforest {
class NativeEntityActivation : public godot::Node3D {
    GDCLASS(NativeEntityActivation,godot::Node3D)
    godot::Ref<NativeEntityStore> store_;
    struct Proxy {NativeEntityActor *body;int64_t handle=0;};
    std::vector<Proxy> proxies_;
    godot::PackedInt64Array active_;
    void sleep_all();
protected:
    static void _bind_methods();
public:
    bool configure(const godot::Ref<NativeEntityStore> &store,int capacity);
    godot::Dictionary select(const godot::Vector3 &center,double radius,int candidate_budget=4096);
    bool tick(const godot::PackedVector3Array &targets,double delta,const godot::PackedByteArray &ready);
    godot::PackedInt64Array active_handles() const {return active_;}
};
}
