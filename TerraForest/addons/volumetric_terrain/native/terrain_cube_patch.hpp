// SPDX-License-Identifier: 0BSD
#pragma once
#include "core.h"
#include <array>
#include <climits>

namespace terraforest {
struct CubePatchBounds {
    int x=0,y=0,z=0,width=0,height=0,depth=0;
    bool valid() const {
        return width>0&&width<=128&&height>0&&height<=128&&depth>0&&depth<=128&&
            x>=0&&x<=WORLD-width&&y>=1&&y<=255-height&&z>=0&&z<=WORLD-depth&&
            int64_t(width)*height*depth<=262144;
    }
    int cells() const {return width*height*depth;}
    bool contains(u32 key) const {
        const u32 packed=key-1;
        const int cell_x=packed&2047,cell_z=(packed>>11)&2047,cell_y=(packed>>22)&511;
        return cell_x>=x&&cell_x<x+width&&cell_y>=y&&cell_y<y+height&&cell_z>=z&&cell_z<z+depth;
    }
};
struct CubePatchResult {int changes=0;V3 minimum{},maximum{};};
constexpr int CUBE_PATCH_HEADER=44;
constexpr int CUBE_PATCH_LIMIT=CUBE_PATCH_HEADER+262144+4;
constexpr u32 CUBE_PATCH_MAGIC=0x31504354;
inline u32 cube_patch_key(int x,int y,int z){return 1+u32(x|(z<<11)|(y<<22));}
inline u32 cube_patch_checksum(const u8 *data,int length){
    u32 result=2166136261u;
    for(int index=0;index<length;++index){result^=data[index];result*=16777619u;}
    return result;
}
inline bool validate_cube_patch(const u8 *data,int length,CubePatchBounds &bounds,int &seed,u32 &generator){
    if(!data||length<CUBE_PATCH_HEADER+5||length>CUBE_PATCH_LIMIT)return false;
    Reader reader{data,length};
    if(reader.u()!=CUBE_PATCH_MAGIC||reader.u()!=1)return false;
    seed=int32_t(reader.u());generator=reader.u();
    bounds.x=int32_t(reader.u());bounds.y=int32_t(reader.u());bounds.z=int32_t(reader.u());
    bounds.width=int32_t(reader.u());bounds.height=int32_t(reader.u());bounds.depth=int32_t(reader.u());
    const u32 count=reader.u();
    if(!bounds.valid()||generator<1||generator>MAX_GENERATOR_ID||count!=u32(bounds.cells())||
        length!=CUBE_PATCH_HEADER+int(count)+4)return false;
    Reader tail{data,length,length-4};
    if(tail.u()!=cube_patch_checksum(data,length-4))return false;
    for(int offset=CUBE_PATCH_HEADER;offset<length-4;++offset)if(data[offset]>3)return false;
    return true;
}
inline bool capture_cube_patch(const World &world,const CubePatchBounds &bounds,Bytes &output){
    if(!bounds.valid()||!world.edit_columns||world.block_columns.n!=4096||tr_oom)return false;
    Bytes staged;const int length=CUBE_PATCH_HEADER+bounds.cells()+4;
    if(!staged.reserve(length))return false;
    staged.u(CUBE_PATCH_MAGIC);staged.u(1);staged.u(u32(world.seed));staged.u(world.generator_id);
    staged.u(bounds.x);staged.u(bounds.y);staged.u(bounds.z);
    staged.u(bounds.width);staged.u(bounds.height);staged.u(bounds.depth);staged.u(bounds.cells());
    for(int y=bounds.y;y<bounds.y+bounds.height;++y)for(int z=bounds.z;z<bounds.z+bounds.depth;++z)for(int x=bounds.x;x<bounds.x+bounds.width;++x){
        const int material=world.blocks.get(cube_patch_key(x,y,z));
        if(material==0||material>3){staged.release();return false;}
        staged.push(u8(material<0?0:material));
    }
    staged.u(cube_patch_checksum(staged.p,staged.n));
    output.release();output=staged;return true;
}
inline bool restore_cube_patch(World &world,const u8 *data,int length,int expected_revision,CubePatchResult &result){
    result={};CubePatchBounds bounds;int seed=0;u32 generator=0;
    if(tr_oom||!validate_cube_patch(data,length,bounds,seed,generator)||!world.edit_columns||world.block_columns.n!=4096||
        seed!=world.seed||generator!=world.generator_id||expected_revision<0||world.revision!=expected_revision||
        world.revision==INT_MAX||world.edits==INT_MAX)return false;
    const int first_x=bounds.x>>5,first_z=bounds.z>>5;
    const int columns=((bounds.x+bounds.width-1)>>5)-first_x+1;
    const int rows=((bounds.z+bounds.depth-1)>>5)-first_z+1;
    std::array<int,25> additions{};
    int changed=0,insertions=0,removals=0,offset=CUBE_PATCH_HEADER;
    for(int y=bounds.y;y<bounds.y+bounds.height;++y)for(int z=bounds.z;z<bounds.z+bounds.depth;++z)for(int x=bounds.x;x<bounds.x+bounds.width;++x){
        const int previous=world.blocks.get(cube_patch_key(x,y,z)),material=data[offset++];
        if((previous<0?0:previous)==material)continue;
        ++changed;
        if(material&&previous<0){++insertions;++additions[((x>>5)-first_x)+columns*((z>>5)-first_z)];}
        else if(!material)++removals;
    }
    if(world.blocks.n-removals+insertions>2000000)return false;
    result.minimum={float(bounds.x),float(bounds.y),float(bounds.z)};
    result.maximum={float(bounds.x+bounds.width),float(bounds.y+bounds.height),float(bounds.z+bounds.depth)};
    if(!changed)return true;
    for(int row=0;row<rows;++row)for(int column=0;column<columns;++column){
        auto &keys=world.block_columns[(first_x+column)+64*(first_z+row)];
        if(!keys.reserve(keys.n+additions[column+columns*row]))return false;
    }
    if(insertions||(changed-removals)>0){
        int capacity=world.blocks.cap?world.blocks.cap:64;
        if(int64_t(world.blocks.used+insertions+1)*10>=int64_t(capacity)*7||!world.blocks.cap){
            while(int64_t(world.blocks.n+insertions+1)*10>=int64_t(capacity)*7)capacity*=2;
            world.blocks.rehash(capacity);
            if(tr_oom)return false;
        }
    }
    offset=CUBE_PATCH_HEADER;
    for(int y=bounds.y;y<bounds.y+bounds.height;++y)for(int z=bounds.z;z<bounds.z+bounds.depth;++z)for(int x=bounds.x;x<bounds.x+bounds.width;++x){
        const u32 key=cube_patch_key(x,y,z);const int previous=world.blocks.get(key),material=data[offset++];
        if((previous<0?0:previous)==material)continue;
        if(material){
            world.blocks.put(key,material);
            if(previous<0)world.block_columns[(x>>5)+64*(z>>5)].push(key);
        }else world.blocks.erase(key);
    }
    if(removals)for(int row=0;row<rows;++row)for(int column=0;column<columns;++column){
        auto &keys=world.block_columns[(first_x+column)+64*(first_z+row)];int kept=0;
        for(int index=0;index<keys.n;++index){const u32 key=keys[index];if(!bounds.contains(key)||world.blocks.get(key)>=0)keys[kept++]=key;}
        keys.n=kept;
    }
    ++world.revision;++world.edits;world.lighting_revision=-1;
    invalidate_geometry_cache(world,result.minimum,result.maximum);
    result.changes=changed;return true;
}
}
