// SPDX-License-Identifier: 0BSD
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/vector3i.hpp>
#include <godot_cpp/variant/array.hpp>
#include <vector>
namespace terraforest {
struct CombatBlast {godot::Vector3 center;godot::PackedInt32Array records;int offset=0;};
class NativeCombatState : public godot::RefCounted {
    GDCLASS(NativeCombatState,godot::RefCounted)
    int rounds=0, assault_rounds=0;
    bool integrity=false;
    std::vector<CombatBlast> blasts;
protected: static void _bind_methods();
public:
    int get_rounds(int weapon=7) const {return weapon==7?rounds:(weapon==8?assault_rounds:0);}
    bool take_round(int weapon=7) {if((weapon!=7&&weapon!=8)||get_rounds(weapon)<=0)return false;--(weapon==7?rounds:assault_rounds);return true;}
    bool load_rounds(int count,int weapon=7) {if((weapon!=7&&weapon!=8)||count<1||count>30-get_rounds(weapon))return false;(weapon==7?rounds:assault_rounds)+=count;return true;}
    bool integrity_enabled() const {return integrity;}
    void set_integrity_enabled(bool value) {integrity=value;}
    godot::PackedByteArray capture_storage_snapshot() const;
    bool validate_snapshot(const godot::PackedByteArray &) const;
    bool restore_storage_snapshot(const godot::PackedByteArray &);
    bool set_blast_jobs(const godot::Array &);
    godot::Array get_blast_jobs() const;
    godot::PackedVector3Array support_probes(const godot::PackedInt32Array &,godot::Vector3i origin) const;
    godot::PackedInt32Array unsupported(const godot::PackedInt32Array &,godot::Vector3i origin,godot::Vector3i size,const godot::PackedFloat32Array &) const;
    godot::PackedInt32Array blast_cells(const godot::PackedInt32Array &,godot::Vector3i origin,godot::Vector3 center,double radius) const;
};
}
