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
    std::map<int64_t,godot::Transform3D> records_;
    std::unordered_map<int,std::set<int64_t>> cells_;
    int64_t next_=1;
    static int cell(const godot::Vector3 &p);
    void remove_cell(int64_t id,const godot::Vector3 &p);
protected: static void _bind_methods();
public:
    int64_t spawn(const godot::Transform3D &pose);
    bool remove(int64_t id);
    bool set_pose(int64_t id,const godot::Transform3D &pose);
    godot::Dictionary get_record(int64_t id) const;
    godot::Dictionary query_near(const godot::Vector3 &center,double radius,int limit,int budget) const;
    godot::Dictionary statistics() const;
    godot::PackedByteArray capture_storage_snapshot() const;
    bool validate_snapshot(const godot::PackedByteArray &data) const;
    bool restore_storage_snapshot(const godot::PackedByteArray &data);
};
}
