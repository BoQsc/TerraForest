// SPDX-License-Identifier: 0BSD
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
namespace terraforest {
class NativeRoadProfile : public godot::RefCounted {
 GDCLASS(NativeRoadProfile,godot::RefCounted)
protected: static void _bind_methods();
public: godot::Dictionary fit(const godot::PackedVector3Array &samples,double grade,double curvature,double cut,double fill) const;
 godot::Dictionary grid_trial(const godot::PackedFloat64Array &coefficients,double spacing) const;
};
}
