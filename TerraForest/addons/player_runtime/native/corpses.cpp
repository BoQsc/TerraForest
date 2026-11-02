// SPDX-License-Identifier: 0BSD
#include "corpses.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <cmath>
#include <cstring>
#include <algorithm>
#include <set>
namespace terraforest {
using namespace godot;
void NativeCorpseStore::_bind_methods(){
    ClassDB::bind_method(D_METHOD("create_corpse","position","yaw","seed","resident","anchor"),&NativeCorpseStore::create_corpse,DEFVAL(0),DEFVAL(0));
    ClassDB::bind_method(D_METHOD("corpse_patch_state"),&NativeCorpseStore::corpse_patch_state);
    ClassDB::bind_method(D_METHOD("capture_corpse_patch","residents","anchors","revision","owner"),&NativeCorpseStore::capture_corpse_patch);
    ClassDB::bind_method(D_METHOD("validate_corpse_patch","bytes"),&NativeCorpseStore::validate_corpse_patch);
    ClassDB::bind_method(D_METHOD("restore_corpse_patch","bytes","revision","owner"),&NativeCorpseStore::restore_corpse_patch);
    ClassDB::bind_method(D_METHOD("update_corpse","id","position","yaw","missing","pose"),&NativeCorpseStore::update_corpse);
    ClassDB::bind_method(D_METHOD("corpse","id"),&NativeCorpseStore::corpse);
    ClassDB::bind_method(D_METHOD("corpse_ids"),&NativeCorpseStore::corpse_ids);
    ClassDB::bind_method(D_METHOD("nearby_corpses","focus","radius","excluded"),&NativeCorpseStore::nearby_corpses);
    ClassDB::bind_method(D_METHOD("erase_corpse","id"),&NativeCorpseStore::erase_corpse);
    ClassDB::bind_method(D_METHOD("capture_corpse_snapshot"),&NativeCorpseStore::capture_corpse_snapshot);
    ClassDB::bind_method(D_METHOD("validate_corpse_snapshot","bytes"),&NativeCorpseStore::validate_corpse_snapshot);
    ClassDB::bind_method(D_METHOD("restore_corpse_snapshot","bytes"),&NativeCorpseStore::restore_corpse_snapshot);
}
bool NativeCorpseStore::valid_pose(const PackedFloat32Array &pose){
    if(pose.is_empty())return true;if(pose.size()!=180)return false;
    for(int i=0;i<15;++i){const float *p=pose.ptr()+12*i;
        Transform3D t(Basis(p[0],p[1],p[2],p[4],p[5],p[6],p[8],p[9],p[10]),Vector3(p[3],p[7],p[11]));
        if(!t.is_finite()||std::abs(t.basis.determinant())<1e-8||t.origin.length_squared()>1e12)return false;
    }return true;
}
bool NativeCorpseStore::valid_owner(int64_t resident,int64_t anchor){return resident>=0&&resident<=2756&&anchor>=0&&anchor<=9007199254740991LL&&(!anchor||resident>2500);}
int64_t NativeCorpseStore::create_corpse(Vector3 position,double yaw,int64_t seed,int64_t resident,int64_t anchor){
    if(schema.is_null()||int64_t(records.size())>=capacity||!position.is_finite()||position.length_squared()>1e12||!std::isfinite(yaw)||!std::isfinite(float(yaw))||next_id==INT64_MAX||!valid_owner(resident,anchor)||(resident&&resident_corpses.count(resident))||(anchor&&anchor_corpses.count(anchor)))return 0;
    uint32_t random=uint32_t(next_id)^uint32_t(seed);random^=random>>16;random*=0x7feb352du;random^=random>>15;
    PackedInt64Array loot;loot.append(201);loot.append(1+random%4);loot.append(102);loot.append(1+(random>>8)%3);
    if(random%9==0){loot.append(301);loot.append(1);}
    // One common trail piece on roughly one third of newly created corpses.
    // Roll once at creation; saved contents remain authoritative on restore.
    if((random>>16)%3==0){
        const int64_t item=304+(random>>24)%3;
        if(schema->has_item(item)){loot.append(item);loot.append(1);}
    }
    if(!initialize_contents(next_id,loot))return 0;
    Corpse entry;entry.position=position;entry.yaw=yaw;entry.resident=resident;entry.anchor=anchor;
    records[next_id]=entry;if(resident)resident_corpses.emplace(resident,next_id);if(anchor)anchor_corpses.emplace(anchor,next_id);return next_id++;
}
bool NativeCorpseStore::update_corpse(int64_t id,Vector3 position,double yaw,int64_t missing,const PackedFloat32Array &pose){
    auto found=records.find(id);if(found==records.end()||!position.is_finite()||position.length_squared()>1e12||!std::isfinite(yaw)||!std::isfinite(float(yaw))||missing<0||missing>16383||!valid_pose(pose)||revision==INT64_MAX)return false;
    const auto &before=found->second;const float heading=float(yaw);
    bool same=std::memcmp(&heading,&before.yaw,sizeof(float))==0&&before.missing==missing&&before.pose.size()==pose.size()&&(pose.is_empty()||std::memcmp(before.pose.ptr(),pose.ptr(),pose.size()*sizeof(float))==0);
    for(int axis=0;axis<3;++axis)same=same&&std::memcmp(&position[axis],&before.position[axis],sizeof(real_t))==0;
    if(!same){found->second={position,heading,uint32_t(missing),pose,before.resident,before.anchor};++revision;}return true;
}
Dictionary NativeCorpseStore::corpse(int64_t id)const{
    Dictionary out;auto found=records.find(id);if(found==records.end())return out;const auto &c=found->second;
    out["position"]=c.position;out["yaw"]=c.yaw;out["missing"]=c.missing;out["pose"]=c.pose;out["resident"]=c.resident;out["anchor"]=c.anchor;return out;
}
PackedInt64Array NativeCorpseStore::corpse_ids()const{PackedInt64Array ids;for(const auto &r:records)ids.append(r.first);return ids;}
PackedInt64Array NativeCorpseStore::nearby_corpses(Vector3 focus,double radius,const PackedInt64Array &excluded)const{
    PackedInt64Array out;if(!focus.is_finite()||!std::isfinite(radius)||radius<=0||radius>512||excluded.size()>32)return out;
    std::set<int64_t> omitted;for(int64_t id:excluded)omitted.insert(id);
    std::vector<std::pair<double,int64_t>> nearest;
    for(const auto &entry:records){if(omitted.count(entry.first))continue;const auto &c=entry.second;
        Vector3 point=c.pose.is_empty()?c.position:Vector3(c.pose[3],c.pose[7],c.pose[11]);double distance=focus.distance_squared_to(point);
        if(distance<radius*radius)nearest.emplace_back(distance,entry.first);
    }
    size_t count=std::min(size_t(12),nearest.size());std::partial_sort(nearest.begin(),nearest.begin()+count,nearest.end());
    for(size_t i=0;i<count;++i)out.append(nearest[i].second);return out;
}
bool NativeCorpseStore::erase_corpse(int64_t id){auto found=records.find(id);if(found==records.end()||has_contents(id))return false;if(found->second.resident)resident_corpses.erase(found->second.resident);if(found->second.anchor)anchor_corpses.erase(found->second.anchor);records.erase(found);++revision;return true;}
PackedByteArray NativeCorpseStore::capture_corpse_snapshot()const{
    auto inventory=NativeContainerStore::capture_storage_snapshot();if(inventory.is_empty())return {};
    const bool owned=!resident_corpses.empty();const int stride=owned?768:752;
    PackedByteArray out;out.resize(32+records.size()*stride+inventory.size());out.fill(0);std::memcpy(out.ptrw(),owned?"TFZC\2\0\0\0":"TFZC\1\0\0\0",8);
    out.encode_u64(8,next_id);out.encode_u64(16,records.size());out.encode_u64(24,inventory.size());int64_t at=32;
    for(const auto &r:records){const auto &c=r.second;out.encode_u64(at,r.first);out.encode_float(at+8,c.position.x);out.encode_float(at+12,c.position.y);out.encode_float(at+16,c.position.z);out.encode_float(at+20,c.yaw);out.encode_u32(at+24,c.missing);out.encode_u32(at+28,c.pose.is_empty()?0:1);
        for(int i=0;i<180;++i)out.encode_float(at+32+i*4,c.pose.is_empty()?0:c.pose[i]);if(owned){out.encode_u64(at+752,c.resident);out.encode_u64(at+760,c.anchor);}at+=stride;
    }std::memcpy(out.ptrw()+at,inventory.ptr(),inventory.size());return out;
}
bool NativeCorpseStore::decode(const PackedByteArray &bytes,std::map<int64_t,Corpse> &staged,int64_t &next,PackedByteArray &inventory)const{
    if(schema.is_null()||bytes.size()<48||std::memcmp(bytes.ptr(),"TFZC",4)||(bytes.decode_u32(4)!=1&&bytes.decode_u32(4)!=2))return false;
    const int stride=bytes.decode_u32(4)==2?768:752;std::set<int64_t> owners,anchors;
    uint64_t count=bytes.decode_u64(16),size=bytes.decode_u64(24);next=bytes.decode_u64(8);
    if(next<1||count>uint64_t(capacity)||size>16+uint64_t(capacity)*528||uint64_t(bytes.size())!=32+count*stride+size)return false;
    int64_t at=32,previous=0;for(uint64_t n=0;n<count;++n){int64_t id=bytes.decode_u64(at);Corpse c;
        c.position=Vector3(bytes.decode_float(at+8),bytes.decode_float(at+12),bytes.decode_float(at+16));c.yaw=bytes.decode_float(at+20);c.missing=bytes.decode_u32(at+24);auto posed=bytes.decode_u32(at+28);
        if(id<=previous||id>=next||!c.position.is_finite()||c.position.length_squared()>1e12||!std::isfinite(c.yaw)||c.missing>16383||posed>1)return false;
        if(posed){c.pose.resize(180);for(int i=0;i<180;++i)c.pose.set(i,bytes.decode_float(at+32+i*4));if(!valid_pose(c.pose))return false;}
        if(stride==768){c.resident=bytes.decode_u64(at+752);c.anchor=bytes.decode_u64(at+760);if(!valid_owner(c.resident,c.anchor)||(c.resident&&!owners.insert(c.resident).second)||(c.anchor&&!anchors.insert(c.anchor).second))return false;}
        previous=id;staged[id]=c;at+=stride;
    }
    inventory=bytes.slice(at);if(!NativeContainerStore::validate_snapshot(inventory)||std::memcmp(inventory.ptr(),"TFCS\3\0\0\0",8))return false;
    for(uint64_t n=0;n<inventory.decode_u64(8);++n)if(!staged.count(inventory.decode_u64(16+n*528)))return false;
    return true;
}
bool NativeCorpseStore::validate_corpse_snapshot(const PackedByteArray &bytes)const{std::map<int64_t,Corpse> staged;int64_t next;PackedByteArray inventory;return decode(bytes,staged,next,inventory);}
bool NativeCorpseStore::restore_corpse_snapshot(const PackedByteArray &bytes){std::map<int64_t,Corpse> staged;int64_t next;PackedByteArray inventory;if(!decode(bytes,staged,next,inventory))return false;decltype(resident_corpses) owners,anchors;for(const auto &[id,corpse]:staged){if(corpse.resident)owners.emplace(corpse.resident,id);if(corpse.anchor)anchors.emplace(corpse.anchor,id);}if(!NativeContainerStore::restore_storage_snapshot(inventory))return false;records.swap(staged);resident_corpses.swap(owners);anchor_corpses.swap(anchors);next_id=next;return true;}
}
