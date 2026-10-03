// SPDX-License-Identifier: 0BSD
#include "entity_renderer.hpp"
#include <godot_cpp/core/class_db.hpp>
using namespace godot;
namespace terraforest {
void NativeEntityRenderer::_bind_methods() {
    ClassDB::bind_method(D_METHOD("configure", "store", "mesh", "capacity"), &NativeEntityRenderer::configure);
    ClassDB::bind_method(D_METHOD("refresh", "center", "radius", "candidate_budget"), &NativeEntityRenderer::refresh, DEFVAL(4096));
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
    store_ = store; instances_ = next; capacity_ = capacity;
    set_multimesh(instances_);
    return true;
}
Dictionary NativeEntityRenderer::refresh(const Vector3 &center, double radius, int candidate_budget) {
    Dictionary result;
    result["ok"] = false; result["complete"] = false; result["rendered"] = 0; result["upload_bytes"] = 0;
    if (store_.is_null()) { result["reason"] = "not_configured"; return result; }
    // The MultiMesh is owned by this adapter. Detect external mutation instead of
    // submitting a wrongly sized buffer or continuing to display stale entities.
    if (get_multimesh() != instances_ || instances_->get_instance_count() != capacity_ ||
        instances_->get_transform_format() != MultiMesh::TRANSFORM_3D ||
        instances_->is_using_colors() || instances_->is_using_custom_data()) {
        instances_->set_visible_instance_count(0);
        set_multimesh(Ref<MultiMesh>());
        result["reason"] = "renderer_resource_modified"; return result;
    }
    result = store_->query_sphere(center, radius, capacity_, candidate_budget);
    result["rendered"] = 0; result["upload_bytes"] = 0;
    if (!bool(result["ok"])) { instances_->set_visible_instance_count(0); return result; }
    const PackedInt64Array ids = result["ids"];
    if (ids.is_empty()) { instances_->set_visible_instance_count(0); return result; }
    float *out = buffer_.ptrw();
    for (int64_t i = 0; i < ids.size(); ++i) {
        const Vector3 p = store_->get_position(ids[i]);
        float *row = out + i * 12;
        row[0]=1; row[1]=0; row[2]=0; row[3]=p.x;
        row[4]=0; row[5]=1; row[6]=0; row[7]=p.y;
        row[8]=0; row[9]=0; row[10]=1; row[11]=p.z;
    }
    instances_->set_buffer(buffer_);
    instances_->set_visible_instance_count(int(ids.size()));
    result["rendered"] = ids.size();
    result["upload_bytes"] = int64_t(capacity_) * 48;
    return result;
}
}
