// SPDX-License-Identifier: 0BSD
#include "quests.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <algorithm>
#include <climits>
#include <unordered_set>

namespace terraforest {
using namespace godot;
namespace {
bool point_valid(Vector3 point) {
    return point.is_finite()&&point.x>=0&&point.x<=2000&&point.z>=0&&point.z<=2000&&point.y>=-256&&point.y<=512;
}
uint32_t all_targets(size_t count) {return count==32?UINT32_MAX:(uint32_t(1)<<count)-1;}
}
void NativeQuestLog::_bind_methods() {
    ClassDB::bind_method(D_METHOD("configure","inventory","coin_item"),&NativeQuestLog::configure);
    ClassDB::bind_method(D_METHOD("register_locations","seed","definitions"),&NativeQuestLog::register_locations);
    ClassDB::bind_method(D_METHOD("get_locations"),&NativeQuestLog::get_locations);
    ClassDB::bind_method(D_METHOD("snapshot"),&NativeQuestLog::snapshot);
    ClassDB::bind_method(D_METHOD("accept","key","expected_revision"),&NativeQuestLog::accept);
    ClassDB::bind_method(D_METHOD("initialize_introduction","expected_revision"),&NativeQuestLog::initialize_introduction);
    ClassDB::bind_method(D_METHOD("talk_to_trader","expected_revision"),&NativeQuestLog::talk_to_trader);
    ClassDB::bind_method(D_METHOD("accept_first_visit","key","inventory","expected_revision","inventory_revision"),&NativeQuestLog::accept_first_visit);
    ClassDB::bind_method(D_METHOD("begin_reset","expected_revision"),&NativeQuestLog::begin_reset);
    ClassDB::bind_method(D_METHOD("finish_reset","token","committed","expected_revision"),&NativeQuestLog::finish_reset);
    ClassDB::bind_method(D_METHOD("record_defeated","resident_key","token"),&NativeQuestLog::record_defeated);
    ClassDB::bind_method(D_METHOD("advance_search","position","milliseconds"),&NativeQuestLog::advance_search);
    ClassDB::bind_method(D_METHOD("abandon","expected_revision"),&NativeQuestLog::abandon);
    ClassDB::bind_method(D_METHOD("claim","inbox","progression","expected_revision"),&NativeQuestLog::claim);
    ClassDB::bind_method(D_METHOD("capture_storage_snapshot"),&NativeQuestLog::capture_storage_snapshot);
    ClassDB::bind_method(D_METHOD("validate_snapshot","data"),&NativeQuestLog::validate_snapshot);
    ClassDB::bind_method(D_METHOD("restore_storage_snapshot","data"),&NativeQuestLog::restore_storage_snapshot);
}
bool NativeQuestLog::configure(const Ref<NativePlayerInventory> &inventory,int64_t coin_item) {
    if(currency||inventory.is_null()||coin_item<=0||coin_item>INT32_MAX||!inventory->has_item(coin_item))return false;
    currency=coin_item;return true;
}
bool NativeQuestLog::valid(const Location &location) {
    if(location.key<=0||location.layout.is_empty()||location.layout.utf8().length()>48||location.title.is_empty()||location.title.utf8().length()>128)return false;
    for(int index=0;index<location.layout.length();++index) {
        const auto letter=location.layout[index];
        if(!((letter>='a'&&letter<='z')||(letter>='0'&&letter<='9')||letter=='_'))return false;
    }
    for(int index=0;index<location.title.length();++index)if(location.title[index]<32||location.title[index]==127)return false;
    if(!point_valid(Vector3(location.origin))||!point_valid(location.marker)||!point_valid(location.bounds.position)||!point_valid(location.bounds.get_end()))return false;
    for(int axis=0;axis<3;++axis)if(location.bounds.size[axis]<=0||location.bounds.size[axis]>128)return false;
    if(!location.bounds.grow(16).has_point(location.marker))return false;
    if(location.rotation>3||location.coins<1||location.coins>10000||location.xp<1||location.xp>100000||location.completed>1000000)return false;
    if(location.residents.empty()||location.residents.size()>MAX_RESIDENTS||location.containers.size()>MAX_CONTAINERS)return false;
    for(const auto identity:location.residents)if(identity<=0)return false;
    for(const auto identity:location.containers)if(identity<=0)return false;
    return true;
}
bool NativeQuestLog::valid_ownership(const std::vector<Location> &entries) {
    std::unordered_set<int64_t> keys,residents,containers;
    for(const auto &location:entries) {
        if(!valid(location)||!keys.insert(location.key).second)return false;
        for(const auto identity:location.residents)if(!residents.insert(identity).second)return false;
        for(const auto identity:location.containers)if(!containers.insert(identity).second)return false;
    }
    for(size_t first=0;first<entries.size();++first)for(size_t second=first+1;second<entries.size();++second)
        if(entries[first].bounds.intersects(entries[second].bounds))return false;
    return true;
}
bool NativeQuestLog::same_definition(const Location &left,const Location &right) {
    return left.key==right.key&&left.layout==right.layout&&left.title==right.title&&left.origin==right.origin&&left.rotation==right.rotation&&left.marker==right.marker&&left.bounds==right.bounds&&left.coins==right.coins&&left.xp==right.xp&&left.residents==right.residents&&left.containers==right.containers;
}
NativeQuestLog::Location *NativeQuestLog::find(int64_t key) {
    const auto found=std::lower_bound(locations.begin(),locations.end(),key,[](const Location &location,int64_t identity){return location.key<identity;});
    return found!=locations.end()&&found->key==key?&*found:nullptr;
}
const NativeQuestLog::Location *NativeQuestLog::find(int64_t key) const {
    return const_cast<NativeQuestLog *>(this)->find(key);
}
Dictionary NativeQuestLog::result(bool ok,const char *reason) const {
    Dictionary out;out["ok"]=ok;out["reason"]=reason;out["revision"]=revision;out["cycle"]=int64_t(cycle);return out;
}
Dictionary NativeQuestLog::describe(const Location &location) {
    Dictionary out;out["key"]=location.key;out["layout"]=location.layout;out["title"]=location.title;out["origin"]=location.origin;out["rotation"]=location.rotation;
    out["marker"]=location.marker;out["bounds"]=location.bounds;out["coins"]=location.coins;out["xp"]=location.xp;out["completed"]=location.completed;
    PackedInt64Array residents,containers;
    for(const auto identity:location.residents)residents.append(identity);
    for(const auto identity:location.containers)containers.append(identity);
    out["residents"]=residents;out["containers"]=containers;return out;
}
Dictionary NativeQuestLog::register_locations(int64_t world_seed,const Array &definitions) {
    if(!currency||world_seed<0||world_seed>INT32_MAX||(seed>=0&&seed!=world_seed)||definitions.is_empty()||definitions.size()>MAX_LOCATIONS||phase==2)return result(false,"invalid_registration");
    auto staged=locations;std::unordered_set<int64_t> incoming;
    for(int index=0;index<definitions.size();++index) {
        if(definitions[index].get_type()!=Variant::DICTIONARY)return result(false,"invalid_location");
        const Dictionary entry=definitions[index];
        for(const char *field:{"key","rotation","coins","xp"})if(!entry.has(field)||entry[field].get_type()!=Variant::INT)return result(false,"invalid_location");
        for(const char *field:{"layout","title"})if(!entry.has(field)||entry[field].get_type()!=Variant::STRING)return result(false,"invalid_location");
        for(const char *field:{"residents","containers"})if(!entry.has(field)||entry[field].get_type()!=Variant::PACKED_INT64_ARRAY)return result(false,"invalid_location");
        if(!entry.has("origin")||entry["origin"].get_type()!=Variant::VECTOR3I||!entry.has("marker")||entry["marker"].get_type()!=Variant::VECTOR3||!entry.has("bounds")||entry["bounds"].get_type()!=Variant::AABB)return result(false,"invalid_location");
        const int64_t rotation=entry["rotation"],coins=entry["coins"],xp=entry["xp"];
        if(rotation<0||rotation>3||coins<1||coins>10000||xp<1||xp>100000)return result(false,"invalid_rewards_or_rotation");
        Location location;location.key=entry["key"];location.layout=entry["layout"];location.title=entry["title"];location.origin=entry["origin"];location.marker=entry["marker"];location.bounds=entry["bounds"];
        location.rotation=rotation;location.coins=coins;location.xp=xp;
        const PackedInt64Array residents=entry["residents"],containers=entry["containers"];
        if(residents.size()>MAX_RESIDENTS||containers.size()>MAX_CONTAINERS)return result(false,"location_capacity");
        for(int target=0;target<residents.size();++target)location.residents.push_back(residents[target]);
        for(int target=0;target<containers.size();++target)location.containers.push_back(containers[target]);
        if(!valid(location)||!incoming.insert(location.key).second)return result(false,"invalid_location");
        const auto previous=find(location.key);
        if(previous) {if(!same_definition(*previous,location))return result(false,"changed_location_definition");}
        else staged.push_back(std::move(location));
    }
    if(staged.size()>MAX_LOCATIONS||!valid_ownership(staged))return result(false,"location_ownership_conflict");
    const int added=int(staged.size()-locations.size());
    std::sort(staged.begin(),staged.end(),[](const Location &left,const Location &right){return left.key<right.key;});
    locations=std::move(staged);seed=world_seed;if(added)++revision;
    auto out=result(true,"");out["added"]=added;return out;
}
Array NativeQuestLog::get_locations() const {
    Array out;for(const auto &location:locations)out.append(describe(location));return out;
}
Dictionary NativeQuestLog::snapshot() const {
    Dictionary out;out["revision"]=revision;out["seed"]=seed;out["phase"]=int64_t(phase);out["cycle"]=int64_t(cycle);out["key"]=active;out["locations"]=int64_t(locations.size());
    const auto location=find(active);int count=0;
    for(uint32_t mask=defeated;mask;mask>>=1)count+=mask&1;
    out["arrived"]=arrived;out["search_ms"]=search_ms;out["reveal_sleepers"]=phase==3&&arrived&&search_ms>=60000;
    out["introduction"]=introduction;out["defeated"]=count;out["target_count"]=location?int(location->residents.size()):0;out["location"]=location?describe(*location):Dictionary();return out;
}
Dictionary NativeQuestLog::initialize_introduction(int64_t expected_revision){
    if(expected_revision!=revision||seed<0||phase||cycle||introduction)return result(false,"unavailable_introduction");
    if(std::none_of(locations.begin(),locations.end(),[](const Location &location){return location.layout=="coal_mine";}))return result(false,"coal_mine_unavailable");
    introduction=1;++revision;return result(true,"");
}
Dictionary NativeQuestLog::talk_to_trader(int64_t expected_revision){
    if(expected_revision!=revision||introduction!=1)return result(false,"unavailable_introduction");
    introduction=2;++revision;return result(true,"");
}
Dictionary NativeQuestLog::accept_first_visit(int64_t key,const Ref<NativePlayerInventory> &inventory,int64_t expected_revision,int64_t inventory_revision){
    const auto location=find(key);
    if(expected_revision!=revision||introduction!=2||phase||cycle==UINT32_MAX||!location||location->layout!="coal_mine"||location->completed||inventory.is_null())return result(false,"unavailable_first_visit");
    PackedInt64Array supplies;for(int64_t value:{6,1,8,1,223,180})supplies.append(value);
    const Dictionary granted=inventory->grant_items(supplies,inventory_revision);
    if(!bool(granted["ok"]))return result(false,"make_room_for_supplies");
    active=key;phase=3;defeated=0;arrived=false;search_ms=0;++cycle;introduction=3;++revision;return result(true,"");
}
Dictionary NativeQuestLog::accept(int64_t key,int64_t expected_revision) {
    if(expected_revision!=revision)return result(false,"stale_revision");
    if(phase||introduction==1||introduction==2||!find(key))return result(false,"unavailable_contract");
    active=key;phase=1;defeated=0;arrived=false;search_ms=0;++revision;return result(true,"");
}
Dictionary NativeQuestLog::begin_reset(int64_t expected_revision) {
    if(expected_revision!=revision)return result(false,"stale_revision");
    if(phase!=1||cycle==UINT32_MAX)return result(false,"unavailable_reset");
    phase=2;++cycle;++revision;return result(true,"");
}
Dictionary NativeQuestLog::finish_reset(int64_t token,bool committed,int64_t expected_revision) {
    if(expected_revision!=revision)return result(false,"stale_revision");
    if(phase!=2||token!=int64_t(cycle))return result(false,"stale_reset");
    phase=committed?3:1;defeated=0;arrived=false;search_ms=0;++revision;return result(true,"");
}
bool NativeQuestLog::advance_search(Vector3 position,int64_t milliseconds) {
    if(phase!=3||!position.is_finite()||milliseconds<0||milliseconds>1000)return false;
    const auto location=find(active);
    if(!location)return false;
    const bool inside=location->bounds.grow(3).has_point(position)||position.distance_to(location->marker)<=8;
    if(!inside)return false;
    bool changed=!arrived;arrived=true;
    if(defeated&&search_ms<60000&&milliseconds){search_ms=std::min(uint32_t(60000),search_ms+uint32_t(milliseconds));changed=true;}
    if(changed)++revision;
    return changed;
}
Dictionary NativeQuestLog::record_defeated(int64_t resident_key,int64_t token) {
    if(phase!=3||token!=int64_t(cycle))return result(false,"inactive_encounter");
    const auto location=find(active);
    for(size_t index=0;index<location->residents.size();++index)if(location->residents[index]==resident_key) {
        const uint32_t bit=uint32_t(1)<<index;
        if(!(defeated&bit)){defeated|=bit;search_ms=0;++revision;}
        if(defeated==all_targets(location->residents.size()))phase=4;
        return result(true,"");
    }
    return result(false,"unowned_resident");
}
Dictionary NativeQuestLog::abandon(int64_t expected_revision) {
    if(expected_revision!=revision)return result(false,"stale_revision");
    if(!phase||phase==2||introduction==3)return result(false,"unavailable_abandon");
    phase=0;active=0;defeated=0;arrived=false;search_ms=0;++revision;return result(true,"");
}
Dictionary NativeQuestLog::claim(const Ref<NativeRewardInbox> &inbox,const Ref<NativePlayerProgression> &progression,int64_t expected_revision) {
    if(expected_revision!=revision)return result(false,"stale_revision");
    auto location=find(active);
    if(phase!=4||!location||location->completed>=1000000)return result(false,"incomplete_contract");
    if(inbox.is_null()||progression.is_null()||!progression->count||inbox->get_last_receipt()==INT64_MAX)return result(false,"invalid_reward_target");
    PackedInt64Array reward;reward.append(currency);reward.append(location->coins);
    const int64_t receipt=inbox->get_last_receipt()+1;
    const Dictionary allowed=inbox->can_accept(reward,receipt);
    if(!bool(allowed["ok"]))return result(false,"reward_inbox_full");
    const Dictionary experience=progression->award(location->xp,progression->revision);
    inbox->accept(reward,receipt);
    const int coins=location->coins;++location->completed;if(introduction==3)introduction=4;
    phase=0;active=0;defeated=0;arrived=false;search_ms=0;++revision;
    auto out=result(true,"");out["coins"]=coins;out["gained"]=experience["gained"];out["levels"]=experience["levels"];out["level"]=experience["level"];return out;
}
PackedByteArray NativeQuestLog::capture_storage_snapshot() const {
    PackedByteArray out;if(!currency||phase==2){out.resize(1);out.set(0,0);return out;}
    int size=48;
    for(const auto &location:locations)size+=84+location.layout.utf8().length()+location.title.utf8().length()+8*(location.residents.size()+location.containers.size());
    out.resize(size);out.fill(0);out.encode_u32(0,0x31514654);out.encode_u32(4,arrived?3:introduction?2:1);out.encode_s32(8,seed);out.encode_u32(12,locations.size());out.encode_u64(16,active);out.encode_u32(36,introduction);
    out.encode_u32(44,arrived?(uint32_t(1)<<31)|search_ms:0);
    out.encode_u32(24,cycle);out.encode_u32(28,phase);out.encode_u32(32,defeated);out.encode_u32(40,currency);
    int at=48;
    for(const auto &location:locations) {
        const auto layout=location.layout.utf8(),title=location.title.utf8();
        out.encode_u64(at,location.key);
        for(int axis=0;axis<3;++axis){out.encode_s32(at+8+axis*4,location.origin[axis]);out.encode_float(at+24+axis*4,location.marker[axis]);out.encode_float(at+36+axis*4,location.bounds.position[axis]);out.encode_float(at+48+axis*4,location.bounds.size[axis]);}
        out.encode_u32(at+20,location.rotation);out.encode_u32(at+60,location.coins);out.encode_u32(at+64,location.xp);out.encode_u16(at+68,location.residents.size());out.encode_u16(at+70,location.containers.size());out.encode_u16(at+72,layout.length());out.encode_u16(at+74,title.length());out.encode_u32(at+76,location.completed);
        at+=84;
        for(int index=0;index<layout.length();++index)out.set(at++,uint8_t(layout[index]));
        for(int index=0;index<title.length();++index)out.set(at++,uint8_t(title[index]));
        for(const auto identity:location.residents){out.encode_u64(at,identity);at+=8;}
        for(const auto identity:location.containers){out.encode_u64(at,identity);at+=8;}
    }
    return out;
}
bool NativeQuestLog::decode(const PackedByteArray &data,std::vector<Location> &parsed,int64_t &world_seed,int64_t &active_key,uint32_t &state,uint32_t &iteration,uint32_t &mask) const {
    world_seed=-1;active_key=0;state=0;iteration=0;mask=0;parsed.clear();
    if(!currency)return false;
    if(data.is_empty())return true;
    if(data.size()<48||data.size()>MAX_BYTES||data.decode_u32(0)!=0x31514654||data.decode_u32(4)<1||data.decode_u32(4)>3||data.decode_u32(40)!=currency)return false;
    const uint32_t guidance=data.decode_u32(44),search=guidance&0x7fffffffu;
    if(data.decode_u32(4)<3?guidance!=0:(!(guidance&0x80000000u)||search>60000))return false;
    const auto intro=data.decode_u32(36);if(intro>4||(data.decode_u32(4)==1&&intro)||(data.decode_u32(4)==2&&!intro))return false;
    world_seed=data.decode_s32(8);active_key=int64_t(data.decode_u64(16));iteration=data.decode_u32(24);state=data.decode_u32(28);mask=data.decode_u32(32);
    if(guidance&&((state!=3&&state!=4)||(search&&(!mask||state!=3))))return false;
    const uint32_t count=data.decode_u32(12);
    if(world_seed< -1||count>MAX_LOCATIONS||(world_seed<0&&count)||active_key<0||state>4||state==2)return false;
    if(!count&&(world_seed!=-1||active_key||state||iteration||mask))return false;
    int at=48;int64_t previous=0;
    for(uint32_t index=0;index<count;++index) {
        if(data.size()-at<84)return false;
        Location location;location.key=int64_t(data.decode_u64(at));location.rotation=data.decode_u32(at+20);location.coins=data.decode_u32(at+60);location.xp=data.decode_u32(at+64);location.completed=data.decode_u32(at+76);
        const int residents=data.decode_u16(at+68),containers=data.decode_u16(at+70),layout_size=data.decode_u16(at+72),title_size=data.decode_u16(at+74);
        if(location.key<=previous||residents<1||residents>MAX_RESIDENTS||containers>MAX_CONTAINERS||layout_size<1||layout_size>48||title_size<1||title_size>128||data.decode_u32(at+80))return false;
        if(data.size()-at-84<layout_size+title_size+8*(residents+containers))return false;
        for(int axis=0;axis<3;++axis){location.origin[axis]=data.decode_s32(at+8+axis*4);location.marker[axis]=data.decode_float(at+24+axis*4);location.bounds.position[axis]=data.decode_float(at+36+axis*4);location.bounds.size[axis]=data.decode_float(at+48+axis*4);}
        at+=84;
        if(location.layout.parse_utf8(reinterpret_cast<const char *>(data.ptr()+at),layout_size)!=OK)return false;
        if(location.layout.utf8().length()!=layout_size)return false;
        at+=layout_size;
        if(location.title.parse_utf8(reinterpret_cast<const char *>(data.ptr()+at),title_size)!=OK)return false;
        if(location.title.utf8().length()!=title_size)return false;
        at+=title_size;
        for(int target=0;target<residents;++target){location.residents.push_back(int64_t(data.decode_u64(at)));at+=8;}
        for(int target=0;target<containers;++target){location.containers.push_back(int64_t(data.decode_u64(at)));at+=8;}
        previous=location.key;parsed.push_back(std::move(location));
    }
    if(at!=data.size()||!valid_ownership(parsed))return false;
    uint64_t completed=0;for(const auto &location:parsed)completed+=location.completed;
    if(completed>iteration)return false;
    const auto found=std::find_if(parsed.begin(),parsed.end(),[active_key](const Location &location){return location.key==active_key;});
    if(intro&&std::none_of(parsed.begin(),parsed.end(),[](const Location &location){return location.layout=="coal_mine";}))return false;
    if((intro==1||intro==2)&&(state||iteration||completed))return false;
    if(intro==3&&(found==parsed.end()||found->layout!="coal_mine"||(state!=3&&state!=4)||found->completed))return false;
    if(intro==4&&!completed)return false;
    if(!state)return active_key==0&&mask==0;
    if(found==parsed.end())return false;
    if(state==1)return mask==0;
    if(!iteration||completed>=iteration)return false;
    const uint32_t full=all_targets(found->residents.size());
    return !(mask&~full)&&(state==4?mask==full:mask!=full);
}
bool NativeQuestLog::validate_snapshot(const PackedByteArray &data) const {
    std::vector<Location> parsed;int64_t world_seed,active_key;uint32_t state,iteration,mask;return decode(data,parsed,world_seed,active_key,state,iteration,mask);
}
bool NativeQuestLog::restore_storage_snapshot(const PackedByteArray &data) {
    if(phase==2)return false;
    std::vector<Location> parsed;int64_t world_seed,active_key;uint32_t state,iteration,mask;
    if(!decode(data,parsed,world_seed,active_key,state,iteration,mask))return false;
    locations=std::move(parsed);seed=world_seed;active=active_key;phase=state;cycle=iteration;defeated=mask;introduction=data.is_empty()?0:data.decode_u32(36);
    const uint32_t guidance=data.is_empty()?0:data.decode_u32(44);arrived=(guidance&0x80000000u)!=0;search_ms=guidance&0x7fffffffu;++revision;return true;
}
}
