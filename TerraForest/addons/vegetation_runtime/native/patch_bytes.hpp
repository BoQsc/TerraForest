// SPDX-License-Identifier: 0BSD
#pragma once
#include <godot_cpp/classes/hashing_context.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <cstring>
namespace terraforest::vegetation_patch {
constexpr int trailer=32;
inline godot::PackedByteArray digest(const godot::PackedByteArray &bytes){
    if(bytes.size()<trailer)return {};
    godot::Ref<godot::HashingContext> hash;hash.instantiate();
    if(hash.is_null()||hash->start(godot::HashingContext::HASH_SHA256)!=godot::OK||hash->update(bytes.slice(0,bytes.size()-trailer))!=godot::OK)return {};
    return hash->finish();
}
inline bool seal(godot::PackedByteArray &bytes){
    const auto checksum=digest(bytes);if(checksum.size()!=trailer)return false;
    std::memcpy(bytes.ptrw()+bytes.size()-trailer,checksum.ptr(),trailer);return true;
}
inline bool verified(const godot::PackedByteArray &bytes){
    return bytes.size()>=trailer&&digest(bytes)==bytes.slice(bytes.size()-trailer);
}
}
