#include "core.h"
#include "road_profile.hpp"
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/rect2.hpp>
#include <godot_cpp/variant/aabb.hpp>
#include <algorithm>
#include <cmath>
#include <limits>
#include <vector>

namespace terraforest {
using namespace godot;
namespace {
double evaluate(const PackedFloat64Array &curve,int section,double fraction){int offset=section*4;return ((curve[offset]*fraction+curve[offset+1])*fraction+curve[offset+2])*fraction+curve[offset+3];}
Dictionary failure(const char *reason){Dictionary result;result["ok"]=false;result["reason"]=reason;return result;}
}
Dictionary normalize_generated_roads(const World &world,const Array &source,const Array &protected_areas){
 if(source.size()>2048||protected_areas.size()>4096)return failure("Road normalization input budget exceeded");
 std::vector<Rect2> protected_rects;
 for(int index=0;index<protected_areas.size();++index){
  if(protected_areas[index].get_type()!=Variant::RECT2)return failure("Invalid protected road area");
  Rect2 area=protected_areas[index];if(!area.position.is_finite()||!area.size.is_finite()||area.size.x<0||area.size.y<0)return failure("Invalid protected road bounds");
  protected_rects.push_back(area);
 }
 for(int first=0;first<source.size();++first){
  if(source[first].get_type()!=Variant::DICTIONARY)return failure("Invalid road crossing descriptor");
  Dictionary road=source[first];
  if(road.get("start",Variant()).get_type()!=Variant::VECTOR3||road.get("finish",Variant()).get_type()!=Variant::VECTOR3)return failure("Invalid crossing endpoints");
  Vector3 start=road["start"],finish=road["finish"];Vector2 origin(start.x,start.z),axis(finish.x-start.x,finish.z-start.z);
  if(axis.length()<2)continue;
  for(int second=0;second<first;++second){
   Dictionary other=source[second];Vector3 other_start=other["start"],other_finish=other["finish"];
   Vector2 neighbor(other_start.x,other_start.z),span(other_finish.x-other_start.x,other_finish.z-other_start.z),offset=neighbor-origin;
   if(span.length()<2)continue;
   double denominator=axis.cross(span);
   if(std::abs(denominator)<1e-5){
    if(std::abs(offset.cross(axis))<.01){
     double lower=std::max(0.,std::min(double(offset.dot(axis)/axis.length_squared()),double((offset+span).dot(axis)/axis.length_squared())));
     double upper=std::min(1.,std::max(double(offset.dot(axis)/axis.length_squared()),double((offset+span).dot(axis)/axis.length_squared())));
     if((upper-lower)*axis.length()>.05){
      Vector2 first_point=origin+axis*lower,last_point=origin+axis*upper;
      protected_rects.push_back(Rect2(first_point.min(last_point),first_point.max(last_point)-first_point.min(last_point)).grow(6.5));
      if(protected_rects.size()>8192)return failure("Road overlap protection budget exceeded");
     }
    }
    continue;
   }
   double along=offset.cross(span)/denominator,across=offset.cross(axis)/denominator;
   if(along<0||along>1||across<0||across>1||((along<1e-5||along>1-1e-5)&&(across<1e-5||across>1-1e-5)))continue;
   Vector2 intersection=origin+axis*along;protected_rects.push_back(Rect2(intersection-Vector2(6.5,6.5),Vector2(13,13)));
   if(protected_rects.size()>8192)return failure("Road crossing protection budget exceeded");
  }
 }
 Ref<NativeRoadProfile> fitter;fitter.instantiate();
 Array result;int changed=0,protected_count=0,earthwork_count=0,samples=0;double maximum_shift=0,maximum_cut=0,maximum_fill=0;
 for(int index=0;index<source.size();++index){
  if(source[index].get_type()!=Variant::DICTIONARY)return failure("Invalid road normalization descriptor");
  Dictionary road=source[index];
  for(const char *field:{"start","finish","half_width","depth","clearance","shoulder","material"})if(!road.has(field))return failure("Incomplete road normalization descriptor");
  if(road["start"].get_type()!=Variant::VECTOR3||road["finish"].get_type()!=Variant::VECTOR3)return failure("Invalid road normalization endpoints");
  for(const char *field:{"half_width","depth","clearance","shoulder","material"})if((road[field].get_type()!=Variant::INT&&road[field].get_type()!=Variant::FLOAT)||!std::isfinite(double(road[field])))return failure("Invalid road normalization limits");
  Vector3 start=road["start"],finish=road["finish"];
  double length=Vector2(finish.x-start.x,finish.z-start.z).length(),width=road["half_width"],shoulder=road["shoulder"];
  if(!start.is_finite()||!finish.is_finite()||!std::isfinite(width)||!std::isfinite(shoulder)||width<.5||width>16||shoulder<0||shoulder>16||length<1||length>128)return failure("Invalid road normalization geometry");
  double edge=std::min({double(start.x),double(start.z),double(finish.x),double(finish.z),2000.-start.x,2000.-start.z,2000.-finish.x,2000.-finish.z});
  if((int(road["material"])!=3&&int(road["material"])!=4)||width<2||length<8||(surrounding_coast(world.generator_id)&&edge<272)){result.push_back(road);continue;}
  PackedFloat64Array curve;
  if(road.has("coefficients")){
   if(road["coefficients"].get_type()!=Variant::PACKED_FLOAT64_ARRAY)return failure("Invalid road normalization curve");
   PackedFloat64Array full=road["coefficients"];int section=road.get("curve_index",0);
   if(section<0||full.size()%4||full.size()>256||section*4+4>full.size())return failure("Invalid road normalization index");
   curve=full.slice(section*4,section*4+4);
  }else for(double value:{0.,0.,double(finish.y-start.y),double(start.y)})curve.push_back(value);
  if(std::abs(evaluate(curve,0,0)-start.y)>.001||std::abs(evaluate(curve,0,1)-finish.y)>.001)return failure("Road curve does not match its endpoints");
  double extent=std::max(6.5,width+shoulder),cut=0,fill=0;bool blocked=false,exceeded=false;
  Vector3 along=(finish-start)/length;along.y=0;Vector3 across(-along.z,0,along.x);
  PackedFloat64Array fixed_ranges;
  for(const auto &area:protected_rects){
   double near=std::numeric_limits<double>::infinity(),far=-near,left=near,right=far;
   for(int corner=0;corner<4;++corner){
    Vector3 point(area.position.x+(corner&1?area.size.x:0),start.y,area.position.y+(corner&2?area.size.y:0));Vector3 offset=point-start;
    near=std::min(near,double(offset.dot(along)));far=std::max(far,double(offset.dot(along)));
    left=std::min(left,double(offset.dot(across)));right=std::max(right,double(offset.dot(across)));
   }
   if(right< -extent||left>extent||far<0||near>length)continue;
   fixed_ranges.push_back(std::clamp(near/length,0.,1.));fixed_ranges.push_back(std::clamp(far/length,0.,1.));
  }
  Dictionary fitted=fitter->normalize_grid(curve,length,fixed_ranges);
  if(!bool(fitted.get("ok",false)))return fitted;
  if(double(fitted["max_shift"])<.005){result.push_back(road);continue;}
  PackedFloat64Array revised=fitted["coefficients"];int divisions=fitted["subdivisions"];
  int longitudinal=int(std::ceil(length/.5)),lateral=int(std::ceil(2*extent/.5));
  for(int step=0;step<=longitudinal&&!blocked&&!exceeded;++step){
   double fraction=double(step)/longitudinal,position=fraction*divisions;int section=std::min(divisions-1,int(position));
   double grade=evaluate(revised,section,position-section),original=evaluate(curve,0,fraction);
   for(int side=0;side<=lateral;++side){
    Vector3 point=start.lerp(finish,fraction)+across*(-extent+2*extent*side/lateral);
    if(point.x<1||point.z<1||point.x>1999||point.z>1999){exceeded=true;break;}
    if(std::abs(grade-original)>.001)for(const auto &area:protected_rects)if(area.has_point(Vector2(point.x,point.z))){blocked=true;break;}
    if(blocked)break;
    double natural=world.height(point.x,point.z,false);++samples;
    cut=std::max(cut,natural-grade);fill=std::max(fill,grade-natural);
    if(cut>3||fill>2){exceeded=true;break;}
   }
  }
  if(blocked||exceeded){protected_count+=blocked;earthwork_count+=exceeded;result.push_back(road);continue;}
  if(result.size()+divisions+source.size()-index-1>4096)return failure("Normalized road stamp budget exceeded");
  for(int part=0;part<divisions;++part){
   Dictionary segment=road.duplicate();Vector3 first=start.lerp(finish,double(part)/divisions),last=start.lerp(finish,double(part+1)/divisions);
   first.y=evaluate(revised,part,0);last.y=evaluate(revised,part,1);
   segment["start"]=first;segment["finish"]=last;segment["coefficients"]=revised;segment["curve_index"]=part;
   double envelope=width+shoulder,rise=std::abs(first.y-last.y)*envelope/(length/divisions)+.55;
   Vector3 low=first.min(last)-Vector3(envelope,double(road["depth"])+rise,envelope),high=first.max(last)+Vector3(envelope,double(road["clearance"])+rise,envelope);
   segment["bounds"]=AABB(low,high-low);result.push_back(segment);
  }
  ++changed;maximum_shift=std::max(maximum_shift,double(fitted["max_shift"]));maximum_cut=std::max(maximum_cut,cut);maximum_fill=std::max(maximum_fill,fill);
 }
 Dictionary report;report["ok"]=true;report["segments"]=result;report["changed"]=changed;report["protected_skips"]=protected_count;report["earthwork_skips"]=earthwork_count;
 report["max_shift"]=maximum_shift;report["max_cut"]=maximum_cut;report["max_fill"]=maximum_fill;report["samples"]=samples;report["version"]=1;return report;
}
}
