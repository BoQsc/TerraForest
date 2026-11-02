// SPDX-License-Identifier: 0BSD
#pragma once
#include <godot_cpp/classes/skeleton_modifier3d.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <array>
namespace terraforest {
class NativeZombieHitReaction : public godot::SkeletonModifier3D {
    GDCLASS(NativeZombieHitReaction,godot::SkeletonModifier3D)
    struct Joint {int bone=-1;godot::String part;godot::Vector3 angle,velocity;};
    std::array<Joint,14> joints;
    bool configured=false;
    void impulse(Joint &,godot::Vector3,godot::Vector3,double);
protected:
    static void _bind_methods();
public:
    bool configure(const godot::Dictionary &parts);
    bool hit(const godot::String &part,godot::Vector3 point,godot::Vector3 impulse,double damage);
    void clear();
    godot::Dictionary statistics()const;
    void _process_modification_with_delta(double delta)override;
};
}
