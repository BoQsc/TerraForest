// SPDX-License-Identifier: 0BSD
#include "entity_renderer.hpp"
#include <godot_cpp/core/class_db.hpp>
using namespace godot;
namespace terraforest {
void NativeEntityRenderer::_bind_methods() {
    ClassDB::bind_method(D_METHOD("set_selection_marker", "marker", "identity"), &NativeEntityRenderer::set_selection_marker);
    ClassDB::bind_method(D_METHOD("refresh_positions"), &NativeEntityRenderer::refresh_positions);
    ClassDB::bind_method(D_METHOD("configure", "store", "mesh", "capacity"), &NativeEntityRenderer::configure);
    ClassDB::bind_method(D_METHOD("refresh", "center", "radius", "candidate_budget"), &NativeEntityRenderer::refresh, DEFVAL(4096));
}
void NativeEntityRenderer::set_selection_marker(Node3D *marker, int64_t identity) {
    auto *old=Object::cast_to<Node3D>(ObjectDB::get_instance(marker_id_));
    if(old)old->hide();
    marker_id_=marker?uint64_t(marker->get_instance_id()):0;
    highlighted_identity_=identity;
    refresh_positions();
}
bool NativeEntityRenderer::configure(const Ref<NativeEntityStore> &store, const Ref<Mesh> &mesh, int capacity) {
    if (store.is_null() || mesh.is_null() || capacity < 1 || capacity > 4096) return false;
    Ref<MultiMesh> next; next.instantiate();
    next->set_transform_format(MultiMesh::TRANSFORM_3D);
    next->set_mesh(mesh);
    next->set_instance_count(capacity);
    next->set_visible_instance_count(0);
    buffer_.resize(int64_t(capacity) * 12);
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
    return publish(result);
}
Dictionary NativeEntityRenderer::refresh_positions(){
    Dictionary result;result["ok"]=true;result["complete"]=false;
    result["positions_only"]=true;result["visited"]=0;result["ids"]=selected_;
    return publish(result);
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
        instances_->is_using_colors() || instances_->is_using_custom_data()) {
        instances_->set_visible_instance_count(0);
        set_multimesh(Ref<MultiMesh>());
        selected_.clear();result["ok"]=false;result["reason"] = "renderer_resource_modified"; return result;
    }
    result["rendered"] = 0; result["upload_bytes"] = 0;
    if (!bool(result["ok"])) { instances_->set_visible_instance_count(0); return result; }
    const PackedInt64Array ids = result["ids"];
    for(int64_t i=0;i<ids.size();++i)if(!store_->contains(ids[i])){
        selected_.clear();instances_->set_visible_instance_count(0);
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
        const float *old = current + i * 12;
        if (old[0]==1 && old[5]==1 && old[10]==1 && old[3]==p.x && old[7]==p.y && old[11]==p.z) continue;
        // Acquire writable storage only on the first changed row. An unchanged
        // refresh neither detaches the packed array nor uploads its GPU buffer.
        if (!out) { out=buffer_.ptrw(); current=out; }
        float *row = out + i * 12;
        row[0]=1; row[1]=0; row[2]=0; row[3]=p.x;
        row[4]=0; row[5]=1; row[6]=0; row[7]=p.y;
        row[8]=0; row[9]=0; row[10]=1; row[11]=p.z;
    }
    if (out) instances_->set_buffer(buffer_);
    instances_->set_visible_instance_count(int(ids.size()));
    result["rendered"] = ids.size();
    result["upload_bytes"] = out ? int64_t(capacity_) * 48 : 0;
    return result;
}
}
