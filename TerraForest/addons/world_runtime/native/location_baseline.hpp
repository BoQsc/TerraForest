// SPDX-License-Identifier: 0BSD
#pragma once
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <map>

namespace terraforest {
struct LocationBaselineEntry {
    godot::PackedByteArray definition,digest;
    int64_t bytes=0;
};
bool parse_location_baselines(const godot::PackedByteArray &data,std::map<int64_t,LocationBaselineEntry> &entries,godot::PackedByteArray &world);
godot::PackedByteArray read_location_baseline(const godot::String &directory,int64_t key,const LocationBaselineEntry &entry,const godot::PackedByteArray &world,godot::Dictionary &sections);
}
