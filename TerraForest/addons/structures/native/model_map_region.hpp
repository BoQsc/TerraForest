// SPDX-License-Identifier: 0BSD
#pragma once
#include "static_batch.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <memory>
namespace terraforest {
// Pure native immutable data may cross workers. Bounds remain conservative
// cartographic input, with captured mesh bounds and collection transform.
struct ModelMapRegionData {
 std::map<int64_t,NativeStaticBatch::Placement> values;
 AABB prototype;
 bool load(const PackedByteArray &bytes,const PackedByteArray &checksum,const String &expected_asset,const AABB &box){
  values.clear();
  if(checksum.size()!=32||bytes.size()<100||bytes.slice(bytes.size()-32)!=checksum||
    !box.position.is_finite()||!box.size.is_finite()||box.size.x<0||box.size.y<0||box.size.z<0)return false;
  String asset;BlockKey region;
  if(!NativeStaticBatch::parse_region(bytes,asset,region,values)||asset!=expected_asset){values.clear();return false;}
  prototype=box;return true;
 }
 Dictionary bounds(int64_t after)const{
  Dictionary out;if(after<0)return out;
  Array boxes;PackedInt64Array ids;auto it=values.upper_bound(after);
  for(int n=0;n<32&&it!=values.end();++n,++it){
   boxes.push_back(NativeStaticBatch::placement_transform(it->second).xform(prototype));ids.push_back(it->first);after=it->first;
  }
  out["ok"]=true;out["bounds"]=boxes;out["ids"]=ids;out["after_id"]=after;out["complete"]=it==values.end();return out;
 }
};
class NativeModelMapRegion : public RefCounted {
 GDCLASS(NativeModelMapRegion,RefCounted)
 std::shared_ptr<const ModelMapRegionData> data_;
protected:
 static void _bind_methods(){
  ClassDB::bind_method(D_METHOD("load_packet","bytes","checksum","asset","prototype_bounds"),&NativeModelMapRegion::load_packet);
  ClassDB::bind_method(D_METHOD("bounds","after_id"),&NativeModelMapRegion::bounds);
 }
public:
 bool load_packet(const PackedByteArray &bytes,const PackedByteArray &checksum,const String &asset,const AABB &box){
  data_.reset();auto next=std::make_shared<ModelMapRegionData>();
  if(!next->load(bytes,checksum,asset,box))return false;data_=std::move(next);return true;
 }
 void adopt(std::shared_ptr<const ModelMapRegionData> data){data_=std::move(data);}
 Dictionary bounds(int64_t after)const{return data_?data_->bounds(after):Dictionary();}
};
inline Dictionary NativeStaticBatch::survey_index()const{
 Dictionary out;out["ready"]=!admission&&source_mesh.is_valid();out["revision"]=int64_t(edit_revision);
 if(admission||source_mesh.is_null())return out;
 std::map<BlockKey,PackedByteArray> entries;
 PackedByteArray absent;absent.resize(32);absent.fill(0);
 for(const auto &entry:groups)entries[entry.first]=absent;
 for(const auto &entry:unloaded_regions)entries[entry.first]=entry.second.checksum;
 PackedInt32Array keys;PackedByteArray sums;
 for(const auto &entry:entries){keys.push_back(entry.first.x);keys.push_back(entry.first.y);keys.push_back(entry.first.z);sums.append_array(entry.second);}
 out["keys"]=keys;out["checksums"]=sums;out["asset"]=asset_id;
 out["prototype_bounds"]=source_mesh->get_aabb();
 out["transform"]=is_inside_tree()?get_global_transform():get_transform();return out;
}
inline Dictionary NativeStaticBatch::survey_bounds(Vector3i key,int64_t after,int64_t expected)const{
 Dictionary out;out["ok"]=false;out["ready"]=!admission&&source_mesh.is_valid();
 if(admission)return out;
 if(expected!=int64_t(edit_revision)){out["stale"]=true;return out;}
 BlockKey region{key.x,key.y,key.z};
 if(after<0||!valid_model_region(region)||source_mesh.is_null())return out;
 if(unloaded_regions.count(region)){out["unloaded"]=true;return out;}
 Array boxes;PackedInt64Array ids;
 auto group=groups.find(region);bool complete=true;
 if(group!=groups.end()){
  auto it=group->second.upper_bound(after);const AABB prototype=source_mesh->get_aabb();
  for(int n=0;n<32&&it!=group->second.end();++n,++it){
   boxes.push_back(placement_transform(placements.at(*it)).xform(prototype));ids.push_back(*it);after=*it;
  }complete=it==group->second.end();
 }
 out["ok"]=true;out["bounds"]=boxes;out["ids"]=ids;out["after_id"]=after;out["complete"]=complete;return out;
}
}
