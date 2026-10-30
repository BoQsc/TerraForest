// SPDX-License-Identifier: 0BSD
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
namespace terraforest {
class NativeVehiclePrototype : public godot::RefCounted {
    GDCLASS(NativeVehiclePrototype,godot::RefCounted)
protected:
    static void _bind_methods();
public:
    godot::Dictionary bake(const godot::Array &parts) const;
};
}
