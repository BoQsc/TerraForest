// SPDX-License-Identifier: 0BSD
#pragma once
#include "core.h"
#include <godot_cpp/classes/hashing_context.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <algorithm>
#include <vector>

namespace terraforest {
// Legacy build_patch dependencies, excluding sky visibility (always refreshed
// on reuse). A whole neighboring page is included for simplify's pin mask.
// No iteration over remote page storage, edit history or global block map.
static godot::Dictionary geometry_content_key(const World &w,int x,int z,int size,int step) {
    godot::Dictionary result;
    if(x<0||z<0||x>=2048||z>=2048||
       (size!=16&&size!=32&&size!=64&&size!=128&&size!=256)||
       (step!=1&&step!=2&&step!=4&&step!=8))return result;
    godot::Ref<godot::HashingContext> hash;hash.instantiate();
    if(hash->start(godot::HashingContext::HASH_SHA256)!=godot::OK)return result;
    int64_t bytes=0,lookups=0,pages=0,blocks=0,page_hash_bytes=0;
    bool ok=true;
    // Feed the identical byte stream in bounded blocks. Calling the Godot hash
    // API (and allocating a PackedByteArray) for every four-byte field made a
    // dependency lookup increasingly expensive as local pages accumulated.
    constexpr int capacity=65536;
    godot::PackedByteArray buffer;buffer.resize(capacity);
    int used=0;
    auto feed=[&](const void *data,int count){
        const auto *source=static_cast<const u8*>(data);bytes+=count;
        while(count){
            int amount=std::min(count,capacity-used);
            copy_bytes(buffer.ptrw()+used,source,amount);
            used+=amount;source+=amount;count-=amount;
            if(used==capacity){ok=ok&&hash->update(buffer)==godot::OK;used=0;}
        }
    };
    auto number=[&](u32 value){u8 b[4]={u8(value),u8(value>>8),u8(value>>16),u8(value>>24)};feed(b,4);};
    number(3);number(w.generator_id);number(w.seed);number(w.surface_style);number(x);number(z);number(size);number(step);
    number(w.caves.n);
    for(int i=0;i<w.caves.n;i++){
        const Cave &c=w.caves[i];float values[]={c.a.x,c.a.y,c.a.z,c.b.x,c.b.y,c.b.z,c.r};
        feed(values,sizeof(values));
    }
    constexpr int np=WORLD/PAGE+1;
    const int x0=std::max(0,(x-1)/PAGE-1),z0=std::max(0,(z-1)/PAGE-1);
    const int x1=std::min(np-1,(x+size)/PAGE+1),z1=std::min(np-1,(z+size)/PAGE+1);
    for(int pz=z0;pz<=z1;pz++)for(int px=x0;px<=x1;px++){
        number(w.edit_columns[px+np*pz]);
        for(int py=0;py<=WORLD_Y/PAGE;py++){
            u32 key=1+u32(px+np*(pz+np*py));int at=w.pages_by_key.get(key);lookups++;
            number(key);number(at>=0?1:0);
            if(at>=0){
                const Page &p=w.pages[at];
                if(!p.geometry_digest_valid){
                    godot::Ref<godot::HashingContext> page_hash;page_hash.instantiate();
                    godot::PackedByteArray samples;samples.resize(PAGE_SAMPLES*3);
                    copy_bytes(samples.ptrw(),p.d,PAGE_SAMPLES*sizeof(i16));
                    copy_bytes(samples.ptrw()+PAGE_SAMPLES*sizeof(i16),p.mat,PAGE_SAMPLES);
                    if(page_hash->start(godot::HashingContext::HASH_SHA256)!=godot::OK||page_hash->update(samples)!=godot::OK)return {};
                    const auto digest=page_hash->finish();if(digest.size()!=32)return {};
                    copy_bytes(p.geometry_digest,digest.ptr(),32);p.geometry_digest_valid=true;
                    page_hash_bytes+=samples.size();
                }
                feed(p.geometry_digest,32);pages++;
            }
        }
    }
    // Only adjacent 32m block columns are inspected, in canonical key order.
    std::vector<u32> keys;
    for(int cz=std::max(0,(z-1)/32);cz<=std::min(63,(z+size)/32);cz++)
      for(int cx=std::max(0,(x-1)/32);cx<=std::min(63,(x+size)/32);cx++){
        const auto &column=w.block_columns[cx+64*cz];
        for(int i=0;i<column.n;i++){
            const u32 key=column[i],raw=key-1;int bx=raw&2047,bz=(raw>>11)&2047;
            if(bx>=x-1&&bx<=x+size&&bz>=z-1&&bz<=z+size)keys.push_back(key);
        }
    }
    std::sort(keys.begin(),keys.end());number(u32(keys.size()));
    for(u32 key:keys){number(key);number(w.blocks.get(key));blocks++;}
    if(used){buffer.resize(used);ok=ok&&hash->update(buffer)==godot::OK;}
    if(!ok)return {};
    result["key"]=hash->finish().hex_encode();result["page_lookups"]=lookups;
    result["pages"]=pages;result["blocks"]=blocks;result["hashed_bytes"]=bytes;
    result["page_hash_bytes"]=page_hash_bytes;
    return result;
}
}
