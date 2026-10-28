// SPDX-License-Identifier: 0BSD
// Offline generation computations. No scene access; guarded by the owning core.
#include "core.h"
#include <godot_cpp/classes/a_star3d.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/rect2.hpp>
#include <godot_cpp/variant/aabb.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <algorithm>
#include <cmath>
#include <map>
#include <set>
#include <tuple>
#include <vector>
#include <godot_cpp/variant/packed_color_array.hpp>
namespace terraforest {
using namespace godot;
namespace {
Dictionary failure(const char *reason){Dictionary d;d["ok"]=false;d["reason"]=reason;return d;}
double horizontal(Vector3 v){return std::hypot(v.x,v.z);}
bool inside(Vector3 p){return p.is_finite()&&p.x>=0&&p.z>=0&&p.x<=2000&&p.z<=2000;}
Dictionary segment(Vector3 a,Vector3 b,double width,double depth,double clearance,double shoulder,int material){
 double extent=width+shoulder,rise=std::abs(b.y-a.y)*extent/horizontal(b-a);
 Vector3 lo=a.min(b)-Vector3(extent,depth+rise,extent),hi=a.max(b)+Vector3(extent,clearance+rise,extent);
 Dictionary d;d["start"]=a;d["finish"]=b;d["half_width"]=width;d["depth"]=depth;d["clearance"]=clearance;d["shoulder"]=shoulder;d["material"]=material;d["bounds"]=AABB(lo,hi-lo);return d;
}
struct Survey {
 const World &world;std::vector<Rect2> reserved;int64_t samples=0;
 bool cache=false;std::map<std::pair<float,float>,double> heights;
 double height(Vector3 p){
  auto key=std::make_pair(float(p.x),float(p.z));
  if(cache){auto found=heights.find(key);if(found!=heights.end())return found->second;}
  ++samples;double result=world.height(p.x,p.z,false);
  if(cache&&heights.size()<65536)heights.emplace(key,result);
  return result;
 }
 bool clear(Vector3 a,Vector3 b){
  if(distributed_region(world.generator_id)){
   for(const auto &area:reserved){
    double enter=0,leave=1;Vector2 origin(a.x,a.z),direction(b.x-a.x,b.z-a.z);
    for(int axis=0;axis<2&&enter<=leave;axis++){
     if(std::abs(direction[axis])<1e-9){if(origin[axis]<area.position[axis]||origin[axis]>=area.get_end()[axis])enter=2;}
     else{double near=(area.position[axis]-origin[axis])/direction[axis],far=(area.get_end()[axis]-origin[axis])/direction[axis];if(near>far)std::swap(near,far);enter=std::max(enter,near);leave=std::min(leave,far);}
    }
    if(enter<=leave)return false;
   }
   return true;
  }
  int count=std::max(1,int(std::ceil(horizontal(b-a)/2)));
  for(const auto &area:reserved)for(int i=0;i<=count;i++){
   Vector3 p=a.lerp(b,double(i)/count);if(area.has_point(Vector2(p.x,p.z)))return false;
  }return true;
 }
 bool corridor(Vector3 a,Vector3 b){
  double length=horizontal(b-a);if(length<1||length>128||std::abs(b.y-a.y)>length*.12||!clear(a,b))return false;
  Vector3 across=Vector3(-(b-a).z,0,(b-a).x).normalized();int n=int(std::ceil(length/2));
  for(int i=0;i<=n;i++)for(double side:{-5.,0.,5.}){
   Vector3 p=a.lerp(b,double(i)/n)+across*side;if(!inside(p))return false;
   double fill=p.y-height(p);if(fill>2||fill< -3)return false;
  }return true;
 }
};
}
// Fit water levels to the actual coastal terrain without changing terrain or saves.
// Catalog bounds remain the same reservations. Closed rim sampling prevents filling
// an obsolete inland level into a coast-adjusted basin.
Dictionary fit_generated_lakes(const World &world,const Array &records){
 if(records.size()>16)return failure("Too many generated lakes");
 Array fitted,rejected;Survey survey{world};
 for(int i=0;i<records.size();++i){
  if(records[i].get_type()!=Variant::DICTIONARY)return failure("Invalid lake record");
  Dictionary record=records[i];
  if(!record.has("id")||!record.has("origin")||!record.has("cells")||!record.has("spacing")||record["origin"].get_type()!=Variant::VECTOR3||record["cells"].get_type()!=Variant::VECTOR3I)return failure("Incomplete lake record");
  Vector3 origin=record["origin"];Vector3i cells=record["cells"];double spacing=record["spacing"];
  if(!std::isfinite(spacing)||spacing<=0||cells.x<=0||cells.z<=0)return failure("Invalid lake spacing");
  double width=cells.x*spacing,depth=cells.z*spacing;
  if(!inside(origin)||width<4||depth<4||width>160||depth>160||!inside(origin+Vector3(width,0,depth)))return failure("Invalid lake bounds");
  double rim=256,minimum=256;Vector3 seed;
  for(double z=0;z<=depth;z+=.5)for(double x:{0.,width})rim=std::min(rim,survey.height(origin+Vector3(x,0,z)));
  for(double x=0;x<=width;x+=.5)for(double z:{0.,depth})rim=std::min(rim,survey.height(origin+Vector3(x,0,z)));
  for(double z=1;z<depth;z+=2)for(double x=1;x<width;x+=2){
   Vector3 p=origin+Vector3(x,0,z);double h=survey.height(p);
   if(h<minimum){minimum=h;seed=p;}
  }
  double level=std::min(rim-1.,minimum+(width>100?5.:9.));
  if(level-minimum<1.5){rejected.push_back(record["id"]);continue;}
  origin.y=std::floor(minimum)-2.;cells.y=int(std::ceil((level+2-origin.y)/spacing));seed.y=minimum+.75;
  record["origin"]=origin;record["cells"]=cells;record["level"]=level;record["seed"]=seed;fitted.push_back(record);
 }
 Dictionary result;result["ok"]=true;result["records"]=fitted;result["rejected"]=rejected;result["height_samples"]=survey.samples;return result;
}
// Regional preview at 2m sampling. This surveys the connected horizontal
// surface of generated bowls, not their volume, and owns no water storage.
Dictionary survey_generated_lake_surfaces(const World &world,const Array &records){
 if(records.size()>16)return failure("Too many preview lakes");
 PackedVector3Array points;int samples=0;
 auto density=[&](Vector3 p){
  const int ix=int(std::floor(p.x)),iy=int(std::floor(p.y)),iz=int(std::floor(p.z));
  const float dx=p.x-ix,dy=p.y-iy,dz=p.z-iz;float d=0;
  for(int c=0;c<8;c++){float weight=(c&1?dx:1-dx)*(c&2?dy:1-dy)*(c&4?dz:1-dz);if(weight>0)d+=world.sample(ix+(c&1),iy+((c>>1)&1),iz+((c>>2)&1))*weight;}
  return d;
 };
 for(int i=0;i<records.size();i++){
  if(records[i].get_type()!=Variant::DICTIONARY)return failure("Invalid preview lake");Dictionary r=records[i];
  for(const char *key:{"origin","cells","spacing","level","seed"})if(!r.has(key))return failure("Incomplete preview lake");
  if(r["origin"].get_type()!=Variant::VECTOR3||r["cells"].get_type()!=Variant::VECTOR3I||r["seed"].get_type()!=Variant::VECTOR3)return failure("Invalid preview lake shape");
  Vector3 origin=r["origin"],seed=r["seed"];Vector3i cells=r["cells"];double spacing=r["spacing"],level=r["level"];
  double width=cells.x*spacing,depth=cells.z*spacing;
  if(!origin.is_finite()||!seed.is_finite()||!std::isfinite(spacing)||!std::isfinite(level)||spacing<=0||width<4||depth<4||width>160||depth>160||level<1||level>254||origin.x<0||origin.z<0||origin.x+width>=1999||origin.z+depth>=1999)return failure("Invalid preview lake bounds");
  int nx=int(std::ceil(width/2)),nz=int(std::ceil(depth/2));std::vector<uint8_t> wet(nx*nz),seen(nx*nz);std::vector<int> queue;
  for(int z=0;z<nz;z++)for(int x=0;x<nx;x++){
   Vector3 p(origin.x+(x+.5)*width/nx,level-.001,origin.z+(z+.5)*depth/nz);
   wet[z*nx+x]=density(p)>=0;++samples;
  }
  int sx=std::clamp(int((seed.x-origin.x)*nx/width),0,nx-1),sz=std::clamp(int((seed.z-origin.z)*nz/depth),0,nz-1),start=sz*nx+sx;
  if(!wet[start])continue;seen[start]=1;queue.push_back(start);
  for(size_t at=0;at<queue.size();at++){
   int index=queue[at],x=index%nx,z=index/nx;
   points.push_back(Vector3(origin.x+(x+.5)*width/nx,level,origin.z+(z+.5)*depth/nz));
   for(int d=0;d<4;d++){int xx=x+(d==0)-(d==1),zz=z+(d==2)-(d==3);
    if(xx<0||zz<0||xx>=nx||zz>=nz)continue;int next=zz*nx+xx;
    if(wet[next]&&!seen[next]){seen[next]=1;queue.push_back(next);}
   }
  }
 }
 Dictionary out;out["ok"]=true;out["points"]=points;out["samples"]=samples;out["spacing_m"]=2;return out;
}
struct RegionalRouteWorkspace{Ref<AStar3D> graph;Vector3 low;int width=0,depth=0;std::vector<Vector3> points;};
static Dictionary route_with_workspace(const World &world,Vector3 start,Vector3 finish,const Array &reservations,RegionalRouteWorkspace *shared){
 if(!inside(start)||!inside(finish)||reservations.size()>4096)return failure("Invalid route input");
 Survey survey{world};
 for(int i=0;i<reservations.size();i++){
  if(reservations[i].get_type()!=Variant::RECT2)return failure("Invalid reservation");
  Rect2 area=reservations[i];if(!area.position.is_finite()||!area.size.is_finite()||area.size.x<0||area.size.y<0)return failure("Invalid reservation");
  survey.reserved.push_back(area.grow(6));
 }
 Vector3 lo=start.min(finish)-Vector3(256,0,256),hi=start.max(finish)+Vector3(256,0,256);
 if(shared){lo=Vector3(16,0,16);hi=Vector3(1984,0,1984);}
 lo.x=std::max<double>(16.,std::floor(lo.x/16)*16);lo.z=std::max<double>(16.,std::floor(lo.z/16)*16);
 hi.x=std::min<double>(1984.,std::ceil(hi.x/16)*16);hi.z=std::min<double>(1984.,std::ceil(hi.z/16)*16);
 int nx=int((hi.x-lo.x)/16)+1,nz=int((hi.z-lo.z)/16)+1;
 if(nx<1||nz<1||nx*nz>15625)return failure("Route search exceeds world bound");
 RegionalRouteWorkspace local;auto &workspace=shared?*shared:local;
 if(workspace.graph.is_null()){
 workspace.graph.instantiate();workspace.graph->reserve_space(nx*nz+2);workspace.low=lo;workspace.width=nx;workspace.depth=nz;workspace.points.resize(nx*nz);
 auto graph=workspace.graph;auto &points=workspace.points;
 for(int z=0;z<nz;z++)for(int x=0;x<nx;x++){
  int id=z*nx+x;Vector3 p(lo.x+x*16,0,lo.z+z*16);p.y=survey.height(p);points[id]=p;
  if(survey.clear(p,p))graph->add_point(id,p);
 }
 const int offsets[4][2]={{1,0},{0,1},{1,1},{-1,1}};
 for(int z=0;z<nz;z++)for(int x=0;x<nx;x++){
  int id=z*nx+x;if(!graph->has_point(id))continue;
  for(auto &offset:offsets){int xx=x+offset[0],zz=z+offset[1];if(xx<0||xx>=nx||zz>=nz)continue;
   int next=zz*nx+xx;if(!graph->has_point(next))continue;Vector3 span=points[next]-points[id];
   if(std::abs(span.y)<=horizontal(span)*.12&&survey.clear(points[id],points[next]))graph->connect_points(id,next);
  }
 }
 }
 auto graph=workspace.graph;auto &points=workspace.points;
 int source=nx*nz,target=source+1;
 if(graph->has_point(source))graph->remove_point(source);
 if(graph->has_point(target))graph->remove_point(target);
 graph->add_point(source,start);graph->add_point(target,finish);
 for(int endpoint=0;endpoint<2;endpoint++){
  Vector3 p=endpoint?finish:start;int x=int(std::round((p.x-lo.x)/16)),z=int(std::round((p.z-lo.z)/16));
  for(int dz=-2;dz<=2;dz++)for(int dx=-2;dx<=2;dx++){
   int xx=x+dx,zz=z+dz;if(xx<0||zz<0||xx>=nx||zz>=nz)continue;int id=zz*nx+xx;
   if(graph->has_point(id)&&survey.corridor(p,points[id]))graph->connect_points(endpoint?target:source,id);
  }
 }
 for(int attempt=0;attempt<32;attempt++){
  auto ids=graph->get_id_path(source,target);if(ids.is_empty())return failure("No route fits terrain and exclusions");
  bool valid=true;
  for(int i=1;i<ids.size();i++)if(!survey.corridor(graph->get_point_position(ids[i-1]),graph->get_point_position(ids[i]))){graph->disconnect_points(ids[i-1],ids[i]);valid=false;}
  if(!valid)continue;
  PackedVector3Array path;path.push_back(start);int index=0;
  while(index<ids.size()-1){int next=std::min(int(ids.size())-1,index+6);
   while(next>index+1&&!survey.corridor(graph->get_point_position(ids[index]),graph->get_point_position(ids[next])))--next;
   path.push_back(graph->get_point_position(ids[next]));index=next;
  }
  Array segments;AABB bounds;bool first=true;
  for(int material:{1,4})for(int i=1;i<path.size();i++){
   Dictionary part=segment(path[i-1],path[i],material==1?5:4,3,4,material==1?1:0,material);
   segments.push_back(part);AABB box=part["bounds"];bounds=first?box:bounds.merge(box);first=false;
  }
  Dictionary d;d["ok"]=true;d["points"]=path;d["segments"]=segments;d["bounds"]=bounds;d["nodes"]=graph->get_point_count();d["attempts"]=attempt+1;d["height_samples"]=survey.samples;d["planner_version"]=1;return d;
 }
 return failure("Route refinement limit reached");
}
Dictionary plan_regional_route(const World &world,Vector3 start,Vector3 finish,const Array &reservations){
 return route_with_workspace(world,start,finish,reservations,nullptr);
}

Dictionary plan_region_network(const World &world,const Array &districts,const Array &reservations,int loops,int trails,int64_t seed,const Array &streets){
 if(districts.is_empty()||districts.size()>9||loops<0||loops>2||reservations.size()>4096||streets.size()>4096||trails<0||trails>2||seed<0||seed>0x7fffffff)return failure("Invalid regional network settings");
 struct FittedEdge{Vector3 start,finish;bool curved;};
 std::vector<FittedEdge> graded;
 for(int index=0;index<streets.size();++index){
  if(streets[index].get_type()!=Variant::DICTIONARY)return failure("Invalid fitted street");
  Dictionary street=streets[index];
  if(!street.has("start")||!street.has("finish")||street["start"].get_type()!=Variant::VECTOR3||street["finish"].get_type()!=Variant::VECTOR3)return failure("Missing fitted street endpoints");
  Vector3 start=street["start"],finish=street["finish"];
  if(!inside(start)||!inside(finish)||horizontal(finish-start)<.01)return failure("Invalid fitted street endpoints");
  graded.push_back({start,finish,street.has("coefficients")});
 }
 int crossing_rejections=0;
 auto compatible=[&](const PackedVector3Array &points){
  for(int index=1;index<points.size();++index){
   const Vector3 start=points[index-1],finish=points[index];
   const Vector2 origin(start.x,start.z),axis(finish.x-start.x,finish.z-start.z);
   for(const auto &edge:graded){
    const Vector2 other(edge.start.x,edge.start.z),span(edge.finish.x-edge.start.x,edge.finish.z-edge.start.z),offset=other-origin;
    auto heights_match=[&](double fraction,double other_fraction){
     const double eased=edge.curved?other_fraction*other_fraction*(3-2*other_fraction):other_fraction;
     return std::abs(start.y+(finish.y-start.y)*fraction-edge.start.y-(edge.finish.y-edge.start.y)*eased)<=.25;
    };
    const double denominator=axis.cross(span);
    if(std::abs(denominator)>.0001){
     const double fraction=offset.cross(span)/denominator,other_fraction=offset.cross(axis)/denominator;
     if(fraction>=0&&fraction<=1&&other_fraction>=0&&other_fraction<=1&&!heights_match(fraction,other_fraction)){++crossing_rejections;return false;}
    }else if(std::abs(offset.cross(axis))<.01){
     const double lower=std::max(0.0,std::min(double(offset.dot(axis)/axis.length_squared()),double((offset+span).dot(axis)/axis.length_squared())));
     const double upper=std::min(1.0,std::max(double(offset.dot(axis)/axis.length_squared()),double((offset+span).dot(axis)/axis.length_squared())));
     if(lower<=upper)for(double fraction:{lower,(lower+upper)*.5,upper}){
      const Vector2 point=origin+axis*fraction;
      if(!heights_match(fraction,std::clamp(double((point-other).dot(span)/span.length_squared()),0.0,1.0))){++crossing_rejections;return false;}
     }
    }
   }
  }
  return true;
 };
 std::vector<PackedVector3Array> exits;
 for(int index=0;index<districts.size();++index){
  if(districts[index].get_type()!=Variant::PACKED_VECTOR3_ARRAY)return failure("Invalid district exits");
  PackedVector3Array points=districts[index];
  if(points.is_empty()||points.size()>16)return failure("District has no unobstructed street exits");
  for(int point=0;point<points.size();++point)if(!inside(points[point]))return failure("District exit outside world");
  exits.push_back(points);
 }
 struct Pair{int source,target;double distance;};
 std::vector<Pair> pairs;
 for(int source=0;source<int(exits.size());++source)for(int target=source+1;target<int(exits.size());++target){
  double distance=1e30;
  for(int first=0;first<exits[source].size();++first)for(int second=0;second<exits[target].size();++second)distance=std::min(distance,double(exits[source][first].distance_squared_to(exits[target][second])));
  pairs.push_back({source,target,distance});
 }
 std::stable_sort(pairs.begin(),pairs.end(),[](const Pair &left,const Pair &right){return left.distance<right.distance;});
 int owners[9]={0,1,2,3,4,5,6,7,8};bool connected[9][9]={};
 Array links,segments;AABB bounds;bool first_bounds=true;double road_length=0,trail_length=0;int attempts=0,loop_count=0;
 std::set<std::tuple<float,float,float,float,float,float,double,double,int>> emitted;
 auto append=[&](Dictionary route,int source,int target,bool trail){
  PackedVector3Array points=route["points"];double length=0;
  Array parts;
  for(int point=1;point<points.size();++point){
   length+=points[point-1].distance_to(points[point]);
   graded.push_back({points[point-1],points[point],false});
   if(trail)parts.push_back(segment(points[point-1],points[point],2.5,3,4,1,1));
  }
  if(!trail)parts=route["segments"];
  for(int part=0;part<parts.size();++part){
   Dictionary value=parts[part];Vector3 start=value["start"],finish=value["finish"];
   if(std::tie(start.x,start.z,start.y)>std::tie(finish.x,finish.z,finish.y))std::swap(start,finish);
   auto key=std::make_tuple(float(start.x),float(start.y),float(start.z),float(finish.x),float(finish.y),float(finish.z),double(value["half_width"]),double(value["shoulder"]),int(value["material"]));
   if(distributed_region(world.generator_id)&&!emitted.insert(key).second)continue;
   AABB box=value["bounds"];bounds=first_bounds?box:bounds.merge(box);first_bounds=false;segments.push_back(value);
  }
  Dictionary link;link["source"]=source;link["target"]=target;link["trail"]=trail;link["points"]=points;link["length_m"]=length;links.push_back(link);
  if(trail)trail_length+=length;else road_length+=length;
 };
 RegionalRouteWorkspace workspace;
 auto connect=[&](int source,int target,bool optional){
  std::vector<Pair> choices;
  for(int first=0;first<exits[source].size();++first)for(int second=0;second<exits[target].size();++second)choices.push_back({first,second,double(exits[source][first].distance_squared_to(exits[target][second]))});
  std::stable_sort(choices.begin(),choices.end(),[](const Pair &left,const Pair &right){return left.distance<right.distance;});
  for(size_t choice=0;choice<std::min(size_t(64),choices.size());++choice){
   const auto &pair=choices[choice];++attempts;
   Dictionary route=route_with_workspace(world,exits[source][pair.source],exits[target][pair.target],reservations,distributed_region(world.generator_id)?&workspace:nullptr);
   if(!bool(route.get("ok",false))||!compatible(route["points"]))continue;
   if(optional&&distributed_region(world.generator_id)){
    PackedVector3Array points=route["points"];double novel=0,total=0;
    for(int segment=1;segment<points.size();segment++){
     double length=horizontal(points[segment]-points[segment-1]);int samples=std::max(1,int(std::ceil(length/8)));
     for(int sample=0;sample<samples;sample++){
      Vector3 position=points[segment-1].lerp(points[segment],(sample+.5)/samples);Vector2 point(position.x,position.z);bool covered=false;
      for(const auto &edge:graded){Vector2 origin(edge.start.x,edge.start.z),axis(edge.finish.x-edge.start.x,edge.finish.z-edge.start.z);double fraction=std::clamp(double((point-origin).dot(axis)/axis.length_squared()),0.,1.);if(point.distance_squared_to(origin+axis*fraction)<16){covered=true;break;}}
      total+=length/samples;if(!covered)novel+=length/samples;
     }
    }
    if(novel<std::max(64.,total*.25))continue;
   }
   append(route,source,target,false);connected[source][target]=true;return true;
  }
  return false;
 };
 for(const auto &pair:pairs){
  if(owners[pair.source]==owners[pair.target])continue;
  if(!connect(pair.source,pair.target,false))continue;
  const int previous=owners[pair.target],replacement=owners[pair.source];
  for(int index=0;index<int(exits.size());++index)if(owners[index]==previous)owners[index]=replacement;
 }
 for(int index=1;index<int(exits.size());++index)if(owners[index]!=owners[0]){
  Dictionary result=failure("Cannot connect every district within terrain limits; try another seed or fewer districts");
  result["isolated_district"]=index;result["route_attempts"]=attempts;result["crossing_rejections"]=crossing_rejections;return result;
 }
 if(loops)for(const auto &pair:pairs){
  if(connected[pair.source][pair.target])continue;
  if(connect(pair.source,pair.target,true)&&++loop_count>=(loops==2?int(exits.size()):1))break;
 }
 const int desired_trails=trails*int(exits.size());
 int trail_count=0;
 for(int source=0;source<int(exits.size());++source)for(int branch=0;branch<trails;++branch){
  for(int direction=0;direction<8;++direction){
   const int rotation=(direction+source*3+branch*4+int(seed%8))%8;
   const double angle=rotation*3.141592653589793/4;
   const Vector3 start=exits[source][(branch+direction)%exits[source].size()];
   Vector3 finish=start+Vector3(std::cos(angle)*240,0,std::sin(angle)*240);
   if(finish.x<32||finish.x>1968||finish.z<32||finish.z>1968)continue;
   finish.y=world.height(finish.x,finish.z,false);++attempts;
   Dictionary route=route_with_workspace(world,start,finish,reservations,distributed_region(world.generator_id)?&workspace:nullptr);
   if(!bool(route.get("ok",false))||!compatible(route["points"]))continue;
   append(route,source,-1,true);++trail_count;break;
  }
 }
 Dictionary result;result["ok"]=true;result["links"]=links;result["segments"]=segments;result["bounds"]=bounds;
 result["district_count"]=int(exits.size());result["road_length_m"]=road_length;result["trail_length_m"]=trail_length;
 result["trail_count"]=trail_count;result["requested_trails"]=desired_trails;result["loop_count"]=loop_count;result["route_attempts"]=attempts;
 result["crossing_rejections"]=crossing_rejections;
 if(!links.is_empty()){Dictionary link=links[0];result["points"]=link["points"];}
 return result;
}

Dictionary plan_street_network(const World &world,const Array &roads,const PackedVector3Array &junctions){
 if(roads.is_empty()||roads.size()>256||junctions.size()>1024)return failure("Invalid street network size");
 using Key=std::pair<int,int>;
 auto key=[](Vector3 p){return Key(int(std::round(p.x*100)),int(std::round(p.z*100)));};
 struct Vertex{Vector3 p;double lo,hi;};
 struct Edge{Key a,b;double length;int begin,count;};
 std::map<Key,Vertex> vertices;std::vector<Edge> edges;Survey survey{world};
 for(int r=0;r<roads.size();r++){
  if(roads[r].get_type()!=Variant::DICTIONARY)return failure("Invalid road");
  Dictionary road=roads[r];if(!road.has("start")||!road.has("finish"))return failure("Missing road endpoints");
  Vector3 start=road["start"],finish=road["finish"];
  if(!inside(start)||!inside(finish)||horizontal(finish-start)<.01)return failure("Invalid street endpoints");
  int count=std::max(2,int(std::floor(horizontal(finish-start)/25))*2),begin=int(edges.size());
  if(count>1024||begin+count>8192)return failure("Street subdivision budget exceeded");
  for(int i=0;i<count;i++){
   Vector3 a=start.lerp(finish,double(i)/count),b=start.lerp(finish,double(i+1)/count);
   for(Vector3 p:{a,b})if(!vertices.count(key(p))){
    double low=1e30,high=-1e30;
    for(double dx:{-5.5,0.,5.5})for(double dz:{-5.5,0.,5.5}){
     Vector3 sample=p+Vector3(dx,0,dz);if(!inside(sample))return failure("Street outside terrain");
     double h=survey.height(sample);low=std::min(low,h);high=std::max(high,h);
    }
    double grade_low=std::ceil(high-3),grade_high=std::floor(low+2);
    if(grade_low>grade_high)return failure("Street node exceeds grid-aligned earthworks budget");
    vertices.emplace(key(p),Vertex{p,grade_low,grade_high});
   }
   edges.push_back({key(a),key(b),a.distance_to(b),begin,count});
  }
 }
 for(int iteration=0;iteration<128;iteration++){
  bool changed=false;
  for(const auto &e:edges){Vertex *a=&vertices.at(e.a),*b=&vertices.at(e.b);double rise=std::floor(e.length*.08+.00001);
   for(int direction=0;direction<2;direction++){
    double lo=std::max(a->lo,b->lo-rise),hi=std::min(a->hi,b->hi+rise);
    if(lo>hi+.0001)return failure("Street requires a different route to meet grade");
    changed|=std::abs(lo-a->lo)>.00001||std::abs(hi-a->hi)>.00001;a->lo=lo;a->hi=hi;std::swap(a,b);
   }
  }if(!changed)break;
 }
 Array segments;double max_fill=0,max_cut=0,sum=0;int samples=0;
 for(const auto &e:edges){
  const auto &va=vertices.at(e.a),&vb=vertices.at(e.b);Vector3 a=va.p,b=vb.p;a.y=std::round((va.lo+va.hi)*.5);b.y=std::round((vb.lo+vb.hi)*.5);
  if(std::abs(a.y-b.y)>e.length*.08001)return failure("Street grade solver did not converge");
  Vector3 across=Vector3(-(b-a).z,0,(b-a).x).normalized();
  for(int step=0;step<9;step++)for(double lateral:{-5.5,-4.,-2.,0.,2.,4.,5.5}){
   double t=step/8.;Vector3 p=a.lerp(b,t)+across*lateral;p.y=a.y+(b.y-a.y)*t*t*(3-2*t);
   if(!inside(p))return failure("Street outside terrain");double fill=p.y-survey.height(p);
   sum+=std::abs(fill);samples++;max_fill=std::max(max_fill,fill);max_cut=std::max(max_cut,-fill);
   if(fill>2.001||fill< -3.001)return failure("Street interior exceeds earthworks budget");
  }
  segments.push_back(segment(a,b,3,1,4,0,4));
 }
 // One coefficient array per authored chain, shared by its segment dictionaries.
 std::map<int,PackedFloat64Array> curves;
 for(int i=0;i<int(edges.size());i++){
  const auto &e=edges[i];if(!curves.count(e.begin)){
   PackedFloat64Array coefficients;
   for(int j=e.begin;j<e.begin+e.count;j++){Dictionary s=segments[j];Vector3 a=s["start"],b=s["finish"];double delta=b.y-a.y;
    for(double v:{-2*delta,3*delta,0.,double(a.y)})coefficients.push_back(v);
   }curves.emplace(e.begin,coefficients);
  }
  Dictionary s=segments[i];s["coefficients"]=curves.at(e.begin);s["curve_index"]=i-e.begin;
 }
 for(int i=0;i<junctions.size();i++){
  if(!inside(junctions[i]))return failure("Invalid junction");auto found=vertices.find(key(junctions[i]));
  if(found==vertices.end())return failure("Junction is not a street node");
  const auto &v=found->second;Vector3 p=v.p;p.y=std::round((v.lo+v.hi)*.5);
  for(int dx=-6;dx<=6;dx++)for(int dz=-6;dz<=6;dz++)if(dx*dx+dz*dz<=5.5*5.5){
   Vector3 q=p+Vector3(dx,0,dz);if(!inside(q))return failure("Junction outside terrain");double fill=p.y-survey.height(q);
   if(fill>2||fill< -3)return failure("Junction exceeds earthworks budget");
  }
  Dictionary s=segment(p-Vector3(.5,0,0),p+Vector3(.5,0,0),3,3,4,2,4);PackedFloat64Array c;for(double value:{0.,0.,0.,double(p.y)})c.push_back(value);
  s["coefficients"]=c;s["curve_index"]=0;segments.push_back(s);
 }
 Dictionary d;d["ok"]=true;d["segments"]=segments;d["max_fill"]=max_fill;d["max_cut"]=max_cut;d["mean_earthwork"]=sum/std::max(1,samples);d["height_samples"]=survey.samples;d["planner_version"]=2;return d;
}
}
namespace terraforest {
namespace {
struct LotRoad {Vector3 start,finish;Vector2 a,axis;double denominator;};
Dictionary entrance_path(Survey &survey,Vector3 a,double street_z,const std::vector<LotRoad> &roads,double width=.75,double target_x=NAN){
 Vector3 b(std::isfinite(target_x)?target_x:a.x,0,street_z);bool found=false;
 for(int i=0;i<roads.size();i++){
  const Vector3 &start=roads[i].start,&finish=roads[i].finish;
  if(std::abs(start.z-b.z)>.001||std::abs(finish.z-b.z)>.001||b.x<std::min(start.x,finish.x)||b.x>std::max(start.x,finish.x)||std::abs(finish.x-start.x)<.001)continue;
  double t=(b.x-start.x)/(finish.x-start.x);b.y=start.y+(finish.y-start.y)*t*t*(3-2*t);found=true;break;
 }
 double length=horizontal(b-a);if(!found||length<.01||std::abs(a.y-b.y)>length*.25)return failure("Entrance not connected");
 int count=int(std::ceil(length*2));if(count>4096)return failure("Entrance exceeds survey budget");
 Vector3 across=Vector3(-(b-a).z,0,(b-a).x).normalized();
 for(int i=0;i<=count;i++)for(double dx:{-width,0.,width}){
  Vector3 p=a.lerp(b,double(i)/count)+across*dx;if(!inside(p))return failure("Entrance outside terrain");
  double fill=p.y-survey.height(p);if(fill>2||fill< -3)return failure("Entrance exceeds earthworks budget");
 }
 Dictionary d;d["ok"]=true;d["segment"]=segment(a,b,width,1,4,0,1);return d;
}
}
Dictionary plan_settlement_lots(const World &world,Vector3 center,const Array &lots,const Array &roads,bool default_streets){
 if(!inside(center)||lots.is_empty()||lots.size()>256||roads.size()>8192)return failure("Invalid lot plan size");
 // Validate before computation: callers supply plain prefab geometry, not scene objects.
 std::vector<LotRoad> road_geometry;road_geometry.reserve(roads.size());
 for(int i=0;i<roads.size();i++){
  if(roads[i].get_type()!=Variant::DICTIONARY)return failure("Invalid lot road");Dictionary r=roads[i];
  if(!r.has("start")||!r.has("finish")||!inside(r["start"])||!inside(r["finish"]))return failure("Invalid lot road endpoints");
  Vector3 a=r["start"],b=r["finish"];Vector2 first(a.x,a.z),axis(b.x-a.x,b.z-a.z);
  road_geometry.push_back({a,b,first,axis,std::max(.001,double(axis.length_squared()))});
 }
 for(int i=0;i<lots.size();i++){
  if(lots[i].get_type()!=Variant::DICTIONARY)return failure("Invalid lot descriptor");Dictionary l=lots[i];
  for(const char *field:{"origin","bounds","samples","entrance_local","surface_offset","street_z","label","rotation","asset"})if(!l.has(field))return failure("Incomplete lot descriptor");
  PackedVector3Array samples=l["samples"];if(samples.is_empty()||samples.size()>65536)return failure("Invalid foundation sample count");
  for(int j=0;j<samples.size();j++)if(!inside(samples[j]))return failure("Invalid foundation sample");
  AABB b=l["bounds"];Vector3 entrance=l["entrance_local"];
  if(!b.position.is_finite()||!b.size.is_finite()||!entrance.is_finite()||!std::isfinite(double(l["street_z"])))return failure("Invalid lot geometry");
  if(b.size.x<=0||b.size.z<=0||b.size.x>128||b.size.z>128)return failure("Lot footprint exceeds bounded survey");
  if(l.has("access_points")){
   if(l["access_points"].get_type()!=Variant::PACKED_VECTOR3_ARRAY)return failure("Invalid access points");
   PackedVector3Array access=l["access_points"];if(access.size()>8)return failure("Too many access points");
   for(int point=0;point<access.size();point++)if(!access[point].is_finite())return failure("Invalid access point");
  }
 }
 Survey survey{world};survey.cache=true;Array fitted,rejected;std::vector<AABB> reserved;
 const int offsets[]={0,-3,3,-6,6,-9,9};
 for(int index=0;index<lots.size();index++){
  Dictionary lot=lots[index],best;double best_cost=1e30;
  Vector3i base=lot["origin"];AABB original=lot["bounds"];PackedVector3Array points=lot["samples"];
  for(int dx:offsets)for(int dz:offsets){
   Vector3 shift(dx,0,dz);Vector3i origin=base+Vector3i(dx,0,dz);AABB bounds(original.position+shift,original.size);bool blocked=false;
   Rect2 footprint(Vector2(bounds.position.x,bounds.position.z),Vector2(bounds.size.x,bounds.size.z));
   for(const auto &occupied:reserved)if(footprint.grow(2).intersects(Rect2(Vector2(occupied.position.x,occupied.position.z),Vector2(occupied.size.x,occupied.size.z)))){blocked=true;break;}
   if(world.generator_id>=EMBED_REGION_GENERATOR_ID&&int(lot["surface_offset"])>0&&!blocked){
    Rect2 corridor=footprint.grow(6.5);
    for(const auto &road:road_geometry){
     double enter=0,leave=1;
     for(int axis=0;axis<2&&enter<=leave;++axis){
      double origin=road.a[axis],direction=road.axis[axis],low=corridor.position[axis],high=corridor.get_end()[axis];
      if(std::abs(direction)<1e-9){if(origin<low||origin>high)enter=2;}
      else{double first=(low-origin)/direction,last=(high-origin)/direction;if(first>last)std::swap(first,last);enter=std::max(enter,first);leave=std::min(leave,last);}
     }
     if(enter<=leave){blocked=true;break;}
    }
   }
   if(blocked)continue;
   double low=1e30,high=-1e30;
   for(int i=0;i<points.size();i++){
    Vector3 p=points[i]+shift;
    if(!inside(p)||std::abs(p.x-center.x)<8){blocked=true;break;}
    if(default_streets){
     for(int street:{-52,0,52})if(std::abs(p.z-center.z-street)<6.5){blocked=true;break;}
     if(std::abs(std::abs(p.x-center.x)-42)<6.5&&std::abs(p.z-center.z)<=57)blocked=true;
    }else for(const auto &road:road_geometry){
     // Unpack Variant endpoints once per request, not for every foundation cell.
     if(p.x<std::min(road.start.x,road.finish.x)-6.5||p.x>std::max(road.start.x,road.finish.x)+6.5||
        p.z<std::min(road.start.z,road.finish.z)-6.5||p.z>std::max(road.start.z,road.finish.z)+6.5)continue;
     Vector2 q(p.x,p.z);double t=std::clamp(double((q-road.a).dot(road.axis))/road.denominator,0.,1.);
     if(q.distance_to(road.a+road.axis*t)<6.5){blocked=true;break;}
    }
    if(blocked)break;double h=survey.height(p);low=std::min(low,h);high=std::max(high,h);
   }
   for(int row=0;row<=int(std::ceil(bounds.size.z+2))&&!blocked;row++)for(int column=0;column<=int(std::ceil(bounds.size.x+2));column++){
    Vector3 sample(bounds.position.x-1+std::min(double(column),double(bounds.size.x+2)),0,bounds.position.z-1+std::min(double(row),double(bounds.size.z+2)));
    if(!inside(sample)){blocked=true;break;}
    double height=survey.height(sample);low=std::min(low,height);high=std::max(high,height);
   }
   if(blocked)continue;int minimum=int(std::ceil(high-3)),maximum=int(std::floor(low+2));if(minimum>maximum)continue;
   double mid=(low+high)*.5;int grade=std::clamp(int(std::round(mid)),minimum,maximum),surface_offset=lot["surface_offset"];Dictionary entrance;
   if(!roads.is_empty()){
    bool found=false;Vector3 local=lot["entrance_local"];
    for(int candidate=minimum;candidate<=maximum;candidate++){
     Vector3 a=local+Vector3(origin.x,candidate-surface_offset,origin.z);
     Dictionary path=entrance_path(survey,a,double(lot["street_z"]),road_geometry);
     if(bool(path["ok"])&&lot.has("access_points")){
      PackedVector3Array access=lot["access_points"];
      Dictionary primary=path["segment"];Vector3 target=primary["finish"];
      for(int point=0;point<access.size();point++){
       Vector3 doorway=access[point]+Vector3(origin.x,candidate-surface_offset,origin.z);
       if(!bool(entrance_path(survey,doorway,double(lot["street_z"]),road_geometry,2.5,target.x)["ok"])){path["ok"]=false;break;}
      }
     }
     if(bool(path["ok"])&&(!found||std::abs(candidate-mid)<std::abs(grade-mid))){grade=candidate;entrance=path;found=true;}
    }if(!found)continue;
   }
   double cost=high-low+.04*(std::abs(dx)+std::abs(dz));if(cost>=best_cost)continue;
   origin.y=grade-surface_offset;bounds.position.y+=origin.y-base.y;
   Dictionary measure;measure["ok"]=true;measure["min_height"]=low;measure["max_height"]=high;measure["grade"]=grade;
   best["asset"]=lot["asset"];best["origin"]=origin;best["rotation"]=lot["rotation"];best["label"]=lot["label"];best["street_z"]=lot["street_z"];
   best["survey"]=measure;best["sample_count"]=points.size();best["bounds"]=bounds;best["entrance"]=entrance;best_cost=cost;
  }
  if(best.is_empty())rejected.push_back(lot["label"]);else{fitted.push_back(best);reserved.push_back(best["bounds"]);}
 }
 Dictionary d;d["ok"]=rejected.is_empty();d["lots"]=fitted;d["rejected"]=rejected;d["reason"]=rejected.is_empty()?"":"Frontage zones require relocation or a different street layout";d["height_samples"]=survey.samples;d["planner_version"]=1;return d;
}
}
namespace terraforest {
godot::PackedByteArray render_generation_map(const godot::PackedByteArray &base,const godot::Array &roads,const godot::Array &lots,const godot::PackedByteArray &water){
 if(base.size()!=256*256*4||roads.size()>16384||lots.size()>512)return {};
 if(!water.is_empty()&&water.size()!=base.size())return {};
 PackedByteArray result=base;auto *pixels=result.ptrw();
 if(!water.is_empty())for(int at=0;at<water.size();at+=4){
  unsigned alpha=water[at+3];
  for(int channel=0;channel<3;channel++)pixels[at+channel]=(pixels[at+channel]*(255-alpha)+water[at+channel]*alpha+127)/255;
 }
 auto pixel=[&](int x,int y,int r,int g,int b){if(x<0||y<0||x>=256||y>=256)return;int i=(y*256+x)*4;pixels[i]=r;pixels[i+1]=g;pixels[i+2]=b;pixels[i+3]=255;};
 for(int i=0;i<roads.size();i++){
  if(roads[i].get_type()!=Variant::DICTIONARY)return {};Dictionary road=roads[i];if(!road.has("start")||!road.has("finish"))return {};
  Vector3 a=road["start"],b=road["finish"];if(!inside(a)||!inside(b))return {};
  double radius=double(road.get("half_width",4.0));if(!std::isfinite(radius)||radius<0||radius>32)return {};
  Vector2 start(a.x,a.z),axis(b.x-a.x,b.z-a.z);double squared=axis.length_squared();if(squared<.0001)continue;
  int left=std::clamp(int(std::floor((std::min(a.x,b.x)-radius)*256/2000)),0,255),right=std::clamp(int(std::ceil((std::max(a.x,b.x)+radius)*256/2000)),0,255);
  int top=std::clamp(int(std::floor((std::min(a.z,b.z)-radius)*256/2000)),0,255),bottom=std::clamp(int(std::ceil((std::max(a.z,b.z)+radius)*256/2000)),0,255);
  bool asphalt=int(road.get("material",4))==4;Color color=asphalt?Color(.21,.22,.23):Color(.45,.40,.31);
  for(int row=top;row<=bottom;row++)for(int column=left;column<=right;column++){
   int covered=0;for(int sample=0;sample<16;sample++){
    Vector2 point((column+((sample%4)+.5)/4)*2000/256,(row+((sample/4)+.5)/4)*2000/256);
    double fraction=std::clamp(double((point-start).dot(axis))/squared,0.,1.);
    if(point.distance_squared_to(start+axis*fraction)<=radius*radius)covered++;
   }
   int at=(row*256+column)*4;for(int channel=0;channel<3;channel++)pixels[at+channel]=uint8_t((pixels[at+channel]*(16-covered)+color[channel]*255*covered)/16);
  }
 }
 std::vector<float> surface_heights(256*256,-1e9f);
 for(int i=0;i<lots.size();i++){
  if(lots[i].get_type()==Variant::DICTIONARY){
   Dictionary surface=lots[i];PackedVector3Array points=surface.get("points",PackedVector3Array());PackedColorArray colors=surface.get("colors",PackedColorArray());
   if(points.size()>65536||points.size()!=colors.size())return {};
   for(int sample=0;sample<points.size();sample++){
    auto point=points[sample];auto color=colors[sample];if(!point.is_finite()||!std::isfinite(color.r)||!std::isfinite(color.g)||!std::isfinite(color.b)||!std::isfinite(color.a))return {};
    int column=int(std::floor(point.x*256/2000)),row=int(std::floor(point.z*256/2000));if(column<0||row<0||column>=256||row>=256)continue;
    int at=row*256+column;if(point.y<surface_heights[at])continue;surface_heights[at]=point.y;
    pixel(column,row,int(std::clamp(color.r,0.f,1.f)*255),int(std::clamp(color.g,0.f,1.f)*255),int(std::clamp(color.b,0.f,1.f)*255));
   }
   continue;
  }
  if(lots[i].get_type()!=Variant::AABB)return {};AABB box=lots[i];if(!box.position.is_finite()||!box.size.is_finite())return {};
  int x0=std::clamp(int(std::floor(box.position.x*256/2000)),0,255),z0=std::clamp(int(std::floor(box.position.z*256/2000)),0,255);
  int x1=std::clamp(int(std::ceil((box.position.x+box.size.x)*256/2000)),0,255),z1=std::clamp(int(std::ceil((box.position.z+box.size.z)*256/2000)),0,255);
  for(int z=z0;z<=z1;z++)for(int x=x0;x<=x1;x++)pixel(x,z,128,119,103);
 }
 return result;
}
}
