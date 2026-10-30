// SPDX-License-Identifier: 0BSD
#pragma once
#include "fleet.hpp"
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/classes/material.hpp>
#include <godot_cpp/classes/multi_mesh_instance3d.hpp>
#include <godot_cpp/classes/multi_mesh.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <vector>

namespace terraforest {
class NativeVehicleHorizon : public godot::Node3D {
    GDCLASS(NativeVehicleHorizon,godot::Node3D)
    static constexpr int PAGE_SIZE=128;
    struct Part {godot::Ref<godot::Mesh> mesh;godot::Ref<godot::Material> material;godot::Transform3D local;};
    struct Page {int cell=0;std::vector<int64_t> ids,published;std::vector<godot::MultiMeshInstance3D*> nodes;};
    struct Location {int page=0;int slot=0;godot::Transform3D pose;};
    godot::Ref<NativeVehicleFleet> fleet;
    godot::String kind;
    std::vector<Part> parts;
    std::map<int,Page> pages;
    std::map<int,std::set<int>> available;
    std::map<int,std::set<int>> cell_pages;
    std::unordered_map<int64_t,Location> locations;
    std::set<int64_t> excluded,changed;
    std::set<int> dirty;
    int next_page=0;
    int64_t cursor=0;
    bool scanned=false,live=false;
    uint64_t uploads=0,upload_bytes=0,last_us=0;
    int last_records=0,last_uploads=0;
    void change(int64_t identity);
    void reset();
    void reconcile(int64_t identity);
    std::set<int> affected(int64_t identity) const;
    void remove(int64_t identity);
    void upload(int page);
protected:
    static void _bind_methods();
    void _notification(int what);
public:
    ~NativeVehicleHorizon();
    bool configure(const godot::Ref<NativeVehicleFleet> &source,const godot::Array &prototype,const godot::String &type);
    bool set_excluded(const godot::PackedInt64Array &identities);
    void advance(int records=128,int page_uploads=3);
    godot::Dictionary statistics() const;
    godot::PackedInt64Array represented_ids() const;
};
}
