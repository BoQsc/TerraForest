// SPDX-License-Identifier: 0BSD
#pragma once
#include "actor_route.hpp"
#include "regional_navigation.hpp"
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/variant/typed_array.hpp>
namespace terraforest {
// Routes for externally owned character bodies. No duplicate actor or store tick.
class NativeActorNavigator : public godot::Node3D {
    GDCLASS(NativeActorNavigator,godot::Node3D)
    struct Agent {
        int64_t id=0;int profile=0;bool active=false,regional=false;
        double age=1;godot::Vector3 position,goal,requested,aimed,planned_from;
        ActorRoute route;
        const char *motion_rejection="none";
        RegionalRoute journey;
        godot::Ref<godot::PhysicsRayQueryParameters3D> ray;
        godot::Ref<godot::PhysicsShapeQueryParameters3D> shape;
        godot::Ref<godot::PhysicsRayQueryParameters3D> motion_ray;
        godot::Ref<godot::PhysicsShapeQueryParameters3D> motion_shape;
    };
    std::vector<Agent> agents_;
    int capacity_=0;size_t cursor_=0;
    godot::Callable readiness_,admission_;
    godot::Callable water_depth_;
    godot::TypedArray<godot::RID> exclusions_;
    godot::TypedArray<godot::RID> interactions_;
    RegionalGraph graph_;
    Agent *find(int64_t id);
protected:
    static void _bind_methods();
public:
    bool configure(int capacity);
    void set_exclusions(const godot::TypedArray<godot::RID> &ids);
    void set_interactions(const godot::TypedArray<godot::RID> &ids);
    void set_water_depth(const godot::Callable &depth);
    bool set_agent(int64_t id,const godot::Vector3 &feet,const godot::Vector3 &goal,int profile,bool active);
    void remove_agent(int64_t id);
    void clear();
    void invalidate(const godot::AABB &bounds=godot::AABB());
    godot::Dictionary advance(double delta,const godot::Callable &readiness,const godot::Callable &admission);
    godot::Vector3 steering_target(int64_t id);
    bool guard_motion(int64_t id,const godot::Vector3 &direction,double travel);
    godot::Dictionary status(int64_t id);
    godot::PackedVector3Array interest_points()const;
    godot::PackedVector3Array route_points(int64_t id);
};
}
