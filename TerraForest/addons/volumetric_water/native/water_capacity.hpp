// SPDX-License-Identifier: 0BSD
#pragma once
#include "lake_volume.hpp"
#include <godot_cpp/classes/ref.hpp>
namespace terraforest {
// Worker-owned, resumable measurement of immutable connected lake geometry.
class NativeWaterCapacity : public godot::RefCounted {
    GDCLASS(NativeWaterCapacity,godot::RefCounted)
    godot::Ref<NativeLakeVolume> source;
    uint32_t cursor=0;
    double cubic_metres=0,compensation=0;
    int status=-1;
protected:
    static void _bind_methods();
public:
    bool begin(const godot::Ref<NativeLakeVolume> &volume);
    godot::Dictionary step(int64_t cell_budget);
    godot::Dictionary statistics() const;
};
}
