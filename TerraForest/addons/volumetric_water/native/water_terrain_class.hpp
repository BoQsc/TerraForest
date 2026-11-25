// SPDX-License-Identifier: 0BSD
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <array>
#include <cstdint>

namespace terraforest {
using WaterSectionSignature=std::array<int16_t,9>;
inline WaterSectionSignature water_section_signature(const uint8_t *record,int y){
    WaterSectionSignature key;
    key[0]=record[0]==3?int16_t(y):-1;
    for(int j=0;j<8;++j)key[1+j]=int16_t(uint16_t(record[1+2*j])|(uint16_t(record[2+2*j])<<8));
    return key;
}
inline godot::PackedByteArray classify_edit_bricks(godot::Object *reader,const godot::PackedInt32Array &origins,int64_t revision,int64_t epoch){
    if(reader->has_method("classify_edit_bricks"))return reader->call("classify_edit_bricks",origins,revision,epoch);
    return reader->call("classify_water_bricks",origins,revision,epoch,true);
}
}
