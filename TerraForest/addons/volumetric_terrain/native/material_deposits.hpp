#pragma once
#include "geology.hpp"
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <chrono>
#include <vector>
namespace terraforest {
inline godot::Dictionary plan_material_deposits(const World &world,const godot::Array &earthworks){
 using namespace godot;
 Dictionary result;result["ok"]=false;
 if(world.generator_id<17||world.generator_id>23||earthworks.size()>4096)return result;
 struct Corridor {Vector3 start,end;float radius;};
 std::vector<Corridor> corridors;
 for(int index=0;index<earthworks.size();++index){
  if(earthworks[index].get_type()!=Variant::DICTIONARY)return result;
  Dictionary entry=earthworks[index];
  if(!entry.has_all(Array::make("start","finish","half_width","shoulder"))||entry["start"].get_type()!=Variant::VECTOR3||entry["finish"].get_type()!=Variant::VECTOR3)return result;
  for(const char *field:{"half_width","shoulder"})if(entry[field].get_type()!=Variant::FLOAT&&entry[field].get_type()!=Variant::INT)return result;
  Vector3 start=entry["start"],end=entry["finish"];
  double width=entry["half_width"],shoulder=entry["shoulder"];
  if(!start.is_finite()||!end.is_finite()||!std::isfinite(width)||!std::isfinite(shoulder)||width<0||width>256||shoulder<0||shoulder>256)return result;
  corridors.push_back({start,end,float(width+shoulder+12)});
 }
 auto began=std::chrono::steady_clock::now();Array deposits;int candidates=0;
 for(int row=0;row<10;++row)for(int column=0;column<10;++column){
  bool accepted=false;
  for(int attempt=0;attempt<16&&!accepted;++attempt){
   ++candidates;
   u32 choice=hash32(u32(world.seed)^u32(column+row*10)*0x68bc21ebu^u32(attempt)*0x9e3779b9u);
   int cell_x=fl((column*200.f+24.f+float(choice&65535)*152.f/65535.f)/32.f);
   int cell_z=fl((row*200.f+24.f+float(choice>>16)*152.f/65535.f)/32.f);
   float initial=world.height(cell_x*32.f+16,cell_z*32.f+16);
   for(int level=fl(initial/32.f);level>=0&&level>=fl(initial/32.f)-2&&!accepted;--level){
    auto vein=geological_vein(cell_x,level,cell_z,u32(world.seed));
    V3 center=(vein.start+vein.end)*.5f;
    float surface=world.height(center.x,center.z),depth=surface-center.y;
    float border=surrounding_coast(world.generator_id)?300.f:32.f;
    if(center.x<border||center.z<border||center.x>WORLD-border||center.z>WORLD-border||surface<20||surface>220||depth<10||depth>38||world.base(center,surface)>=0)continue;
    bool blocked=false;
    for(int basin=0;basin<world.basin_count;++basin){
     auto lake=world.basins[basin];float radius=basin==0?170.f:100.f;
     if(length(V3{center.x-lake.x,0,center.z-lake.z})<radius){blocked=true;break;}
    }
    if(blocked)continue;
    Vector3 position(center.x,surface,center.z);
    for(const auto &corridor:corridors){
     Vector3 axis=corridor.end-corridor.start;axis.y=0;
     Vector3 offset=position-corridor.start;offset.y=0;
     float along=std::clamp(float(offset.dot(axis)/std::max(double(axis.length_squared()),.0001)),0.f,1.f);
     if((offset-axis*along).length_squared()<corridor.radius*corridor.radius){blocked=true;break;}
    }
    if(blocked)continue;
    float low=surface,high=surface;
    for(int north=-1;north<=1;++north)for(int east=-1;east<=1;++east){
     float sample=world.height(center.x+east*1.35f,center.z+north*1.35f);
     low=mn(low,sample);high=mx(high,sample);
    }
    if(high-low>.3f||world.ore_weight(center,surface)*(vein.material==8?1.f:-1.f)<.99f)continue;
    for(float height=center.y;height<surface-.25f;height+=.5f){
     if(world.base({center.x,height,center.z},surface)>=0){blocked=true;break;}
    }
    if(blocked)continue;
    uint32_t identity=1+uint32_t(cell_x+cell_z*63+level*63*63)*2+uint32_t(vein.material-8);
    Basis basis(Vector3(0,1,0),float(choice&65535)/65535.f*6.283185307f);
    basis=basis.scaled(Vector3(3.3f,3.8f,3.5f));
    Dictionary deposit;deposit["id"]=identity;deposit["material"]=int(vein.material);
    deposit["position"]=position;
    deposit["transform"]=Transform3D(basis,Vector3(center.x,low+.46f,center.z));
    deposit["start"]=Vector3(vein.start.x,vein.start.y,vein.start.z);deposit["finish"]=Vector3(vein.end.x,vein.end.y,vein.end.z);deposit["radius"]=vein.radius;
    deposit["title"]=String(vein.material==8?"Iron vein ":"Copper vein ")+String::num_int64(identity);
    deposit["detail"]=String(vein.material==8?"Iron":"Copper")+"-bearing stone above a natural underground vein. The stone is mineable; the map records the deposit, not remaining reserves.";
    deposits.append(deposit);accepted=true;
   }
  }
 }
 result["ok"]=true;result["deposits"]=deposits;result["candidates"]=candidates;
 result["worker_ms"]=std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-began).count();return result;
}
}
