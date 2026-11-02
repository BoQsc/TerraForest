// SPDX-License-Identifier: 0BSD
#pragma once
#include "geology.hpp"
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/rect2.hpp>
#include <godot_cpp/variant/vector3i.hpp>
#include <godot_cpp/variant/aabb.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <map>
#include <algorithm>
#include <cmath>
#include <chrono>
#include <vector>

namespace terraforest {
inline godot::Dictionary plan_exploration_sites(const World &world,const godot::Array &layouts,const godot::Array &reservations,const godot::Array &earthworks,const godot::PackedVector3Array &road_stops={}){
 using namespace godot;
 Dictionary result;result["ok"]=false;
 if(world.generator_id<17||world.generator_id>MAX_GENERATOR_ID||layouts.is_empty()||layouts.size()>8||reservations.size()>2048||earthworks.size()>16384)return result;
 if(road_stops.size()>32768)return result;
 std::map<std::pair<int,int>,std::vector<Vector3>> stop_bins;
 for(int index=0;index<road_stops.size();++index){
  const Vector3 point=road_stops[index];if(!point.is_finite()||point.x<0||point.x>2000||point.z<0||point.z>2000||point.y< -256||point.y>512)return result;
  stop_bins[{int(std::floor(point.x/64)),int(std::floor(point.z/64))}].push_back(point);
 }
 struct Passage {Vector3 start,finish;double width,height;};
 struct Entrance {double across,front,back,width,height;};
 struct Layout {String id;std::vector<Passage> passages;std::vector<Entrance> entrances;Vector3 lower,upper;};
 std::vector<Layout> compiled;std::vector<Rect2> excluded;
 for(int basin=0;basin<world.basin_count;++basin){
  const auto &lake=world.basins[basin];Vector2 radius;
  if(lake.half_length>0)radius=Vector2(lake.along_x?lake.half_length:lake.half_width,lake.along_x?lake.half_width:lake.half_length)*1.25+Vector2(24,24);
  else radius=Vector2(basin==0?190:125,basin==0?190:125);
  excluded.push_back(Rect2(Vector2(lake.x,lake.z)-radius,radius*2));
 }
 for(int index=0;index<layouts.size();++index){
  if(layouts[index].get_type()!=Variant::DICTIONARY)return result;
  Dictionary entry=layouts[index];
  if(!entry.has_all(Array::make("id","tunnels"))||entry["id"].get_type()!=Variant::STRING||entry["tunnels"].get_type()!=Variant::ARRAY)return result;
  Layout layout;layout.id=entry["id"];Array tunnels=entry["tunnels"];
  if(layout.id.is_empty()||layout.id.length()>48||!layout.id.is_valid_identifier()||tunnels.size()<2||tunnels.size()>16)return result;
  for(const auto &other:compiled)if(other.id==layout.id)return result;
  if(entry.has("entrance_cuts")){
   if(entry["entrance_cuts"].get_type()!=Variant::ARRAY)return result;
   Array entrances=entry["entrance_cuts"];if(entrances.size()>4)return result;
   for(int cut=0;cut<entrances.size();++cut){
    if(entrances[cut].get_type()!=Variant::ARRAY)return result;
    Array dimensions=entrances[cut];if(dimensions.size()!=5)return result;
    for(int dimension=0;dimension<5;++dimension)if((dimensions[dimension].get_type()!=Variant::FLOAT&&dimensions[dimension].get_type()!=Variant::INT)||!std::isfinite(double(dimensions[dimension])))return result;
    Entrance entrance{dimensions[0],dimensions[1],dimensions[2],dimensions[3],dimensions[4]};
    if(std::abs(entrance.across)>4||entrance.front< -4||entrance.front>0||entrance.back<1||entrance.back>7||entrance.width<1||entrance.width>4||entrance.height<8||entrance.height>12)return result;
    layout.entrances.push_back(entrance);
   }
  }
  for(int part=0;part<tunnels.size();++part){
   if(tunnels[part].get_type()!=Variant::DICTIONARY)return result;
   Dictionary tunnel=tunnels[part];
   if(!tunnel.has_all(Array::make("start","finish","half_width","clearance"))||tunnel["start"].get_type()!=Variant::VECTOR3||tunnel["finish"].get_type()!=Variant::VECTOR3)return result;
   for(const char *field:{"half_width","clearance"})if(tunnel[field].get_type()!=Variant::FLOAT&&tunnel[field].get_type()!=Variant::INT)return result;
   Passage passage{tunnel["start"],tunnel["finish"],tunnel["half_width"],tunnel["clearance"]};
   if(!passage.start.is_finite()||!passage.finish.is_finite())return result;
   for(Vector3 point:{passage.start,passage.finish})if(point.y!=0||std::abs(point.x)>64||std::abs(point.z)>64)return result;
   double span=passage.start.distance_to(passage.finish);
   if(!std::isfinite(passage.width)||!std::isfinite(passage.height)||passage.width<1.5||passage.width>8||passage.height<passage.width||passage.height>std::min(12.,passage.width*1.75)||span<1||span>64)return result;
   layout.passages.push_back(passage);
   for(Vector3 point:{passage.start,passage.finish}){layout.lower=layout.lower.min(point-Vector3(passage.width,0,passage.width));layout.upper=layout.upper.max(point+Vector3(passage.width,passage.height,passage.width));}
  }
  compiled.push_back(layout);
 }
 for(int index=0;index<reservations.size();++index){
  if(reservations[index].get_type()!=Variant::RECT2)return result;
  Rect2 area=reservations[index];if(!area.position.is_finite()||!area.size.is_finite()||area.size.x<0||area.size.y<0)return result;
  excluded.push_back(area.grow(4));
 }
 for(int index=0;index<earthworks.size();++index){
  if(earthworks[index].get_type()!=Variant::DICTIONARY)return result;
  Dictionary entry=earthworks[index];
  if(!entry.has_all(Array::make("start","finish","half_width","shoulder"))||entry["start"].get_type()!=Variant::VECTOR3||entry["finish"].get_type()!=Variant::VECTOR3)return result;
  for(const char *field:{"half_width","shoulder"})if(entry[field].get_type()!=Variant::FLOAT&&entry[field].get_type()!=Variant::INT)return result;
  Vector3 start=entry["start"],finish=entry["finish"];double width=entry["half_width"],shoulder=entry["shoulder"];
  if(!start.is_finite()||!finish.is_finite()||!std::isfinite(width)||!std::isfinite(shoulder)||width<0||width>256||shoulder<0||shoulder>256)return result;
  Vector3 lower=start.min(finish),upper=start.max(finish);
  excluded.push_back(Rect2(Vector2(lower.x,lower.z),Vector2(upper.x-lower.x,upper.z-lower.z)).grow(width+shoulder+6));
 }
 auto rotate=[](Vector3 point,int rotation){for(int quarter=0;quarter<rotation;++quarter)point=Vector3(1-point.z,point.y,point.x);return point;};
 auto began=std::chrono::steady_clock::now();Array sites,skipped;int samples=0,candidates=0,roof_rejections=0,approach_rejections=0,occupied_rejections=0;
 auto height=[&](Vector3 point){++samples;return double(world.height(point.x,point.z));};
 for(int layout_index=0;layout_index<int(compiled.size());++layout_index){
  const auto &layout=compiled[layout_index];bool accepted=false;
  auto roof_at=[&](Vector3 local){
   double roof=-1;
   for(const auto &passage:layout.passages){
    Vector3 axis=passage.finish-passage.start;double along=std::clamp(double((local-passage.start).dot(axis)/axis.length_squared()),0.,1.);
    double square=local.distance_squared_to(passage.start+axis*along),radius_square=passage.width*passage.width;
    if(square<=radius_square)roof=std::max(roof,passage.height-passage.width+std::sqrt(radius_square-square));
   }
   return roof;
  };
  for(int attempt=0;attempt<4096&&!accepted;++attempt){
   u32 choice=hash32(u32(world.seed)^u32(attempt)*0x9e3779b9u^u32(layout_index+1)*0x68bc21ebu);
   Vector3 origin(320+int(choice&65535)%1360,0,320+int(choice>>16)%1360);
   if(layout.id=="coal_mine"&&!road_stops.is_empty()){
    const Vector3 stop=road_stops[choice%road_stops.size()];const u32 scatter=hash32(choice^0xe527a31du);
    origin=Vector3(std::round(stop.x)+int(scatter&65535)%113-56,0,std::round(stop.z)+int(scatter>>16)%113-56);
    if(origin.x<128||origin.x>1872||origin.z<128||origin.z>1872)continue;
   }
   origin.y=std::floor(height(origin+Vector3(.5,0,.5)))-1;
   if(origin.y<12||origin.y>225)continue;
   bool wet=false;
   for(int basin=0;basin<world.basin_count;++basin){auto lake=world.basins[basin];if(std::hypot(origin.x-lake.x,origin.z-lake.z)<(basin==0?190:125)){wet=true;break;}}
   if(wet)continue;
   for(int turn=0;turn<4&&!accepted;++turn){
    ++candidates;int rotation=(turn+int(choice&3))%4;
    Vector3 probe=origin+rotate(Vector3(.5,0,16.5),rotation);
    if(height(probe)<origin.y+7)continue;
    Vector3 lower=origin,upper=origin;
    for(const auto &passage:layout.passages)for(Vector3 point:{passage.start,passage.finish}){Vector3 actual=origin+rotate(point,rotation);lower=lower.min(actual-Vector3(passage.width,1,passage.width));upper=upper.max(actual+Vector3(passage.width,passage.height,passage.width));}
    for(const auto &entrance:layout.entrances)for(double across:{entrance.across-entrance.width,entrance.across+entrance.width})for(double north:{entrance.front,entrance.back}){
     Vector3 actual=origin+rotate(Vector3(across,0,north),rotation);lower=lower.min(actual-Vector3(0,1,0));upper=upper.max(actual+Vector3(0,entrance.height,0));
    }
    Vector3 approach=origin+rotate(Vector3(.5,0,-7.5),rotation),mouth=origin+rotate(Vector3(.5,0,.5),rotation);
    Rect2 footprint(Vector2(lower.x,lower.z),Vector2(upper.x-lower.x,upper.z-lower.z));
    footprint=footprint.merge(Rect2(Vector2(approach.x-3,approach.z-3),Vector2(6,6)));bool blocked=false;
    for(const auto &area:excluded)if(area.intersects(footprint.grow(4))){blocked=true;break;}
    if(blocked){++occupied_rejections;continue;}
    approach.y=height(approach);
    if(std::abs(approach.y-mouth.y)>2){++approach_rejections;continue;}
    Dictionary road_access;
    if(layout.id=="coal_mine"&&!road_stops.is_empty()){
     std::vector<std::pair<double,Vector3>> nearby;
     const int cell_x=int(std::floor(approach.x/64)),cell_z=int(std::floor(approach.z/64));
     for(int offset_z=-2;offset_z<=2;++offset_z)for(int offset_x=-2;offset_x<=2;++offset_x){
      auto found=stop_bins.find({cell_x+offset_x,cell_z+offset_z});if(found==stop_bins.end())continue;
      for(Vector3 stop:found->second){double distance=stop.distance_squared_to(approach);if(distance>=100&&distance<=64*64)nearby.push_back({distance,stop});}
     }
     std::stable_sort(nearby.begin(),nearby.end(),[](const auto &left,const auto &right){return left.first<right.first;});
     for(int candidate=0;candidate<std::min(8,int(nearby.size()))&&road_access.is_empty();++candidate){
      const Vector3 stop=nearby[candidate].second;Vector3 direction=approach-stop;direction.y=0;
      const double span=direction.length();if(span<1||std::abs(approach.y-stop.y)>span*.25)continue;
      const Vector3 side=Vector3(0,1,0).cross(direction/span);bool clear=true;
      for(int step=0;step<=int(std::ceil(span*2))&&clear;++step)for(int lateral=-4;lateral<=4;++lateral){
       const Vector3 point=stop.lerp(approach,std::min(1.,step*.5/span))+side*(lateral*.5);
       const double fill=point.y-height(point);if(fill>2||fill< -3){clear=false;break;}
       for(int reservation=0;reservation<reservations.size();++reservation)if(Rect2(reservations[reservation]).grow(1).has_point(Vector2(point.x,point.z))){clear=false;break;}
       if(!clear)break;
      }
      if(!clear)continue;
      road_access["start"]=stop;road_access["finish"]=approach;road_access["half_width"]=2.;road_access["depth"]=2.;road_access["clearance"]=3.;road_access["shoulder"]=1.;road_access["material"]=1;road_access["level_caps"]=true;
      const Vector3 low=stop.min(approach)-Vector3(3,2,3),high=stop.max(approach)+Vector3(3,3,3);road_access["bounds"]=AABB(low,high-low);
     }
     if(road_access.is_empty()){++approach_rejections;continue;}
    }
    Vector3 across=rotate(Vector3(1.5,0,.5),rotation)-rotate(Vector3(.5,0,.5),rotation);
    for(int step=0;step<=16&&!blocked;++step)for(int side=-4;side<=4;++side){Vector3 position=approach.lerp(mouth,step/16.)+across*(side*.5);double fill=position.y-height(position);if(fill>2||fill< -3){blocked=true;break;}}
    if(blocked){++approach_rejections;continue;}
    for(const auto &entrance:layout.entrances){
     for(double north=entrance.front;north<=entrance.back+.01&&!blocked;north+=.5)for(double across=entrance.across-entrance.width;across<=entrance.across+entrance.width+.01;across+=.5){
      double ground=height(origin+rotate(Vector3(across,0,north),rotation));
      if(ground<origin.y-.25||ground>origin.y+entrance.height-1){blocked=true;break;}
     }
    }
    if(blocked){++roof_rejections;continue;}
    for(int east=-3;east<=4&&!blocked;++east){
     bool covered=false;
     for(int station=1;station<16;++station){
      Vector3 local(east,0,station*.5);double roof=roof_at(local);if(roof<0)continue;
      double cover=height(origin+rotate(local,rotation))-origin.y-roof;
      if(covered&&cover<.2){blocked=true;break;}
      if(cover>.6)covered=true;
     }
    }
    for(int north=8;north<=int(std::ceil(layout.upper.z))&&!blocked;++north)for(int east=int(std::floor(layout.lower.x));east<=int(std::ceil(layout.upper.x));++east){
     Vector3 local(east,0,north);double roof=roof_at(local);
     if(roof<0)continue;
     Vector3 position=origin+rotate(local,rotation);double ground=height(position);roof+=origin.y;
     if(ground<roof+1.5||world.base({position.x,float(origin.y-.5),position.z},float(ground))>=0||world.base({position.x,float(roof+.5),position.z},float(ground))>=0){blocked=true;break;}
    }
    if(blocked){++roof_rejections;continue;}
    Dictionary site;site["id"]=layout.id;site["origin"]=Vector3i(origin);site["rotation"]=rotation;site["bounds"]=AABB(lower,upper-lower);
    Dictionary entry;entry["start"]=approach;entry["finish"]=mouth;entry["half_width"]=2.;entry["depth"]=2.;entry["clearance"]=3.;entry["shoulder"]=1.;entry["material"]=1;entry["level_caps"]=true;
    Vector3 entry_lower=approach.min(mouth)-Vector3(3,2,3),entry_upper=approach.max(mouth)+Vector3(3,3,3);entry["bounds"]=AABB(entry_lower,entry_upper-entry_lower);site["approach"]=entry;
    if(!road_access.is_empty())site["road_access"]=road_access;
    sites.append(site);excluded.push_back(footprint.grow(64));accepted=true;
   }
  }
  if(!accepted)skipped.append(layout.id);
 }
 result["ok"]=true;result["sites"]=sites;result["skipped"]=skipped;result["candidates"]=candidates;result["height_samples"]=samples;
 result["roof_rejections"]=roof_rejections;result["approach_rejections"]=approach_rejections;result["occupied_rejections"]=occupied_rejections;
 result["worker_ms"]=std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-began).count();return result;
}
}
