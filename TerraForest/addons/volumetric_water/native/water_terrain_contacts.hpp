// SPDX-License-Identifier: 0BSD
#pragma once
#include "water_cell_profile.hpp"
#include <limits>

namespace terraforest {
// A 4 m receiver owns the precise clipped bed triangles. Most of its 512
// cells have no bed. Reuse the space formerly spent on 512 vector headers
// for hydraulic data shared by simulation, publication and surface queries.
struct TerrainWaterContacts {
    using Profile=WaterCellProfile;
    using Floor=std::vector<Profile::Triangle>;
    using Storage=Profile::FloorStorage;

    uint64_t bytes=0;
    std::array<uint16_t,512> index{};
    std::vector<Profile::Bed> floors;
    std::vector<Storage> storage;
    TerrainWaterContacts()=default;
    TerrainWaterContacts(const TerrainWaterContacts&)=delete;
    TerrainWaterContacts &operator=(const TerrainWaterContacts&)=delete;

    void add(int cell,Floor triangles){
        if(triangles.empty())return;
        index[cell]=uint16_t(floors.size()+1);
        floors.push_back({std::move(triangles),nullptr});
    }
    const Floor *floor(int cell)const{
        return index[cell]?&floors[index[cell]-1].triangles:nullptr;
    }
    void attach(Profile &shape,int cell)const{
        if(!index[cell])return;
        shape.contact=&floors[index[cell]-1];
        const auto *curve=shape.contact->storage;
        shape.cut=true;shape.ceiling=500;shape.open_bottom=shape.minimum()<0;
        for(int n=0;n<4;++n){
            if(!curve)shape.floor[n]=shape.raw_bottom(n&1,n>>1);
            else if(std::isfinite(curve->corners[n]))shape.floor[n]=curve->corners[n];
        }
    }
    void seal(){
        floors.shrink_to_fit();
        const size_t headers=sizeof(*this)+sizeof(Profile::Bed)*floors.capacity();
        constexpr size_t old_headers=512*sizeof(Floor);
        const size_t count=std::min(floors.size(),(old_headers-std::min(old_headers,headers))/sizeof(Storage));
        storage.reserve(count);
        for(size_t i=0;i<count;++i){
            Profile p;p.contact=&floors[i];
            Storage curve{};
            curve.minimum=p.minimum();curve.maximum=p.maximum();curve.mean=p.mean();
            curve.zero=curve.minimum<0?p.raw_volume(0):0;curve.capacity=p.capacity();
            // Preserve the terrain density corner wherever the saved triangle
            // footprint leaves that corner uncovered.
            p.floor.fill(std::numeric_limits<double>::quiet_NaN());
            for(int corner=0;corner<4;++corner)curve.corners[corner]=p.raw_bottom(corner&1,corner>>1);
            storage.push_back(curve);
            floors[i].storage=&storage.back();
        }
        bytes=headers+sizeof(Storage)*storage.capacity();
        for(const auto &f:floors)bytes+=f.triangles.capacity()*sizeof(Profile::Triangle);
    }
};
}
