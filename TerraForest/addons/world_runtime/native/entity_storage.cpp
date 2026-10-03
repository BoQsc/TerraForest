// SPDX-License-Identifier: 0BSD
#include "entity_store.hpp"
#include <godot_cpp/classes/ref.hpp>
#include <cmath>
#include <cstring>
#include <utility>
#include <unordered_set>
using namespace godot;
namespace terraforest {
namespace {
uint32_t read32(const uint8_t *p) {
    return uint32_t(p[0]) | (uint32_t(p[1])<<8) | (uint32_t(p[2])<<16) | (uint32_t(p[3])<<24);
}
void write32(uint8_t *p, uint32_t value) {
    for (int i=0;i<4;++i) p[i]=uint8_t(value>>(8*i));
}
uint64_t read64(const uint8_t *p) { return read32(p)|(uint64_t(read32(p+4))<<32); }
void write64(uint8_t *p,uint64_t value) {write32(p,uint32_t(value));write32(p+4,uint32_t(value>>32));}
float read_float(const uint8_t *p) {
    uint32_t bits=read32(p); float value; std::memcpy(&value,&bits,4); return value;
}
void write_float(uint8_t *p,float value) {
    uint32_t bits;std::memcpy(&bits,&value,4);write32(p,bits);
}
}
PackedByteArray NativeEntityStore::capture_storage_snapshot() const {
    PackedByteArray data;
    if (!capacity_) return data;
    data.resize(24+int64_t(count_)*32);
    uint8_t *p=data.ptrw();
    write32(p,0x31454654);write32(p+4,2);write32(p+8,capacity_);write32(p+12,count_);
    write64(p+16,next_persistent_id_);
    for(uint32_t i=0;i<count_;++i) {
        const Slot &slot=slots_[dense_[i]];
        write64(p+24+i*32,slot.persistent_id);
        for(int axis=0;axis<3;++axis) {
            write_float(p+32+i*32+axis*4,slot.position[axis]);
            write_float(p+44+i*32+axis*4,slot.velocity[axis]);
        }
    }
    return data;
}
bool NativeEntityStore::validate_snapshot(const PackedByteArray &data) const {
    // Worker-safe: only examines the immutable input, never mutable store state.
    if(data.size()<16)return false;
    const uint8_t *p=data.ptr();
    uint32_t capacity=read32(p+8),count=read32(p+12);
    const uint32_t version=read32(p+4);
    if(read32(p)!=0x31454654||(version!=1&&version!=2)||capacity<1||capacity>262144||count>capacity||
       data.size()!=(version==1?16:24)+int64_t(count)*(version==1?24:32))return false;
    uint64_t cursor=version==1?uint64_t(count)+1:read64(p+16);
    if(cursor<1||cursor>0x8000000000000000ULL)return false;
    std::unordered_set<uint64_t> identities;
    for(uint32_t i=0;i<count;++i) {
        const uint8_t *row=p+(version==1?16:24)+i*(version==1?24:32);
        if(version==2) {
            const uint64_t id=read64(row);
            if(id==0||id>=cursor||!identities.insert(id).second)return false;
            row+=8;
        }
        for(int axis=0;axis<6;++axis)if(!std::isfinite(read_float(row+axis*4)))return false;
    }
    return true;
}
bool NativeEntityStore::restore_storage_snapshot(const PackedByteArray &data) {
    if(!validate_snapshot(data))return false;
    const uint8_t *p=data.ptr();const uint32_t count=read32(p+12);
    if(uint64_t(next_generation_)+count>0x80000000ULL)return false;
    // Stage pool and index before replacing the live state. Runtime handles are
    // deliberately not serialized: restored slots receive unused generations.
    Ref<NativeEntityStore> staged;staged.instantiate();
    if(!staged->configure(read32(p+8)))return false;
    staged->next_generation_=next_generation_;
    const bool legacy=read32(p+4)==1;
    staged->next_persistent_id_=legacy?uint64_t(count)+1:read64(p+16);
    for(uint32_t i=0;i<count;++i) {
        const uint8_t *row=p+(legacy?16:24)+i*(legacy?24:32);
        uint64_t identity=legacy?uint64_t(i)+1:read64(row);
        if(!legacy)row+=8;
        staged->spawn_unchecked(Vector3(read_float(row),read_float(row+4),read_float(row+8)),
                                Vector3(read_float(row+12),read_float(row+16),read_float(row+20)),identity);
    }
    slots_.swap(staged->slots_);dense_.swap(staged->dense_);free_.swap(staged->free_);
    moving_.swap(staged->moving_);moving_count_=staged->moving_count_;last_step_visited_=0;
    cell_heads_.swap(staged->cell_heads_);
    identity_slots_.swap(staged->identity_slots_);
    next_persistent_id_=staged->next_persistent_id_;
    capacity_=staged->capacity_;count_=staged->count_;free_count_=staged->free_count_;
    next_generation_=staged->next_generation_;ticks_=0;
    return true;
}
}
