// SPDX-License-Identifier: 0BSD
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/array.hpp>
#include <set>
#include <map>
#include <algorithm>
#include <vector>
#include <godot_cpp/variant/transform3d.hpp>
#include <cmath>
namespace terraforest {
class NativeGeneratedRegion : public godot::RefCounted {
 GDCLASS(NativeGeneratedRegion,godot::RefCounted)
 godot::PackedByteArray snapshot;
 int64_t revision=0;
 struct Road {godot::Vector3 a,b;float width;};
 std::vector<Road> corridors;
 std::map<std::pair<int,int>,std::vector<int>> bins;
 void index_roads(){
  corridors.clear();bins.clear();auto plan=decode(snapshot);godot::Array roads=plan["roads"];
  for(int i=0;i<roads.size();i++){
   godot::Dictionary item=roads[i];Road road{item["a"],item["b"],float(double(item["width"]))};
   corridors.push_back(road);float radius=road.width*.5f+4.f;
   int x0=int(std::floor((std::min(road.a.x,road.b.x)-radius)/64.f)),x1=int(std::floor((std::max(road.a.x,road.b.x)+radius)/64.f));
   int z0=int(std::floor((std::min(road.a.z,road.b.z)-radius)/64.f)),z1=int(std::floor((std::max(road.a.z,road.b.z)+radius)/64.f));
   for(int z=z0;z<=z1;z++)for(int x=x0;x<=x1;x++)bins[{x,z}].push_back(i);
  }
 }

 static bool position(godot::Vector3 p){return p.is_finite()&&p.x>=0&&p.x<=2000&&p.z>=0&&p.z<=2000&&p.y>=0&&p.y<=250;}
 static bool label(const godot::PackedByteArray &s,int limit){
  if(s.is_empty()||s.size()>limit)return false;
  for(int i=0;i<s.size();i++)if(s[i]<32||s[i]>126)return false;
  return true;
 }
 static void point(godot::PackedByteArray &out,godot::Vector3 p){
  int at=out.size();out.resize(at+12);for(int i=0;i<3;i++)out.encode_float(at+i*4,p[i]);
 }
 static godot::Vector3 read_point(const godot::PackedByteArray &in,int at){return {float(in.decode_float(at)),float(in.decode_float(at+4)),float(in.decode_float(at+8))};}
 static void word(godot::PackedByteArray &out,uint32_t v){int at=out.size();out.resize(at+4);out.encode_u32(at,v);}
 godot::Dictionary decode(const godot::PackedByteArray &in)const{
  using namespace godot;
  Dictionary result;result["ok"]=false;
  Array places,roads;
  if(in.is_empty()){result["ok"]=true;result["present"]=false;result["places"]=places;result["roads"]=roads;return result;}
  if(in.size()<24||in.size()>512*1024||in.decode_u32(0)!=0x31524754||in.decode_u32(4)!=1)return result;
  uint32_t seed=in.decode_u32(8),generator=in.decode_u32(12),np=in.decode_u32(16),nr=in.decode_u32(20);
  if(seed>2147483647u||(generator!=17&&generator!=18&&generator!=19)||np>256||nr>4096)return result;
  int at=24;std::set<uint32_t> ids;
  for(uint32_t i=0;i<np;i++){
   if(at+24>in.size())return result;
   uint32_t id=in.decode_u32(at),nt=in.decode_u32(at+16),nd=in.decode_u32(at+20);
   Vector3 p=read_point(in,at+4);at+=24;
   if(!ids.insert(id).second||!position(p)||nt>96||nd>192||uint64_t(at)+nt+nd>uint64_t(in.size()))return result;
   auto title=in.slice(at,at+nt);at+=nt;auto detail=in.slice(at,at+nd);at+=nd;
   if(!label(title,96)||!label(detail,192))return result;
   Dictionary item;item["id"]=id;item["title"]=title.get_string_from_utf8();item["detail"]=detail.get_string_from_utf8();item["position"]=p;places.append(item);
  }
  if(int64_t(at)+int64_t(nr)*28!=in.size())return result;
  for(uint32_t i=0;i<nr;i++,at+=28){
   Vector3 a=read_point(in,at),b=read_point(in,at+12);float width=in.decode_float(at+24);
   if(!position(a)||!position(b)||a.distance_to(b)<0.05||!std::isfinite(width)||width<1||width>64)return result;
   Dictionary item;item["a"]=a;item["b"]=b;item["width"]=width;roads.append(item);
  }
  result["ok"]=true;result["present"]=true;result["seed"]=seed;result["generator"]=generator;result["places"]=places;result["roads"]=roads;return result;
 }
protected:
 static void _bind_methods(){
  using namespace godot;
  ClassDB::bind_method(D_METHOD("placement_mask","poses","margin"),&NativeGeneratedRegion::placement_mask);
  ClassDB::bind_method(D_METHOD("set_plan","seed","generator","places","roads"),&NativeGeneratedRegion::set_plan);
  ClassDB::bind_method(D_METHOD("get_plan"),&NativeGeneratedRegion::get_plan);
  ClassDB::bind_method(D_METHOD("get_revision"),&NativeGeneratedRegion::get_revision);
  ClassDB::bind_method(D_METHOD("capture_snapshot"),&NativeGeneratedRegion::capture_snapshot);
  ClassDB::bind_method(D_METHOD("restore_snapshot","data"),&NativeGeneratedRegion::restore_snapshot);
  ClassDB::bind_method(D_METHOD("validate_snapshot","data"),&NativeGeneratedRegion::validate_snapshot);
 }
public:
 bool set_plan(int64_t seed,int generator,const godot::Array &places,const godot::Array &roads){
  using namespace godot;
  if(seed<0||seed>2147483647||(generator!=17&&generator!=18&&generator!=19)||places.size()>256||roads.size()>4096)return false;
  PackedByteArray out;word(out,0x31524754);word(out,1);word(out,seed);word(out,generator);word(out,places.size());word(out,roads.size());
  for(int i=0;i<places.size();i++){
   if(places[i].get_type()!=Variant::DICTIONARY)return false;
   Dictionary p=places[i];
   if(!p.has("id")||!p.has("title")||!p.has("detail")||!p.has("position")||p["id"].get_type()!=Variant::INT||p["position"].get_type()!=Variant::VECTOR3||p["title"].get_type()!=Variant::STRING||p["detail"].get_type()!=Variant::STRING)return false;
   int64_t id=p["id"];if(id<0||id>4294967295LL)return false;
   auto title=String(p["title"]).to_utf8_buffer(),detail=String(p["detail"]).to_utf8_buffer();
   if(!label(title,96)||!label(detail,192)||!position(p["position"]))return false;
   word(out,id);point(out,p["position"]);word(out,title.size());word(out,detail.size());out.append_array(title);out.append_array(detail);
  }
  for(int i=0;i<roads.size();i++){
   if(roads[i].get_type()!=Variant::DICTIONARY)return false;
   Dictionary r=roads[i];
   if(!r.has("a")||!r.has("b")||!r.has("width")||r["a"].get_type()!=Variant::VECTOR3||r["b"].get_type()!=Variant::VECTOR3||(r["width"].get_type()!=Variant::FLOAT&&r["width"].get_type()!=Variant::INT))return false;
   point(out,r["a"]);point(out,r["b"]);int at=out.size();out.resize(at+4);out.encode_float(at,double(r["width"]));
  }
  return restore_snapshot(out);
 }
 godot::PackedByteArray placement_mask(const godot::Array &poses,double margin)const{
  godot::PackedByteArray result;
  if(poses.size()>65536||!std::isfinite(margin)||margin<0||margin>4)return result;
  result.resize(poses.size());result.fill(0);
  for(int i=0;i<poses.size();i++){
   if(poses[i].get_type()!=godot::Variant::TRANSFORM3D)return {};
   godot::Vector3 p=godot::Transform3D(poses[i]).origin;
   if(!p.is_finite())return {};
   auto found=bins.find({int(std::floor(p.x/64.f)),int(std::floor(p.z/64.f))});if(found==bins.end())continue;
   for(int id:found->second){
    const Road &r=corridors[id];auto span=r.b-r.a;float length=span.x*span.x+span.z*span.z;
    if(length<.0001f)continue;
    float t=std::clamp(((p.x-r.a.x)*span.x+(p.z-r.a.z)*span.z)/length,0.f,1.f);
    auto near=r.a+span*t;float dx=p.x-near.x,dz=p.z-near.z,radius=r.width*.5f+float(margin);
    if(dx*dx+dz*dz<=radius*radius&&std::abs(p.y-near.y)<4){result.set(i,1);break;}
   }
  }
  return result;
 }
 bool validate_snapshot(const godot::PackedByteArray &in)const{return bool(decode(in)["ok"]);}
 bool restore_snapshot(const godot::PackedByteArray &in){if(!validate_snapshot(in))return false;snapshot=in;index_roads();revision++;return true;}
 godot::PackedByteArray capture_snapshot()const{return snapshot;}
 godot::Dictionary get_plan()const{return decode(snapshot);}
 int64_t get_revision()const{return revision;}
};
}
