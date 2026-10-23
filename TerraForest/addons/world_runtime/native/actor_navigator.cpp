// SPDX-License-Identifier: 0BSD
#include "actor_navigator.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/classes/world3d.hpp>
#include <algorithm>
#include <cmath>
using namespace godot;
namespace terraforest {
static const Vector3 CENTRE(0,.93,0);
void NativeActorNavigator::_bind_methods(){
    ClassDB::bind_method(D_METHOD("configure","capacity"),&NativeActorNavigator::configure);
    ClassDB::bind_method(D_METHOD("set_exclusions","ids"),&NativeActorNavigator::set_exclusions);
    ClassDB::bind_method(D_METHOD("set_agent","id","feet","goal","profile","active"),&NativeActorNavigator::set_agent);
    ClassDB::bind_method(D_METHOD("remove_agent","id"),&NativeActorNavigator::remove_agent);
    ClassDB::bind_method(D_METHOD("clear"),&NativeActorNavigator::clear);
    ClassDB::bind_method(D_METHOD("invalidate","bounds"),&NativeActorNavigator::invalidate,DEFVAL(AABB()));
    ClassDB::bind_method(D_METHOD("advance","delta","readiness","admission"),&NativeActorNavigator::advance);
    ClassDB::bind_method(D_METHOD("steering_target","id"),&NativeActorNavigator::steering_target);
    ClassDB::bind_method(D_METHOD("guard_motion","id","direction","travel"),&NativeActorNavigator::guard_motion);
    ClassDB::bind_method(D_METHOD("status","id"),&NativeActorNavigator::status);
}
NativeActorNavigator::Agent *NativeActorNavigator::find(int64_t id){
    for(auto &agent:agents_)if(agent.id==id)return &agent;return nullptr;
}
bool NativeActorNavigator::configure(int capacity){
    if(capacity_ || capacity<1 || capacity>64)return false;
    capacity_=capacity;agents_.reserve(capacity);return true;
}
void NativeActorNavigator::set_exclusions(const TypedArray<RID> &ids){
    if(ids.size()>64)return;exclusions_=ids.duplicate();
    for(auto &agent:agents_){agent.ray->set_exclude(exclusions_);agent.shape->set_exclude(exclusions_);agent.route.invalidate();}
}
bool NativeActorNavigator::set_agent(int64_t id,const Vector3 &feet,const Vector3 &goal,int profile,bool active){
    if(id<=0 || !feet.is_finite() || !goal.is_finite() || profile<0 || profile>1 || !capacity_)return false;
    Agent *agent=find(id);
    if(!agent){
        if(agents_.size()>=size_t(capacity_))return false;
        agents_.emplace_back();agent=&agents_.back();agent->id=id;agent->profile=-1;
        agent->ray.instantiate();agent->ray->set_collision_mask(7);agent->ray->set_exclude(exclusions_);
        agent->shape.instantiate();agent->shape->set_collision_mask(7);agent->shape->set_margin(.001);agent->shape->set_exclude(exclusions_);
    }
    agent->position=feet+CENTRE;agent->requested=goal+CENTRE;
    if(agent->profile!=profile){
        Ref<CapsuleShape3D> shape;shape.instantiate();shape->set_height(1.8);shape->set_radius(profile==0?.35:.75);
        agent->shape->set_shape(shape);agent->profile=profile;agent->route.maximum_step=profile==0?.3:0;
        agent->route.invalidate();agent->age=1;
    }
    if(!active){agent->active=false;agent->route.invalidate();agent->goal=agent->position;return true;}
    const bool retarget=!agent->active || (agent->age>=.4 && agent->requested.distance_to(agent->aimed)>.75) ||
        (agent->route.state==ActorRoute::ARRIVED && agent->requested.distance_to(agent->goal)>.2);
    agent->active=true;
    if(retarget){
        Vector3 offset=agent->requested-agent->position;offset.y=0;
        agent->horizon=offset.length()>12;
        agent->goal=agent->horizon?agent->position+offset.normalized()*12:agent->requested;
        agent->project=agent->horizon;agent->age=0;agent->project_retry=0;agent->aimed=agent->requested;agent->route.invalidate();
    }
    return true;
}
void NativeActorNavigator::remove_agent(int64_t id){
    agents_.erase(std::remove_if(agents_.begin(),agents_.end(),[&](const Agent &agent){return agent.id==id;}),agents_.end());
}
void NativeActorNavigator::clear(){agents_.clear();cursor_=0;}
void NativeActorNavigator::invalidate(const AABB &bounds){for(auto &agent:agents_)agent.route.invalidate(bounds);}
Dictionary NativeActorNavigator::advance(double delta,const Callable &readiness,const Callable &admission){
    Dictionary out;out["ok"]=false;out["route_work"]=0;out["route_work_limit"]=12;
    if(!is_inside_tree() || !readiness.is_valid() || !std::isfinite(delta) || delta<=0 || delta>.1)return out;
    readiness_=readiness;admission_=admission;auto *space=get_world_3d()->get_direct_space_state();
    const uint64_t started=Time::get_singleton()->get_ticks_usec();int projections=0;
    for(auto &agent:agents_){
        agent.age+=delta;agent.project_retry-=delta;if(!agent.active)continue;
        if(agent.project){
            if(agent.project_retry>0)continue;
            agent.project_retry=.5;
            AABB bounds(agent.goal-Vector3(.8,9,.8),Vector3(1.6,14,1.6));Variant ready=readiness.call(bounds);
            if(ready.get_type()!=Variant::BOOL || !bool(ready)){agent.route.state=ActorRoute::UNAVAILABLE;continue;}
            agent.ray->set_from(agent.goal+Vector3(0,4,0));agent.ray->set_to(agent.goal-Vector3(0,8,0));
            Dictionary hit=space->intersect_ray(agent.ray);++projections;
            if(hit.is_empty()){agent.route.state=ActorRoute::UNAVAILABLE;continue;}
            agent.goal.y=Vector3(hit["position"]).y+.93;agent.project=false;
        }
        agent.route.prepare(agent.position,agent.goal,delta);agent.route.moved(agent.position,delta);
    }
    int work=0;size_t idle=0;
    while(space && !agents_.empty() && work<12 && idle<agents_.size()){
        auto &agent=agents_[cursor_++%agents_.size()];
        if(!agent.active || agent.project || agent.route.state!=ActorRoute::PLANNING){++idle;continue;}
        idle=0;agent.route.step(space,readiness,admission,agent.ray,agent.shape);++work;
        if(Time::get_singleton()->get_ticks_usec()-started>=750)break;
    }
    out["ok"]=true;out["route_work"]=work;out["goal_probes"]=projections;
    out["planning_us"]=int64_t(Time::get_singleton()->get_ticks_usec()-started);out["agents"]=int(agents_.size());return out;
}
Vector3 NativeActorNavigator::steering_target(int64_t id){auto *agent=find(id);return agent?agent->route.target(agent->position)-CENTRE:Vector3(INFINITY,INFINITY,INFINITY);}
bool NativeActorNavigator::guard_motion(int64_t id,const Vector3 &direction,double travel){
    auto *agent=find(id);if(!agent || !direction.is_finite() || !std::isfinite(travel) || travel<0 || travel>.5 || !readiness_.is_valid())return false;
    Vector3 heading=direction;heading.y=0;if(heading.length_squared()<.00001)return true;
    Vector3 to=agent->position+heading.normalized()*real_t(std::max(.02,travel));
    return agent->route.permits_motion(get_world_3d()->get_direct_space_state(),agent->position,to,readiness_,admission_,agent->ray,agent->shape);
}
Dictionary NativeActorNavigator::status(int64_t id){
    auto *agent=find(id);Dictionary out;if(!agent){out["state"]="sleeping";return out;}
    out=agent->route.status();if(!agent->active)out["state"]="idle";
    out["profile"]=agent->profile;out["local_horizon"]=agent->horizon;out["goal"]=agent->goal-CENTRE;return out;
}
}
