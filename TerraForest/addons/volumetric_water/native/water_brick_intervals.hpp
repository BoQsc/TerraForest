// SPDX-License-Identifier: 0BSD
#pragma once
#include <array>
#include <cstdint>

namespace terraforest {
// Classify the measured half-metre lattice once, after correcting its signs
// against the terrain triangles. Each row describes eight adjacent cells.
struct WaterLatticeSigns {
    std::array<uint8_t,64> air{},mixed{};
    explicit WaterLatticeSigns(const std::array<float,729> &density) {
        std::array<uint16_t,81> rows{};
        for (int row=0;row<81;++row) {
            unsigned bits=0;
            for (int x=0;x<9;++x) bits|=unsigned(density[9*row+x]>0)<<x;
            rows[row]=uint16_t(bits);
        }
        for (int z=0;z<8;++z) for (int y=0;y<8;++y) {
            const auto *r=rows.data()+9*z+y;
            const unsigned all=r[0]&r[1]&r[9]&r[10];
            const unsigned any=r[0]|r[1]|r[9]|r[10];
            air[8*z+y]=uint8_t(all&(all>>1));
            mixed[8*z+y]=uint8_t((any|(any>>1))&~air[8*z+y]);
        }
    }
};

// One bit per vertical tier in a 4 m column. Consumers may skip entire
// certified intervals. Mixed cells retain their original clipped profiles.
struct WaterBrickIntervals {
    std::array<uint8_t,64> air{},closed{};
    static int column(int index) { return (index&7)+8*(index>>6); }
    static int tier(int index) { return (index>>3)&7; }
    static int run(uint8_t mask,int tier) {
        // The sentinel makes the count well-defined for an all-set column.
        const unsigned ends=(256u|(~unsigned(mask)&255u))>>tier;
        return __builtin_ctz(ends);
    }
    bool full_air(int index) const { return air[column(index)]&(1u<<tier(index)); }
};
}
