#include "static_batch.hpp"
#include "block_world.hpp"
#include <godot_cpp/classes/multi_mesh.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <cmath>
#include <map>
namespace terraforest {
void NativeStaticBatch::_bind_methods() {
    ClassDB::bind_method(D_METHOD("set_instances","mesh","transforms"),&NativeStaticBatch::set_instances);
    ClassDB::bind_method(D_METHOD("stats"),&NativeStaticBatch::stats);
}
bool NativeStaticBatch::set_instances(const Ref<Mesh> &mesh,const PackedFloat32Array &transforms) {
    if(mesh.is_null()||transforms.size()%12||transforms.size()>1200000)return false;
    std::map<BlockKey,std::vector<float>> groups;
    for(int64_t i=0;i<transforms.size();i+=12) {
        for(int j=0;j<12;j++)if(!std::isfinite(transforms[i+j])||std::abs(transforms[i+j])>1048575)return false;
        // Reject singular transforms, which cannot produce valid lighting normals.
        const float *t=transforms.ptr()+i;
        double determinant=t[0]*(double(t[5])*t[10]-double(t[6])*t[9])-t[1]*(double(t[4])*t[10]-double(t[6])*t[8])+t[2]*(double(t[4])*t[9]-double(t[5])*t[8]);
        if(std::abs(determinant)<1e-9)return false;
        BlockKey k{int(std::floor(t[3]/32)),int(std::floor(t[7]/32)),int(std::floor(t[11]/32))};
        if(!groups.count(k)&&groups.size()>=4096)return false;
        auto &g=groups[k];g.insert(g.end(),t,t+12);
        size_t p=g.size()-12;g[p+3]-=k.x*32;g[p+7]-=k.y*32;g[p+11]-=k.z*32;
    }
    for(auto *batch:batches)memdelete(batch);batches.clear();
    for(auto &e:groups) {
        Ref<MultiMesh> multi;multi.instantiate();multi->set_transform_format(MultiMesh::TRANSFORM_3D);multi->set_mesh(mesh);multi->set_instance_count(e.second.size()/12);
        PackedFloat32Array buffer;buffer.resize(e.second.size());std::copy(e.second.begin(),e.second.end(),buffer.ptrw());multi->set_buffer(buffer);
        auto *instance=memnew(MultiMeshInstance3D);instance->set_multimesh(multi);instance->set_position(Vector3(e.first.x*32,e.first.y*32,e.first.z*32));
        add_child(instance);batches.push_back(instance);
    }
    count=transforms.size()/12;return true;
}
Dictionary NativeStaticBatch::stats() const {Dictionary d;d["instances"]=count;d["spatial_batches"]=int(batches.size());d["transform_bytes"]=count*48;return d;}
}
