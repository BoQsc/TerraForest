// SPDX-License-Identifier: 0BSD
#pragma once
#include "water_cell_profile.hpp"

namespace terraforest {
// A transaction-local evaluator. Geometry is immutable during a face solve;
// reuse its floor moments instead of scanning triangles at every bisection.
// Keep the same arithmetic order, clipping, inverse iterations and rounding as
// WaterCellProfile. This caches neither water quantities nor mutable regions.
class WaterVolumeQuery {
    const WaterCellProfile &shape;
    double minimum=0,maximum=0,mean=0,zero=0;
    uint64_t limit=0;
    double raw(double h) const {
        h=std::min(h,shape.ceiling);if(h<=minimum)return 0;
        if(h>=maximum)return (h-mean)*250;
        double result=0;
        shape.polygons(h,[&](double area,WaterCellProfile::Point a,WaterCellProfile::Point b,WaterCellProfile::Point c){result+=area*(h-(a.y+b.y+c.y)/3.0)*250;});
        return std::max(0.0,result);
    }
public:
    explicit WaterVolumeQuery(const WaterCellProfile &source):shape(source){
        if(shape.solid){limit=shape.capacity();return;}
        minimum=shape.minimum();maximum=shape.maximum();mean=shape.mean();
        if(minimum<0)zero=raw(0);
        limit=uint64_t(std::floor(volume(shape.ceiling)+1e-7));
    }
    uint64_t capacity() const {return limit;}
    double volume(double h) const {
        if(shape.solid)return shape.volume(h);
        return h<=0?0:std::max(0.0,raw(h)-zero);
    }
    double head(uint64_t ml) const {
        if(shape.solid)return shape.head(ml);
        if(!ml)return std::max(0.0,minimum);
        if(ml>=limit)return shape.ceiling;
        if(ml>=volume(maximum))return std::min(shape.ceiling,mean+(ml+zero)/250.0);
        double lo=1e30,hi=shape.ceiling;
        for(int i=0;i<4;++i)lo=std::min(lo,shape.floor[i]);
        for(int n=0;n<26;++n){double mid=(lo+hi)*.5;if(volume(mid)<ml)lo=mid;else hi=mid;}
        return (lo+hi)*.5;
    }
};
}
