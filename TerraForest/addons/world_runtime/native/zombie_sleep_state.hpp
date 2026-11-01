// SPDX-License-Identifier: 0BSD
#pragma once
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <cmath>
namespace terraforest {
inline bool valid_sleep_intent(const godot::PackedByteArray &bytes){
    if(bytes.size()!=28)return false;
    const auto pose=bytes.decode_u32(0),phase=bytes.decode_u32(4),provoked=bytes.decode_u32(24);
    const double elapsed=bytes.decode_float(8);
    if(pose<1||pose>2||phase<1||phase>2||provoked>1||!std::isfinite(elapsed)||elapsed<0||elapsed>8)return false;
    if(phase==1&&(elapsed!=0||provoked))return false;
    for(int axis=0;axis<3;++axis){const double position=bytes.decode_float(12+axis*4);if(!std::isfinite(position)||std::abs(position)>1000000)return false;}
    return true;
}
inline bool valid_sleep_pose(const godot::PackedByteArray &bytes){
    if(bytes.size()!=16)return false;
    const auto pose=bytes.decode_u32(0),phase=bytes.decode_u32(4),flags=bytes.decode_u32(8);
    const double cursor=bytes.decode_float(12);
    if(pose<1||pose>2||phase<1||phase>3||flags>2||!std::isfinite(cursor)||cursor<0)return false;
    const double length=flags==1?(pose==1?2.8:2.6):(pose==1?3.2:4.2);
    if(cursor>length+.000001||(phase==1&&(cursor!=0||flags))||(phase==3&&(std::abs(cursor-length)>.000001||flags==2)))return false;
    return true;
}
inline bool valid_sleep_state(const godot::PackedByteArray &bytes){
    if(bytes.is_empty())return true;
    if(bytes.size()!=44||!valid_sleep_intent(bytes.slice(0,28))||!valid_sleep_pose(bytes.slice(28)))return false;
    return bytes.decode_u32(0)==bytes.decode_u32(28)&&((bytes.decode_u32(4)==1)==(bytes.decode_u32(32)==1));
}
}
