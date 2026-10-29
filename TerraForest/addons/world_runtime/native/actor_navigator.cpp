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
    ClassDB::bind_method(D_METHOD("set_interactions","ids"),&NativeActorNavigator::set_interactions);
    ClassDB::bind_method(D_METHOD("set_water_depth","depth"),&NativeActorNavigator::set_water_depth);
    ClassDB::bind_method(D_METHOD("set_agent","id","feet","goal","profile","active"),&NativeActorNavigator::set_agent);
    ClassDB::bind_method(D_METHOD("remove_agent","id"),&NativeActorNavigator::remove_agent);
    ClassDB::bind_method(D_METHOD("clear"),&NativeActorNavigator::clear);
    ClassDB::bind_method(D_METHOD("invalidate","bounds"),&NativeActorNavigator::invalidate,DEFVAL(AABB()));
    ClassDB::bind_method(D_METHOD("advance","delta","readiness","admission"),&NativeActorNavigator::advance);
    ClassDB::bind_method(D_METHOD("steering_target","id"),&NativeActorNavigator::steering_target);
    ClassDB::bind_method(D_METHOD("guard_motion","id","direction","travel"),&NativeActorNavigator::guard_motion);
    ClassDB::bind_method(D_METHOD("status","id"),&NativeActorNavigator::status);
    ClassDB::bind_method(D_METHOD("state","id"),&NativeActorNavigator::state);
    ClassDB::bind_method(D_METHOD("interest_points"),&NativeActorNavigator::interest_points);
    ClassDB::bind_method(D_METHOD("route_points","id"),&NativeActorNavigator::route_points);
}
NativeActorNavigator::Agent *NativeActorNavigator::find(int64_t id){
    for(auto &agent:agents_)if(agent.id==id)return &agent;return nullptr;
}
bool NativeActorNavigator::configure(int capacity){
    if(capacity_ || capacity<1 || capacity>64)return false;
    capacity_=capacity;agents_.reserve(capacity);return true;
}
void NativeActorNavigator::set_water_depth(const Callable &depth){
    if(depth==water_depth_)return;water_depth_=depth;graph_.clear();
    for(auto &agent:agents_){agent.route.water_depth=depth;agent.route.invalidate();agent.journey.invalidate();}
}
void NativeActorNavigator::set_exclusions(const TypedArray<RID> &ids){
    if(ids.size()>64)return;exclusions_=ids.duplicate();
    graph_.clear();
    TypedArray<RID> planning=exclusions_.duplicate();planning.append_array(interactions_);
    for(auto &agent:agents_){agent.ray->set_exclude(planning);agent.shape->set_exclude(planning);agent.motion_ray->set_exclude(exclusions_);agent.motion_shape->set_exclude(exclusions_);agent.route.invalidate();agent.journey.invalidate();}
}
void NativeActorNavigator::set_interactions(const TypedArray<RID> &ids){
    if(ids.size()>64||ids==interactions_)return;interactions_=ids.duplicate();set_exclusions(exclusions_);
}
bool NativeActorNavigator::set_agent(int64_t id,const Vector3 &feet,const Vector3 &goal,int profile,bool active){
    if(id<=0 || !feet.is_finite() || !goal.is_finite() || profile<0 || profile>1 || !capacity_)return false;
    Agent *agent=find(id);
    if(!agent){
        if(agents_.size()>=size_t(capacity_))return false;
        agents_.emplace_back();agent=&agents_.back();agent->id=id;agent->profile=-1;
        agent->route.water_depth=water_depth_;
        agent->ray.instantiate();agent->ray->set_collision_mask(7);agent->ray->set_exclude(exclusions_);
        agent->shape.instantiate();agent->shape->set_collision_mask(7);agent->shape->set_margin(.001);agent->shape->set_exclude(exclusions_);
        agent->motion_ray.instantiate();agent->motion_ray->set_collision_mask(7);agent->motion_ray->set_exclude(exclusions_);
        agent->motion_shape.instantiate();agent->motion_shape->set_collision_mask(7);agent->motion_shape->set_margin(.001);agent->motion_shape->set_exclude(exclusions_);
        TypedArray<RID> planning=exclusions_.duplicate();planning.append_array(interactions_);agent->ray->set_exclude(planning);agent->shape->set_exclude(planning);
    }
    agent->position=feet+CENTRE;agent->requested=goal+CENTRE;
    if(agent->profile!=profile){
        Ref<CapsuleShape3D> shape;shape.instantiate();shape->set_height(1.8);shape->set_radius(profile==0?.35:.75);
        agent->shape->set_shape(shape);agent->profile=profile;agent->route.maximum_step=profile==0?.3:0;
        // Match the standing controller's 45-degree floor capability, with a
        // small conservative tolerance. Legacy actors retain their .85 default.
        agent->route.minimum_floor_normal=profile==0?.7072:.85;
        agent->motion_shape->set_shape(shape);
        agent->route.invalidate();agent->journey.invalidate();agent->age=1;
    }
    if(!active){agent->active=false;agent->route.invalidate();agent->journey.invalidate();agent->goal=agent->position;return true;}
    const auto state=agent->regional?agent->journey.state:agent->route.state;
    const bool change=agent->requested.distance_to(agent->aimed)>.75;
    const bool regional_update=std::abs(agent->requested.y-agent->aimed.y)>2.5||
        ((state==ActorRoute::FOLLOWING||state==ActorRoute::ARRIVED)&&
        (agent->position.distance_to(agent->planned_from)>4||agent->position.distance_to(agent->goal)<4));
    const bool retarget=!agent->active || (agent->age>=.4 && change && (!agent->regional||regional_update)) ||
        ((agent->regional?agent->journey.state:agent->route.state)==ActorRoute::ARRIVED && agent->requested.distance_to(agent->goal)>.2);
    agent->active=true;
    if(retarget){
        Vector3 offset=agent->requested-agent->position;offset.y=0;
        agent->regional=offset.length()>12||std::abs(agent->requested.y-agent->position.y)>.5;
        agent->goal=agent->requested;agent->planned_from=agent->position;
        agent->age=0;agent->aimed=agent->requested;agent->route.invalidate();agent->journey.invalidate();
    }
    return true;
}
void NativeActorNavigator::remove_agent(int64_t id){
    agents_.erase(std::remove_if(agents_.begin(),agents_.end(),[&](const Agent &agent){return agent.id==id;}),agents_.end());
}
void NativeActorNavigator::clear(){agents_.clear();cursor_=0;graph_.clear();}
void NativeActorNavigator::invalidate(const AABB &bounds){
    // Cache entries may participate in any pursuit. A publication mutation
    // resets the derived graph atomically, never the authoritative world data.
    graph_.clear();for(auto &agent:agents_){agent.route.invalidate(bounds);agent.journey.invalidate();}
}
Dictionary NativeActorNavigator::advance(double delta,const Callable &readiness,const Callable &admission){
    Dictionary out;out["ok"]=false;out["route_work"]=0;out["route_work_limit"]=12;
    if(!is_inside_tree() || !readiness.is_valid() || !std::isfinite(delta) || delta<=0 || delta>.1)return out;
    readiness_=readiness;admission_=admission;auto *space=get_world_3d()->get_direct_space_state();
    const uint64_t started=Time::get_singleton()->get_ticks_usec();
    readiness_cache_.regions.clear();readiness_cache_.probes=readiness_cache_.hits=0;
    PackedVector3Array pending;
    for(int i=0;i<graph_.requests.size();++i){
        const Vector3 p=graph_.requests[i];Variant ready=readiness.call(AABB(p-Vector3(1,1.9,1),Vector3(2,3.7,2)));
        if(ready.get_type()!=Variant::BOOL||!bool(ready))pending.push_back(p);
    }
    graph_.requests=pending;
    for(auto &agent:agents_){
        agent.age+=delta;if(!agent.active)continue;
        if(!agent.regional&&(agent.route.state==ActorRoute::BLOCKED||agent.route.state==ActorRoute::SEARCH_LIMIT)){
            agent.regional=true;agent.journey.invalidate();
        }
        if(agent.regional)agent.journey.prepare(agent.position,agent.goal,agent.profile,delta);
        else {agent.route.prepare(agent.position,agent.goal,delta);agent.route.moved(agent.position,delta);}
    }
    int work=0,limit=12;size_t idle=0;
    for(auto &agent:agents_)agent.route.readiness_cache=&readiness_cache_;
    for(const auto &agent:agents_)if(agent.active&&agent.regional&&agent.journey.state==ActorRoute::PLANNING){limit=48;break;}
    out["route_work_limit"]=limit;
    while(space && !agents_.empty() && work<limit && idle<agents_.size()){
        auto &agent=agents_[cursor_++%agents_.size()];
        if(!agent.active || (agent.regional?agent.journey.state:agent.route.state)!=ActorRoute::PLANNING){++idle;continue;}
        idle=0;
        if(agent.regional)agent.journey.step(graph_,agent.route,space,readiness,admission,agent.ray,agent.shape);
        else agent.route.step(space,readiness,admission,agent.ray,agent.shape);
        ++work;
        if(Time::get_singleton()->get_ticks_usec()-started>=750)break;
    }
    out["ok"]=true;out["route_work"]=work;out["goal_probes"]=0;
    for(auto &agent:agents_)agent.route.readiness_cache=nullptr;
    out["readiness_probes"]=readiness_cache_.probes;out["readiness_cache_hits"]=readiness_cache_.hits;
    out["readiness_cache_entries"]=int(readiness_cache_.regions.size());
    out["graph_nodes"]=int(graph_.vertices.size());out["graph_node_limit"]=RegionalGraph::NODE_LIMIT;
    out["graph_cache_hits"]=int64_t(graph_.hits);out["streaming_requests"]=graph_.requests.size();
    out["planning_us"]=int64_t(Time::get_singleton()->get_ticks_usec()-started);out["agents"]=int(agents_.size());return out;
}
Vector3 NativeActorNavigator::steering_target(int64_t id){auto *agent=find(id);return agent?(agent->regional?agent->journey.target(agent->position):agent->route.target(agent->position))-CENTRE:Vector3(INFINITY,INFINITY,INFINITY);}
bool NativeActorNavigator::guard_motion(int64_t id,const Vector3 &direction,double travel){
    auto *agent=find(id);if(!agent || !direction.is_finite() || !std::isfinite(travel) || travel<0 || travel>.5 || !readiness_.is_valid())return false;
    Vector3 heading=direction;heading.y=0;if(heading.length_squared()<.00001)return true;
    Vector3 to=agent->position+heading.normalized()*real_t(std::max(.02,travel));
    const bool allowed=agent->route.permits_motion(get_world_3d()->get_direct_space_state(),agent->position,to,readiness_,admission_,agent->motion_ray,agent->motion_shape);
    agent->motion_rejection=agent->route.edge_failure();return allowed;
}
String NativeActorNavigator::state(int64_t id){
    auto *agent=find(id);if(!agent)return "sleeping";
    if(!agent->active)return "idle";
    static const char *names[]={"idle","planning","following","arrived","blocked","unavailable","search_limit"};
    return names[agent->regional?agent->journey.state:agent->route.state];
}
Dictionary NativeActorNavigator::status(int64_t id){
    auto *agent=find(id);Dictionary out;if(!agent){out["state"]="sleeping";return out;}
    out=agent->regional?agent->journey.status(graph_):agent->route.status();if(!agent->active)out["state"]="idle";
    out["planner"]=agent->regional?"regional":"local";
    out["conditional_door_count"]=interactions_.size();
    out["motion_rejection"]=agent->motion_rejection;
    out["minimum_floor_normal_y"]=agent->route.minimum_floor_normal;
    out["profile"]=agent->profile;out["local_horizon"]=false;out["goal"]=agent->goal-CENTRE;return out;
}
PackedVector3Array NativeActorNavigator::route_points(int64_t id){auto *agent=find(id);return agent&&agent->regional?agent->journey.points():PackedVector3Array();}
PackedVector3Array NativeActorNavigator::interest_points()const{
    PackedVector3Array out;
    // Keep actor bodies resident first. Unknown frontier points use remaining
    // slots. The host clips these to its declared encounter domain.
    for(const auto &agent:agents_)if(out.size()<8)out.push_back(agent.position-CENTRE);
    for(int i=0;i<graph_.requests.size()&&out.size()<8;++i)out.push_back(graph_.requests[i]-CENTRE);
    return out;
}
}
