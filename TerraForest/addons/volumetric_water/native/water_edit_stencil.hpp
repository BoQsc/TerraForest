// SPDX-License-Identifier: 0BSD
#pragma once
#include <algorithm>
#include <array>
#include <cstdint>
#include <vector>
#include "water_packet.hpp"

namespace terraforest {
// Native edit receipts describe inclusive runs of changed density samples.
// A bounded 3-D difference grid unions their extraction stencils in O(runs
// + captured bricks). A failed receipt leaves the full reconstruction path.
class WaterEditStencil {
    using Point=std::array<int,3>;
    Point origin{},extent{};
    std::vector<int32_t> cells;
    int index(const Point &p)const{return p[0]+extent[0]*(p[1]+extent[1]*p[2]);}
    void add(Point lo,Point hi){
        for(int a=0;a<3;++a){
            // Each 4 m brick reads the lattice around its six-metre mesh
            // query and the sign/solid halo at finite world boundaries.
            lo[a]=std::max(0,(std::max(0,lo[a]-8)+3)/4-origin[a]);
            hi[a]=std::min(extent[a]-1,(hi[a]+4)/4-origin[a]+1);
            if(lo[a]>=hi[a])return;
        }
        for(int i=0;i<8;++i){
            Point p;int sign=1;
            for(int a=0;a<3;++a){const bool upper=i&(1<<a);p[a]=upper?hi[a]:lo[a];if(upper)sign=-sign;}
            cells[index(p)]+=sign;
        }
    }
public:
    bool begin(Point lo,Point hi){
        origin=lo;
        for(int a=0;a<3;++a){if(hi[a]<lo[a])return false;extent[a]=hi[a]-lo[a]+2;}
        const size_t n=size_t(extent[0])*extent[1]*extent[2];
        if(n>65536)return false;
        cells.assign(n,0);return true;
    }
    bool records(const uint8_t *data,size_t bytes){
        if(bytes%8||bytes/8>262144)return false;
        for(size_t offset=0;offset<bytes;offset+=8){
            const auto address=water_u32(data+offset),detail=water_u32(data+offset+4);
            Point p{int(address&2047),int(address>>22),int((address>>11)&2047)},q=p;
            if(p[0]>2000||p[2]>2000||p[1]>255)return false;
            if(detail==65536){
                if((p[0]|p[1]|p[2])&15)return false;
                p[1]-=1;q[0]+=15;q[1]+=17;q[2]+=15;
            }else if(detail!=131072){
                if(detail>255||int(detail)<p[1])return false;
                q[1]=int(detail);
            }
            add(p,q);
        }
        return true;
    }
    void seal(){
        const int stride[]={1,extent[0],extent[0]*extent[1]};
        for(int a=0;a<3;++a)for(int z=0;z<extent[2];++z)for(int y=0;y<extent[1];++y)for(int x=0;x<extent[0];++x){
            Point p{x,y,z};if(p[a]){const int i=index(p);cells[i]+=cells[i-stride[a]];}
        }
    }
    bool changed(Point p)const{
        for(int a=0;a<3;++a){p[a]-=origin[a];if(p[a]<0||p[a]>=extent[a]-1)return true;}
        return cells[index(p)]!=0;
    }
};
}
