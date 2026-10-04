// SPDX-License-Identifier: 0BSD
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <set>
namespace terraforest {
using namespace godot;
// Main-thread state; validate_snapshot is pure and safe on the archive worker.
// Stable generator IDs are tombstones, independent of resident render cells.
class NativeHarvestState : public RefCounted {
    GDCLASS(NativeHarvestState,RefCounted)
    std::set<int64_t> removed;
    mutable PackedByteArray snapshot_cache;
    mutable bool snapshot_dirty=true;
    static constexpr size_t LIMIT=262144;
    static uint64_t read(const uint8_t *p){uint64_t v=0;for(int i=0;i<8;++i)v|=uint64_t(p[i])<<(8*i);return v;}
    static void write(uint8_t *p,uint64_t v){for(int i=0;i<8;++i)p[i]=uint8_t(v>>(8*i));}
protected:
    static void _bind_methods(){
        ClassDB::bind_method(D_METHOD("contains","id"),&NativeHarvestState::contains);
        ClassDB::bind_method(D_METHOD("mark","id"),&NativeHarvestState::mark);
        ClassDB::bind_method(D_METHOD("unmark","id"),&NativeHarvestState::unmark);
        ClassDB::bind_method(D_METHOD("mask","ids"),&NativeHarvestState::mask);
        ClassDB::bind_method(D_METHOD("capture_storage_snapshot"),&NativeHarvestState::capture_storage_snapshot);
        ClassDB::bind_method(D_METHOD("validate_snapshot","data"),&NativeHarvestState::validate_snapshot);
        ClassDB::bind_method(D_METHOD("restore_storage_snapshot","data"),&NativeHarvestState::restore_storage_snapshot);
    }
public:
    bool contains(int64_t id) const{return removed.count(id)!=0;}
    bool mark(int64_t id){
        if(id<=0||contains(id)||removed.size()>=LIMIT)return false;
        const bool inserted=removed.insert(id).second;
        if(inserted)snapshot_dirty=true;
        return inserted;
    }
    bool unmark(int64_t id){const bool erased=removed.erase(id)!=0;if(erased)snapshot_dirty=true;return erased;}
    PackedByteArray mask(const PackedInt64Array &ids) const{
        PackedByteArray out;if(ids.size()>4096)return out;
        out.resize(ids.size());for(int64_t i=0;i<ids.size();++i)out.set(i,contains(ids[i])?1:0);return out;
    }
    PackedByteArray capture_storage_snapshot() const{
        // PackedByteArray shares immutable storage until a caller writes to it.
        // Main-thread capture alone owns this cache; worker validation is pure.
        if(!snapshot_dirty)return snapshot_cache;
        PackedByteArray out;out.resize(16+removed.size()*8);auto *p=out.ptrw();
        write(p,0x3154534556524148ULL);write(p+8,removed.size()); // HARVEST1
        size_t i=0;for(auto id:removed)write(p+16+(i++)*8,id);
        snapshot_cache=out;snapshot_dirty=false;return snapshot_cache;
    }
    bool validate_snapshot(const PackedByteArray &data) const{
        if(data.size()<16||data.size()>int64_t(16+LIMIT*8))return false;
        const auto *p=data.ptr();const uint64_t count=read(p+8);
        if(read(p)!=0x3154534556524148ULL||count>LIMIT||data.size()!=int64_t(16+count*8))return false;
        uint64_t previous=0;
        for(uint64_t i=0;i<count;++i){const auto id=read(p+16+i*8);if(id<=previous||id>INT64_MAX)return false;previous=id;}
        return true;
    }
    bool restore_storage_snapshot(const PackedByteArray &data){
        if(!validate_snapshot(data))return false;
        std::set<int64_t> staged;const auto *p=data.ptr();const auto count=read(p+8);
        for(uint64_t i=0;i<count;++i)staged.insert(int64_t(read(p+16+i*8)));
        removed.swap(staged);snapshot_cache=data;snapshot_dirty=false;return true;
    }
};
}
