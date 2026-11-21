// SPDX-License-Identifier: 0BSD
#pragma once
#include "core.h"
#include <array>
#include <atomic>
#include <mutex>

// One sealed terrain revision supplies terrain rendering, real collision and
// every intersecting 4 m water receiver. Publish each canonical 16 m column
// once. Its 256 vertical runs preserve extraction order and allow water to
// select only crossings inside the requested vertical interval.
class SealedSurfaceColumns final : public ResidentSurfaceColumns {
    struct Column {
        List<Vertex> vertices;
        std::array<int,257> runs{};
        std::atomic<int> state{0}; // 0 absent, 1 immutable, 2 bypass.
        std::mutex writer;
        ~Column(){vertices.release();}
    };
    std::array<Column,25> columns;
    int first_x,first_z,count_x,count_z;
    static constexpr size_t limit=4*1024*1024;
    const Column *get(const World &world,int x,int z,u32 epoch){
        auto &column=columns[(x-first_x)/16+count_x*((z-first_z)/16)];
        if(column.state.load(std::memory_order_acquire)==1)return &column;
        std::lock_guard<std::mutex> guard(column.writer);
        const auto state=column.state.load(std::memory_order_relaxed);
        if(state)return state==1?&column:nullptr;
        auto &vertices=column.vertices;
        if(!extract_surface_column(world,x,z,epoch,vertices)){vertices.release();return nullptr;}
        const size_t charge=sizeof(Vertex)*vertices.cap;
        if(retained.fetch_add(charge)+charge>limit){
            retained.fetch_sub(charge);vertices.release();column.state.store(2,std::memory_order_release);return nullptr;
        }
        int next=0;
        for(int i=0;i<256;++i){
            column.runs[i]=next;
            while(next<vertices.n&&vertices[next].cx==x+(i&15)&&vertices[next].cz==z+(i>>4))++next;
        }
        column.runs[256]=next;
        if(next!=vertices.n){
            retained.fetch_sub(charge);vertices.release();column.state.store(2,std::memory_order_release);return nullptr;
        }
        ++built;column.state.store(1,std::memory_order_release);
        return &column;
    }
public:
    std::atomic<size_t> retained{0},built{0},mesh_reads{0},contact_reads{0};
    SealedSurfaceColumns(int x,int z,int width,int depth){
        first_x=imx(0,x-1)&~15;first_z=imx(0,z-1)&~15;
        count_x=((x+width-1-first_x)>>4)+1;count_z=((z+depth-1-first_z)>>4)+1;
    }
    bool read(const World &world,int x,int z,int size,int bottom,int top,u32 epoch,List<Vertex> &out) override{
        int left=(x-1)&~15,north=(z-1)&~15;
        int right=(x+size-1)&~15,south=(z+size-1)&~15;
        if(count_x*count_z>int(columns.size())||size>32||left<first_x||north<first_z||
           right>=first_x+16*count_x||south>=first_z+16*count_z||
           left-1<world.contact_x0||north-1<world.contact_z0||
           right+16>world.contact_x1||south+16>world.contact_z1)return false;
        std::array<const Column*,9> sources;
        const int width=(right-left)/16+1;
        for(int cz=north;cz<=south;cz+=16)for(int cx=left;cx<=right;cx+=16){
            auto *source=get(world,cx,cz,epoch);
            if(!source)return false;
            sources[(cx-left)/16+width*((cz-north)/16)]=source;
        }
        const int old_size=out.n;
        for(int cz=z-1;cz<z+size;++cz)for(int cx=x-1;cx<x+size;++cx){
            const auto &column=*sources[(cx-left)/16+width*((cz-north)/16)];
            int run=(cx&15)+16*(cz&15);
            for(int i=column.runs[run];i<column.runs[run+1];++i){
                const auto &v=column.vertices[i];
                if(v.cy>=top)break;
                if(v.cy>=bottom-1)out.push(v);
            }
        }
        if(tr_oom||terrain_build_epoch(&world)!=epoch){out.n=old_size;return false;}
        if(size==6)++contact_reads;else ++mesh_reads;
        return true;
    }
};
