// SPDX-License-Identifier: 0BSD
#pragma once
#include "actor_route.hpp"
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/variant/typed_array.hpp>
namespace terraforest {
// Routes for externally owned character bodies. No duplicate actor or store tick.
class NativeActorNavigator : public godot::Node3D {
    GDCLASS(NativeActorNavigator,godot::Node3D)
    struct Agent {
        int64_t id=0;int profile=0;bool active=false,horizon=false,project=false;
        double age=1,project_retry=0;godot::Vector3 position,goal,requested,aimed;
        ActorRoute route;
        godot::Ref<godot::PhysicsRayQueryParameters3D> ray;
        godot::Ref<godot::PhysicsShapeQueryParameters3D> shape;
    };
    std::vector<Agent> agents_;
    int capacity_=0;size_t cursor_=0;
    godot::Callable readiness_,admission_;
    godot::TypedArray<godot::RID> exclusions_;
    Agent *find(int64_t id);
protected:
    static void _bind_methods();
public:
    bool configure(int capacity);
    void set_exclusions(const godot::TypedArray<godot::RID> &ids);
    bool set_agent(int64_t id,const godot::Vector3 &feet,const godot::Vector3 &goal,int profile,bool active);
    void remove_agent(int64_t id);
    void clear();
    void invalidate(const godot::AABB &bounds=godot::AABB());
    godot::Dictionary advance(double delta,const godot::Callable &readiness,const godot::Callable &admission);
    godot::Vector3 steering_target(int64_t id);
    bool guard_motion(int64_t id,const godot::Vector3 &direction,double travel);
    godot::Dictionary status(int64_t id);
};
}
