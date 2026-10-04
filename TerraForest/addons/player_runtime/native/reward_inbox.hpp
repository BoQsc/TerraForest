// SPDX-License-Identifier: 0BSD
#pragma once
#include "inventory.hpp"
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <climits>

namespace terraforest {
using namespace godot;
// Main-thread mutations; pure byte validation may run on the save worker.
class NativeRewardInbox : public RefCounted {
    GDCLASS(NativeRewardInbox,RefCounted)
    struct Entry { int64_t item=0,count=0; };
    std::array<Entry,32> pending{};
    int64_t last_receipt=0;
    static constexpr int64_t LIMIT=1000000000000LL;
    static uint64_t read(const uint8_t *p,int n){uint64_t v=0;for(int i=0;i<n;++i)v|=uint64_t(p[i])<<(i*8);return v;}
    static void write(uint8_t *p,uint64_t v,int n){for(int i=0;i<n;++i)p[i]=uint8_t(v>>(i*8));}
    static Dictionary result(bool ok,const char *reason){Dictionary d;d["ok"]=ok;d["reason"]=reason;return d;}
protected:
    static void _bind_methods(){
        ClassDB::bind_method(D_METHOD("accept","items","receipt"),&NativeRewardInbox::accept);
        ClassDB::bind_method(D_METHOD("claim","inventory","items","expected_revision"),&NativeRewardInbox::claim);
        ClassDB::bind_method(D_METHOD("get_pending"),&NativeRewardInbox::get_pending);
        ClassDB::bind_method(D_METHOD("get_last_receipt"),&NativeRewardInbox::get_last_receipt);
        ClassDB::bind_method(D_METHOD("capture_storage_snapshot"),&NativeRewardInbox::capture_storage_snapshot);
        ClassDB::bind_method(D_METHOD("validate_snapshot","data"),&NativeRewardInbox::validate_snapshot);
        ClassDB::bind_method(D_METHOD("restore_storage_snapshot","data"),&NativeRewardInbox::restore_storage_snapshot);
    }
public:
    int64_t get_last_receipt() const{return last_receipt;}
    PackedInt64Array get_pending() const{
        PackedInt64Array out;for(auto e:pending)if(e.item){out.append(e.item);out.append(e.count);}return out;
    }
    Dictionary accept(const PackedInt64Array &items,int64_t receipt){
        if(receipt<=last_receipt)return result(false,"stale_receipt");
        if(items.is_empty()||items.size()>64||items.size()%2)return result(false,"invalid_items");
        auto staged=pending;
        for(int64_t i=0;i<items.size();i+=2){
            int64_t id=items[i],count=items[i+1];
            if(id<=0||id>INT32_MAX||count<=0||count>LIMIT)return result(false,"invalid_item_or_count");
            Entry *selected=nullptr;
            for(auto &e:staged)if(e.item==id){selected=&e;break;}
            if(!selected)for(auto &e:staged)if(!e.item){selected=&e;break;}
            if(!selected||count>LIMIT-selected->count)return result(false,"inbox_full");
            selected->item=id;selected->count+=count;
        }
        pending=staged;last_receipt=receipt;return result(true,"");
    }
    Dictionary claim(const Ref<NativePlayerInventory> &inventory,const PackedInt64Array &items,int64_t expected){
        if(inventory.is_null()||items.is_empty()||items.size()>64||items.size()%2)return result(false,"invalid_claim");
        auto staged=pending;
        for(int64_t i=0;i<items.size();i+=2){
            int64_t id=items[i],count=items[i+1];Entry *selected=nullptr;
            if(id<=0||count<=0)return result(false,"invalid_claim");
            for(auto &e:staged)if(e.item==id){selected=&e;break;}
            if(!selected||count>selected->count)return result(false,"insufficient_pending");
            selected->count-=count;if(!selected->count)selected->item=0;
        }
        // Native inventory emits no callbacks: commit the inbox only after its
        // all-or-nothing grant succeeds. Full inventory leaves rewards intact.
        Dictionary granted=inventory->grant_items(items,expected);
        if(bool(granted["ok"]))pending=staged;
        return granted;
    }
    PackedByteArray capture_storage_snapshot() const{
        PackedByteArray out;out.resize(400);auto *p=out.ptrw();
        write(p,0x31524654,4);write(p+4,32,4);write(p+8,last_receipt,8); // TFR1
        for(int i=0;i<32;++i){write(p+16+i*12,pending[i].item,4);write(p+20+i*12,pending[i].count,8);}return out;
    }
    bool validate_snapshot(const PackedByteArray &data) const{
        if(data.size()!=400)return false;const auto *p=data.ptr();
        if(read(p,4)!=0x31524654||read(p+4,4)!=32||read(p+8,8)>INT64_MAX)return false;
        for(int i=0;i<32;++i){
            uint64_t id=read(p+16+i*12,4),count=read(p+20+i*12,8);
            if(id>INT32_MAX||count>LIMIT||((id==0)!=(count==0))||(id&&read(p+8,8)==0))return false;
            if(id)for(int j=0;j<i;++j)if(read(p+16+j*12,4)==id)return false;
        }
        return true;
    }
    bool restore_storage_snapshot(const PackedByteArray &data){
        if(!validate_snapshot(data))return false;const auto *p=data.ptr();
        for(int i=0;i<32;++i)pending[i]={int64_t(read(p+16+i*12,4)),int64_t(read(p+20+i*12,8))};
        last_receipt=int64_t(read(p+8,8));return true;
    }
};
}
