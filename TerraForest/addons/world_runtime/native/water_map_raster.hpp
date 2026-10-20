// SPDX-License-Identifier: 0BSD
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <vector>
namespace terraforest {
// Fixed 512-square sampling grid, downsampled into a 256-square overlay.
// Approximate regional coverage; not an exact rendered mesh silhouette.
class NativeWaterMapRaster : public godot::RefCounted {
 GDCLASS(NativeWaterMapRaster,godot::RefCounted)
 std::vector<godot::Vector3> samples=std::vector<godot::Vector3>(512*512);
 std::vector<uint8_t> occupied=std::vector<uint8_t>(512*512,0),visible=std::vector<uint8_t>(512*512,0);
 std::vector<int> touched;
 static int index(godot::Vector3 p){return int(p.x*512/2000)+512*int(p.z*512/2000);}
protected:
 static void _bind_methods(){
  godot::ClassDB::bind_method(godot::D_METHOD("offer","points"),&NativeWaterMapRaster::offer);
  godot::ClassDB::bind_method(godot::D_METHOD("count"),&NativeWaterMapRaster::count);
  godot::ClassDB::bind_method(godot::D_METHOD("batch","offset"),&NativeWaterMapRaster::batch);
  godot::ClassDB::bind_method(godot::D_METHOD("accept","offset","mask"),&NativeWaterMapRaster::accept);
  godot::ClassDB::bind_method(godot::D_METHOD("pixels"),&NativeWaterMapRaster::pixels);
 }
public:
 bool offer(const godot::PackedVector3Array &points){
  if(points.size()>256)return false;
  for(int i=0;i<points.size();++i){auto p=points[i];if(!p.is_finite()||p.x<0||p.z<0||p.x>=1999||p.z>=1999||p.y<0||p.y>=255)return false;}
  for(int i=0;i<points.size();++i){auto p=points[i];int at=index(p);
   if(!occupied[at]){occupied[at]=1;touched.push_back(at);samples[at]=p;}
   else if(p.y>samples[at].y)samples[at]=p;
  }return true;
 }
 int64_t count()const{return touched.size();}
 godot::PackedVector3Array batch(int64_t offset)const{
  godot::PackedVector3Array out;if(offset<0||offset>=count())return out;
  for(int64_t i=offset;i<count()&&i<offset+16;++i)out.push_back(samples[touched[i]]);return out;
 }
 bool accept(int64_t offset,const godot::PackedByteArray &mask){
  if(offset<0||offset>=count()||mask.size()!=std::min<int64_t>(16,count()-offset))return false;
  for(int i=0;i<mask.size();++i)if(mask[i]>1)return false;
  for(int i=0;i<mask.size();++i)visible[touched[offset+i]]=mask[i];return true;
 }
 godot::PackedByteArray pixels()const{
  godot::PackedByteArray out;out.resize(256*256*4);auto*p=out.ptrw();
  for(int z=0;z<256;++z)for(int x=0;x<256;++x){int a=x*2+z*2*512;
   int coverage=visible[a]+visible[a+1]+visible[a+512]+visible[a+513];int at=(x+z*256)*4;
   p[at]=54;p[at+1]=117;p[at+2]=140;p[at+3]=uint8_t(coverage*255/4);
  }return out;
 }
};
}
