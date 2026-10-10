// SPDX-License-Identifier: 0BSD
#pragma once
#include "entity_store.hpp"
#include <godot_cpp/classes/multi_mesh_instance3d.hpp>
#include <godot_cpp/classes/multi_mesh.hpp>
#include <godot_cpp/classes/mesh.hpp>

namespace terraforest {
// Main-thread rendering adapter. Positions and query centers are renderer-local.
// Simulation scheduling remains with the caller; no implicit full-store tick.
class NativeEntityRenderer : public godot::MultiMeshInstance3D {
    GDCLASS(NativeEntityRenderer, godot::MultiMeshInstance3D)
    godot::Ref<NativeEntityStore> store_;
    godot::Ref<godot::MultiMesh> instances_;
    godot::PackedFloat32Array buffer_;
    int capacity_ = 0;
    uint64_t marker_id_ = 0;
    int64_t highlighted_identity_ = 0;
    godot::PackedInt64Array selected_;
    godot::Dictionary publish(godot::Dictionary result);
protected:
    static void _bind_methods();
public:
    void set_selection_marker(godot::Node3D *marker, int64_t identity);
    bool configure(const godot::Ref<NativeEntityStore> &store, const godot::Ref<godot::Mesh> &mesh, int capacity);
    godot::Dictionary refresh_positions();
    godot::Dictionary refresh(const godot::Vector3 &center, double radius, int candidate_budget = 4096);
};
}
