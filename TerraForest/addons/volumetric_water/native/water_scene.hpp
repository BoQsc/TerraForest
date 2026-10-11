// SPDX-License-Identifier: 0BSD
#pragma once
#include "water_surface.hpp"
#include <godot_cpp/classes/node3d.hpp>
#include <godot_cpp/classes/material.hpp>
namespace terraforest {
// Main-thread scene publication; native water data work remains in sliced builders.
class NativeWaterScene : public godot::Node3D {
    GDCLASS(NativeWaterScene,godot::Node3D)
    godot::Ref<NativeWaterNetwork> active,pending;
    godot::Ref<NativeWaterSurface> surface;
    godot::Ref<godot::Material> material;
    godot::Node3D *shown=nullptr,*staging=nullptr,*retiring=nullptr;
    uint64_t active_revision=0,pending_revision=0;
    int status=-1,piece=0,published_regions=0,staged_regions=0;
    int64_t work_total=0,publications=0;
    bool valid(const godot::Ref<NativeWaterNetwork> &,uint64_t) const;
    bool identity() const;
    bool keep_previous=false;
    void cancel();
protected:
    static void _bind_methods();
public:
    bool begin_publish(const godot::Ref<NativeWaterNetwork> &water,const godot::Ref<godot::Material> &water_material);
    godot::Dictionary advance(int64_t work_budget);
    void refresh();
    void set_keep_previous_surface(bool enabled){keep_previous=enabled;refresh();}
    void _process(double delta) override;
    godot::Dictionary probe(const godot::Vector3 &point);
    double depth_at(const godot::Vector3 &point);
    godot::Dictionary statistics() const;
};
}
