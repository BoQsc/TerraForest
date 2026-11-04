// SPDX-License-Identifier: 0BSD
#pragma once
#include "entity_store.hpp"
#include <godot_cpp/variant/rid.hpp>
#include <godot_cpp/variant/callable.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <array>
#include <map>
namespace terraforest {
// Engine-owned rigid integration, bounded residency, canonical native pickup data.
class NativePickupPhysics : public godot::RefCounted {
    GDCLASS(NativePickupPhysics,godot::RefCounted)
    static constexpr int LIMIT=64;
    struct Motion {
        int batch=0;int64_t identity=0,handle=0;
        godot::RID body;
        godot::Vector3 velocity;
        bool sleeping=false,suspended=true;
    };
    std::array<Motion,LIMIT> records{};
    std::map<int,godot::Ref<NativeEntityStore>> stores;
    struct Layout {godot::Vector3 half=godot::Vector3(.17,.17,.17),offset;godot::RID shape;};
    std::map<int,Layout> layouts;
    Layout layout_for(int batch)const;
    godot::RID space,shape,excluded;
    godot::Transform3D world;
    int available() const;
    void release(Motion &motion);
    bool create_body(Motion &motion);
protected:
    static void _bind_methods();
public:
    ~NativePickupPhysics();
    bool configure(godot::RID physics_space,godot::RID exclude,const godot::Transform3D &transform);
    bool bind_store(int batch,const godot::Ref<NativeEntityStore> &store);
    bool set_layout(int batch,const godot::Vector3 &half,const godot::Vector3 &offset);
    bool can_launch() const;
    bool launch(int batch,int64_t handle,const godot::Vector3 &velocity);
    void forget(int batch,int64_t identity);
    void reset();
    godot::Dictionary step(double delta,bool run,const godot::Callable &ready);
    godot::Dictionary statistics() const;
    godot::PackedByteArray capture_storage_snapshot() const;
    bool validate_snapshot(const godot::PackedByteArray &bytes) const;
    bool restore_storage_snapshot(const godot::PackedByteArray &bytes);
};
}
