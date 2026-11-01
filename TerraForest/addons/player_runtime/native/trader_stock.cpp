#include "trader_stock.hpp"
#include <godot_cpp/core/class_db.hpp>

namespace terraforest {
using namespace godot;
void NativeTraderStock::_bind_methods() {
    ClassDB::bind_method(D_METHOD("configure","stock","legacy_additions"),&NativeTraderStock::configure);
    ClassDB::bind_method(D_METHOD("flush_pending"),&NativeTraderStock::flush_pending);
    ClassDB::bind_method(D_METHOD("capture_storage_snapshot"),&NativeTraderStock::capture_storage_snapshot);
    ClassDB::bind_method(D_METHOD("validate_snapshot","data"),&NativeTraderStock::validate_snapshot);
    ClassDB::bind_method(D_METHOD("restore_storage_snapshot","data"),&NativeTraderStock::restore_storage_snapshot);
}
int64_t NativeTraderStock::index_of(int64_t identity) const {
    for(int64_t index=0;index<count;++index)if(identities[index]==identity)return index;
    return -1;
}
bool NativeTraderStock::configure(const Ref<NativePlayerInventory> &stock,const PackedInt64Array &legacy_additions) {
    if(inventory.is_valid()||stock.is_null()||legacy_additions.is_empty()||legacy_additions.size()>64||legacy_additions.size()%2)return false;
    int64_t previous=0;
    for(int64_t index=0;index<legacy_additions.size();index+=2) {
        auto limit=stock->catalog().find(legacy_additions[index]);
        if(legacy_additions[index]<=previous||limit==stock->catalog().end()||stock->max_durability(legacy_additions[index])||legacy_additions[index+1]<=0||legacy_additions[index+1]>limit->second)return false;
        previous=legacy_additions[index];
    }
    inventory=stock;count=legacy_additions.size()/2;
    for(int64_t index=0;index<count;++index){identities[index]=legacy_additions[index*2];amounts[index]=legacy_additions[index*2+1];}
    return true;
}
bool NativeTraderStock::flush_pending() {
    if(inventory.is_null())return false;
    bool changed=false;
    for(int64_t index=0;index<count;++index)if(pending[index]) {
        Dictionary granted=inventory->grant(identities[index],pending[index],inventory->revision);
        if(bool(granted["ok"])) {pending[index]=0;changed=true;}
    }
    return changed;
}
PackedByteArray NativeTraderStock::capture_storage_snapshot() const {
    if(inventory.is_null())return PackedByteArray();
    PackedByteArray stock=inventory->capture_storage_snapshot();int64_t queued=0;
    for(int64_t index=0;index<count;++index)if(pending[index])++queued;
    PackedByteArray data;data.resize(16+stock.size()+queued*8);
    data.encode_u32(0,0x53544654);data.encode_u32(4,1);data.encode_u32(8,stock.size());data.encode_u32(12,queued);
    for(int64_t index=0;index<stock.size();++index)data.set(16+index,stock[index]);
    int64_t offset=16+stock.size();
    for(int64_t index=0;index<count;++index)if(pending[index]){data.encode_u32(offset,identities[index]);data.encode_u32(offset+4,pending[index]);offset+=8;}
    return data;
}
bool NativeTraderStock::validate_snapshot(const PackedByteArray &data) const {
    if(inventory.is_null())return false;
    if(inventory->validate_snapshot(data))return true;
    if(data.size()<280||data.size()>792||data.decode_u32(0)!=0x53544654||data.decode_u32(4)!=1)return false;
    const int64_t bytes=data.decode_u32(8),queued=data.decode_u32(12);
    if((bytes!=264&&bytes!=392&&bytes!=520)||queued>count||data.size()!=16+bytes+queued*8||!inventory->validate_snapshot(data.slice(16,16+bytes)))return false;
    int64_t previous=0;
    for(int64_t offset=16+bytes;offset<data.size();offset+=8) {
        const int64_t identity=data.decode_u32(offset),quantity=data.decode_u32(offset+4),index=index_of(identity);
        if(identity<=previous||index<0||quantity<=0||quantity>amounts[index])return false;
        previous=identity;
    }
    return true;
}
bool NativeTraderStock::restore_storage_snapshot(const PackedByteArray &data) {
    if(!validate_snapshot(data))return false;
    pending.fill(0);
    if(inventory->validate_snapshot(data)) {
        inventory->restore_storage_snapshot(data);
        for(int64_t index=0;index<count;++index) {
            bool present=false;
            for(const auto &slot:inventory->slots)present=present||slot.item==identities[index];
            if(!present)pending[index]=amounts[index];
        }
        flush_pending();
    } else {
        const int64_t bytes=data.decode_u32(8);
        inventory->restore_storage_snapshot(data.slice(16,16+bytes));
        for(int64_t offset=16+bytes;offset<data.size();offset+=8)pending[index_of(data.decode_u32(offset))]=data.decode_u32(offset+4);
    }
    return true;
}
}
