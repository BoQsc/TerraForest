// SPDX-License-Identifier: 0BSD
#include "survival.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <algorithm>

namespace terraforest {
using namespace godot;
void NativePlayerSurvival::_bind_methods() {
    ClassDB::bind_method(D_METHOD("configure","item_rules","effect_rules"),&NativePlayerSurvival::configure);
    ClassDB::bind_method(D_METHOD("advance","elapsed_ms"),&NativePlayerSurvival::advance);
    ClassDB::bind_method(D_METHOD("scale_damage","base"),&NativePlayerSurvival::scale_damage);
    ClassDB::bind_method(D_METHOD("scale_experience","base"),&NativePlayerSurvival::scale_experience);
    ClassDB::bind_method(D_METHOD("use","inventory","progression","slot","expected_inventory","expected_revision"),&NativePlayerSurvival::use);
    ClassDB::bind_method(D_METHOD("snapshot"),&NativePlayerSurvival::snapshot);
    ClassDB::bind_method(D_METHOD("capture_storage_snapshot"),&NativePlayerSurvival::capture_storage_snapshot);
    ClassDB::bind_method(D_METHOD("validate_snapshot","data"),&NativePlayerSurvival::validate_snapshot);
    ClassDB::bind_method(D_METHOD("restore_storage_snapshot","data"),&NativePlayerSurvival::restore_storage_snapshot);
}
Dictionary NativePlayerSurvival::result(bool ok,const char *reason) const {
    Dictionary out;out["ok"]=ok;out["reason"]=reason;out["revision"]=revision;return out;
}
int64_t NativePlayerSurvival::effect_index(int64_t identity) const {
    for(int64_t index=0;index<effect_count;++index)if(effects[index].id==identity)return index;
    return -1;
}
bool NativePlayerSurvival::configure(const PackedInt64Array &item_rules,const PackedInt64Array &effect_rules) {
    if(item_count||item_rules.is_empty()||item_rules.size()>160||item_rules.size()%5||effect_rules.size()>24||effect_rules.size()%3)return false;
    std::array<Effect,8> staged{};int64_t previous=0;
    for(int64_t index=0;index<effect_rules.size();index+=3) {
        const int64_t identity=effect_rules[index],damage=effect_rules[index+1],learning=effect_rules[index+2];
        if(identity<=previous||identity>65535||damage<0||damage>250||learning<0||learning>250)return false;
        staged[index/3]={identity,damage,learning,0};previous=identity;
    }
    previous=0;
    for(int64_t index=0;index<item_rules.size();index+=5) {
        const int64_t identity=item_rules[index],nutrition=item_rules[index+1],xp=item_rules[index+2],effect=item_rules[index+3],duration=item_rules[index+4];
        if(identity<=previous||identity>INT32_MAX||nutrition<0||nutrition>100||xp<0||xp>1000||(!nutrition&&!xp)||effect<0||duration<0||duration>3600)return false;
        if((effect==0)!=(duration==0))return false;
        bool found=effect==0;
        for(int64_t candidate=0;candidate<effect_rules.size()/3;++candidate)found=found||staged[candidate].id==effect;
        if(!found)return false;
        previous=identity;
    }
    effects=staged;effect_count=effect_rules.size()/3;item_count=item_rules.size()/5;
    for(int64_t index=0;index<item_count;++index)items[index]={item_rules[index*5],item_rules[index*5+1]*36000,item_rules[index*5+2],item_rules[index*5+3],item_rules[index*5+4]*1000,0};
    return true;
}
bool NativePlayerSurvival::advance(int64_t elapsed_ms) {
    if(!item_count||elapsed_ms<=0||elapsed_ms>86400000)return false;
    bool changed=food>0;food=std::max(int64_t(0),food-elapsed_ms);
    for(int64_t index=0;index<effect_count;++index) {
        changed=changed||effects[index].remaining>0;
        effects[index].remaining=std::max(int64_t(0),effects[index].remaining-elapsed_ms);
    }
    if(changed)++revision;return changed;
}
int64_t NativePlayerSurvival::scale_damage(int64_t base) const {
    if(base<0||base>1000000)return 0;
    int64_t factor=food==0?800:food<=FULL/5?900:1000;
    for(int64_t index=0;index<effect_count;++index)if(effects[index].remaining)factor+=effects[index].damage;
    return (base*factor+500)/1000;
}
int64_t NativePlayerSurvival::scale_experience(int64_t base) const {
    if(base<0||base>1000000)return 0;
    int64_t factor=1000;
    for(int64_t index=0;index<effect_count;++index)if(effects[index].remaining)factor+=effects[index].learning;
    return std::min(int64_t(1000000),(base*factor+500)/1000);
}
Dictionary NativePlayerSurvival::use(const Ref<NativePlayerInventory> &inventory,const Ref<NativePlayerProgression> &progression,int64_t slot,int64_t expected_inventory,int64_t expected_revision) {
    if(!item_count||inventory.is_null()||progression.is_null()||!progression->count||slot<0||slot>=32)return result(false,"invalid_use");
    if(revision!=expected_revision||inventory->revision!=expected_inventory)return result(false,"stale_revision");
    const auto &stack=inventory->slots[slot];Item *selected=nullptr;
    for(int64_t index=0;index<item_count;++index)if(items[index].id==stack.item){selected=&items[index];break;}
    if(!selected||stack.count<=0)return result(false,"not_usable");
    if(selected->food&&food==FULL)return result(false,"already_full");
    if(selected->xp&&selected->read>=1000000)return result(false,"reading_limit");
    const int64_t xp=scale_experience(selected->xp);
    const int64_t gained_food=std::min(selected->food,FULL-food);
    const int64_t item=selected->id;
    const Dictionary debit=inventory->consume(slot,1,expected_inventory);
    if(!bool(debit["ok"]))return result(false,"inventory_changed");
    int64_t gained_xp=0,level=progression->level_for(progression->experience);
    if(xp) {
        Dictionary learned=progression->award(xp,progression->revision);
        gained_xp=learned["gained"];level=learned["level"];++selected->read;
    }
    food+=gained_food;
    const int64_t effect=effect_index(selected->effect);
    if(effect>=0)effects[effect].remaining=std::max(effects[effect].remaining,selected->duration);
    ++revision;
    Dictionary out=result(true,"");out["item"]=item;out["xp"]=gained_xp;out["level"]=level;out["food_ms"]=gained_food;out["effect"]=selected->effect;return out;
}
Dictionary NativePlayerSurvival::snapshot() const {
    Dictionary out,active,readings;
    for(int64_t index=0;index<effect_count;++index)if(effects[index].remaining)active[effects[index].id]=effects[index].remaining;
    for(int64_t index=0;index<item_count;++index)if(items[index].read)readings[items[index].id]=items[index].read;
    out["revision"]=revision;out["food_ms"]=food;out["food_max_ms"]=FULL;out["effects"]=active;out["readings"]=readings;return out;
}
PackedByteArray NativePlayerSurvival::capture_storage_snapshot() const {
    int64_t active=0,read=0;
    for(int64_t index=0;index<effect_count;++index)if(effects[index].remaining)++active;
    for(int64_t index=0;index<item_count;++index)if(items[index].read)++read;
    PackedByteArray data;data.resize(24+(active+read)*8);data.encode_u32(0,0x53534654);data.encode_u32(4,1);data.encode_u32(8,food);data.encode_u32(12,active);data.encode_u32(16,read);data.encode_u32(20,0);
    int64_t offset=24;
    for(int64_t index=0;index<effect_count;++index)if(effects[index].remaining){data.encode_u32(offset,effects[index].id);data.encode_u32(offset+4,effects[index].remaining);offset+=8;}
    for(int64_t index=0;index<item_count;++index)if(items[index].read){data.encode_u32(offset,items[index].id);data.encode_u32(offset+4,items[index].read);offset+=8;}
    return data;
}
bool NativePlayerSurvival::validate_snapshot(const PackedByteArray &data) const {
    if(!item_count||data.size()<24||data.size()>344||data.decode_u32(0)!=0x53534654||data.decode_u32(4)!=1||data.decode_u32(8)>FULL||data.decode_u32(20)!=0)return false;
    const uint32_t active=data.decode_u32(12),read=data.decode_u32(16);
    if(active>effect_count||read>item_count||data.size()!=24+(active+read)*8)return false;
    uint32_t previous=0;int64_t offset=24;
    for(uint32_t index=0;index<active;++index,offset+=8) {
        const uint32_t identity=data.decode_u32(offset),remaining=data.decode_u32(offset+4);
        if(identity<=previous||effect_index(identity)<0||!remaining||remaining>3600000)return false;
        previous=identity;
    }
    previous=0;
    for(uint32_t index=0;index<read;++index,offset+=8) {
        const uint32_t identity=data.decode_u32(offset),amount=data.decode_u32(offset+4);bool found=false;
        for(int64_t candidate=0;candidate<item_count;++candidate)found=found||(items[candidate].id==identity&&items[candidate].xp>0);
        if(identity<=previous||!amount||amount>1000000||!found)return false;
        previous=identity;
    }
    return true;
}
bool NativePlayerSurvival::restore_storage_snapshot(const PackedByteArray &data) {
    if(!validate_snapshot(data))return false;
    food=data.decode_u32(8);
    for(int64_t index=0;index<effect_count;++index)effects[index].remaining=0;
    for(int64_t index=0;index<item_count;++index)items[index].read=0;
    int64_t offset=24;
    for(uint32_t index=0;index<data.decode_u32(12);++index,offset+=8)effects[effect_index(data.decode_u32(offset))].remaining=data.decode_u32(offset+4);
    for(uint32_t index=0;index<data.decode_u32(16);++index,offset+=8)
        for(int64_t candidate=0;candidate<item_count;++candidate)if(items[candidate].id==data.decode_u32(offset))items[candidate].read=data.decode_u32(offset+4);
    ++revision;return true;
}
}
