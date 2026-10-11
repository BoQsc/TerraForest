// SPDX-License-Identifier: 0BSD
#include "actor_route.hpp"
#include <cmath>
#include <algorithm>
using namespace godot;
namespace terraforest {
static double horizontal(const Vector3 &a,const Vector3 &b){Vector3 d=a-b;d.y=0;return d.length();}
void ActorRoute::include(const AABB &b){bounds_=has_bounds_?bounds_.merge(b):b;has_bounds_=true;}
void ActorRoute::start(const Vector3 &position,const Vector3 &goal){
    nodes_.clear();lookup_.clear();open_={};path_.clear();waypoint_=0;
    expanding_=-1;neighbour_=0;limited_=unknown_=false;has_bounds_=false;expansions=0;
    origin_=expected_=position;goal_=goal;retry_=stuck_=0;state=PLANNING;
    nodes_.push_back({position,0,0,-1,0});lookup_[{0,0,0}]=0;
    open_.push({horizontal(position,goal),0});
    if(std::abs(goal.x-position.x)>16 || std::abs(goal.z-position.z)>16)state=SEARCH_LIMIT;
}
void ActorRoute::prepare(const Vector3 &position,const Vector3 &goal,double delta){
    retry_-=delta;
    if(goal.distance_to(goal_)>.01 || position.distance_to(expected_)>.35){stalls_=0;start(position,goal);}
    else if(state==IDLE || (state==UNAVAILABLE && retry_<=0))start(position,goal);
    if(horizontal(position,goal)<.16 && std::abs(position.y-goal.y)<.3)state=ARRIVED;
}
bool ActorRoute::edge(PhysicsDirectSpaceState3D *space,const Vector3 &from,Vector3 &to,
    const Callable &readiness,const Callable &admission,const Ref<PhysicsRayQueryParameters3D> &ray,
    const Ref<PhysicsShapeQueryParameters3D> &shape){
    // Includes the support ray, capsule clearance and entire swept edge.
    AABB region(from-Vector3(.4,1.25,.4),Vector3(.8,2.4,.8));
    region=region.merge(AABB(to-Vector3(.4,1.25,.4),Vector3(.8,2.4,.8)));include(region);
    Variant ready=readiness.call(region);
    if(ready.get_type()!=Variant::BOOL || !bool(ready)){unknown_=true;return false;}
    // Conservative walking only: at most 15cm height change over a half metre.
    // No fake step-up: a real capsule sweep must still clear the edge.
    ray->set_from(Vector3(to.x,from.y-.70,to.z));ray->set_to(Vector3(to.x,from.y-1.08,to.z));
    Dictionary hit=space->intersect_ray(ray);if(hit.is_empty())return false;
    Vector3 floor=hit["position"],normal=hit["normal"];
    if(normal.y<.85)return false;
    to.y=floor.y+.93;
    if(std::abs(to.y-from.y)>.16)return false;
    Vector3 middle=(from+to)*.5;
    ray->set_from(middle-Vector3(0,.70,0));ray->set_to(middle-Vector3(0,1.08,0));
    Dictionary support=space->intersect_ray(ray);if(support.is_empty() || Vector3(support["normal"]).y<.85)return false;
    if(admission.is_valid()){
        for(const Vector3 &point:{to,middle}){Variant allowed=admission.call(point);if(allowed.get_type()!=Variant::BOOL || !bool(allowed))return false;}
    }
    shape->set_transform(Transform3D(Basis(),to));shape->set_motion(Vector3());
    if(!space->intersect_shape(shape,1).is_empty())return false;
    // Initial overlap is ignored by cast_motion, so destination occupancy is
    // checked separately above. Both endpoints come from checked supported cells.
    shape->set_transform(Transform3D(Basis(),from+Vector3(0,.03,0)));shape->set_motion(to-from);
    PackedFloat32Array travel=space->cast_motion(shape);
    return travel.size()==2 && travel[0]>.999;
}
void ActorRoute::step(PhysicsDirectSpaceState3D *space,const Callable &readiness,const Callable &admission,
    const Ref<PhysicsRayQueryParameters3D> &ray,const Ref<PhysicsShapeQueryParameters3D> &shape){
    if(state!=PLANNING || !space)return;
    if(expanding_<0){
        // Bound stale priority-queue cleanup as well as physics work.
        int stale=0;
        while(!open_.empty() && nodes_[open_.top().index].closed){open_.pop();if(++stale==12)return;}
        if(open_.empty()){state=unknown_?UNAVAILABLE:(limited_?SEARCH_LIMIT:BLOCKED);retry_=.5;return;}
        expanding_=open_.top().index;open_.pop();nodes_[expanding_].closed=true;neighbour_=-1;++expansions;
    }
    const int parent=expanding_;const Node current=nodes_[parent];
    if(neighbour_==-1){
        neighbour_=0;
        if(horizontal(current.p,goal_)<.72 && std::abs(current.p.y-goal_.y)<.3){
            Vector3 end=goal_;
            if(edge(space,current.p,end,readiness,admission,ray,shape)){
                path_.push_back(end);for(int n=expanding_;n>=0;n=nodes_[n].parent)path_.push_back(nodes_[n].p);
                std::reverse(path_.begin(),path_.end());waypoint_=1;state=FOLLOWING;return;
            }
        }
        return;
    }
    static constexpr int dx[8]={1,0,-1,0,1,-1,-1,1},dz[8]={0,1,0,-1,1,1,-1,-1};
    const int direction=neighbour_++,x=current.x+dx[direction],z=current.z+dz[direction];
    if(neighbour_==8)expanding_=-1;
    if(std::abs(x)>32 || std::abs(z)>32){limited_=true;return;}
    Vector3 next=origin_+Vector3(x*.5,0,z*.5);next.y=current.p.y;
    if(!edge(space,current.p,next,readiness,admission,ray,shape))return;
    const double g=current.g+horizontal(current.p,next);
    auto key=std::make_tuple(x,z,int(std::round((next.y-origin_.y)*10)));auto found=lookup_.find(key);
    if(found!=lookup_.end()){
        Node &old=nodes_[found->second];if(old.closed || old.g<=g)return;
        old.g=g;
        // Parent is the cell just expanded, even after advancing to the next one.
        old.parent=parent;
        open_.push({g+horizontal(next,goal_),found->second});return;
    }
    if(nodes_.size()>=2048){state=SEARCH_LIMIT;return;}
    int index=int(nodes_.size());nodes_.push_back({next,x,z,parent,g});lookup_[key]=index;
    open_.push({g+horizontal(next,goal_),index});
}
Vector3 ActorRoute::target(const Vector3 &position){
    if(state!=FOLLOWING)return position;
    while(waypoint_<path_.size() && horizontal(position,path_[waypoint_])<.04)++waypoint_;
    if(waypoint_==path_.size()){state=ARRIVED;return position;}
    return path_[waypoint_];
}
void ActorRoute::moved(const Vector3 &position,double delta){
    if(state==FOLLOWING){
        stuck_=horizontal(position,expected_)<.001?stuck_+delta:0;
        if(stuck_>1){if(++stalls_<=2)invalidate();else state=BLOCKED;}
    }
    expected_=position;
}
Dictionary ActorRoute::status() const {
    static const char *names[]={"idle","planning","following","arrived","blocked","unavailable","search_limit"};
    Dictionary out;out["state"]=names[state];out["nodes"]=int(nodes_.size());out["expansions"]=expansions;
    out["waypoints"]=int(path_.size());out["node_limit"]=2048;out["radius_m"]=16;return out;
}
}
