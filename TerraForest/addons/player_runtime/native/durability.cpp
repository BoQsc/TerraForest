// SPDX-License-Identifier: 0BSD
#include "durability.hpp"
#include "inventory.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <algorithm>
#include <cstring>
namespace terraforest {
using namespace godot;
void NativeWorldDurability::_bind_methods(){
    ClassDB::bind_method(D_METHOD("hit","key","maximum","amount"),&NativeWorldDurability::hit);
    ClassDB::bind_method(D_METHOD("preview_harvest","key","maximum","amount","damage_per_item","finishing_bonus"),&NativeWorldDurability::preview_harvest);
    ClassDB::bind_method(D_METHOD("harvest_hit","key","maximum","amount","item","damage_per_item","finishing_bonus","inventory","expected_revision"),&NativeWorldDurability::harvest_hit);
    ClassDB::bind_method(D_METHOD("repair","key","maximum","amount"),&NativeWorldDurability::repair);
    ClassDB::bind_method(D_METHOD("damage","key","maximum"),&NativeWorldDurability::damage);
    ClassDB::bind_method(D_METHOD("forget","key"),&NativeWorldDurability::forget);
    ClassDB::bind_method(D_METHOD("record_count"),&NativeWorldDurability::record_count);
    ClassDB::bind_method(D_METHOD("capture_storage_snapshot"),&NativeWorldDurability::capture_storage_snapshot);
    ClassDB::bind_method(D_METHOD("validate_snapshot","data"),&NativeWorldDurability::validate_snapshot);
    ClassDB::bind_method(D_METHOD("restore_storage_snapshot","data"),&NativeWorldDurability::restore_storage_snapshot);
}
static bool valid(const std::string &s){if(s.empty()||s.size()>160)return false;for(unsigned char c:s)if(c<32||c>126)return false;return true;}
Dictionary NativeWorldDurability::quote_hit(String key,int64_t maximum,int64_t amount) const {
    Dictionary out;out["ok"]=false;std::string k=key.utf8().get_data();
    if(!valid(k)||maximum<1||maximum>1000000||amount<1||amount>1000000)return out;
    auto at=damaged.find(k);if(at==damaged.end()&&damaged.size()>=65536){out["reason"]="Durability capacity reached";return out;}
    const int64_t previous=at==damaged.end()||at->second.health!=maximum?0:at->second.damage;
    const int64_t applied=std::min(amount,maximum-previous);
    out["ok"]=true;out["previous"]=previous;out["applied"]=applied;out["remaining"]=maximum-previous-applied;out["maximum"]=maximum;out["destroyed"]=previous+applied==maximum;return out;
}
Dictionary NativeWorldDurability::hit(String key,int64_t maximum,int64_t amount){
    Dictionary out=quote_hit(key,maximum,amount);if(!bool(out["ok"]))return out;
    damaged[key.utf8().get_data()]={int(maximum),int(maximum-int64_t(out["remaining"]))};return out;
}
Dictionary NativeWorldDurability::preview_harvest(String key,int64_t maximum,int64_t amount,int64_t damage_per_item,int64_t finishing_bonus) const {
    Dictionary out;out["ok"]=false;
    if(damage_per_item<1||damage_per_item>1000000||finishing_bonus<0||finishing_bonus>1000000)return out;
    out=quote_hit(key,maximum,amount);if(!bool(out["ok"]))return out;
    const int64_t previous=out["previous"],applied=out["applied"];
    out["reward_count"]=(previous+applied)/damage_per_item-previous/damage_per_item+(applied>0&&bool(out["destroyed"])?finishing_bonus:0);return out;
}
Dictionary NativeWorldDurability::harvest_hit(String key,int64_t maximum,int64_t amount,int64_t item,int64_t damage_per_item,int64_t finishing_bonus,const Ref<NativePlayerInventory> &inventory,int64_t expected_revision){
    Dictionary out;out["ok"]=false;
    if(inventory.is_null()||item<1||item>INT32_MAX||!inventory->has_item(item)||inventory->get_revision()!=expected_revision){out["reason"]="Inventory changed; try again";return out;}
    out=preview_harvest(key,maximum,amount,damage_per_item,finishing_bonus);if(!bool(out["ok"]))return out;
    const int64_t count=out["reward_count"];
    if(count>0){
        PackedInt64Array items;items.append(item);items.append(count);
        Dictionary granted=inventory->grant_items(items,expected_revision);
        if(!bool(granted["ok"])){out["ok"]=false;out["reason"]="Make room in inventory before harvesting";return out;}
    }
    damaged[key.utf8().get_data()]={int(maximum),int(maximum-int64_t(out["remaining"]))};out["reward_item"]=item;return out;
}
void NativeWorldDurability::forget(String key){damaged.erase(key.utf8().get_data());}
int64_t NativeWorldDurability::damage(String key,int64_t maximum) const {
    auto at=damaged.find(key.utf8().get_data());
    return at==damaged.end()||at->second.health!=maximum?0:at->second.damage;
}
Dictionary NativeWorldDurability::repair(String key,int64_t maximum,int64_t amount){
    Dictionary out;out["ok"]=false;std::string k=key.utf8().get_data();
    if(!valid(k)||maximum<1||maximum>1000000||amount<1||amount>1000000)return out;
    auto at=damaged.find(k);
    if(at==damaged.end()||at->second.health!=maximum){out["reason"]="Already fully repaired";return out;}
    int restored=std::min(at->second.damage,int(amount));at->second.damage-=restored;
    out["ok"]=true;out["restored"]=restored;out["remaining"]=maximum-at->second.damage;out["maximum"]=maximum;
    if(!at->second.damage)damaged.erase(at);return out;
}
PackedByteArray NativeWorldDurability::capture_storage_snapshot() const {
    int64_t size=8;for(const auto &e:damaged)size+=12+e.first.size();
    PackedByteArray b;b.resize(size);b.encode_u32(0,0x31444654);b.encode_u32(4,damaged.size());int64_t at=8;
    for(const auto &e:damaged){b.encode_u32(at,e.first.size());b.encode_u32(at+4,e.second.health);b.encode_u32(at+8,e.second.damage);std::memcpy(b.ptrw()+at+12,e.first.data(),e.first.size());at+=12+e.first.size();}return b;
}
bool NativeWorldDurability::decode(const PackedByteArray &b,std::map<std::string,Entry> *out){
    if(b.size()<8||b.size()>8+65536*172||b.decode_u32(0)!=0x31444654||b.decode_u32(4)>65536)return false;
    int64_t at=8;std::string last;
    for(uint32_t i=0;i<b.decode_u32(4);++i){
        if(at+12>b.size())return false;auto n=b.decode_u32(at),h=b.decode_u32(at+4),d=b.decode_u32(at+8);
        if(n<1||n>160||at+12+n>b.size()||h<1||h>1000000||d<1||d>h)return false;
        std::string key(reinterpret_cast<const char *>(b.ptr()+at+12),n);
        if(!valid(key)||key<=last)return false;last=key;if(out)out->emplace(key,Entry{int(h),int(d)});at+=12+n;
    }return at==b.size();
}
bool NativeWorldDurability::restore_storage_snapshot(const PackedByteArray &b){std::map<std::string,Entry> staged;if(!decode(b,&staged))return false;damaged.swap(staged);return true;}
}
