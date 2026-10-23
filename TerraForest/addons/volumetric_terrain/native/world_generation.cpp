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
#include <vector>
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
 double height(Vector3 p){++samples;return world.height(p.x,p.z,false);}
 bool clear(Vector3 a,Vector3 b){
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
Dictionary plan_regional_route(const World &world,Vector3 start,Vector3 finish,const Array &reservations){
 if(!inside(start)||!inside(finish)||reservations.size()>4096)return failure("Invalid route input");
 Survey survey{world};
 for(int i=0;i<reservations.size();i++){
  if(reservations[i].get_type()!=Variant::RECT2)return failure("Invalid reservation");
  Rect2 area=reservations[i];if(!area.position.is_finite()||!area.size.is_finite()||area.size.x<0||area.size.y<0)return failure("Invalid reservation");
  survey.reserved.push_back(area.grow(6));
 }
 Vector3 lo=start.min(finish)-Vector3(256,0,256),hi=start.max(finish)+Vector3(256,0,256);
 lo.x=std::max<double>(16.,std::floor(lo.x/16)*16);lo.z=std::max<double>(16.,std::floor(lo.z/16)*16);
 hi.x=std::min<double>(1984.,std::ceil(hi.x/16)*16);hi.z=std::min<double>(1984.,std::ceil(hi.z/16)*16);
 int nx=int((hi.x-lo.x)/16)+1,nz=int((hi.z-lo.z)/16)+1;
 if(nx<1||nz<1||nx*nz>15625)return failure("Route search exceeds world bound");
 Ref<AStar3D> graph;graph.instantiate();graph->reserve_space(nx*nz+2);
 std::vector<Vector3> points(nx*nz);
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
 int source=nx*nz,target=source+1;graph->add_point(source,start);graph->add_point(target,finish);
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
  int count=int(std::ceil(start.distance_to(finish)/14))*2,begin=int(edges.size());
  if(count>1024||begin+count>8192)return failure("Street subdivision budget exceeded");
  for(int i=0;i<count;i++){
   Vector3 a=start.lerp(finish,double(i)/count),b=start.lerp(finish,double(i+1)/count);
   for(Vector3 p:{a,b})if(!vertices.count(key(p))){
    double low=1e30,high=-1e30;
    for(double dx:{-5.5,0.,5.5})for(double dz:{-5.5,0.,5.5}){
     Vector3 sample=p+Vector3(dx,0,dz);if(!inside(sample))return failure("Street outside terrain");
     double h=survey.height(sample);low=std::min(low,h);high=std::max(high,h);
    }
    if(high-3>low+2)return failure("Street node exceeds earthworks budget");
    vertices.emplace(key(p),Vertex{p,high-3,low+2});
   }
   edges.push_back({key(a),key(b),a.distance_to(b),begin,count});
  }
 }
 for(int iteration=0;iteration<128;iteration++){
  bool changed=false;
  for(const auto &e:edges){Vertex *a=&vertices.at(e.a),*b=&vertices.at(e.b);double rise=e.length*.08;
   for(int direction=0;direction<2;direction++){
    double lo=std::max(a->lo,b->lo-rise),hi=std::min(a->hi,b->hi+rise);
    if(lo>hi+.0001)return failure("Street requires a different route to meet grade");
    changed|=std::abs(lo-a->lo)>.00001||std::abs(hi-a->hi)>.00001;a->lo=lo;a->hi=hi;std::swap(a,b);
   }
  }if(!changed)break;
 }
 Array segments;double max_fill=0,max_cut=0,sum=0;int samples=0;
 for(const auto &e:edges){
  const auto &va=vertices.at(e.a),&vb=vertices.at(e.b);Vector3 a=va.p,b=vb.p;a.y=(va.lo+va.hi)*.5;b.y=(vb.lo+vb.hi)*.5;
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
  const auto &v=found->second;Vector3 p=v.p;p.y=(v.lo+v.hi)*.5;
  for(int dx=-6;dx<=6;dx++)for(int dz=-6;dz<=6;dz++)if(dx*dx+dz*dz<=5.5*5.5){
   Vector3 q=p+Vector3(dx,0,dz);if(!inside(q))return failure("Junction outside terrain");double fill=p.y-survey.height(q);
   if(fill>2||fill< -3)return failure("Junction exceeds earthworks budget");
  }
  Dictionary s=segment(p-Vector3(.5,0,0),p+Vector3(.5,0,0),3,3,4,2,4);PackedFloat64Array c;for(double value:{0.,0.,0.,double(p.y)})c.push_back(value);
  s["coefficients"]=c;s["curve_index"]=0;segments.push_back(s);
 }
 Dictionary d;d["ok"]=true;d["segments"]=segments;d["max_fill"]=max_fill;d["max_cut"]=max_cut;d["mean_earthwork"]=sum/std::max(1,samples);d["height_samples"]=survey.samples;d["planner_version"]=1;return d;
}
}
namespace terraforest {
namespace {
struct LotRoad {Vector3 start,finish;Vector2 a,axis;double denominator;};
Dictionary entrance_path(Survey &survey,Vector3 a,double street_z,const std::vector<LotRoad> &roads){
 Vector3 b(a.x,0,street_z);bool found=false;
 for(int i=0;i<roads.size();i++){
  const Vector3 &start=roads[i].start,&finish=roads[i].finish;
  if(std::abs(start.z-b.z)>.001||std::abs(finish.z-b.z)>.001||b.x<std::min(start.x,finish.x)||b.x>std::max(start.x,finish.x)||std::abs(finish.x-start.x)<.001)continue;
  double t=(b.x-start.x)/(finish.x-start.x);b.y=start.y+(finish.y-start.y)*t*t*(3-2*t);found=true;break;
 }
 double length=horizontal(b-a);if(!found||length<.01||std::abs(a.y-b.y)>length*.25)return failure("Entrance not connected");
 int count=int(std::ceil(length*2));if(count>4096)return failure("Entrance exceeds survey budget");
 for(int i=0;i<=count;i++)for(double dx:{-.75,0.,.75}){
  Vector3 p=a.lerp(b,double(i)/count)+Vector3(dx,0,0);if(!inside(p))return failure("Entrance outside terrain");
  double fill=p.y-survey.height(p);if(fill>2||fill< -3)return failure("Entrance exceeds earthworks budget");
 }
 Dictionary d;d["ok"]=true;d["segment"]=segment(a,b,.75,1,4,0,1);return d;
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
 }
 Survey survey{world};Array fitted,rejected;std::vector<AABB> reserved;
 const int offsets[]={0,-3,3,-6,6,-9,9};
 for(int index=0;index<lots.size();index++){
  Dictionary lot=lots[index],best;double best_cost=1e30;
  Vector3i base=lot["origin"];AABB original=lot["bounds"];PackedVector3Array points=lot["samples"];
  for(int dx:offsets)for(int dz:offsets){
   Vector3 shift(dx,0,dz);Vector3i origin=base+Vector3i(dx,0,dz);AABB bounds(original.position+shift,original.size);bool blocked=false;
   Rect2 footprint(Vector2(bounds.position.x,bounds.position.z),Vector2(bounds.size.x,bounds.size.z));
   for(const auto &occupied:reserved)if(footprint.grow(2).intersects(Rect2(Vector2(occupied.position.x,occupied.position.z),Vector2(occupied.size.x,occupied.size.z)))){blocked=true;break;}
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
   if(blocked)continue;int minimum=int(std::ceil(high-3)),maximum=int(std::floor(low+2));if(minimum>maximum)continue;
   double mid=(low+high)*.5;int grade=std::clamp(int(std::round(mid)),minimum,maximum),surface_offset=lot["surface_offset"];Dictionary entrance;
   if(!roads.is_empty()){
    bool found=false;Vector3 local=lot["entrance_local"];
    for(int candidate=minimum;candidate<=maximum;candidate++){
     Vector3 a=local+Vector3(origin.x,candidate-surface_offset,origin.z);
     Dictionary path=entrance_path(survey,a,double(lot["street_z"]),road_geometry);
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
  int n=std::max(1,int(std::ceil(horizontal(b-a)*256/2000*2)));
  for(int j=0;j<=n;j++){Vector3 p=a.lerp(b,double(j)/n);pixel(int(p.x*256/2000),int(p.z*256/2000),224,178,91);}
 }
 for(int i=0;i<lots.size();i++){
  if(lots[i].get_type()!=Variant::AABB)return {};AABB box=lots[i];if(!box.position.is_finite()||!box.size.is_finite())return {};
  int x0=std::clamp(int(std::floor(box.position.x*256/2000)),0,255),z0=std::clamp(int(std::floor(box.position.z*256/2000)),0,255);
  int x1=std::clamp(int(std::ceil((box.position.x+box.size.x)*256/2000)),0,255),z1=std::clamp(int(std::ceil((box.position.z+box.size.z)*256/2000)),0,255);
  for(int z=z0;z<=z1;z++)for(int x=x0;x<=x1;x++)pixel(x,z,245,235,210);
 }
 return result;
}
}
