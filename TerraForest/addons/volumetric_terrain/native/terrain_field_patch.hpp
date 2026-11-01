// SPDX-License-Identifier: 0BSD
#pragma once
#include "core.h"
#include <array>
#include <climits>

namespace terraforest {
struct FieldPatchBounds {
    int x=0,y=0,z=0,width=0,height=0,depth=0;
    bool valid() const {
        return width>0&&width<=128&&height>0&&height<=128&&depth>0&&depth<=128&&
            x>=1&&x<=WORLD-width&&y>=4&&y<=255-height&&z>=1&&z<=WORLD-depth&&
            int64_t(width)*height*depth<=1048576;
    }
    int samples() const {return width*height*depth;}
    V3 minimum() const {return {float(x),float(y),float(z)};}
    V3 maximum() const {return {float(x+width-1),float(y+height-1),float(z+depth-1)};}
};
struct FieldPatchResult {int changes=0;V3 minimum{},maximum{};};
constexpr int FIELD_PATCH_HEADER=44;
constexpr int FIELD_PATCH_LIMIT=FIELD_PATCH_HEADER+1048576*3+4;
constexpr u32 FIELD_PATCH_MAGIC=0x31504654;
inline u32 field_patch_checksum(const u8 *data,int length){
    u32 result=2166136261u;
    for(int index=0;index<length;++index){result^=data[index];result*=16777619u;}
    return result;
}
inline i16 field_patch_quantize(float value){
    value=clampf(value,-SDF_BAND,SDF_BAND)*SDF_SCALE;
    return i16(value>=0?value+.5f:value-.5f);
}
inline u32 field_patch_page_key(int x,int y,int z){return 1+u32(x+WORLD_PAGE_COLUMNS*(z+WORLD_PAGE_COLUMNS*y));}
inline int field_patch_sample_offset(const FieldPatchBounds &bounds,int x,int y,int z){
    return FIELD_PATCH_HEADER+3*((x-bounds.x)+bounds.width*((z-bounds.z)+bounds.depth*(y-bounds.y)));
}
inline i16 field_patch_density(const u8 *data){return i16(u16(data[0])|(u16(data[1])<<8));}
class FieldPatchPagePin {
    World &world_;
    bool previous_;
    V3 minimum_,maximum_;
public:
    FieldPatchPagePin(World &world,V3 minimum,V3 maximum):world_(world),previous_(world.pages_pinned),minimum_(world.pin_lo),maximum_(world.pin_hi){
        world_.pages_pinned=true;world_.pin_lo=minimum;world_.pin_hi=maximum;
    }
    ~FieldPatchPagePin(){world_.pages_pinned=previous_;world_.pin_lo=minimum_;world_.pin_hi=maximum_;}
};
inline bool validate_field_patch(const u8 *data,int length,FieldPatchBounds &bounds,int &seed,u32 &generator){
    if(!data||length<FIELD_PATCH_HEADER+7||length>FIELD_PATCH_LIMIT)return false;
    Reader reader{data,length};
    if(reader.u()!=FIELD_PATCH_MAGIC||reader.u()!=1)return false;
    seed=int32_t(reader.u());generator=reader.u();
    bounds.x=int32_t(reader.u());bounds.y=int32_t(reader.u());bounds.z=int32_t(reader.u());
    bounds.width=int32_t(reader.u());bounds.height=int32_t(reader.u());bounds.depth=int32_t(reader.u());
    const u32 count=reader.u();
    if(!bounds.valid()||generator<1||generator>MAX_GENERATOR_ID||count!=u32(bounds.samples())||
        length!=FIELD_PATCH_HEADER+int(count)*3+4)return false;
    Reader tail{data,length,length-4};
    if(tail.u()!=field_patch_checksum(data,length-4))return false;
    for(int offset=FIELD_PATCH_HEADER;offset<length-4;offset+=3){
        const int density=field_patch_density(data+offset);
        if(density<-4096||density>4096||data[offset+2]>15)return false;
    }
    return true;
}
inline bool capture_field_patch(World &world,const FieldPatchBounds &bounds,Bytes &output){
    if(!bounds.valid()||!world.edit_columns)return false;
    Bytes staged;
    const int length=FIELD_PATCH_HEADER+3*bounds.samples()+4;
    if(!staged.reserve(length))return false;
    staged.u(FIELD_PATCH_MAGIC);staged.u(1);staged.u(u32(world.seed));staged.u(world.generator_id);
    staged.u(bounds.x);staged.u(bounds.y);staged.u(bounds.z);
    staged.u(bounds.width);staged.u(bounds.height);staged.u(bounds.depth);staged.u(bounds.samples());
    staged.resize(length-4);
    FieldPatchPagePin pin(world,bounds.minimum(),bounds.maximum());
    if(!world.prepare_pages(bounds.minimum(),bounds.maximum())){staged.release();return false;}
    for(int z=bounds.z;z<bounds.z+bounds.depth;++z)for(int x=bounds.x;x<bounds.x+bounds.width;++x){
        float height=0;bool height_ready=false;
        for(int y=bounds.y;y<bounds.y+bounds.height;++y){
            const int page_index=world.pages_by_key.get(field_patch_page_key(x>>4,y>>4,z>>4));
            i16 density;u8 material;
            if(page_index>=0){
                const Page &page=world.pages[page_index];
                const int sample=(x&15)+16*((z&15)+16*(y&15));
                density=page.d[sample];material=page.mat[sample];
            }else{
                if(!height_ready){height=world.height(float(x),float(z));height_ready=true;}
                const V3 point{float(x),float(y),float(z)};
                density=field_patch_quantize(world.base(point,height));material=world.base_material(point,height);
            }
            const int offset=field_patch_sample_offset(bounds,x,y,z);
            staged.p[offset]=u8(density);staged.p[offset+1]=u8(u16(density)>>8);staged.p[offset+2]=material;
        }
    }
    if(tr_oom){staged.release();return false;}
    staged.u(field_patch_checksum(staged.p,staged.n));
    output.release();output=staged;
    return true;
}
inline bool restore_field_patch(World &world,const u8 *data,int length,int expected_revision,FieldPatchResult &result){
    result={};FieldPatchBounds bounds;int seed=0;u32 generator=0;
    if(!validate_field_patch(data,length,bounds,seed,generator)||!world.edit_columns||seed!=world.seed||generator!=world.generator_id||
        expected_revision<0||world.revision!=expected_revision||world.revision==INT_MAX||world.edits==INT_MAX||world.storage_serial==UINT64_MAX)return false;
    FieldPatchPagePin pin(world,bounds.minimum(),bounds.maximum());
    if(!world.prepare_pages(bounds.minimum(),bounds.maximum()))return false;
    struct PatchPage {int index=-1;bool changed=false;};
    std::array<PatchPage,729> pages;
    const int page_x=bounds.x>>4,page_y=bounds.y>>4,page_z=bounds.z>>4;
    const int columns=((bounds.x+bounds.width-1)>>4)-page_x+1;
    const int rows=((bounds.z+bounds.depth-1)>>4)-page_z+1;
    const int levels=((bounds.y+bounds.height-1)>>4)-page_y+1;
    auto slot=[&](int x,int y,int z){return ((x>>4)-page_x)+columns*(((z>>4)-page_z)+rows*((y>>4)-page_y));};
    for(int y=0;y<levels;++y)for(int z=0;z<rows;++z)for(int x=0;x<columns;++x)
        pages[x+columns*(z+rows*y)].index=world.pages_by_key.get(field_patch_page_key(x+page_x,y+page_y,z+page_z));
    int changes=0,needed=0;
    for(int z=bounds.z;z<bounds.z+bounds.depth;++z)for(int x=bounds.x;x<bounds.x+bounds.width;++x){
        float height=0;bool height_ready=false;
        for(int y=bounds.y;y<bounds.y+bounds.height;++y){
            auto &entry=pages[slot(x,y,z)];
            i16 density;u8 material;
            if(entry.index>=0){
                const auto &page=world.pages[entry.index];const int sample=(x&15)+16*((z&15)+16*(y&15));
                density=page.d[sample];material=page.mat[sample];
            }else{
                if(!height_ready){height=world.height(float(x),float(z));height_ready=true;}
                const V3 point{float(x),float(y),float(z)};
                density=field_patch_quantize(world.base(point,height));material=world.base_material(point,height);
            }
            const int offset=field_patch_sample_offset(bounds,x,y,z);
            if(density!=field_patch_density(data+offset)||material!=data[offset+2]){
                if(!entry.changed&&entry.index<0)++needed;
                entry.changed=true;++changes;
            }
        }
    }
    if(tr_oom)return false;
    result.minimum=bounds.minimum();result.maximum=bounds.maximum();
    if(!changes)return true;
    const int original_pages=world.pages.n;
    if(original_pages+needed>(world.page_access?MAX_AUTHORED_PAGES:MAX_PAGES))return false;
    if(needed){
        if(!world.pages.reserve(original_pages+needed))return false;
        int capacity=world.pages_by_key.cap?world.pages_by_key.cap:64;
        while((world.pages_by_key.n+needed+1)*10>=capacity*7)capacity*=2;
        if(capacity!=world.pages_by_key.cap||(world.pages_by_key.used+needed+1)*10>=capacity*7)world.pages_by_key.rehash(capacity);
        if(tr_oom)return false;
        bool admitted=true;
        for(int y=0;y<levels&&admitted;++y)for(int z=0;z<rows&&admitted;++z)for(int x=0;x<columns&&admitted;++x){
            auto &entry=pages[x+columns*(z+rows*y)];
            if(!entry.changed||entry.index>=0)continue;
            if(!world.ensure(x+page_x,y+page_y,z+page_z)||tr_oom){admitted=false;break;}
            entry.index=world.pages.n-1;
        }
        if(!admitted){
            for(int index=world.pages.n-1;index>=original_pages;--index){
                auto &page=world.pages[index];u32 coordinate=page.key-1;
                const int x=coordinate%WORLD_PAGE_COLUMNS;coordinate/=WORLD_PAGE_COLUMNS;
                const int z=coordinate%WORLD_PAGE_COLUMNS,y=coordinate/WORLD_PAGE_COLUMNS;
                world.pages_by_key.erase(page.key);world.edit_columns[x+WORLD_PAGE_COLUMNS*z]&=~(1u<<y);
                if(world.page_access)world.page_access->removed(world,index);
                tr_free(page.d);tr_free(page.mat);
            }
            world.pages.n=original_pages;return false;
        }
    }
    ++world.storage_serial;
    for(int y=bounds.y;y<bounds.y+bounds.height;++y)for(int z=bounds.z;z<bounds.z+bounds.depth;++z)for(int x=bounds.x;x<bounds.x+bounds.width;++x){
        const auto &entry=pages[slot(x,y,z)];if(!entry.changed)continue;
        auto &page=world.pages[entry.index];const int sample=(x&15)+16*((z&15)+16*(y&15));
        const int offset=field_patch_sample_offset(bounds,x,y,z);
        page.d[sample]=field_patch_density(data+offset);page.mat[sample]=data[offset+2];
        page.storage_version=world.storage_serial;page.geometry_digest_valid=false;
    }
    ++world.revision;++world.edits;world.changed_samples+=changes;world.lighting_revision=-1;
    invalidate_geometry_cache(world,bounds.minimum(),bounds.maximum());
    result.changes=changes;return true;
}
}
