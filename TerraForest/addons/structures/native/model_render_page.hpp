// SPDX-License-Identifier: 0BSD
#pragma once
#include "static_batch.hpp"
#include <godot_cpp/classes/multi_mesh.hpp>
#include <memory>

namespace terraforest {
class ModelRenderPageData {
public:
    using Record=ModelPlacementRecord;
private:
    std::vector<Record> records_;
    Vector3i region_;
    bool valid_=false;
public:
    ModelRenderPageData();
    ~ModelRenderPageData();
    ModelRenderPageData(const ModelRenderPageData &)=delete;
    ModelRenderPageData &operator=(const ModelRenderPageData &)=delete;
    static int64_t live_pages();
    bool load_packet(const PackedByteArray &bytes,const PackedByteArray &checksum,const String &asset,Vector3i region);
    const std::vector<Record> &records()const{return records_;}
    Vector3 origin()const{return Vector3(region_)*32;}
    Dictionary stats()const;
    Dictionary page(int64_t first,int64_t limit)const;
    Ref<MultiMesh> create_multimesh(const Ref<Mesh> &mesh,int64_t first,int64_t limit)const;
private:
    bool valid_range(int64_t first,int64_t limit)const;
    PackedFloat32Array buffer(int64_t first,int64_t count)const;
};
class NativeModelRenderPage : public RefCounted {
    GDCLASS(NativeModelRenderPage,RefCounted)
    std::shared_ptr<ModelRenderPageData> data_;
protected:
    static void _bind_methods();
public:
    void adopt(std::shared_ptr<ModelRenderPageData> data){data_=std::move(data);}
    static int64_t live_pages(){return ModelRenderPageData::live_pages();}
    bool load_packet(const PackedByteArray &bytes,const PackedByteArray &checksum,const String &asset,Vector3i region);
    Dictionary stats()const{return data_?data_->stats():Dictionary();}
    Dictionary page(int64_t first,int64_t limit)const{return data_?data_->page(first,limit):Dictionary();}
    Ref<MultiMesh> create_multimesh(const Ref<Mesh> &mesh,int64_t first,int64_t limit)const{return data_?data_->create_multimesh(mesh,first,limit):Ref<MultiMesh>();}
};
}
