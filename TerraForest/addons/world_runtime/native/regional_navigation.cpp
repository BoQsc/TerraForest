// SPDX-License-Identifier: 0BSD
#include "regional_navigation.hpp"
#include <algorithm>
#include <cmath>
using namespace godot;
namespace terraforest {
static constexpr int DX[9]={1,0,-1,0,1,-1,-1,1,0},DZ[9]={0,1,0,-1,1,1,-1,-1,0};
static double planar(Vector3 a,Vector3 b){a.y=b.y=0;return a.distance_to(b);}
// Prefer progress onto the recipient's connected height layer rather than
// flooding an entire outdoor plane underneath an upstairs/underground goal.
// This is guidance, not an admissible shortest-path heuristic. Every chosen
// connection is still physically verified before a complete route is published.
static double estimate(Vector3 a,Vector3 b,double height){return (planar(a,b)+height*std::abs(a.y-b.y))*1.25;}
void RegionalGraph::request(const Vector3 &point){
    // Requests persist until the host services them; bounded and deduplicated by
    // terrain column, without changing the player's authoritative focus.
    for(int i=0;i<requests.size();++i)if(std::floor(requests[i].x/16)==std::floor(point.x/16)&&std::floor(requests[i].z/16)==std::floor(point.z/16))return;
    if(requests.size()<8)requests.push_back(point);
}
int RegionalGraph::candidate(int from,const Vector3 &origin,int profile,int direction,
    ActorRoute &validator,PhysicsDirectSpaceState3D *space,const Callable &readiness,const Callable &admission,
    const Ref<PhysicsRayQueryParameters3D> &ray,const Ref<PhysicsShapeQueryParameters3D> &shape){
    ++queries;
    const Vector3 p=from<0?origin:vertices[from].p;
    const bool cached=from>=0&&vertices[from].edge[direction]!=-2;
    const int progress=from>=0?vertices[from].progress[direction]:0;
    const Vector3 previous=progress?vertices[from].probe[direction]:p;
    Vector3 next(std::round(previous.x*2)*.5+DX[direction]*.5,previous.y,std::round(previous.z*2)*.5+DZ[direction]*.5);
    if(cached&&vertices[from].edge[direction]>=0)next=vertices[vertices[from].edge[direction]].p;
    // A cached edge still needs live collision coverage. Geometry edits and
    // changed recipient exclusions clear the graph; missing coverage never
    // becomes a cached negative edge.
    const real_t radius=profile==0?.4:.8;
    AABB region(p-Vector3(radius,1.9,radius),Vector3(radius*2,3.7,radius*2));
    region=region.merge(AABB(next-Vector3(radius,1.9,radius),Vector3(radius*2,3.7,radius*2)));
    if(cached){
        if(!validator.collision_ready(region,readiness)){request(next);return -3;}
        ++hits;return vertices[from].edge[direction];
    }
    const bool permitted=validator.sample_motion(space,previous,next,readiness,admission,ray,shape);
    if(!permitted){
        if(validator.edge_unavailable()){request(next);return -3;}
        if(!progress){if(from>=0)vertices[from].edge[direction]=-1;return -1;}
        next=previous;
    }else if(from>=0&&progress<3&&std::abs(next.y-previous.y)<.03){
        // Open space uses two-metre graph links. Validate only one supported
        // half-metre segment per scheduler quantum; stop/refine near obstacles
        // or a change in height instead of skipping a doorway or stair.
        vertices[from].probe[direction]=next;vertices[from].progress[direction]=progress+1;return -5;
    }
    auto key=std::make_tuple(profile,int(std::round(next.x*2)),int(std::round(next.z*2)),int(std::round(next.y*100)));
    auto found=index.find(key);int id;
    if(found==index.end()){
        if(vertices.size()>=NODE_LIMIT)return -4;
        if(vertices.empty())lowest=highest=next.y;else {lowest=std::min(lowest,next.y);highest=std::max(highest,next.y);}
        id=int(vertices.size());vertices.emplace_back(next,profile);index.emplace(key,id);
    }else id=found->second;
    if(from>=0)vertices[from].edge[direction]=id;
    return id;
}
void RegionalRoute::begin(Vector3 start,Vector3 goal,int profile){
    start_=expected_=progress_anchor_=start;goal_=goal;profile_=profile;nodes_.clear();visited_.clear();open_={};path_.clear();
    expanding_=-1;direction_=0;waypoint_=0;retry_=stuck_=0;waiting_=false;finishing_=false;finish_samples_.clear();expansions=0;
    height_weight_=goal.y>start.y+.5?16:2;
    nodes_.push_back({-1,-1,0});open_.push({estimate(start,goal,height_weight_),0});state=ActorRoute::PLANNING;
    if(std::abs(goal.x-start.x)>RADIUS||std::abs(goal.z-start.z)>RADIUS||std::abs(goal.y-start.y)>64)state=ActorRoute::SEARCH_LIMIT;
}
void RegionalRoute::prepare(Vector3 point,Vector3 goal,int profile,double delta){
    retry_-=delta;
    if(state==ActorRoute::IDLE||goal.distance_to(goal_)>.01||profile!=profile_||point.distance_to(expected_)>.35){stalls_=0;begin(point,goal,profile);}
    if(state==ActorRoute::UNAVAILABLE&&retry_<=0)state=ActorRoute::PLANNING;
    if(state==ActorRoute::FOLLOWING){
        // Collision jitter must not reset the stalled-route timer each tick.
        if(planar(point,progress_anchor_)>=.05){progress_anchor_=point;stuck_=0;}
        else stuck_+=delta;
        if(stuck_>1){if(++stalls_<=2)begin(point,goal,profile);else state=ActorRoute::BLOCKED;}
    }
    expected_=point;
    if(planar(point,goal)<.16&&std::abs(point.y-goal.y)<.3)state=ActorRoute::ARRIVED;
}
void RegionalRoute::step(RegionalGraph &graph,ActorRoute &validator,PhysicsDirectSpaceState3D *space,
    const Callable &readiness,const Callable &admission,const Ref<PhysicsRayQueryParameters3D> &ray,
    const Ref<PhysicsShapeQueryParameters3D> &shape){
    if(state!=ActorRoute::PLANNING||!space)return;
    if(expanding_<0){
        int stale=0;
        while(!open_.empty()&&nodes_[open_.top().node].closed){open_.pop();if(++stale==12)return;}
        if(open_.empty()){state=ActorRoute::BLOCKED;return;}
        expanding_=open_.top().node;open_.pop();nodes_[expanding_].closed=true;++expansions;
        direction_=-1;
    }
    const int parent=expanding_;const Node current=nodes_[parent];const Vector3 p=position(current,graph);
    if(direction_==-1&&!finishing_){
        finishing_=planar(p,goal_)<2.9&&std::abs(p.y-goal_.y)<.3;
        finish_samples_.clear();
        if(!finishing_){direction_=current.vertex<0?8:0;return;}
    }
    if(finishing_){
        const Vector3 from=finish_samples_.empty()?p:finish_samples_.back();
        const double distance=planar(from,goal_);Vector3 end=goal_;end.y=from.y;
        if(distance>.5)end=from+(end-from)*real_t(.5/distance);
        if(!validator.sample_motion(space,from,end,readiness,admission,ray,shape)){
            if(validator.edge_unavailable()){graph.request(end);state=ActorRoute::UNAVAILABLE;retry_=.1;return;}
            finishing_=false;direction_=current.vertex<0?8:0;return;
        }
        finish_samples_.push_back(end);
        if(distance<=.5){
            finishing_=false;
            if(std::abs(end.y-goal_.y)<.3){
                for(int n=parent;n>=0;n=nodes_[n].parent)path_.push_back(position(nodes_[n],graph));
                std::reverse(path_.begin(),path_.end());path_.insert(path_.end(),finish_samples_.begin(),finish_samples_.end());
                waypoint_=1;state=ActorRoute::FOLLOWING;return;
            }
            direction_=current.vertex<0?8:0;
        }
        return;
    }
    const int direction=direction_;
    // Root first tries the nearest aligned cell, then the eight neighbours.
    const int id=graph.candidate(current.vertex,p,profile_,direction,validator,space,readiness,admission,ray,shape);
    if(id==-5)return;
    if(id==-3){state=ActorRoute::UNAVAILABLE;retry_=.1;waiting_=true;return;}
    waiting_=false;
    if(direction_==8){if(id>=0)expanding_=-1;else direction_=0;}
    else if(++direction_==8)expanding_=-1;
    if(id==-4){state=ActorRoute::SEARCH_LIMIT;return;}
    if(id<0)return;
    const Vector3 next=graph.vertices[id].p;
    if(std::abs(next.x-start_.x)>RADIUS||std::abs(next.z-start_.z)>RADIUS||std::abs(next.y-start_.y)>64)return;
    const double g=current.g+p.distance_to(next);auto old=visited_.find(id);
    if(old!=visited_.end()){
        Node &node=nodes_[old->second];if(node.closed||node.g<=g)return;
        node.g=g;node.parent=parent;open_.push({g+estimate(next,goal_,height_weight_),old->second});return;
    }
    if(nodes_.size()>=QUERY_LIMIT){state=ActorRoute::SEARCH_LIMIT;return;}
    const int n=int(nodes_.size());nodes_.push_back({id,parent,g});visited_[id]=n;
    open_.push({g+estimate(next,goal_,height_weight_),n});
}
Vector3 RegionalRoute::target(Vector3 point){
    if(state!=ActorRoute::FOLLOWING)return point;
    while(waypoint_<path_.size()){
        const Vector3 p=path_[waypoint_];bool reached=planar(point,p)<.04&&std::abs(point.y-p.y)<.3;
        if(!reached&&waypoint_>0&&waypoint_+1<path_.size()){
            Vector3 a=p-path_[waypoint_-1],b=path_[waypoint_+1]-p;
            if(std::abs(a.y)<.05&&std::abs(b.y)<.05&&std::abs(point.y-p.y)<.1){
                a.y=b.y=0;
                if(a.length_squared()>.0001&&b.length_squared()>.0001&&a.normalized().dot(b.normalized())>.999){
                    Vector3 offset=point-p;offset.y=0;const Vector3 d=a.normalized();const real_t along=offset.dot(d);
                    reached=offset.length()<.15||(along>=0&&along<.5&&(offset-d*along).length()<.35);
                }
            }
        }
        if(!reached)break;++waypoint_;
    }
    if(waypoint_==path_.size()){state=ActorRoute::ARRIVED;return point;}return path_[waypoint_];
}
PackedVector3Array RegionalRoute::points()const{PackedVector3Array out;for(const auto &p:path_)out.push_back(p-Vector3(0,.93,0));return out;}
Dictionary RegionalRoute::status(const RegionalGraph &graph)const{
    static const char *names[]={"idle","planning","following","arrived","blocked","unavailable","search_limit"};
    Dictionary out;out["state"]=names[state];out["nodes"]=int(nodes_.size());out["expansions"]=expansions;
    out["node_limit"]=QUERY_LIMIT;out["radius_m"]=RADIUS;out["waypoints"]=int(path_.size());out["waypoint_index"]=int(waypoint_);
    out["stuck_seconds"]=stuck_;out["replans"]=stalls_;out["graph_nodes"]=int(graph.vertices.size());out["graph_node_limit"]=RegionalGraph::NODE_LIMIT;
    out["graph_cache_hits"]=int64_t(graph.hits);out["graph_revision"]=int64_t(graph.revision);out["complete_path"]=!path_.empty();
    out["lowest_surface"]=graph.lowest-.93;out["highest_surface"]=graph.highest-.93;
    if(waypoint_<path_.size())out["waypoint_target"]=path_[waypoint_];
    std::set<std::tuple<int,int,int>> regions;int portals=0;
    std::tuple<int,int,int> previous;bool first=true;
    for(const auto &p:path_){auto tile=std::make_tuple(int(std::floor(p.x/8)),int(std::floor((p.y-.93)/4)),int(std::floor(p.z/8)));
        regions.insert(tile);if(!first&&tile!=previous)++portals;first=false;previous=tile;}
    out["regions"]=int(regions.size());out["portals"]=portals;return out;
}
}
