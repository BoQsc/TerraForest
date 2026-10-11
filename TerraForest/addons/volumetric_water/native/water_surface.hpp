// SPDX-License-Identifier: 0BSD
#pragma once
#include "water_network.hpp"
#include <deque>
namespace terraforest {
// One region's finite-water free surface. No per-frame rebuild or fluid tick.
class NativeWaterSurface : public godot::RefCounted {
    friend class NativeWaterScene;
    GDCLASS(NativeWaterSurface,godot::RefCounted)
    godot::Ref<NativeWaterNetwork> network;
    uint64_t revision=0;
    int piece=-1,status=-1,phase=0,cursor=0;
    int64_t work_total=0;
    std::vector<double> heads,quads;
    std::deque<godot::Vector3> triangles;
    godot::PackedVector3Array vertices,normals;
    godot::PackedVector2Array uv;
    bool current() const;
    void unit();
    void triangle(const godot::Vector3 &a,const godot::Vector3 &b,const godot::Vector3 &c);
protected:
    static void _bind_methods();
public:
    bool begin(const godot::Ref<NativeWaterNetwork> &water,const godot::Vector3i &coordinate);
    godot::Dictionary advance(int64_t work_budget);
    godot::Dictionary statistics() const;
    godot::Array surface_arrays() const;
};
}
