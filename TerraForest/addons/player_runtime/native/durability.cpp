// SPDX-License-Identifier: 0BSD
#include "durability.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <algorithm>
#include <cstring>
namespace terraforest {
using namespace godot;
void NativeWorldDurability::_bind_methods(){
    ClassDB::bind_method(D_METHOD("hit","key","maximum","amount"),&NativeWorldDurability::hit);
    ClassDB::bind_method(D_METHOD("forget","key"),&NativeWorldDurability::forget);
    ClassDB::bind_method(D_METHOD("record_count"),&NativeWorldDurability::record_count);
    ClassDB::bind_method(D_METHOD("capture_storage_snapshot"),&NativeWorldDurability::capture_storage_snapshot);
    ClassDB::bind_method(D_METHOD("validate_snapshot","data"),&NativeWorldDurability::validate_snapshot);
    ClassDB::bind_method(D_METHOD("restore_storage_snapshot","data"),&NativeWorldDurability::restore_storage_snapshot);
}
static bool valid(const std::string &s){if(s.empty()||s.size()>160)return false;for(unsigned char c:s)if(c<32||c>126)return false;return true;}
Dictionary NativeWorldDurability::hit(String key,int64_t maximum,int64_t amount){
    Dictionary out;out["ok"]=false;std::string k=key.utf8().get_data();
    if(!valid(k)||maximum<1||maximum>1000000||amount<1||amount>1000000)return out;
    auto at=damaged.find(k);if(at==damaged.end()&&damaged.size()>=65536){out["reason"]="Durability capacity reached";return out;}
    auto &e=damaged[k];if(e.health!=maximum)e={int(maximum),0};
    e.damage=std::min(e.health,e.damage+int(amount));out["ok"]=true;out["remaining"]=e.health-e.damage;out["maximum"]=e.health;out["destroyed"]=e.damage==e.health;return out;
}
void NativeWorldDurability::forget(String key){damaged.erase(key.utf8().get_data());}
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
