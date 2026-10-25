#pragma once
#include <algorithm>
#include <cmath>
#include <cstdint>
namespace terraforest {
inline double biome_noise(double world_x, double world_z, uint32_t seed) {
    const int column = int(std::floor(world_x)), row = int(std::floor(world_z));
    auto sample = [seed](int px, int pz) {
        uint32_t value = uint32_t(px)*73856093u ^ uint32_t(pz)*19349663u ^ seed;
        value ^= value >> 16; value *= 0x7feb352du; value ^= value >> 15;
        value *= 0x846ca68bu; value ^= value >> 16;
        return double(value & 65535u)/65535.0;
    };
    double horizontal = world_x-column, vertical = world_z-row;
    horizontal *= horizontal*(3-2*horizontal); vertical *= vertical*(3-2*vertical);
    return (sample(column,row)*(1-horizontal)+sample(column+1,row)*horizontal)*(1-vertical)
        +(sample(column,row+1)*(1-horizontal)+sample(column+1,row+1)*horizontal)*vertical;
}
inline double biome_woodland(double world_x, double world_z, uint32_t seed, int profile) {
    const double broad = biome_noise(world_x/230.0,world_z/230.0,seed^0x76b3a921u);
    const double edge = biome_noise(world_x/65.0,world_z/65.0,seed^0x1b873593u);
    const double threshold = profile==2 ? .62 : profile==1 ? .46 : .34;
    return std::clamp((broad*.8+edge*.2-threshold)*4.0,0.0,1.0);
}
}
