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
    ClassDB::bind_method(D_METHOD("configure","roads","stop_spacing"),&NativeRoadJourney::configure,DEFVAL(0.0));
    ClassDB::bind_method(D_METHOD("get_stops"),&NativeRoadJourney::get_stops);
    ClassDB::bind_method(D_METHOD("connected_stops","start","maximum_snap"),&NativeRoadJourney::connected_stops);
    ClassDB::bind_method(D_METHOD("round_trip_stops","start","maximum_snap"),&NativeRoadJourney::round_trip_stops);
    ClassDB::bind_method(D_METHOD("route","start","destination","maximum_snap","heading"),&NativeRoadJourney::route,DEFVAL(Vector3()));
    ClassDB::bind_method(D_METHOD("follow","points"),&NativeRoadJourney::follow);
    ClassDB::bind_method(D_METHOD("resume","points","waypoint"),&NativeRoadJourney::resume);
    ClassDB::bind_method(D_METHOD("advance","pose","velocity","delta","ready","clear"),&NativeRoadJourney::advance);
    ClassDB::bind_method(D_METHOD("get_state"),&NativeRoadJourney::get_state);
    ClassDB::bind_method(D_METHOD("get_path"),&NativeRoadJourney::get_path);
}
PackedVector3Array NativeRoadJourney::get_stops()const{
    PackedVector3Array result;result.resize(nodes.size());for(int index=0;index<int(nodes.size());++index)result.set(index,nodes[index]);return result;
}
PackedVector3Array NativeRoadJourney::connected_stops(Vector3 start,double maximum_snap)const{
    PackedVector3Array result;
    if(!start.is_finite()||!std::isfinite(maximum_snap)||maximum_snap<0||maximum_snap>128)return result;
    int first=-1;double best=maximum_snap*maximum_snap;
    for(int index=0;index<int(nodes.size());++index){const double distance=nodes[index].distance_squared_to(start);if(distance<=best){first=index;best=distance;}}
    if(first<0)return result;
    std::vector<bool> visited(nodes.size(),false);std::vector<int> pending{first};visited[first]=true;
    for(size_t cursor=0;cursor<pending.size();++cursor)for(const auto &edge:edges[pending[cursor]])if(!visited[edge.to]){visited[edge.to]=true;pending.push_back(edge.to);}
    for(int index=0;index<int(nodes.size());++index)if(visited[index])result.push_back(nodes[index]);
    return result;
}
Dictionary NativeRoadJourney::round_trip_stops(Vector3 start,double maximum_snap)const{
    PackedVector3Array result;
    if(!start.is_finite()||!std::isfinite(maximum_snap)||maximum_snap<0||maximum_snap>128)return fail("unavailable");
    int first=-1;double best=maximum_snap*maximum_snap;
    for(int index=0;index<int(nodes.size());++index){double distance=nodes[index].distance_squared_to(start);if(distance<=best){first=index;best=distance;}}
    if(first<0)return fail("no_road_stop");
    // Match route()'s shortest outward arrival exactly, then reverse-walk the
    // legal incoming-edge states to reject stops that cannot drive home. An
    // undirected component includes dead ends and illegal turning approaches.
    struct Arrival{int previous,node;double distance;};
    std::vector<Arrival> arrivals{{-1,first,0}};
    std::vector<std::vector<int>> reverse(1);
    std::vector<int> earliest(nodes.size(),-1);
    std::map<std::pair<int,int>,int> identities{{{-1,first},0}};
    using Entry=std::pair<double,int>;std::priority_queue<Entry,std::vector<Entry>,std::greater<Entry>> queue;
    queue.push({0,0});int work=0,transitions=0;
    while(!queue.empty()){
        auto [cost,state_id]=queue.top();queue.pop();const Arrival current=arrivals[state_id];
        if(cost>current.distance)continue;if(++work>32768)return fail("search_limit");
        if(earliest[current.node]<0)earliest[current.node]=state_id;
        Vector3 arrival=current.previous<0?Vector3():flat(nodes[current.node]-nodes[current.previous]);
        for(auto edge:edges[current.node]){
            if(arrival.length_squared()>.001&&arrival.normalized().dot(flat(nodes[edge.to]-nodes[current.node]).normalized())<-.1)continue;
            if(++transitions>262144)return fail("search_limit");
            auto key=std::make_pair(current.node,edge.to);auto found=identities.find(key);int next;
            if(found==identities.end()){
                if(arrivals.size()>=32768)return fail("search_limit");
                next=int(arrivals.size());identities[key]=next;arrivals.push_back({current.node,edge.to,std::numeric_limits<double>::infinity()});reverse.emplace_back();
            }else next=found->second;
            reverse[next].push_back(state_id);
            if(cost+edge.cost<arrivals[next].distance){arrivals[next].distance=cost+edge.cost;queue.push({arrivals[next].distance,next});}
        }
    }
    std::vector<bool> returns(arrivals.size(),false);std::vector<int> pending;
    for(int index=0;index<int(arrivals.size());++index)if(arrivals[index].node==first){returns[index]=true;pending.push_back(index);}
    for(size_t cursor=0;cursor<pending.size();++cursor)for(int previous:reverse[pending[cursor]])if(!returns[previous]){returns[previous]=true;pending.push_back(previous);}
    for(int node=0;node<int(nodes.size());++node){int arrival=earliest[node];if(arrival>=0&&arrivals[arrival].distance>=20&&returns[arrival])result.push_back(nodes[node]);}
    Array frontiers;
    for(int node=0;node<int(nodes.size())&&frontiers.size()<16;++node)if(earliest[node]>=0){
        const auto &arrival=arrivals[earliest[node]];
        for(auto edge:edges[node])if(earliest[edge.to]<0&&arrival.previous>=0){Dictionary item;item["from"]=nodes[arrival.previous];item["junction"]=nodes[node];item["to"]=nodes[edge.to];frontiers.push_back(item);if(frontiers.size()>=16)break;}
    }
    Dictionary survey;survey["ok"]=true;survey["stops"]=result;survey["states"]=int(arrivals.size());survey["transitions"]=transitions;survey["frontiers"]=frontiers;return survey;
}
Dictionary NativeRoadJourney::configure(const Array &source,double stop_spacing){
    roads.clear();nodes.clear();edges.clear();path.clear();state="unavailable";
    if(source.is_empty()||source.size()>8192||!std::isfinite(stop_spacing)||(stop_spacing!=0&&(stop_spacing<8||stop_spacing>64)))return fail("road_limit");
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
        if(stop_spacing>0){const int count=int(std::ceil(r.a.distance_to(r.b)/stop_spacing));for(int stop=1;stop<count;++stop)r.cuts.push_back(double(stop)/count);}
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
    // Turn legality depends on the incoming edge, not only the junction.
    // A cheaper arrival from the wrong direction must not discard a legal
    // approach or prevent a forward loop back through the departure junction.
    struct Arrival {int previous,node,parent;double distance;};
    std::vector<Arrival> arrivals{{-1,first,-1,0}};
    std::map<std::pair<int,int>,int> identities{{{-1,first},0}};
    using Entry=std::pair<double,int>;std::priority_queue<Entry,std::vector<Entry>,std::greater<Entry>> queue;
    queue.push({0,0});int work=0,terminal=-1;
    while(!queue.empty()){
        auto [cost,state_id]=queue.top();queue.pop();const Arrival current=arrivals[state_id];
        if(cost>current.distance)continue;if(++work>32768)return fail("search_limit");
        if(current.node==last){terminal=state_id;break;}
        const Vector3 arrival=current.previous<0?flat(heading):flat(nodes[current.node]-nodes[current.previous]);
        for(auto edge:edges[current.node]){
            if(arrival.length_squared()>.001&&arrival.normalized().dot(flat(nodes[edge.to]-nodes[current.node]).normalized())<-.1)continue;
            const auto key=std::make_pair(current.node,edge.to);auto found=identities.find(key);
            int next;
            if(found==identities.end()){
                if(arrivals.size()>=32768)return fail("search_limit");
                next=int(arrivals.size());identities[key]=next;
                arrivals.push_back({current.node,edge.to,-1,std::numeric_limits<double>::infinity()});
            }else next=found->second;
            if(cost+edge.cost<arrivals[next].distance){arrivals[next].distance=cost+edge.cost;arrivals[next].parent=state_id;queue.push({arrivals[next].distance,next});}
        }
    }
    if(terminal<0)return fail("disconnected");
    const double route_distance=arrivals[terminal].distance;
    if(route_distance<20)return fail("same_stop");
    std::vector<int> reverse;for(int id=terminal;id>=0;id=arrivals[id].parent)reverse.push_back(arrivals[id].node);
    PackedVector3Array points;for(auto it=reverse.rbegin();it!=reverse.rend();++it)points.push_back(nodes[*it]);
    Dictionary result;result["ok"]=true;result["points"]=points;result["distance_m"]=route_distance;result["fare"]=10+int(std::ceil(route_distance/100))*2;result["work"]=work;return result;
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
