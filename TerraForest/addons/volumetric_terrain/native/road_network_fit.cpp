#include "core.h"
#include "generation_contact.hpp"
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/variant.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/rect2.hpp>
#include <godot_cpp/variant/aabb.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <algorithm>
#include <array>
#include <cmath>
#include <map>
#include <tuple>
#include <vector>

namespace terraforest {
using namespace godot;
namespace {
using Curve=std::array<double,4>;
double value(const Curve &curve,double fraction){return ((curve[0]*fraction+curve[1])*fraction+curve[2])*fraction+curve[3];}
double derivative(const Curve &curve,double fraction){return (3*curve[0]*fraction+2*curve[1])*fraction+curve[2];}
double maximum_grade(const Curve &curve,double length){
 double result=std::max(std::abs(derivative(curve,0)),std::abs(derivative(curve,1)))/length;
 if(std::abs(curve[0])>1e-12){double fraction=-curve[1]/(3*curve[0]);if(fraction>0&&fraction<1)result=std::max(result,std::abs(derivative(curve,fraction))/length);}
 return result;
}
struct Station{Vector3 position;double original=0,height=0,target=0,low=0,high=0;bool fixed=false;};
struct FootPoint{int section;std::array<double,4> weights;double original;};
struct Footprint{std::array<FootPoint,9> points;};
struct Edge{Dictionary record;Vector3 start,finish;double length,width,step,grade_width,extent;Curve original;std::vector<int> nodes;std::vector<double> tangents;std::vector<Curve> curves;std::vector<Footprint> footprints;std::vector<double> gradient,weight;};
Dictionary rejected(const char *reason,int road=-1){Dictionary result;result["ok"]=false;result["reason"]=reason;result["road"]=road;result["version"]=2;return result;}
double clamp_station(Station &station){double previous=station.height;station.height=std::clamp(station.height,station.low,station.high);return std::abs(previous-station.height);}
bool contact(double minimum,double maximum){return generation_contact::fits(minimum,maximum);}
double evaluate_foot(const FootPoint &point,const Edge &edge,const std::vector<Station> &nodes){
 return point.weights[0]*nodes[edge.nodes[point.section]].height+point.weights[1]*edge.tangents[point.section]+point.weights[2]*nodes[edge.nodes[point.section+1]].height+point.weights[3]*edge.tangents[point.section+1];
}
}
Dictionary fit_generated_road_network(const World &world,const Array &source,const Array &protected_areas,bool footprint_policy){
 if(source.is_empty()||source.size()>2048||protected_areas.size()>4096)return rejected("Connected road input budget exceeded");
 std::vector<Rect2> reserved;
 for(int index=0;index<protected_areas.size();++index){
  if(protected_areas[index].get_type()!=Variant::RECT2)return rejected("Invalid protected corridor");
  Rect2 area=protected_areas[index];if(!area.position.is_finite()||!area.size.is_finite()||area.size.x<0||area.size.y<0)return rejected("Invalid protected corridor bounds");reserved.push_back(area);
 }
 std::vector<Station> nodes;std::vector<Edge> edges;
 std::map<std::tuple<int,int,int>,int> junctions;
 int samples=0,fixed_count=0,footprint_count=0;
 for(int index=0;index<source.size();++index){
  if(source[index].get_type()!=Variant::DICTIONARY)return rejected("Invalid connected road descriptor",index);
  Dictionary record=source[index];
  for(const char *field:{"start","finish","half_width","depth","clearance","shoulder","material","bounds"})if(!record.has(field))return rejected("Incomplete connected road descriptor",index);
  if(record["start"].get_type()!=Variant::VECTOR3||record["finish"].get_type()!=Variant::VECTOR3)return rejected("Invalid connected road endpoints",index);
  if(record["bounds"].get_type()!=Variant::AABB)return rejected("Invalid connected road bounds",index);
  AABB bounds=record["bounds"];
  if(!bounds.position.is_finite()||!bounds.size.is_finite()||bounds.size.x<0||bounds.size.y<0||bounds.size.z<0)return rejected("Invalid connected road bounds",index);
  for(const char *field:{"half_width","depth","clearance","shoulder","material"})if((record[field].get_type()!=Variant::FLOAT&&record[field].get_type()!=Variant::INT)||!std::isfinite(double(record[field])))return rejected("Invalid connected road limits",index);
  Edge edge;edge.record=record;edge.start=record["start"];edge.finish=record["finish"];edge.length=Vector2(edge.finish.x-edge.start.x,edge.finish.z-edge.start.z).length();edge.width=record["half_width"];
  if(!edge.start.is_finite()||!edge.finish.is_finite()||edge.length<.5||edge.length>128||edge.width<.5||edge.width>16)return rejected("Connected road geometry outside limits",index);
  for(const auto &point:{edge.start,edge.finish})if(point.x<1||point.z<1||point.x>1999||point.z>1999||point.y<1||point.y>250)return rejected("Connected road endpoints outside world",index);
  if(double(record["shoulder"])<0||double(record["shoulder"])>16||double(record["depth"])<=0||double(record["depth"])>16||double(record["clearance"])<0||double(record["clearance"])>32)return rejected("Connected road edit limits outside budget",index);
  edge.grade_width=edge.width;edge.extent=std::max(6.5,edge.width+double(record["shoulder"]));
  if(footprint_policy){
   for(const char *field:{"support_half_width","support_shoulder"})if(record.has(field)&&((record[field].get_type()!=Variant::FLOAT&&record[field].get_type()!=Variant::INT)||!std::isfinite(double(record[field]))))return rejected("Invalid generated support envelope",index);
   edge.grade_width=record.get("support_half_width",edge.width);double support_shoulder=record.get("support_shoulder",0.0);
   if(edge.grade_width<edge.width||edge.grade_width>16||support_shoulder<0||support_shoulder>16)return rejected("Generated support envelope outside budget",index);
   edge.extent=std::max(edge.extent,edge.grade_width+support_shoulder);
  }
  edge.original={0,0,double(edge.finish.y-edge.start.y),double(edge.start.y)};
  if(record.has("coefficients")){
   if(record["coefficients"].get_type()!=Variant::PACKED_FLOAT64_ARRAY)return rejected("Invalid road curve type",index);
   PackedFloat64Array curve=record["coefficients"];int part=record.get("curve_index",0);
   if(part<0||curve.size()%4||curve.size()>256||part*4+4>curve.size())return rejected("Invalid road curve index",index);
   for(int component=0;component<4;++component)edge.original[component]=curve[part*4+component];
  }
  for(double coefficient:edge.original)if(!std::isfinite(coefficient)||std::abs(coefficient)>4096)return rejected("Nonfinite road curve",index);
  if(std::abs(value(edge.original,0)-edge.start.y)>.001||std::abs(value(edge.original,1)-edge.finish.y)>.001)return rejected("Road curve/endpoints disagree",index);
  int divisions=std::max(1,int(std::ceil(edge.length/3.)));edge.step=edge.length/divisions;
  Vector3 across(-(edge.finish-edge.start).z,0,(edge.finish-edge.start).x);across.normalize();
  double extent=edge.extent;
  bool level=std::abs(edge.original[0])+std::abs(edge.original[1])+std::abs(edge.original[2])<1e-6&&std::abs(edge.start.y-std::round(edge.start.y))<.001;
  for(int station=0;station<=divisions;++station){
   double fraction=double(station)/divisions,original=value(edge.original,fraction);Vector3 position=edge.start.lerp(edge.finish,fraction);position.y=original;
   bool fixed=level||edge.length<2;
   for(const auto &area:reserved){
    if(!footprint_policy){if(area.grow(extent+3).has_point(Vector2(position.x,position.z))){fixed=true;break;}continue;}
    Vector2 origin(edge.start.x,edge.start.z),direction(edge.finish.x-edge.start.x,edge.finish.z-edge.start.z);direction/=edge.length;Vector2 lateral(-direction.y,direction.x);
    double near=1e30,far=-1e30,left=1e30,right=-1e30;
    for(int corner=0;corner<4;++corner){Vector2 offset=area.position+Vector2(corner&1?area.size.x:0,corner&2?area.size.y:0)-origin;double along=offset.dot(direction),side=offset.dot(lateral);near=std::min(near,along);far=std::max(far,along);left=std::min(left,side);right=std::max(right,side);}
    if(left<=extent&&right>=-extent&&fraction*edge.length>=near-3&&fraction*edge.length<=far+3){fixed=true;break;}
   }
   double low=original-.55,high=original+.55;
   if(!fixed){
    int count=int(std::ceil(2*extent/.5));
    for(int side=0;side<=count;++side){
     Vector3 point=position+across*(-extent+2*extent*side/count);
     if(point.x<1||point.z<1||point.x>1999||point.z>1999)return rejected("Road survey outside world",index);
     double terrain=world.height(point.x,point.z,false);++samples;low=std::max(low,terrain-2.94);high=std::min(high,terrain+1.94);
    }
   }else{low=high=original;++fixed_count;}
   if(low>high){Dictionary failure=rejected("Corridor requires rerouting: no permitted cut/fill grade",index);failure["position"]=position;failure["low"]=low;failure["high"]=high;return failure;}
   int node=-1;auto key=std::make_tuple(int(std::round(position.x*1000)),int(std::round(position.z*1000)),int(std::round(original*1000)));
   if(station==0||station==divisions){auto found=junctions.find(key);if(found!=junctions.end())node=found->second;}
   if(node<0){
    node=int(nodes.size());Station next;next.position=position;next.original=original;next.height=original;next.target=footprint_policy?generation_contact::preferred_height(original):std::floor(original+.42)+.04;next.low=low;next.high=high;next.fixed=fixed;clamp_station(next);nodes.push_back(next);
    if(station==0||station==divisions)junctions[key]=node;
   }else{
    auto &next=nodes[node];next.low=std::max(next.low,low);next.high=std::min(next.high,high);next.fixed|=fixed;
    if(next.low>next.high)return rejected("Shared junction has incompatible grade limits",index);clamp_station(next);
   }
   edge.nodes.push_back(node);
   edge.tangents.push_back(derivative(edge.original,fraction)/divisions);
  }
  if(footprint_policy){
   Vector2 origin(edge.start.x,edge.start.z),axis(edge.finish.x-edge.start.x,edge.finish.z-edge.start.z);
   int first_x=int(std::floor(std::min(edge.start.x,edge.finish.x)-edge.grade_width)),last_x=int(std::ceil(std::max(edge.start.x,edge.finish.x)+edge.grade_width));
   int first_z=int(std::floor(std::min(edge.start.z,edge.finish.z)-edge.grade_width)),last_z=int(std::ceil(std::max(edge.start.z,edge.finish.z)+edge.grade_width));
   for(int across_cell=first_x;across_cell<last_x;++across_cell)for(int along_cell=first_z;along_cell<last_z;++along_cell){
    Vector2 offset=Vector2(across_cell+.5,along_cell+.5)-origin;double fraction=offset.dot(axis)/axis.length_squared(),lateral=std::abs(offset.cross(axis))/edge.length;
    if(fraction*edge.length<.71||(1-fraction)*edge.length<.71||lateral>edge.grade_width-.71)continue;
    if(++footprint_count>131072)return rejected("Generation footprint budget exceeded");
    Footprint footprint;int point_index=0;
    for(double offset_x:{.08,.5,.92})for(double offset_z:{.08,.5,.92}){
     double projected=(Vector2(across_cell+offset_x,along_cell+offset_z)-origin).dot(axis)/axis.length_squared();double location=projected*divisions;int section=std::clamp(int(location),0,divisions-1);double local=location-section,square=local*local,cube=square*local;
     footprint.points[point_index++]={section,{2*cube-3*square+1,cube-2*square+local,-2*cube+3*square,cube-square},value(edge.original,projected)};
    }
    edge.footprints.push_back(footprint);
   }
   edge.gradient.resize(edge.nodes.size());edge.weight.resize(edge.nodes.size());
  }
  edges.push_back(std::move(edge));if(nodes.size()>8192)return rejected("Connected road station budget exceeded");
 }
 int protected_crossings=0;
 for(size_t first=0;first<edges.size();++first)for(size_t second=0;second<first;++second){
  auto &left=edges[first];auto &right=edges[second];Vector2 origin(left.start.x,left.start.z),axis(left.finish.x-left.start.x,left.finish.z-left.start.z),other(right.start.x,right.start.z),span(right.finish.x-right.start.x,right.finish.z-right.start.z),offset=other-origin;
  double denominator=axis.cross(span);if(std::abs(denominator)<1e-5)continue;
  double along=offset.cross(span)/denominator,across=offset.cross(axis)/denominator;
  if(along<0||along>1||across<0||across>1||((along<1e-5||along>1-1e-5)&&(across<1e-5||across>1-1e-5)))continue;
  ++protected_crossings;Vector2 crossing=origin+axis*along;
  for(auto *edge:{&left,&right})for(int node:edge->nodes){
   auto &station=nodes[node];if(Vector2(station.position.x,station.position.z).distance_to(crossing)>std::max(left.width,right.width)+6)continue;
   if(station.original<station.low-1e-5||station.original>station.high+1e-5)return rejected("Crossing requires corridor replanning",int(first));
   station.low=station.high=station.height=station.original;station.fixed=true;
  }
 }
 auto project=[&](){
  double residual=0;
  for(auto &node:nodes)residual=std::max(residual,clamp_station(node));
  for(auto &edge:edges){
   double grade_limit=.135*edge.step;
   for(size_t station=1;station<edge.nodes.size();++station){
    auto &first=nodes[edge.nodes[station-1]];auto &last=nodes[edge.nodes[station]];double difference=last.height-first.height;
    double error=difference-std::clamp(difference,-grade_limit,grade_limit);residual=std::max(residual,std::abs(error));
    double norm=(!first.fixed)+(!last.fixed);if(norm>0){if(!first.fixed)first.height+=error/norm;if(!last.fixed)last.height-=error/norm;clamp_station(first);clamp_station(last);}
   }
   for(size_t station=1;station+1<edge.nodes.size();++station){
    auto &first=nodes[edge.nodes[station-1]];auto &middle=nodes[edge.nodes[station]];auto &last=nodes[edge.nodes[station+1]];
    double curvature=first.height-2*middle.height+last.height,limit=.03*edge.step*edge.step,error=curvature-std::clamp(curvature,-limit,limit);
    residual=std::max(residual,std::abs(error));double norm=(!first.fixed)+4*(!middle.fixed)+(!last.fixed);
    if(norm>0){if(!first.fixed)first.height-=error/norm;if(!middle.fixed)middle.height+=2*error/norm;if(!last.fixed)last.height-=error/norm;clamp_station(first);clamp_station(middle);clamp_station(last);}
   }
   for(size_t station=1;station<edge.nodes.size();++station){
    auto &first=nodes[edge.nodes[station-1]];auto &last=nodes[edge.nodes[station]];
    bool near_fixed=first.fixed||station==1,far_fixed=last.fixed||station+1==edge.nodes.size();
    double &near=edge.tangents[station-1],&far=edge.tangents[station];
    for(bool end:{false,true}){
     double first_weight=end?6:-6,last_weight=-first_weight,near_weight=end?2:-4,far_weight=end?4:-2;
     double curvature=first_weight*first.height+last_weight*last.height+near_weight*near+far_weight*far,limit=.04*edge.step*edge.step;
     double error=curvature-std::clamp(curvature,-limit,limit);residual=std::max(residual,std::abs(error));
     double norm=36*(!first.fixed)+36*(!last.fixed)+near_weight*near_weight*(!near_fixed)+far_weight*far_weight*(!far_fixed);
     if(norm>0){if(!first.fixed)first.height-=error*first_weight/norm;if(!last.fixed)last.height-=error*last_weight/norm;if(!near_fixed)near-=error*near_weight/norm;if(!far_fixed)far-=error*far_weight/norm;clamp_station(first);clamp_station(last);}
    }
   }
  }
  return residual;
 };
 std::vector<double> node_gradient(nodes.size()),node_weight(nodes.size());
 for(int iteration=0;iteration<160;++iteration){
  if(footprint_policy){
   std::fill(node_gradient.begin(),node_gradient.end(),0);std::fill(node_weight.begin(),node_weight.end(),0);
   for(auto &edge:edges){
    std::fill(edge.gradient.begin(),edge.gradient.end(),0);std::fill(edge.weight.begin(),edge.weight.end(),0);
    for(const auto &footprint:edge.footprints){
     double minimum=1e30,maximum=-1e30;const FootPoint *lower=nullptr,*upper=nullptr;
     for(const auto &point:footprint.points){double height=evaluate_foot(point,edge,nodes);if(height<minimum){minimum=height;lower=&point;}if(height>maximum){maximum=height;upper=&point;}}
     auto penalty=generation_contact::penalty(minimum,maximum,-.02,.18);
     auto accumulate=[&](const FootPoint &point,double gradient){
      for(int endpoint=0;endpoint<2;++endpoint){int station=point.section+endpoint,node=edge.nodes[station];double height_weight=point.weights[endpoint*2],tangent_weight=point.weights[endpoint*2+1];node_gradient[node]+=gradient*height_weight;node_weight[node]+=std::abs(height_weight);edge.gradient[station]+=gradient*tangent_weight;edge.weight[station]+=std::abs(tangent_weight);}
     };
     accumulate(*lower,penalty.lower_gradient);accumulate(*upper,penalty.upper_gradient);
    }
   }
   for(size_t node=0;node<nodes.size();++node)if(!nodes[node].fixed&&node_weight[node]>0)nodes[node].height-=.6*node_gradient[node]/node_weight[node];
   for(auto &edge:edges)for(size_t station=1;station+1<edge.nodes.size();++station)if(!nodes[edge.nodes[station]].fixed&&edge.weight[station]>0)edge.tangents[station]-=.6*edge.gradient[station]/edge.weight[station];
  }
  for(auto &node:nodes)if(!node.fixed)node.height+=(std::clamp(node.target,node.low,node.high)-node.height)*(footprint_policy?.12:.18);
  for(int pass=0;pass<12;++pass)project();
 }
 for(int pass=0;pass<2048;++pass)if(project()<1e-7)break;
 Array output;int changed=0,good_before=0,good_after=0,contact_count=0,footprints_before=0,footprints_after=0;double max_shift=0,max_grade=0,max_curvature=0,max_cut=0,max_fill=0,cost_before=0,cost_after=0;
 Array unresolved;
 for(size_t index=0;index<edges.size();++index){
  auto &edge=edges[index];int divisions=int(edge.nodes.size())-1;
  for(const auto &footprint:edge.footprints){
   double minimum=1e30,maximum=-1e30,original_min=1e30,original_max=-1e30;
   for(const auto &point:footprint.points){double height=evaluate_foot(point,edge,nodes);minimum=std::min(minimum,height);maximum=std::max(maximum,height);original_min=std::min(original_min,point.original);original_max=std::max(original_max,point.original);}
   footprints_before+=contact(original_min,original_max);footprints_after+=contact(minimum,maximum);cost_before+=generation_contact::penalty(original_min,original_max).cost;cost_after+=generation_contact::penalty(minimum,maximum).cost;
  }
  PackedFloat64Array coefficients;bool modified=false;
  for(int station=0;station<divisions;++station){
   double first=nodes[edge.nodes[station]].height,last=nodes[edge.nodes[station+1]].height,delta=last-first,near=edge.tangents[station],far=edge.tangents[station+1];
   Curve curve{-2*delta+near+far,3*delta-2*near-far,near,first};edge.curves.push_back(curve);for(double coefficient:curve)coefficients.push_back(coefficient);
   max_grade=std::max(max_grade,maximum_grade(curve,edge.step));
   max_curvature=std::max(max_curvature,std::max(std::abs(2*curve[1]),std::abs(6*curve[0]+2*curve[1]))/(edge.step*edge.step));
   if(max_grade>.201)return rejected("Connected road cubic exceeds grade limit",int(index));
   if(max_curvature>.04001)return rejected("Connected road cubic exceeds curvature limit",int(index));
  }
  Vector3 across(-(edge.finish-edge.start).z,0,(edge.finish-edge.start).x);across.normalize();double extent=edge.extent;
  int longitudinal=int(std::ceil(edge.length/.5)),lateral=int(std::ceil(2*extent/.5));
  for(int step=0;step<=longitudinal;++step){
   double fraction=double(step)/longitudinal,position=fraction*divisions;int section=std::min(divisions-1,int(position));double local=position-section;
   double original=value(edge.original,fraction),height=value(edge.curves[section],local),shift=std::abs(height-original),grade=std::abs(derivative(edge.curves[section],local)/edge.step);
   max_shift=std::max(max_shift,shift);max_grade=std::max(max_grade,grade);modified|=shift>.001;
   if(shift>.555||grade>.201)return rejected("Connected road solution exceeds smoothness/displacement limits",int(index));
   if(shift>.001)for(int side=0;side<=lateral;++side){
    Vector3 point=edge.start.lerp(edge.finish,fraction)+across*(-extent+2*extent*side/lateral);double terrain=world.height(point.x,point.z,false);++samples;
    if(footprint_policy)for(const auto &area:reserved)if(area.has_point(Vector2(point.x,point.z)))return rejected("Generated grade affects a protected entrance",int(index));
    double cut=terrain-height,fill=height-terrain;max_cut=std::max(max_cut,cut);max_fill=std::max(max_fill,fill);
    if(cut>3.001||fill>2.001){Dictionary failure=rejected("Connected road needs denser terrain fitting before bake",int(index));failure["position"]=point;failure["cut"]=cut;failure["fill"]=fill;return failure;}
   }
   if(step%2==0){
    double half=.5*(std::abs(across.x)+std::abs(across.z)),old_grade=std::abs(derivative(edge.original,fraction)/edge.length);
    bool before=contact(original-old_grade*half,original+old_grade*half),after=contact(height-grade*half,height+grade*half);
    good_before+=before;good_after+=after;++contact_count;
    if(!after&&unresolved.size()<128){Dictionary gap;gap["position"]=edge.start.lerp(edge.finish,fraction);gap["height"]=height;gap["road"]=int(index);unresolved.push_back(gap);}
   }
  }
  if(!modified){output.push_back(edge.record);if(output.size()>4096)return rejected("Connected road output budget exceeded");continue;}
  ++changed;
  for(int section=0;section<divisions;++section){
   Dictionary part=edge.record.duplicate();Vector3 start=edge.start.lerp(edge.finish,double(section)/divisions),finish=edge.start.lerp(edge.finish,double(section+1)/divisions);
   start.y=value(edge.curves[section],0);finish.y=value(edge.curves[section],1);part["start"]=start;part["finish"]=finish;part["coefficients"]=coefficients;part["curve_index"]=section;
   AABB bounds=edge.record["bounds"];part["bounds"]=bounds.grow(.56);part["grid_fit"]=2;output.push_back(part);
  }
  if(output.size()>4096)return rejected("Connected road output budget exceeded");
 }
 if(good_after<good_before)return rejected("Connected grade solution worsens network block contact");
 if(footprint_policy&&(footprints_after<footprints_before||cost_after>cost_before+1e-6))return rejected("Generation policy worsens footprint contact");
 Dictionary result;result["ok"]=true;result["version"]=2;result["segments"]=output;result["changed"]=changed;result["stations"]=int(nodes.size());result["fixed_stations"]=fixed_count;
 if(footprint_policy){result["version"]=3;result["footprints"]=footprint_count;result["footprints_before"]=footprints_before;result["footprints_after"]=footprints_after;result["contact_cost_before"]=cost_before;result["contact_cost_after"]=cost_after;result["observation_bytes"]=int64_t(footprint_count*sizeof(Footprint));}
 result["protected_crossings"]=protected_crossings;result["samples"]=samples;result["max_shift"]=max_shift;result["max_grade"]=max_grade;result["max_curvature"]=max_curvature;result["max_cut"]=max_cut;result["max_fill"]=max_fill;result["contact_samples"]=contact_count;result["contact_before"]=good_before;result["contact_after"]=good_after;result["unresolved"]=unresolved;result["quality_complete"]=good_after==contact_count&&(!footprint_policy||footprints_after==footprint_count);return result;
}
}
