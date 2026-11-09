// SPDX-License-Identifier: 0BSD
#pragma once
#include "static_batch.hpp"
#include <godot_cpp/classes/omni_light3d.hpp>
namespace terraforest {
class NativeResidentLights : public godot::Node3D {
    GDCLASS(NativeResidentLights,godot::Node3D)
    struct Source {uint64_t owner;godot::Vector3 offset;godot::Color color;double energy,range;bool shadows;};
    struct Candidate {int source;int64_t identity;double distance;godot::Vector3 position;};
    struct Slot {godot::OmniLight3D *light=nullptr;int source=-1;int64_t identity=0;};
    std::vector<Source> sources;
    std::vector<Slot> slots;
    std::vector<Candidate> selected;
    godot::Vector3 focus;
    double timer=0;
    uint64_t updates=0,visited=0,total_visited=0,last_us=0,max_us=0;
    uint64_t last_started_us=0,last_ended_us=0;
    size_t source_cursor=0,cell_cursor=0;
    int64_t after_identity=0;
    std::vector<BlockKey> scan_cells;
    godot::Vector3 scan_focus;
    bool enabled=true,scanning=false;
    void select();
    void publish();
    bool point(const Source &,int64_t,godot::Vector3 &) const;
protected:
    static void _bind_methods();
public:
    bool configure(const godot::Array &definitions,int limit);
    void set_focus(godot::Vector3 value);
    void set_enabled(bool value);
    void _process(double delta) override;
    godot::Dictionary statistics() const;
    godot::Dictionary process_frame_profile() const;
};
}
