// SPDX-License-Identifier: 0BSD
#pragma once
#include "block_world.hpp"
#include "modular_shapes.hpp"
#include "map_material.hpp"
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/core/class_db.hpp>
namespace terraforest {
// At most one occupied chunk (256 column samples) per call. All samples are
// local-space points; the map consumer applies the captured world transform.
inline Dictionary block_map_columns(const std::map<BlockKey,BlockChunk>&chunks,BlockKey region,int64_t offset){
 Dictionary out;out["ok"]=false;if(offset<0||offset>=64)return out;
 PackedVector3Array points;godot::PackedColorArray colors;
 for(;offset<64;++offset){BlockKey k{region.x*4+int(offset%4),region.y*4+int((offset/4)%4),region.z*4+int(offset/16)};
  auto found=chunks.find(k);if(found==chunks.end())continue;
  const auto &chunk=found->second;
  for(int z=0;z<16;++z)for(int x=0;x<16;++x){uint16_t column=chunk.columns[x+16*z];if(!column)continue;
   int y=15;while(!(column&(1u<<y)))--y;int shape=block_shape(chunk.cells[x+16*y+256*z]);
   // Vertical projection at cell centre; stair boundaries use the higher step.
   float top=shape==2?.5f:shape==3?.75f:shape==4?.5f:1.f;
   if(shape>8){top=0;int rotation=block_rotation(chunk.cells[x+16*y+256*z]);for(const auto &vertex:modular_geometry(shape).vertices)top=std::max(top,.5f+orient_block_vector(Vector3(vertex.x-.5f,vertex.y-.5f,vertex.z-.5f),rotation).y);}
   points.push_back(Vector3(k.x*16+x+.5f,k.y*16+y+top,k.z*16+z+.5f));
   colors.push_back(block_map_material(block_material(chunk.cells[x+16*y+256*z])));
  }++offset;break;
 }
 out["ok"]=true;out["offset"]=offset;out["complete"]=offset==64;out["points"]=points;out["colors"]=colors;return out;
}
// Worker-owned decoder for one checksum-bound archived region. Does not load
// the region into gameplay, construct meshes or allocate physics objects.
class NativeBlockMapRegion : public RefCounted {
 GDCLASS(NativeBlockMapRegion,RefCounted)
 friend class BlockHorizon;
 std::map<BlockKey,BlockChunk> chunks;BlockKey region;bool valid=false;
protected:
 static void _bind_methods(){
  ClassDB::bind_method(D_METHOD("load_packet","bytes","expected_checksum"),&NativeBlockMapRegion::load_packet);
  ClassDB::bind_method(D_METHOD("columns","offset"),&NativeBlockMapRegion::columns);
 }
public:
 bool load_packet(const PackedByteArray &bytes,const PackedByteArray &expected){
  valid=false;chunks.clear();if(expected.size()!=32||bytes.size()<100||bytes.slice(bytes.size()-32)!=expected)return false;
  valid=NativeBlockWorld::parse_region(bytes,region,chunks);return valid;
 }
 Dictionary columns(int64_t offset)const{return valid?block_map_columns(chunks,region,offset):Dictionary();}
};
}
