// SPDX-License-Identifier: 0BSD
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/array.hpp>
#include <vector>
#include <unordered_map>
#include <unordered_set>
#include <algorithm>
#include <cmath>
namespace terraforest {
// Sparse, bounded top-down samples, reduced 2x2 into regional map coverage.
class NativeSurfaceMapRaster : public godot::RefCounted {
 GDCLASS(NativeSurfaceMapRaster,godot::RefCounted)
 int size=256;
 static constexpr size_t LIMIT=262144;
 std::vector<godot::Vector3> samples;
 std::vector<int> keys;
 std::vector<uint8_t> visible;
 std::unordered_map<int,int> lookup;
 int index(godot::Vector3 p)const{return int(p.x*(size*2)/2000)+size*2*int(p.z*(size*2)/2000);}
 static bool inside(godot::Vector3 p){return p.x>=0&&p.z>=0&&p.x<1999&&p.z<1999&&p.y>=0&&p.y<255;}
protected:
 static void _bind_methods(){
  godot::ClassDB::bind_method(godot::D_METHOD("configure","size"),&NativeSurfaceMapRaster::configure);
  godot::ClassDB::bind_method(godot::D_METHOD("project_bounds","boxes","transform","cursor"),&NativeSurfaceMapRaster::project_bounds);
  godot::ClassDB::bind_method(godot::D_METHOD("offer","points"),&NativeSurfaceMapRaster::offer);
  godot::ClassDB::bind_method(godot::D_METHOD("count"),&NativeSurfaceMapRaster::count);
  godot::ClassDB::bind_method(godot::D_METHOD("batch","offset","limit"),&NativeSurfaceMapRaster::batch,DEFVAL(16));
  godot::ClassDB::bind_method(godot::D_METHOD("accept_prefix","offset","mask"),&NativeSurfaceMapRaster::accept_prefix);
  godot::ClassDB::bind_method(godot::D_METHOD("accept","offset","mask"),&NativeSurfaceMapRaster::accept);
  godot::ClassDB::bind_method(godot::D_METHOD("pixels","color"),&NativeSurfaceMapRaster::pixels,DEFVAL(godot::Color(54/255.f,117/255.f,140/255.f)));
 }
public:
 godot::Dictionary project_bounds(const godot::Array &boxes,const godot::Transform3D &frame,godot::Vector2i cursor)const{
  godot::Dictionary out;out["ok"]=false;
  if(boxes.size()>32||!frame.is_finite()||cursor.x<0||cursor.x>boxes.size()||cursor.y<0)return out;
  for(int i=0;i<boxes.size();++i){
   if(boxes[i].get_type()!=godot::Variant::AABB)return out;
   godot::AABB b=boxes[i];if(!b.position.is_finite()||!b.size.is_finite()||b.size.x<0||b.size.y<0||b.size.z<0)return out;
  }
  godot::PackedVector3Array points;const int edge=size*2;const double step=2000.0/edge;
  for(;cursor.x<boxes.size();++cursor.x,cursor.y=0){
   godot::AABB box=frame.xform(godot::AABB(boxes[cursor.x]));
   if(!box.position.is_finite()||!box.size.is_finite())return out;
   // Regional cartography omits small props; it does not force every chair or
   // grass instance into a building-sized pixel. Larger extents remain visible.
   if(double(box.size.x)*box.size.z<4.0)continue;
   const auto end=box.position+box.size;
   if(end.x<0||end.z<0||box.position.x>=1999||box.position.z>=1999||end.y<0||end.y>=255)continue;
   int x0=std::clamp(int(std::floor(std::clamp(double(box.position.x),0.,1999.)/step)),0,edge-1);
   int z0=std::clamp(int(std::floor(std::clamp(double(box.position.z),0.,1999.)/step)),0,edge-1);
   int x1=std::clamp(int(std::ceil(std::clamp(double(end.x),0.,1999.)/step))-1,x0,edge-1);
   int z1=std::clamp(int(std::ceil(std::clamp(double(end.z),0.,1999.)/step))-1,z0,edge-1);
   int width=x1-x0+1,total=width*(z1-z0+1);
   if(cursor.y>total)return out;
   while(cursor.y<total&&points.size()<256){
    int x=x0+cursor.y%width,z=z0+cursor.y/width;
    points.push_back(godot::Vector3((x+.5)*step,end.y,(z+.5)*step));++cursor.y;
   }
   if(cursor.y<total)break;
  }
  out["ok"]=true;out["points"]=points;out["cursor"]=cursor;out["complete"]=cursor.x==boxes.size();return out;
 }
 bool configure(int edge){if(!samples.empty()||(edge!=256&&edge!=512))return false;size=edge;return true;}
 bool offer(const godot::PackedVector3Array &points){
  if(points.size()>256)return false;
  for(int i=0;i<points.size();++i)if(!points[i].is_finite())return false;
  if(samples.size()+points.size()>LIMIT){std::unordered_set<int> added;for(int i=0;i<points.size();++i)if(inside(points[i])&&!lookup.count(index(points[i])))added.insert(index(points[i]));if(samples.size()+added.size()>LIMIT)return false;}
  for(int i=0;i<points.size();++i){auto p=points[i];if(!inside(p))continue;int key=index(p);auto found=lookup.find(key);
   if(found==lookup.end()){lookup.emplace(key,int(samples.size()));keys.push_back(key);samples.push_back(p);visible.push_back(0);}
   else if(p.y>samples[found->second].y)samples[found->second]=p;
  }return true;
 }
 int64_t count()const{return samples.size();}
 godot::PackedVector3Array batch(int64_t offset,int64_t limit=16)const{
  godot::PackedVector3Array out;if(offset<0||offset>=count()||limit<1||limit>256)return out;
  for(int64_t i=offset;i<count()&&i<offset+limit;++i)out.push_back(samples[i]);return out;
 }
 bool accept_prefix(int64_t offset,const godot::PackedByteArray &mask){
  if(offset<0||mask.is_empty()||mask.size()>256||offset+mask.size()>count())return false;
  for(int i=0;i<mask.size();++i)if(mask[i]>1)return false;
  for(int i=0;i<mask.size();++i)visible[offset+i]=mask[i];return true;
 }
 bool accept(int64_t offset,const godot::PackedByteArray &mask){
  if(offset<0||offset>=count()||mask.size()!=std::min<int64_t>(16,count()-offset))return false;
  for(int i=0;i<mask.size();++i)if(mask[i]>1)return false;
  for(int i=0;i<mask.size();++i)visible[offset+i]=mask[i];return true;
 }
 godot::PackedByteArray pixels(godot::Color color)const{
  godot::PackedByteArray out;out.resize(size*size*4);out.fill(0);auto*p=out.ptrw();
  for(size_t i=0;i<samples.size();++i)if(visible[i]){int x=keys[i]%(size*2),z=keys[i]/(size*2),at=(x/2+(z/2)*size)*4;p[at+3]++;}
  for(int i=0;i<size*size;++i){int at=i*4;p[at]=uint8_t(std::clamp(color.r,0.f,1.f)*255);p[at+1]=uint8_t(std::clamp(color.g,0.f,1.f)*255);p[at+2]=uint8_t(std::clamp(color.b,0.f,1.f)*255);p[at+3]=uint8_t(p[at+3]*255/4);}
  return out;
 }
};
}
