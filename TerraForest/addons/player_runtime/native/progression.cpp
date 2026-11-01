// SPDX-License-Identifier: 0BSD
#include "progression.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <algorithm>

namespace terraforest {
using namespace godot;
void NativePlayerProgression::_bind_methods() {
    ClassDB::bind_method(D_METHOD("configure","definitions"),&NativePlayerProgression::configure);
    ClassDB::bind_method(D_METHOD("snapshot"),&NativePlayerProgression::snapshot);
    ClassDB::bind_method(D_METHOD("award","amount","expected_revision"),&NativePlayerProgression::award);
    ClassDB::bind_method(D_METHOD("spend","skill","expected_revision"),&NativePlayerProgression::spend);
    ClassDB::bind_method(D_METHOD("scale_action","skill","base"),&NativePlayerProgression::scale_action);
    ClassDB::bind_method(D_METHOD("capture_storage_snapshot"),&NativePlayerProgression::capture_storage_snapshot);
    ClassDB::bind_method(D_METHOD("validate_snapshot","data"),&NativePlayerProgression::validate_snapshot);
    ClassDB::bind_method(D_METHOD("restore_storage_snapshot","data"),&NativePlayerProgression::restore_storage_snapshot);
}
int64_t NativePlayerProgression::threshold(int64_t level) { return 125*(level-1)*level; }
int64_t NativePlayerProgression::level_for(int64_t experience) {
    int64_t lower=1,upper=MAX_LEVEL;
    while(lower<upper) {
        const int64_t middle=(lower+upper+1)/2;
        if(experience>=threshold(middle))lower=middle;else upper=middle-1;
    }
    return lower;
}
int64_t NativePlayerProgression::available_points() const {
    int64_t points=level_for(experience)-1;
    for(int64_t index=0;index<count;++index)points-=skills[index].rank;
    return points;
}
Dictionary NativePlayerProgression::result(bool ok,const char *reason) const {
    Dictionary out;out["ok"]=ok;out["reason"]=reason;out["revision"]=revision;return out;
}
bool NativePlayerProgression::configure(const PackedInt64Array &definitions) {
    if(count||definitions.is_empty()||definitions.size()>96||definitions.size()%3)return false;
    int64_t previous=0;
    for(int64_t index=0;index<definitions.size();index+=3) {
        const int64_t id=definitions[index],maximum=definitions[index+1],bonus=definitions[index+2];
        if(id<=previous||id>65535||maximum<1||maximum>20||bonus<0||bonus>250)return false;
        previous=id;
    }
    count=definitions.size()/3;
    for(int64_t index=0;index<count;++index)skills[index]={definitions[index*3],definitions[index*3+1],definitions[index*3+2],0};
    return true;
}
Dictionary NativePlayerProgression::snapshot() const {
    Dictionary out,ranks;
    const int64_t level=level_for(experience);
    for(int64_t index=0;index<count;++index)ranks[skills[index].id]=skills[index].rank;
    out["xp"]=experience;out["level"]=level;out["points"]=available_points();out["revision"]=revision;
    out["level_start"]=threshold(level);out["next_level"]=threshold(std::min(level+1,MAX_LEVEL));
    out["maximum_level"]=MAX_LEVEL;out["skills"]=ranks;return out;
}
Dictionary NativePlayerProgression::award(int64_t amount,int64_t expected_revision) {
    if(!count||amount<1||amount>1000000)return result(false,"invalid_award");
    if(expected_revision!=revision)return result(false,"stale_revision");
    const int64_t gained=std::min(amount,threshold(MAX_LEVEL)-experience);
    const int64_t previous_level=level_for(experience);
    experience+=gained;if(gained)++revision;
    Dictionary out=result(true,"");out["gained"]=gained;out["levels"]=level_for(experience)-previous_level;
    out["level"]=level_for(experience);return out;
}
Dictionary NativePlayerProgression::spend(int64_t skill,int64_t expected_revision) {
    if(expected_revision!=revision)return result(false,"stale_revision");
    for(int64_t index=0;index<count;++index)if(skills[index].id==skill) {
        if(skills[index].rank>=skills[index].maximum)return result(false,"maximum_rank");
        if(available_points()<1)return result(false,"no_points");
        ++skills[index].rank;++revision;return result(true,"");
    }
    return result(false,"unknown_skill");
}
int64_t NativePlayerProgression::scale_action(int64_t skill,int64_t base) const {
    if(base<0||base>1000000)return 0;
    for(int64_t index=0;index<count;++index)if(skills[index].id==skill)
        return (base*(1000+skills[index].bonus*skills[index].rank)+500)/1000;
    return base;
}
PackedByteArray NativePlayerProgression::capture_storage_snapshot() const {
    PackedByteArray data;data.resize(24+count*8);
    data.encode_u32(0,0x50584654);data.encode_u32(4,1);data.encode_u32(8,count);data.encode_u32(12,0);data.encode_u64(16,experience);
    for(int64_t index=0;index<count;++index) {
        data.encode_u32(24+index*8,skills[index].id);data.encode_u32(28+index*8,skills[index].rank);
    }
    return data;
}
bool NativePlayerProgression::validate_snapshot(const PackedByteArray &data) const {
    if(!count||data.size()<24||data.size()>280||data.decode_u32(0)!=0x50584654||data.decode_u32(4)!=1||data.decode_u32(12)!=0)return false;
    const uint32_t saved_count=data.decode_u32(8);
    if(!saved_count||saved_count>count||data.size()!=24+saved_count*8)return false;
    const uint64_t saved_xp=data.decode_u64(16);
    if(saved_xp>uint64_t(threshold(MAX_LEVEL)))return false;
    int64_t spent=0,catalog_index=0,previous=0;
    for(uint32_t index=0;index<saved_count;++index) {
        const uint32_t identity=data.decode_u32(24+index*8);
        const uint32_t rank=data.decode_u32(28+index*8);
        while(catalog_index<count&&skills[catalog_index].id<identity)++catalog_index;
        if(identity<=previous||catalog_index==count||skills[catalog_index].id!=identity||rank>skills[catalog_index].maximum)return false;
        previous=identity;spent+=rank;
    }
    return spent<=level_for(saved_xp)-1;
}
bool NativePlayerProgression::restore_storage_snapshot(const PackedByteArray &data) {
    if(!validate_snapshot(data))return false;
    experience=data.decode_u64(16);
    for(int64_t index=0;index<count;++index)skills[index].rank=0;
    int64_t catalog_index=0;
    for(uint32_t index=0;index<data.decode_u32(8);++index) {
        while(skills[catalog_index].id!=data.decode_u32(24+index*8))++catalog_index;
        skills[catalog_index].rank=data.decode_u32(28+index*8);
    }
    ++revision;return true;
}
}
