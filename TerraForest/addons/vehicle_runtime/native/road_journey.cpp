// SPDX-License-Identifier: 0BSD
#include "road_journey.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <algorithm>
#include <cmath>
#include <limits>
#include <map>
#include <queue>
#include <set>
#include <tuple>
using namespace godot;
namespace terraforest {
namespace {
double cross(Vector3 a,Vector3 b){return double(a.x)*b.z-double(a.z)*b.x;}
Vector3 flat(Vector3 p){p.y=0;return p;}
// Generated approach roads can end at the half-cell frontage of a street.
// Join only overlapping vehicle-width road surfaces at the same elevation;
// live footprint/support guards still validate the driven connection.
bool junction(Vector3 a,Vector3 b){return flat(a-b).length()<=.75&&std::abs(a.y-b.y)<=.15;}
double parameter(Vector3 p,Vector3 a,Vector3 b){auto d=flat(b-a);return std::clamp(double(flat(p-a).dot(d))/std::max(double(d.length_squared()),1e-9),0.0,1.0);}
Dictionary fail(const char *reason){Dictionary d;d["ok"]=false;d["reason"]=reason;return d;}
}
void NativeRoadJourney::_bind_methods(){
    ClassDB::bind_method(D_METHOD("configure","roads"),&NativeRoadJourney::configure);
    ClassDB::bind_method(D_METHOD("route","start","destination","maximum_snap","heading"),&NativeRoadJourney::route,DEFVAL(Vector3()));
    ClassDB::bind_method(D_METHOD("follow","points"),&NativeRoadJourney::follow);
    ClassDB::bind_method(D_METHOD("resume","points","waypoint"),&NativeRoadJourney::resume);
    ClassDB::bind_method(D_METHOD("advance","pose","velocity","delta","ready","clear"),&NativeRoadJourney::advance);
    ClassDB::bind_method(D_METHOD("get_state"),&NativeRoadJourney::get_state);
    ClassDB::bind_method(D_METHOD("get_path"),&NativeRoadJourney::get_path);
}
Dictionary NativeRoadJourney::configure(const Array &source){
    roads.clear();nodes.clear();edges.clear();path.clear();state="unavailable";
    if(source.is_empty()||source.size()>8192)return fail("road_limit");
    std::map<std::pair<int,int>,std::vector<int>> bins;
    int references=0;
    for(int i=0;i<source.size();i++){
        if(source[i].get_type()!=Variant::DICTIONARY)return fail("invalid_road");
        Dictionary item=source[i];
        if(!item.has("a")||!item.has("b")||!item.has("width")||item["a"].get_type()!=Variant::VECTOR3||item["b"].get_type()!=Variant::VECTOR3||(item["width"].get_type()!=Variant::FLOAT&&item["width"].get_type()!=Variant::INT))return fail("invalid_road");
        Road r{item["a"],item["b"],double(item["width"]),{0,1}};
        if(!r.a.is_finite()||!r.b.is_finite()||std::max(r.a.abs().length(),r.b.abs().length())>8192||!std::isfinite(r.width)||r.width<1||r.width>64||r.a.distance_to(r.b)<.05||r.a.distance_to(r.b)>4096)return fail("invalid_road");
        // Footpaths/trails are not taxi roads. Reject grades beyond the service
        // profile even if their metadata connects to a street.
        if(r.width<5||std::abs(r.a.y-r.b.y)>flat(r.b-r.a).length()*.25)continue;
        int id=int(roads.size());roads.push_back(r);
        for(int z=int(std::floor((std::min(r.a.z,r.b.z)-.75)/32));z<=int(std::floor((std::max(r.a.z,r.b.z)+.75)/32));z++)
            for(int x=int(std::floor((std::min(r.a.x,r.b.x)-.75)/32));x<=int(std::floor((std::max(r.a.x,r.b.x)+.75)/32));x++){
                if(++references>131072){roads.clear();return fail("search_limit");}bins[{x,z}].push_back(id);
            }
    }
    if(roads.empty())return fail("no_vehicle_roads");
    std::set<std::pair<int,int>> pairs;
    int work=0,attempts=0;
    for(auto &bin:bins)for(int a:bin.second)for(int b:bin.second){
        if(++attempts>1048576){roads.clear();return fail("search_limit");}
        if(a>=b||!pairs.insert({a,b}).second)continue;
        if(++work>262144){roads.clear();return fail("search_limit");}
        Road &r=roads[a],&s=roads[b];auto u=r.b-r.a,v=s.b-s.a;
        double denom=cross(u,v);
        if(std::abs(denom)>1e-8){
            double t=cross(s.a-r.a,v)/denom,q=cross(s.a-r.a,u)/denom;
            if(t>=0&&t<=1&&q>=0&&q<=1&&std::abs(r.a.lerp(r.b,t).y-s.a.lerp(s.b,q).y)<=.15){r.cuts.push_back(t);s.cuts.push_back(q);}
        }
        // Also connect collinear segments and T-junction endpoints. Different
        // storeys/overpasses must never acquire an edge merely by crossing XZ.
        for(auto point:{r.a,r.b}){double t=parameter(point,s.a,s.b);if(junction(point,s.a.lerp(s.b,t)))s.cuts.push_back(t);}
        for(auto point:{s.a,s.b}){double t=parameter(point,r.a,r.b);if(junction(point,r.a.lerp(r.b,t)))r.cuts.push_back(t);}
    }
    std::map<std::tuple<int,int,int>,std::vector<int>> buckets;
    auto node=[&](Vector3 p){
        int x=int(std::floor(p.x)),y=int(std::floor(p.y/.2)),z=int(std::floor(p.z));
        for(int dz=-1;dz<=1;dz++)for(int dy=-1;dy<=1;dy++)for(int dx=-1;dx<=1;dx++){
            auto found=buckets.find({x+dx,y+dy,z+dz});if(found==buckets.end())continue;
            for(int id:found->second)if(junction(nodes[id],p))return id;
        }
        int id=int(nodes.size());nodes.push_back(p);edges.emplace_back();buckets[{x,y,z}].push_back(id);return id;
    };
    for(auto &r:roads){
        std::sort(r.cuts.begin(),r.cuts.end());int previous=-1;
        for(double t:r.cuts){int current=node(r.a.lerp(r.b,t));if(current==previous)continue;
            if(previous>=0){double length=nodes[previous].distance_to(nodes[current]);edges[previous].push_back({current,length});edges[current].push_back({previous,length});}previous=current;
        }
        if(nodes.size()>32768){roads.clear();nodes.clear();edges.clear();return fail("search_limit");}
    }
    state="idle";Dictionary result;result["ok"]=true;result["nodes"]=int(nodes.size());result["roads"]=int(roads.size());result["work"]=work;return result;
}
Dictionary NativeRoadJourney::route(Vector3 start,Vector3 destination,double snap,Vector3 heading)const{
    if(nodes.empty()||!start.is_finite()||!destination.is_finite()||!heading.is_finite()||!std::isfinite(snap)||snap<0||snap>128)return fail("unavailable");
    // Terminal points are existing graph nodes: fare and preview include the
    // entire driven route. No invisible shortcut from a building to a road.
    auto nearest=[&](Vector3 p){int found=-1;double best=snap*snap;for(int i=0;i<int(nodes.size());i++){double d=nodes[i].distance_squared_to(p);if(d<=best){best=d;found=i;}}return found;};
    int first=nearest(start),last=nearest(destination);if(first<0||last<0)return fail("no_road_stop");
    std::vector<double> distance(nodes.size(),std::numeric_limits<double>::infinity());std::vector<int> parent(nodes.size(),-1);
    using Entry=std::pair<double,int>;std::priority_queue<Entry,std::vector<Entry>,std::greater<Entry>> queue;
    distance[first]=0;queue.push({0,first});int work=0;
    while(!queue.empty()){
        auto [cost,id]=queue.top();queue.pop();if(cost>distance[id])continue;if(++work>32768)return fail("search_limit");if(id==last)break;
        for(auto edge:edges[id]){
            Vector3 arrival=id==first?flat(heading):(parent[id]>=0?flat(nodes[id]-nodes[parent[id]]):Vector3());
            if(arrival.length_squared()>.001&&arrival.normalized().dot(flat(nodes[edge.to]-nodes[id]).normalized())<-.1)continue;
            if(cost+edge.cost<distance[edge.to]){distance[edge.to]=cost+edge.cost;parent[edge.to]=id;queue.push({distance[edge.to],edge.to});}
        }
    }
    if(!std::isfinite(distance[last]))return fail("disconnected");
    if(distance[last]<20)return fail("same_stop");
    std::vector<int> reverse;for(int id=last;id>=0;id=parent[id])reverse.push_back(id);
    PackedVector3Array points;for(auto it=reverse.rbegin();it!=reverse.rend();++it)points.push_back(nodes[*it]);
    Dictionary result;result["ok"]=true;result["points"]=points;result["distance_m"]=distance[last];result["fare"]=10+int(std::ceil(distance[last]/100))*2;result["work"]=work;return result;
}
bool NativeRoadJourney::follow(const PackedVector3Array &points){
    if(points.size()<2||points.size()>32768)return false;
    for(int i=0;i<points.size();i++)if(!points[i].is_finite()||(i&&points[i].distance_to(points[i-1])<.01))return false;
    path=points;cursor=0;stalled=0;observed=false;state="following";return true;
}
bool NativeRoadJourney::resume(const PackedVector3Array &points,int waypoint){
    if(waypoint<0||waypoint>=points.size()-1||!follow(points))return false;
    cursor=waypoint;return true;
}
Dictionary NativeRoadJourney::advance(Transform3D pose,Vector3 velocity,double delta,bool ready,bool clear){
    Dictionary out;out["steer"]=0.0;out["throttle"]=0.0;out["brake"]=1.0;out["hold"]=true;
    auto finish=[&](){out["state"]=state;out["cursor"]=cursor;return out;};
    if(!pose.is_finite()||!velocity.is_finite()||!std::isfinite(delta)||delta<=0||delta>.1||path.size()<2){state="unavailable";return finish();}
    if(!ready){state="unavailable";return finish();}if(!clear){state="blocked";return finish();}
    if(state=="arrived"||state=="search_limit")return finish();
    auto p=pose.origin;double speed=flat(velocity).length();
    // Incremental nearest-segment search never scans the whole road graph per tick.
    int work=0;
    while(cursor<path.size()-2&&work++<32){
        double t=parameter(p,path[cursor],path[cursor+1]);
        double next_t=parameter(p,path[cursor+1],path[cursor+2]);
        double current_distance=flat(p-path[cursor].lerp(path[cursor+1],t)).length();
        double next_distance=flat(p-path[cursor+1].lerp(path[cursor+2],next_t)).length();
        bool rounded=next_t>0&&next_distance+.1<current_distance;
        if(t<.995&&flat(p-path[cursor+1]).length()>1.25&&!rounded)break;cursor++;
    }
    auto a=path[cursor],b=path[cursor+1];double t=parameter(p,a,b);auto projected=a.lerp(b,t);
    double lane=flat(p-projected).length();out["lane_error_m"]=lane;
    if(lane>3.5||std::abs(p.y-projected.y)>3){state="blocked";return finish();}
    double remaining=flat(p-path[path.size()-1]).length();
    if(cursor==path.size()-2&&remaining<1.25&&speed<.25){state="arrived";return finish();}
    // Pure pursuit, 4--8 m lookahead, bounded to 32 published road segments.
    double look=std::clamp(4+speed*.6,4.0,8.0),left=look;Vector3 target=projected;
    for(int i=cursor;i<path.size()-1&&i<cursor+32;i++){
        Vector3 end=path[i+1];double length=flat(end-target).length();
        if(length>=left){target=target.lerp(end,left/std::max(length,.001));break;}
        left-=length;target=end;
    }
    Vector3 forward=flat(pose.basis.get_column(2)).normalized(),offset=flat(target-p);double length=offset.length();
    double angle=std::atan2(forward.cross(offset).y,double(forward.dot(offset)));
    // A road route is not a turn-around permission. A rear-facing departure
    // remains blocked until an explicitly validated maneuver is available.
    if(std::abs(angle)>1.5){state="blocked";return finish();}
    double wheel=std::atan(2*2.726*std::sin(angle)/std::max(length,1.0));
    double desired=std::min(8.0,std::sqrt(2.5/std::max(std::abs(2*std::sin(angle)/std::max(length,1.0)),.001)));
    if(cursor>=path.size()-4)desired=std::min(desired,std::sqrt(std::max(0.0,remaining-.65)*4));
    if(!observed||flat(p-last_position).length()>=.25){last_position=p;stalled=0;observed=true;}
    else if(desired>1)stalled+=delta;
    if(stalled>8){state="blocked";return finish();}
    state="following";out["steer"]=std::clamp(wheel/.4537856055,-1.0,1.0);out["throttle"]=speed<desired-.25?1.0:0.0;out["brake"]=speed>desired+.25?1.0:0.0;out["hold"]=false;out["target"]=target;out["target_speed"]=desired;return finish();
}
}
