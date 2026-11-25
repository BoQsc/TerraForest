// SPDX-License-Identifier: 0BSD
#pragma once
#include <cstdint>
#include <cstring>

namespace terraforest {
// Terrain packets use Godot's little-endian wire format. Read only after
// validating the packet length and element counts at the extension boundary.
inline uint16_t water_u16(const uint8_t *p){
    return uint16_t(p[0])|(uint16_t(p[1])<<8);
}
inline uint32_t water_u32(const uint8_t *p){
    return uint32_t(p[0])|(uint32_t(p[1])<<8)|(uint32_t(p[2])<<16)|(uint32_t(p[3])<<24);
}
inline uint64_t water_u64(const uint8_t *p){
    return uint64_t(water_u32(p))|(uint64_t(water_u32(p+4))<<32);
}
inline float water_f32(const uint8_t *p){
    uint32_t bits=water_u32(p);float f;std::memcpy(&f,&bits,sizeof(f));return f;
}
inline void water_store_f32(uint8_t *p,float f){
    uint32_t bits;std::memcpy(&bits,&f,sizeof(bits));
    for(int i=0;i<4;++i)p[i]=uint8_t(bits>>(i*8));
}
}
