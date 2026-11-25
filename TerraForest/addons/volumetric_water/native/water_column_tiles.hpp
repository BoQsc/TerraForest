// SPDX-License-Identifier: 0BSD
#pragma once
#include "water_cell_profile.hpp"

namespace terraforest {
// Hydraulic equivalence only. Picking and meshing keep every original
// contact triangle. Closed cells have no portal. A flat bed has a constant
// elevation over the whole footprint, including the density fallback at
// uncovered corners. Check the storage offset as well as the side openings.
struct WaterFlatTier {
    bool closed=false,open_bottom=false;
    double floor=0,ceiling=0;
    uint64_t capacity=0;
    bool read(const WaterCellProfile &s){
        if(s.solid)return false;
        if(s.is_full_air()){*this={false,true,0,500,125000};return true;}
        const double h=s.floor[0];
        if(!std::all_of(s.floor.begin(),s.floor.end(),[&](double y){return y==h;}))return false;
        if(s.contact&&(s.minimum()!=h||s.maximum()!=h||s.mean()!=h))return false;
        *this={false,s.open_bottom,h,s.ceiling,s.capacity()};
        return true;
    }
    bool operator==(const WaterFlatTier &other) const{
        return closed==other.closed&&open_bottom==other.open_bottom&&floor==other.floor&&
            ceiling==other.ceiling&&capacity==other.capacity;
    }
};
}
