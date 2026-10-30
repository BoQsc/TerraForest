// SPDX-License-Identifier: 0BSD
#pragma once
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/classes/shader_material.hpp>
#include <godot_cpp/classes/multi_mesh.hpp>
#include <godot_cpp/classes/multi_mesh_instance3d.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <map>
#include <vector>
#include <array>
namespace terraforest {
class NativeBoulderFracture : public godot::Node3D {
    GDCLASS(NativeBoulderFracture,godot::Node3D)
    struct Rock {godot::Transform3D pose;int stage=0;std::array<int,2> slots{-1,-1};double began=0;float impact=0;bool tap=false;godot::Vector2 slope;};
    struct Group {godot::Ref<godot::Mesh> mesh;godot::Ref<godot::MultiMesh> instances;godot::Ref<godot::ShaderMaterial> appearance;godot::MultiMeshInstance3D *node=nullptr;std::vector<int64_t> ids;bool dirty=false;};
    int capacity=512,group_count=4;
    bool horizon=false,view_valid=false;
    godot::Vector3 view_eye;
    float projection=1.0f;
    std::array<Group,8> groups;
    std::map<int64_t,Rock> rocks;
    godot::Ref<godot::RefCounted> durability;
    godot::Ref<godot::ShaderMaterial> material;
    int cache_triangles=0;
    void detach(int64_t id);
    void attach(int64_t id);
    void attach_tier(int64_t id,int tier);
    void detach_tier(int64_t id,int tier);
    void select_tiers(int64_t id);
    void flush();
    void bounds(int stage);
    static godot::Color custom(const Rock &rock);
    int damage_stage(int64_t id)const;
protected:
    static void _bind_methods();
public:
    bool configure(const godot::Ref<godot::Mesh> &source,const godot::Ref<godot::ShaderMaterial> &appearance,const godot::Ref<godot::RefCounted> &damage);
    bool configure_horizon(const godot::Ref<godot::Mesh> &distant);
    bool upsert_rows(const godot::PackedInt64Array &ids,const godot::PackedFloat32Array &transforms);
    bool sync_damage(int64_t id,godot::Vector3 hit_from=godot::Vector3());
    bool finish(int64_t id);
    void remove_rows(const godot::PackedInt64Array &ids);
    void clear();
    void advance(godot::Vector3 eye);
    void advance_view(godot::Vector3 eye,double projection_scale);
    godot::Dictionary statistics()const;
    int64_t stage(int64_t id)const;
    godot::Ref<godot::Mesh> stage_mesh(int64_t stage)const;
};
}
