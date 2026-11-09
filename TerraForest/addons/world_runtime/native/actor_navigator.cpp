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
    ClassDB::bind_method(D_METHOD("set_query_profiling","enabled"),&NativeActorNavigator::set_query_profiling);
    ClassDB::bind_method(D_METHOD("set_support_cache_enabled","enabled"),&NativeActorNavigator::set_support_cache_enabled);
    ClassDB::bind_method(D_METHOD("set_exclusions","ids"),&NativeActorNavigator::set_exclusions);
    ClassDB::bind_method(D_METHOD("set_interactions","ids"),&NativeActorNavigator::set_interactions);
    ClassDB::bind_method(D_METHOD("set_water_depth","depth"),&NativeActorNavigator::set_water_depth);
    ClassDB::bind_method(D_METHOD("set_agent","id","feet","goal","profile","active"),&NativeActorNavigator::set_agent);
    ClassDB::bind_method(D_METHOD("remove_agent","id"),&NativeActorNavigator::remove_agent);
    ClassDB::bind_method(D_METHOD("clear"),&NativeActorNavigator::clear);
    ClassDB::bind_method(D_METHOD("invalidate","bounds"),&NativeActorNavigator::invalidate,DEFVAL(AABB()));
    ClassDB::bind_method(D_METHOD("invalidation_stats"),&NativeActorNavigator::invalidation_stats);
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
    if(depth==water_depth_)return;water_depth_=depth;invalidate();
    for(auto &agent:agents_){agent.continuing=false;agent.route.water_depth=depth;agent.route.invalidate();agent.journey.invalidate();}
}
void NativeActorNavigator::set_exclusions(const TypedArray<RID> &ids){
    if(ids.size()>64)return;exclusions_=ids.duplicate();
    invalidate();
    TypedArray<RID> planning=exclusions_.duplicate();planning.append_array(interactions_);
    for(auto &agent:agents_){agent.continuing=false;agent.ray->set_exclude(planning);agent.shape->set_exclude(planning);agent.motion_ray->set_exclude(exclusions_);agent.motion_shape->set_exclude(exclusions_);agent.route.invalidate();agent.journey.invalidate();}
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
        // Standing routes must fit the actual 0.24 m body. The former 0.35 m
        // radius rejected physically usable aisles; height remains conservative.
        Ref<CapsuleShape3D> shape;shape.instantiate();shape->set_height(1.8);shape->set_radius(profile==0?.24:.75);
        agent->shape->set_shape(shape);agent->profile=profile;agent->route.maximum_step=profile==0?.3:0;
        // Match the standing controller's 45-degree floor capability, with a
        // small conservative tolerance. Legacy actors retain their .85 default.
        agent->route.minimum_floor_normal=profile==0?.7072:.85;
        agent->motion_shape->set_shape(shape);
        agent->continuing=false;agent->route.invalidate();agent->journey.invalidate();agent->age=1;
    }
    if(!active){agent->active=false;agent->continuing=false;agent->route.invalidate();agent->journey.invalidate();agent->goal=agent->position;return true;}
    const auto state=agent->regional?agent->journey.state:agent->route.state;
    const bool change=agent->requested.distance_to(agent->aimed)>.75;
    const bool regional_update=std::abs(agent->requested.y-agent->aimed.y)>2.5||
        ((state==ActorRoute::FOLLOWING||state==ActorRoute::ARRIVED)&&
        (agent->position.distance_to(agent->planned_from)>4||agent->position.distance_to(agent->goal)<4));
    // Queue the latest observation while planning. Resetting a search every
    // 0.4 s can starve every actor behind an obstacle when the recipient moves.
    // Once following, keep useful validated progress until the end is near,
    // the recipient changes storey, or a substantial diversion warrants it.
    const bool local_update=agent->position.distance_to(agent->goal)<3||
        std::abs(agent->requested.y-agent->aimed.y)>2.5||
        (agent->requested.distance_to(agent->aimed)>4&&agent->position.distance_to(agent->planned_from)>1);
    const bool retarget=!agent->active || (!agent->continuing && ((state!=ActorRoute::PLANNING && agent->age>=.4 && change && (agent->regional?regional_update:local_update)) ||
        (state==ActorRoute::ARRIVED && agent->requested.distance_to(agent->goal)>.2)));
    if(retarget){
        // Preserve only the next waypoint of a previously COMPLETE route.
        // Plan from that fixed join, so a moving body cannot invalidate the
        // replacement or be sent back to its obsolete starting position.
        agent->continuing=false;
        if(agent->active&&state==ActorRoute::FOLLOWING){
            const Vector3 next=agent->regional?agent->journey.target(agent->position):agent->route.target(agent->position);
            const double distance=agent->position.distance_to(next);
            if(distance>.04&&distance<=2.5){agent->continuation=next;agent->continuing=true;agent->continuation_progress=agent->position;agent->continuation_stuck=0;}
        }
        const Vector3 origin=agent->continuing?agent->continuation:agent->position;
        Vector3 offset=agent->requested-origin;offset.y=0;
        agent->regional=offset.length()>12||std::abs(agent->requested.y-origin.y)>.5;
        agent->goal=agent->requested;agent->planned_from=origin;
        agent->age=0;agent->aimed=agent->requested;agent->route.invalidate();agent->journey.invalidate();
    }
    agent->active=true;
    return true;
}
void NativeActorNavigator::remove_agent(int64_t id){
    agents_.erase(std::remove_if(agents_.begin(),agents_.end(),[&](const Agent &agent){return agent.id==id;}),agents_.end());
}
void NativeActorNavigator::clear(){agents_.clear();cursor_=0;invalidate();}
void NativeActorNavigator::invalidate(const AABB &bounds){
    const auto began=Time::get_singleton()->get_ticks_usec();
    invalidation_global_=graph_.invalidate(bounds);invalidation_queries_=0;
    for(auto &agent:agents_){
        if(!agent.active)continue;
        bool affected=invalidation_global_||(agent.regional?agent.journey.affected(bounds):agent.route.affected(bounds));
        if(agent.continuing){
            const real_t radius=agent.profile==0?.4:.8;
            const Vector3 extent(radius,1.9,radius);
            const AABB segment=AABB(agent.position-extent,extent*2).merge(AABB(agent.continuation-extent,extent*2));
            affected=affected||segment.intersects(bounds.grow(.001));
        }
        if(affected){++invalidation_queries_;agent.continuing=false;agent.route.invalidate();agent.journey.invalidate();}
    }
    invalidation_us_=Time::get_singleton()->get_ticks_usec()-began;
    ++invalidation_count_;if(invalidation_global_)++invalidation_global_count_;
    invalidation_total_us_+=invalidation_us_;invalidation_max_us_=std::max(invalidation_max_us_,invalidation_us_);
}
Dictionary NativeActorNavigator::invalidation_stats()const{
    Dictionary out;out["global"]=invalidation_global_;out["elapsed_us"]=int64_t(invalidation_us_);
    out["count"]=int64_t(invalidation_count_);out["global_count"]=int64_t(invalidation_global_count_);
    out["total_us"]=int64_t(invalidation_total_us_);out["max_us"]=int64_t(invalidation_max_us_);
    out["queries_reset"]=int64_t(invalidation_queries_);out["vertices_scanned"]=int64_t(graph_.invalidation_scanned);
    out["vertices_retired"]=int64_t(graph_.invalidation_vertices);out["edges_reset"]=int64_t(graph_.invalidation_edges);
    out["live_vertices"]=int64_t(graph_.live_size());out["allocated_slots"]=int64_t(graph_.vertices.size());
    out["free_slots"]=int64_t(graph_.free_slots());out["vertex_capacity_bytes"]=int64_t(graph_.vertices.capacity()*sizeof(RegionalGraph::Vertex));
    out["revision"]=int64_t(graph_.revision);return out;
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
        if(agent.continuing){
            Vector3 remaining=agent.continuation-agent.position;remaining.y=0;
            Vector3 progress=agent.position-agent.continuation_progress;progress.y=0;
            if((remaining.length()<=.04&&std::abs(agent.continuation.y-agent.position.y)<=.3)||progress.length()>=.05){agent.continuation_progress=agent.position;agent.continuation_stuck=0;}
            else agent.continuation_stuck+=delta;
            if(agent.continuation_stuck>1){
                agent.continuing=false;agent.planned_from=agent.position;agent.route.invalidate();agent.journey.invalidate();
            }
        }
        // Direct corridors stay cheap/local. As soon as an obstacle requires
        // graph search, share the regional surface cache instead of repeating
        // the same expensive sampled edges independently for every pursuer.
        if(!agent.regional&&(agent.route.expansions>0||agent.route.state==ActorRoute::BLOCKED||agent.route.state==ActorRoute::SEARCH_LIMIT)){
            agent.regional=true;agent.journey.invalidate();
        }
        const Vector3 origin=agent.continuing?agent.continuation:agent.position;
        // The new planner has not taken ownership of physical movement until
        // the old validated waypoint is reached. Do not count this as a stall.
        const auto planning_state=agent.regional?agent.journey.state:agent.route.state;
        const double elapsed=agent.continuing&&planning_state==ActorRoute::FOLLOWING?0:delta;
        if(agent.regional)agent.journey.prepare(origin,agent.goal,agent.profile,elapsed);
        else {agent.route.prepare(origin,agent.goal,elapsed);agent.route.moved(origin,elapsed);}
    }
    int work=0,limit=12;size_t idle=0;
    ActorRoute::QueryProfile profile;
    // Every geometry, water, recipient or conditional-door invalidation changes
    // this revision. Coverage is still checked before every sampled edge.
    support_cache_.revision=graph_.revision+1;support_cache_.hits=support_cache_.misses=0;
    for(auto &agent:agents_){
        agent.route.readiness_cache=&readiness_cache_;agent.route.query_profile=query_profiling_?&profile:nullptr;
        agent.route.support_cache=support_cache_enabled_?&support_cache_:nullptr;
    }
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
    for(auto &agent:agents_){agent.route.readiness_cache=nullptr;agent.route.query_profile=nullptr;agent.route.support_cache=nullptr;}
    out["support_cache_hits"]=int64_t(support_cache_.hits);out["support_cache_misses"]=int64_t(support_cache_.misses);
    out["support_cache_limit"]=int64_t(ActorRoute::SupportCache::LIMIT);
    out["support_cache_bytes"]=int64_t(sizeof(ActorRoute::SupportCache::Entry)*support_cache_.entries.size());
    if(query_profiling_){
        Dictionary measured;
        measured["readiness_us"]=profile.readiness_ns/1000.0;measured["support_us"]=profile.support_ns/1000.0;
        measured["hazard_us"]=profile.hazard_ns/1000.0;measured["clearance_us"]=profile.clearance_ns/1000.0;
        measured["edges"]=int64_t(profile.edges);measured["support_rays"]=int64_t(profile.support_rays);
        measured["support_cache_hits"]=int64_t(support_cache_.hits);
        measured["support_raycasts"]=int64_t(profile.support_rays-support_cache_.hits);
        measured["water_queries"]=int64_t(profile.water_queries);measured["admission_queries"]=int64_t(profile.admission_queries);
        measured["shape_queries"]=int64_t(profile.shape_queries);measured["sweeps"]=int64_t(profile.sweeps);
        out["query_profile"]=measured;
        out["invalidation"]=invalidation_stats();
    }
    out["readiness_probes"]=readiness_cache_.probes;out["readiness_cache_hits"]=readiness_cache_.hits;
    out["readiness_cache_entries"]=int(readiness_cache_.regions.size());
    out["graph_nodes"]=int(graph_.live_size());out["graph_node_limit"]=RegionalGraph::NODE_LIMIT;
    out["graph_cache_hits"]=int64_t(graph_.hits);out["streaming_requests"]=graph_.requests.size();
    out["planning_us"]=int64_t(Time::get_singleton()->get_ticks_usec()-started);out["agents"]=int(agents_.size());return out;
}
Vector3 NativeActorNavigator::steering_target(int64_t id){
    auto *agent=find(id);if(!agent)return Vector3(INFINITY,INFINITY,INFINITY);
    if(agent->continuing){
        const auto state=agent->regional?agent->journey.state:agent->route.state;
        if(state!=ActorRoute::PLANNING&&state!=ActorRoute::FOLLOWING&&state!=ActorRoute::ARRIVED)return agent->position-CENTRE;
        Vector3 offset=agent->continuation-agent->position;offset.y=0;
        if(offset.length()>.04||std::abs(agent->continuation.y-agent->position.y)>.3)return agent->continuation-CENTRE;
        if(state==ActorRoute::PLANNING)return agent->position-CENTRE;
        agent->continuing=false;
    }
    return (agent->regional?agent->journey.target(agent->position):agent->route.target(agent->position))-CENTRE;
}
bool NativeActorNavigator::guard_motion(int64_t id,const Vector3 &direction,double travel){
    auto *agent=find(id);if(!agent || !direction.is_finite() || !std::isfinite(travel) || travel<0 || travel>.5 || !readiness_.is_valid())return false;
    Vector3 heading=direction;heading.y=0;if(heading.length_squared()<.00001)return true;
    Vector3 to=agent->position+heading.normalized()*real_t(std::max(.02,travel));
    const bool allowed=agent->route.permits_motion(get_world_3d()->get_direct_space_state(),agent->position,to,readiness_,admission_,agent->motion_ray,agent->motion_shape);
    agent->motion_rejection=agent->route.edge_failure();
    if(!allowed&&agent->continuing){agent->continuing=false;agent->planned_from=agent->position;agent->route.invalidate();agent->journey.invalidate();}
    if(!allowed&&agent->regional){
        const String failure=agent->motion_rejection;
        bool conditional_door=false;
        if(failure=="capsule_clearance")for(int i=0;i<interactions_.size();++i)
            if(RID(interactions_[i])==agent->route.edge_obstacle()){conditional_door=true;break;}
        // Keep an intentional door approach for the host's interaction policy.
        // Other live clearance discrepancies must not replay the same cached
        // connection until the stuck timer gives up. Reuse the bounded failure
        // memory and full-route search already used for missed steep support.
        if(failure=="steep_support"||(failure=="capsule_clearance"&&!conditional_door))agent->journey.reject_motion();
    }
    return allowed;
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
    out["continuing_previous_path"]=agent->continuing;
    if(agent->continuing)out["continuation_target"]=agent->continuation-CENTRE;
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
