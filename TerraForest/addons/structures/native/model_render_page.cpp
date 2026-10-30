// SPDX-License-Identifier: 0BSD
#include "model_render_page.hpp"
#include "static_batch.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <atomic>
#include <algorithm>

namespace terraforest {
static std::atomic<int64_t> model_render_pages{0};
ModelRenderPageData::ModelRenderPageData(){++model_render_pages;}
ModelRenderPageData::~ModelRenderPageData(){--model_render_pages;}
int64_t ModelRenderPageData::live_pages(){return model_render_pages.load();}
bool ModelRenderPageData::load_packet(const PackedByteArray &bytes,const PackedByteArray &checksum,const String &expected_asset,Vector3i expected_region) {
    if(valid_||checksum.size()!=32||bytes.size()<105||bytes.size()>5600232||bytes.slice(bytes.size()-32)!=checksum)return false;
    String asset;BlockKey region;std::map<int64_t,NativeStaticBatch::Placement> values;
    std::vector<Record> staged;
    if(!NativeStaticBatch::parse_region(bytes,asset,region,values,&staged)||asset!=expected_asset||
       region.x!=expected_region.x||region.y!=expected_region.y||region.z!=expected_region.z)return false;
    records_=std::move(staged);region_=expected_region;valid_=true;return true;
}
bool ModelRenderPageData::valid_range(int64_t first,int64_t limit)const {
    return valid_&&first>=0&&uint64_t(first)<=records_.size()&&limit>=1&&limit<=1024;
}
PackedFloat32Array ModelRenderPageData::buffer(int64_t first,int64_t count)const {
    PackedFloat32Array out;out.resize(count*12);float *target=out.ptrw();const Vector3 offset=origin();
    for(int64_t index=0;index<count;++index) {
        const auto &pose=records_[size_t(first+index)].transform;
        std::copy(pose.begin(),pose.end(),target+index*12);
        target[index*12+3]-=offset.x;target[index*12+7]-=offset.y;target[index*12+11]-=offset.z;
    }
    return out;
}
Dictionary ModelRenderPageData::stats()const {
    Dictionary out;out["valid"]=valid_;out["instances"]=int64_t(records_.size());out["region"]=region_;out["origin"]=origin();
    out["record_bytes"]=int64_t(records_.size()*sizeof(Record));out["allocated_record_bytes"]=int64_t(records_.capacity()*sizeof(Record));
    out["payload_bytes"]=int64_t(sizeof(*this)+records_.capacity()*sizeof(Record));out["page_capacity"]=1024;return out;
}
Dictionary ModelRenderPageData::page(int64_t first,int64_t limit)const {
    Dictionary out;if(!valid_range(first,limit))return out;
    const int64_t count=std::min<int64_t>(limit,records_.size()-size_t(first));
    PackedInt64Array ids;ids.resize(count);for(int64_t index=0;index<count;++index)ids.set(index,records_[size_t(first+index)].id);
    out["ids"]=ids;out["transforms"]=buffer(first,count);out["origin"]=origin();out["next"]=first+count;
    out["complete"]=size_t(first+count)==records_.size();return out;
}
Ref<MultiMesh> ModelRenderPageData::create_multimesh(const Ref<Mesh> &mesh,int64_t first,int64_t limit)const {
    if(mesh.is_null()||!valid_range(first,limit)||size_t(first)==records_.size())return {};
    const int64_t count=std::min<int64_t>(limit,records_.size()-size_t(first));
    const AABB prototype=mesh->get_aabb();
    if(!prototype.position.is_finite()||!prototype.get_end().is_finite()||prototype.size.x<0||prototype.size.y<0||prototype.size.z<0)return {};
    const auto transforms=buffer(first,count);AABB bounds;
    for(int64_t index=0;index<count;++index) {
        NativeStaticBatch::Placement pose;std::copy_n(transforms.ptr()+index*12,12,pose.begin());
        const AABB next=NativeStaticBatch::placement_transform(pose).xform(prototype);
        if(!next.position.is_finite()||!next.get_end().is_finite())return {};
        bounds=index?bounds.merge(next):next;
    }
    Ref<MultiMesh> result;result.instantiate();result->set_transform_format(MultiMesh::TRANSFORM_3D);
    result->set_mesh(mesh);result->set_instance_count(int(count));result->set_buffer(transforms);result->set_custom_aabb(bounds);
    return result;
}
void NativeModelRenderPage::_bind_methods() {
    ClassDB::bind_static_method("NativeModelRenderPage",D_METHOD("live_pages"),&NativeModelRenderPage::live_pages);
    ClassDB::bind_method(D_METHOD("load_packet","bytes","checksum","asset","region"),&NativeModelRenderPage::load_packet);
    ClassDB::bind_method(D_METHOD("stats"),&NativeModelRenderPage::stats);
    ClassDB::bind_method(D_METHOD("page","first","limit"),&NativeModelRenderPage::page,DEFVAL(1024));
    ClassDB::bind_method(D_METHOD("create_multimesh","mesh","first","limit"),&NativeModelRenderPage::create_multimesh,DEFVAL(1024));
}
bool NativeModelRenderPage::load_packet(const PackedByteArray &bytes,const PackedByteArray &checksum,const String &asset,Vector3i region) {
    if(data_)return false;
    auto staged=std::make_shared<ModelRenderPageData>();if(!staged->load_packet(bytes,checksum,asset,region))return false;
    data_=std::move(staged);return true;
}
}
