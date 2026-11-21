// SPDX-License-Identifier: 0BSD
#pragma once
#include "water_spill_hierarchy.hpp"
#include "water_volume_query.hpp"
#include <godot_cpp/variant/vector3i.hpp>
#include <limits>

namespace terraforest {
// A vertically open interval fills from its bottom. Its capacity at any
// elevation is a prefix of completely filled tiers and at most one cut tier.
// Keep distinct intervals for roofs and for openings that retain water above
// their sill. Neighbouring columns communicate through their lowest common
// open face, including the clipped faces of authored solids.
template<class Spans,class Lookup,class Shape>
bool settle_spill_columns(Spans &spans,const std::vector<int> &body,const std::vector<unsigned char> &reached,
                          Lookup lookup,Shape profile_at,double upper,uint64_t quantity,size_t leaf_limit,
                          const std::atomic<bool> &cancelled,size_t &leaf_count){
    using godot::Vector3i;
    const WaterCellProfile air;
    std::vector<int> shape_index(spans.size(),-1);
    std::vector<WaterCellProfile> shapes;
    for(int id:body)if(!spans[id].air){
        shape_index[id]=int(shapes.size());
        shapes.push_back(profile_at(spans[id]));
    }
    std::vector<WaterVolumeQuery> queries;queries.reserve(shapes.size());
    for(const auto &shape:shapes)queries.emplace_back(shape);
    auto shape=[&](int id)->const WaterCellProfile &{
        return shape_index[id]<0?air:shapes[shape_index[id]];
    };
    struct Tier {int span;uint64_t below,capacity;};
    struct Column {
        size_t begin,end;
        uint64_t capacity=0,before=0,after=0;
        double fraction=0;
    };
    std::vector<int> next(spans.size(),-1),owner(spans.size(),-1);
    std::vector<unsigned char> has_lower(spans.size());
    for(int id:body){
        const auto &s=spans[id];
        int above=lookup(s.base+Vector3i(0,int(s.length),0));
        if(above>=0&&reached[above]&&WaterCellProfile::connected(shape(id),500.,shape(above),1e-5,5)){
            next[id]=above;has_lower[above]=1;
        }
    }
    std::vector<Tier> tiers;tiers.reserve(body.size());
    std::vector<Column> columns;
    for(int bottom:body)if(!has_lower[bottom]){
        if(columns.size()>=leaf_limit||cancelled.load(std::memory_order_relaxed))return false;
        Column column{tiers.size(),tiers.size()};
        for(int id=bottom;id>=0;id=next[id]){
            auto &s=spans[id];owner[id]=int(columns.size());
            uint64_t capacity=s.air?125000ULL*s.length:queries[shape_index[id]].capacity();
            tiers.push_back({id,column.capacity,capacity});
            column.capacity+=capacity;column.before+=s.before;
        }
        column.end=tiers.size();columns.push_back(column);
    }
    if(tiers.size()!=body.size()||columns.empty()||columns.size()==tiers.size())return false;
    const Vector3i steps[]={{0,-1,0},{1,0,0},{-1,0,0},{0,0,1},{0,0,-1},{0,1,0}};
    std::vector<WaterSpillEdge> edges;
    std::vector<int> touched;
    const double infinity=std::numeric_limits<double>::infinity();
    std::vector<double> least(columns.size(),infinity);
    for(int c=0;c<int(columns.size());++c){
        if(cancelled.load(std::memory_order_relaxed))return false;
        const auto &column=columns[c];
        for(size_t at=column.begin;at<column.end;++at){
            const auto id=tiers[at].span;const auto &s=spans[id];
            for(int d=0;d<6;++d){
                int y=d==5?int(s.length)-1:0, end=d==0?1:int(s.length);
                while(y<end){
                    auto p=s.base+Vector3i(0,y++,0),q=p+steps[d];int j=lookup(q);
                    if(j<0)continue;
                    const auto &n=spans[j];
                    if(d>=1&&d<=4)y=std::min(end,int(n.base.y+n.length)-s.base.y);
                    int other=owner[j];if(other<=c)continue;
                    double sill=std::max(p.y,q.y)*.5;
                    if(least[other]<=sill)continue;
                    auto &a=shape(id);auto &b=shape(j);
                    if(!WaterCellProfile::connected(a,std::min(500.,(upper-p.y*.5)*1000.),
                                                    b,std::min(500.,(upper-q.y*.5)*1000.),d))continue;
                    if(d>=1&&d<=4&&(!s.air||!n.air)){
                        int axis=d<=2?0:2,side=d==1||d==3?1:0;
                        sill+=.001*(a.solid||b.solid?WaterCellProfile::clipped_spill_height(a,b,axis,side):
                                                     WaterCellProfile::floor_spill_height(a,b,axis,side));
                    }
                    if(least[other]==infinity)touched.push_back(other);
                    least[other]=std::min(least[other],std::min(upper,sill+2e-9));
                }
            }
        }
        if(edges.size()+touched.size()>leaf_limit*6)return false;
        for(int other:touched){edges.push_back({c,other,least[other]});least[other]=infinity;}
        touched.clear();
    }
    auto capacity=[&](int c){return columns[c].capacity;};
    auto volume=[&](int c,double h){
        const auto &column=columns[c];
        auto first=tiers.begin()+column.begin,last=tiers.begin()+column.end;
        auto next_tier=std::upper_bound(first,last,h,[&](double level,const Tier &tier){
            return level<spans[tier.span].base.y*.5;
        });
        if(next_tier==first)return 0.;
        const auto &tier=*std::prev(next_tier);
        const auto &s=spans[tier.span];double depth=(h-s.base.y*.5)*1000.;
        double part=s.air?depth*250.:queries[shape_index[tier.span]].volume(depth);
        return double(tier.below)+std::clamp(part,0.,double(tier.capacity));
    };
    auto integral=[&](int c,double h){return uint64_t(std::floor(volume(c,h)));};
    int64_t exchange=0;const char *error=nullptr;
    if(!distribute_basin_water(columns,edges,-1,upper,quantity,exchange,volume,capacity,integral,cancelled,[](int){},error,56))
        return false;
    for(const auto &column:columns){
        uint64_t remaining=column.after;
        for(size_t at=column.begin;at<column.end;++at){
            auto &tier=tiers[at];
            auto amount=std::min(remaining,tier.capacity);
            spans[tier.span].after=amount;remaining-=amount;
        }
    }
    leaf_count=columns.size();return true;
}
}
