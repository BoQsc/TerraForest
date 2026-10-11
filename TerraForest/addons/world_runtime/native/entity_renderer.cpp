// SPDX-License-Identifier: 0BSD
#include "entity_renderer.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <cmath>
#include <unordered_set>
using namespace godot;
namespace terraforest {
void NativeEntityRenderer::_bind_methods() {
    ClassDB::bind_method(D_METHOD("set_selection_marker", "marker", "identity"), &NativeEntityRenderer::set_selection_marker);
    ClassDB::bind_method(D_METHOD("refresh_positions"), &NativeEntityRenderer::refresh_positions);
    ClassDB::bind_method(D_METHOD("configure", "store", "mesh", "capacity", "animated"), &NativeEntityRenderer::configure, DEFVAL(false));
    ClassDB::bind_method(D_METHOD("refresh_animated_positions","delta"), &NativeEntityRenderer::refresh_animated_positions);
    ClassDB::bind_method(D_METHOD("refresh", "center", "radius", "candidate_budget"), &NativeEntityRenderer::refresh, DEFVAL(4096));
}
void NativeEntityRenderer::set_selection_marker(Node3D *marker, int64_t identity) {
    auto *old=Object::cast_to<Node3D>(ObjectDB::get_instance(marker_id_));
    if(old)old->hide();
    marker_id_=marker?uint64_t(marker->get_instance_id()):0;
    highlighted_identity_=identity;
    refresh_positions();
}
bool NativeEntityRenderer::configure(const Ref<NativeEntityStore> &store, const Ref<Mesh> &mesh, int capacity, bool animated) {
    if (store.is_null() || mesh.is_null() || capacity < 1 || capacity > 4096) return false;
    Ref<MultiMesh> next; next.instantiate();
    next->set_transform_format(MultiMesh::TRANSFORM_3D);
    next->set_use_custom_data(animated);
    next->set_mesh(mesh);
    next->set_instance_count(capacity);
    next->set_visible_instance_count(0);
    animated_=animated;gait_.clear();gait_.reserve(animated?capacity:0);animation_delta_=0;
    buffer_.resize(int64_t(capacity) * (animated?16:12));
    buffer_.fill(0);
    selected_.clear();
    store_ = store; instances_ = next; capacity_ = capacity;
    set_multimesh(instances_);
    return true;
}
Dictionary NativeEntityRenderer::refresh(const Vector3 &center, double radius, int candidate_budget) {
    Dictionary result;
    if(store_.is_valid())result=store_->query_sphere_nearest(center,radius,capacity_,candidate_budget);
    selected_=bool(result.get("ok",false))?PackedInt64Array(result["ids"]):PackedInt64Array();
    // Render residency owns gait history. Never retain visited-world actors.
    if(animated_){
        std::unordered_set<int64_t> retained;
        retained.reserve(selected_.size());
        for(int64_t i=0;i<selected_.size();++i)retained.insert(selected_[i]);
        for(auto it=gait_.begin();it!=gait_.end();)
            if(!retained.count(it->first))it=gait_.erase(it);else ++it;
    }
    return publish(result);
}
Dictionary NativeEntityRenderer::refresh_positions(){
    Dictionary result;result["ok"]=true;result["complete"]=false;
    result["positions_only"]=true;result["visited"]=0;result["ids"]=selected_;
    return publish(result);
}
Dictionary NativeEntityRenderer::refresh_animated_positions(double delta){
    if(!animated_||!std::isfinite(delta)||delta<=0||delta>0.1){Dictionary out;out["ok"]=false;return out;}
    animation_delta_=delta;auto out=refresh_positions();animation_delta_=0;return out;
}
Dictionary NativeEntityRenderer::publish(Dictionary result){
    auto *marker=Object::cast_to<Node3D>(ObjectDB::get_instance(marker_id_));
    if(marker)marker->hide();
    result["rendered"]=0;result["upload_bytes"]=0;
    if(store_.is_null()){result["ok"]=false;result["reason"]="not_configured";return result;}
    // The MultiMesh is owned by this adapter. Detect external mutation instead of
    // submitting a wrongly sized buffer or continuing to display stale entities.
    if (get_multimesh() != instances_ || instances_->get_instance_count() != capacity_ ||
        instances_->get_transform_format() != MultiMesh::TRANSFORM_3D ||
        instances_->is_using_colors() || instances_->is_using_custom_data()!=animated_) {
        instances_->set_visible_instance_count(0);
        set_multimesh(Ref<MultiMesh>());
        selected_.clear();gait_.clear();result["ok"]=false;result["reason"] = "renderer_resource_modified"; return result;
    }
    result["rendered"] = 0; result["upload_bytes"] = 0;
    if (!bool(result["ok"])) { instances_->set_visible_instance_count(0); return result; }
    const PackedInt64Array ids = result["ids"];
    for(int64_t i=0;i<ids.size();++i)if(!store_->contains(ids[i])){
        selected_.clear();gait_.clear();instances_->set_visible_instance_count(0);
        result["ok"]=false;result["reason"]="stale_selection";return result;
    }
    if (ids.is_empty()) { instances_->set_visible_instance_count(0); return result; }
    const float *current = buffer_.ptr();
    float *out = nullptr;
    for (int64_t i = 0; i < ids.size(); ++i) {
        const Vector3 p = store_->get_position(ids[i]);
        if(marker && marker->is_inside_tree() && is_inside_tree() && store_->persistent_id(ids[i])==highlighted_identity_) {
            marker->set_global_position(get_global_transform().xform(p)+Vector3(0,1.08,0));
            marker->show();
        }
        const int stride=animated_?16:12;
        float next[16]={1,0,0,p.x,0,1,0,p.y,0,0,1,p.z,0,0,0,0};
        if(animated_){
            auto inserted=gait_.try_emplace(ids[i],Gait{p});auto &g=inserted.first->second;
            if(animation_delta_>0){
                Vector3 movement=p-g.position;movement.y=0;const double distance=movement.length();
                // Teleports reset gait rather than producing an unbounded stride.
                if(distance>1){g.phase=0;g.amplitude=0;}
                else {g.amplitude=std::min(1.0,distance/(animation_delta_*2.5));
                    if(distance>0.00001){g.yaw=std::atan2(-movement.x,-movement.z);g.phase=std::fmod(g.phase+distance*4.0,6.283185307179586);}}
                g.position=p;
            }
            const float c=std::cos(g.yaw),sn=std::sin(g.yaw);
            next[0]=c;next[2]=sn;next[8]=-sn;next[10]=c;
            next[12]=g.phase;next[13]=g.amplitude;
        }
        const float *old=current+i*stride;bool changed=false;
        for(int k=0;k<stride;++k)if(old[k]!=next[k]){changed=true;break;}
        if(!changed)continue;
        if(!out){out=buffer_.ptrw();current=out;}
        for(int k=0;k<stride;++k)out[i*stride+k]=next[k];
    }
    if (out) instances_->set_buffer(buffer_);
    instances_->set_visible_instance_count(int(ids.size()));
    result["rendered"] = ids.size();
    result["gait_states"] = int64_t(gait_.size());
    result["upload_bytes"] = out ? int64_t(capacity_) * (animated_?64:48) : 0;
    return result;
}
}
