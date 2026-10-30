// SPDX-License-Identifier: 0BSD
#pragma once
#include "storage.hpp"
#include <map>
#include <unordered_map>
#include <set>
namespace terraforest {
// Scene-thread mutable ownership. Only validate_snapshot is worker-safe.
class NativeVehicleFleet : public godot::RefCounted {
    GDCLASS(NativeVehicleFleet,godot::RefCounted)
    friend class NativeVehicleHorizon;
    std::map<int64_t,godot::Transform3D> records_;
    std::map<godot::String,std::set<int64_t>> kinds_;
    std::map<int64_t,std::pair<godot::String,godot::PackedByteArray>> modules_;
    uint64_t revision_=0;
    int64_t state_bytes_=0;
    std::unordered_map<int,std::set<int64_t>> cells_;
    int64_t next_=1;
    static int cell(const godot::Vector3 &p);
    void remove_cell(int64_t id,const godot::Vector3 &p);
protected: static void _bind_methods();
public:
    int64_t spawn(const godot::Transform3D &pose);
    int64_t spawn_module(const godot::Transform3D &pose,const godot::String &kind,const godot::PackedByteArray &state);
    bool set_module_state(int64_t id,const godot::PackedByteArray &state);
    godot::Dictionary read_records(int64_t after,int limit) const;
    int64_t first_of_kind(const godot::String &kind) const;
    bool remove(int64_t id);
    bool set_pose(int64_t id,const godot::Transform3D &pose);
    godot::Dictionary get_record(int64_t id) const;
    godot::Dictionary query_near(const godot::Vector3 &center,double radius,int limit,int budget) const;
    godot::Dictionary query_near_kind(const godot::Vector3 &center,double radius,int limit,int budget,const godot::String &kind) const;
    godot::Dictionary statistics() const;
    godot::PackedByteArray capture_storage_snapshot() const;
    bool validate_snapshot(const godot::PackedByteArray &data) const;
    bool restore_storage_snapshot(const godot::PackedByteArray &data);
};
}
