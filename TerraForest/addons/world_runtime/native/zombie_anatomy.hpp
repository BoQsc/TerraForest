// SPDX-License-Identifier: 0BSD
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/skeleton3d.hpp>
#include <godot_cpp/classes/physics_body3d.hpp>
#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/classes/skin.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <godot_cpp/variant/aabb.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <array>
#include <vector>
namespace terraforest {
class NativeZombieAnatomy : public godot::RefCounted {
    GDCLASS(NativeZombieAnatomy,godot::RefCounted)
    struct Surface {
        godot::PackedVector3Array vertices;
        godot::PackedInt32Array indices,bones;
        godot::PackedFloat32Array weights;
        std::vector<godot::PackedVector3Array> morphs;
        bool relative=false;
    };
    struct Part {
        double maximum=0,health=0;int parent=-1;bool missing=false;
        uint64_t mesh=0;std::vector<int> bone_ids;
        godot::Ref<godot::Mesh> asset;
        godot::Ref<godot::Skin> skin;
        std::vector<godot::Transform3D> binds;std::vector<Surface> surfaces;
    };
    struct JointState {uint64_t node=0,body_b=0;int type=0;bool physical=false;godot::Dictionary properties;godot::Transform3D frame_b;};
    struct Ragdoll {std::vector<uint64_t> bodies;std::vector<JointState> joints;double quiet=0;bool ground_damped=false,parked=false;};
    std::array<Part,14> parts_;
    std::vector<Ragdoll> ragdolls_;
    std::vector<godot::Transform3D> death_poses_;
    std::vector<godot::Transform3D> geometry_rest_,geometry_pose_,geometry_mesh_transforms_;
    std::vector<godot::StringName> geometry_names_;
    std::array<std::vector<double>,14> geometry_morphs_;
    godot::Dictionary fitted_shapes_;
    bool geometry_valid_=false,geometry_reused_=false,shapes_reused_=false;
    uint64_t skeleton_=0;double health_=180,maximum_=180,ragdoll_clock_=0;
    int vertices_=0,triangles_=0,settle_events_=0;bool configured_=false;
    static int part_index(const godot::String &part);
    void park_constraints(Ragdoll &group,bool park);
    void invalidate_geometry();
    std::vector<godot::Transform3D> evaluated_poses() const;
protected:
    static void _bind_methods();
public:
    bool configure(const godot::Dictionary &definitions);
    bool set_hit_meshes(godot::Skeleton3D *skeleton,const godot::Dictionary &meshes,const godot::Ref<NativeZombieAnatomy> &geometry=godot::Ref<NativeZombieAnatomy>());
    godot::PackedVector3Array sample_vertices(const godot::String &part,const godot::Transform3D &to_local) const;
    godot::Dictionary hand_groups(const godot::String &part,const godot::Transform3D &to_local) const;
    godot::Dictionary closest_contact(const godot::String &part,godot::Vector3 target,bool use_point,const godot::Array &shapes,const godot::AABB &mouth) const;
    godot::Dictionary fit_collision_shapes();
    godot::Dictionary geometry_stats() const;
    godot::Dictionary hit(const godot::String &part,double damage,bool force_sever,const godot::String &impact);
    bool detach(const godot::String &part);
    void kill();
    godot::Dictionary snapshot() const;
    godot::PackedByteArray capture_vitals() const;
    bool restore_vitals(const godot::PackedByteArray &bytes);
    godot::Dictionary pick(godot::Vector3 from,godot::Vector3 to) const;
    bool track_ragdoll(const godot::TypedArray<godot::PhysicsBody3D> &bodies);
    void advance_ragdolls(double delta);
    void wake_ragdolls(const godot::AABB &bounds=godot::AABB());
    godot::Dictionary ragdoll_stats() const;
};
}
