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
    struct ConnectedColumn {
        Mesh mesh;
        List<SurfaceFaceRun> runs;
        std::array<int,257> offsets{};
        std::mutex writer;
        std::atomic<int> state{0};
        void release(){mesh.release();runs.release();}
        ~ConnectedColumn(){release();}
    };
    std::array<ConnectedColumn,25> connected;
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
    bool gather(const World &world,int x,int z,int size,int bottom,int top,u32 epoch,List<Vertex> &out){
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
        return true;
    }
    const ConnectedColumn *topology(const World &w,int x,int z,u32 epoch){
        if(x<first_x||z<first_z||x>=first_x+16*count_x||z>=first_z+16*count_z||
           count_x*count_z>int(connected.size())||x-1<w.contact_x0||z-1<w.contact_z0||
           x+16>w.contact_x1||z+16>w.contact_z1)return nullptr;
        auto &tile=connected[(x-first_x)/16+count_x*((z-first_z)/16)];
        auto state=tile.state.load(std::memory_order_acquire);
        if(state)return state==1?&tile:nullptr;
        std::lock_guard<std::mutex> guard(tile.writer);
        state=tile.state.load(std::memory_order_relaxed);
        if(state)return state==1?&tile:nullptr;
        auto &mesh=tile.mesh;
        if(!gather(w,x,z,16,0,WORLD_Y,epoch,mesh.v))return nullptr;
        connect_surface_column(w,x,z,mesh,tile.runs);
        if(tr_oom||terrain_build_epoch(&w)!=epoch){tile.release();return nullptr;}
        const size_t bytes=sizeof(Vertex)*mesh.v.cap+sizeof(u32)*mesh.i.cap+sizeof(SurfaceFaceRun)*tile.runs.cap;
        if(retained.fetch_add(bytes)+bytes>limit){
            retained.fetch_sub(bytes);tile.release();tile.state.store(2,std::memory_order_release);return nullptr;
        }
        int j=0;
        for(int col=0;col<256;++col){
            tile.offsets[col]=j;
            while(j<tile.runs.n&&tile.runs[j].column==col)++j;
        }
        tile.offsets[256]=j;
        ++connected_columns;tile.state.store(1,std::memory_order_release);return &tile;
    }
public:
    std::atomic<size_t> retained{0},built{0},mesh_reads{0},contact_reads{0},connected_columns{0},connected_contacts{0};
    SealedSurfaceColumns(int x,int z,int width,int depth){
        first_x=imx(0,x-1)&~15;first_z=imx(0,z-1)&~15;
        count_x=((x+width-1-first_x)>>4)+1;count_z=((z+depth-1-first_z)>>4)+1;
    }
    bool read(const World &w,int x,int z,int size,int bottom,int top,u32 epoch,List<Vertex> &out) override{
        if(!gather(w,x,z,size,bottom,top,epoch,out))return false;
        if(size==6)++contact_reads;else ++mesh_reads;
        return true;
    }
    bool read_mesh(const World &w,int x,int z,u32 epoch,Mesh &out) override{
        const auto *tile=topology(w,x,z,epoch);
        if(!tile)return false;
        const auto &m=tile->mesh;
        if(!out.v.reserve(m.v.n)||!out.i.reserve(m.i.n))return false;
        out.v.n=m.v.n;out.i.n=m.i.n;
        if(m.v.n)copy_bytes(out.v.p,m.v.p,sizeof(Vertex)*m.v.n);
        if(m.i.n)copy_bytes(out.i.p,m.i.p,sizeof(u32)*m.i.n);
        ++mesh_reads;return true;
    }
    // Preserve connector order by the lattice crossing that owns each face.
    // Triangle extents alone cannot separate opposite sides of a thin roof.
    // References stay local to the output packet, including ambiguous faces
    // with shared arc vertices and additional fan centres.
    bool read_contacts(const World &w,int x,int z,int bottom,int top,u32 epoch,Bytes &out) override{
        const int left=x&~15,north=z&~15,right=(x+5)&~15,south=(z+5)&~15;
        std::array<const ConnectedColumn*,4> tiles{};
        for(int tz=north;tz<=south;tz+=16)for(int tx=left;tx<=right;tx+=16){
            auto *t=topology(w,tx,tz,epoch);
            if(!t||t->mesh.v.n>0x3fffffff)return false;
            tiles[(tx-left)/16+2*((tz-north)/16)]=t;
        }
        List<V3> vertices;List<u32> indices;Map used;
        for(int cz=z;cz<z+6;++cz)for(int cx=x;cx<x+6;++cx){
            const int slot=((cx-left)>>4)+2*((cz-north)>>4),column=(cx&15)+16*(cz&15);
            const auto &tile=*tiles[slot];
            for(int j=tile.offsets[column];j<tile.offsets[column+1];++j){
                const auto &run=tile.runs[j];if(run.y>=top)break;if(run.y<bottom)continue;
                const int end=j+1<tile.runs.n?tile.runs[j+1].first:tile.mesh.i.n;
                for(int n=run.first;n<end;++n){
                    const auto v=tile.mesh.i[n];u32 key=(u32(slot)<<30)+v+1;
                    int id=used.get(key);
                    if(id<0){id=vertices.push(tile.mesh.v[v].p);used.put(key,id);}
                    indices.push(u32(id));
                    if(tr_oom)break;
                }
                if(tr_oom)break;
            }
        }
        bool ok=!tr_oom&&vertices.n<=4096&&indices.n<=24576&&terrain_build_epoch(&w)==epoch;
        if(ok){
            out.u(vertices.n);out.u(indices.n);
            if(vertices.n)out.raw(vertices.p,vertices.n*sizeof(V3));
            if(indices.n)out.raw(indices.p,indices.n*sizeof(u32));
            ++contact_reads;++connected_contacts;
        }
        used.release();indices.release();vertices.release();return ok&&!tr_oom;
    }
};
