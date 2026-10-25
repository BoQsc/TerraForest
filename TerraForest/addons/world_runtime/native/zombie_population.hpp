#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <algorithm>
#include <array>
#include <cmath>
#include <vector>

namespace terraforest {
class NativeZombiePopulation : public godot::RefCounted {
    GDCLASS(NativeZombiePopulation,godot::RefCounted)
    struct Resident {godot::Vector3 position;float yaw=0;uint32_t state=0;godot::PackedByteArray vitals;};
    std::vector<Resident> residents_;
    std::array<std::vector<int>,2500> cells_;
    int64_t seed_=-1,revision_=0;
    godot::Vector3 sanctuary_;
    static uint32_t mix(uint32_t value){value^=value>>16;value*=0x7feb352d;value^=value>>15;value*=0x846ca68b;return value^(value>>16);}
    static int cell(godot::Vector3 point){return std::clamp(int(std::floor(point.x/40)),0,49)+50*std::clamp(int(std::floor(point.z/40)),0,49);}
    static bool valid_position(godot::Vector3 point){return point.is_finite()&&point.x>=0&&point.x<=2000&&point.z>=0&&point.z<=2000&&point.y>=-256&&point.y<=512;}
    static bool valid_vitals(const godot::PackedByteArray &bytes){
        if(bytes.is_empty())return true;
        if(bytes.size()!=60||bytes.decode_u32(56)>=16384)return false;
        constexpr float maximum[]={180,50,50,38,24,50,38,24,65,52,32,65,52,32};
        constexpr int parent[]={-1,0,0,2,3,0,5,6,0,8,9,0,11,12};
        uint32_t missing=bytes.decode_u32(56);
        for(int part=0;part<14;part++){
            double health=bytes.decode_float(part*4);
            if(!std::isfinite(health)||health<0||health>maximum[part]||((missing&(1<<part))&&health!=0))return false;
            if(parent[part]>=0&&(missing&(1<<parent[part]))&&!(missing&(1<<part)))return false;
        }
        return !(missing&3)||bytes.decode_float(0)==0;
    }
    void index(){for(auto &bucket:cells_)bucket.clear();for(int item=0;item<int(residents_.size());item++)if(residents_[item].state<2)cells_[cell(residents_[item].position)].push_back(item);}
protected:
    static void _bind_methods(){
        using namespace godot;
        ClassDB::bind_method(D_METHOD("initialize","seed","sanctuary"),&NativeZombiePopulation::initialize);
        ClassDB::bind_method(D_METHOD("nearby","focus","radius"),&NativeZombiePopulation::nearby);
        ClassDB::bind_method(D_METHOD("resident","identity"),&NativeZombiePopulation::resident);
        ClassDB::bind_method(D_METHOD("update_resident","identity","position","yaw","vitals"),&NativeZombiePopulation::update_resident);
        ClassDB::bind_method(D_METHOD("add_resident","position","yaw","vitals"),&NativeZombiePopulation::add_resident);
        ClassDB::bind_method(D_METHOD("exclude","identity"),&NativeZombiePopulation::exclude);
        ClassDB::bind_method(D_METHOD("capture_snapshot"),&NativeZombiePopulation::capture_snapshot);
        ClassDB::bind_method(D_METHOD("validate_snapshot","bytes"),&NativeZombiePopulation::validate_snapshot);
        ClassDB::bind_method(D_METHOD("restore_snapshot","bytes"),&NativeZombiePopulation::restore_snapshot);
        ClassDB::bind_method(D_METHOD("statistics"),&NativeZombiePopulation::statistics);
    }
public:
    bool initialize(int64_t seed,godot::Vector3 sanctuary){
        if(seed<0||seed>2147483647||!valid_position(sanctuary))return false;
        if(seed_>=0)return seed_==seed;
        seed_=seed;sanctuary_=sanctuary;residents_.resize(2500);
        for(int item=0;item<2500;item++){
            uint32_t random=mix(uint32_t(seed)^mix(item+1));auto &record=residents_[item];
            record.position={float(item%50)*40+10+float(random&65535)*20/65535,0,float(item/50)*40+10+float(random>>16)*20/65535};
            record.yaw=float(mix(random)&65535)*6.28318530718f/65535;
            auto offset=record.position-sanctuary;offset.y=0;if(offset.length_squared()<40*40)record.state=3;
        }
        index();revision_++;return true;
    }
    godot::Dictionary resident(int64_t identity)const{
        godot::Dictionary out;if(identity<1||identity>int64_t(residents_.size()))return out;
        const auto &record=residents_[identity-1];out["id"]=identity;out["position"]=record.position;out["yaw"]=record.yaw;out["state"]=record.state;out["vitals"]=record.vitals;return out;
    }
    godot::Array nearby(godot::Vector3 focus,double radius)const{
        godot::Array out;if(!valid_position(focus)||!std::isfinite(radius)||radius<=0||radius>96)return out;
        std::vector<std::pair<float,int>> matches;
        int min_x=std::clamp(int(std::floor((focus.x-radius)/40)),0,49),max_x=std::clamp(int(std::floor((focus.x+radius)/40)),0,49);
        int min_z=std::clamp(int(std::floor((focus.z-radius)/40)),0,49),max_z=std::clamp(int(std::floor((focus.z+radius)/40)),0,49);
        for(int row=min_z;row<=max_z;row++)for(int column=min_x;column<=max_x;column++)for(int item:cells_[column+50*row]){
            auto offset=residents_[item].position-focus;offset.y=0;float distance=offset.length_squared();
            if(residents_[item].state<2&&distance<=radius*radius)matches.push_back({distance,item});
        }
        std::sort(matches.begin(),matches.end());
        for(int item=0;item<std::min(32,int(matches.size()));item++)out.append(resident(matches[item].second+1));
        return out;
    }
    bool update_resident(int64_t identity,godot::Vector3 position,double yaw,const godot::PackedByteArray &vitals){
        if(identity<1||identity>int64_t(residents_.size())||!valid_position(position)||!std::isfinite(yaw)||std::abs(yaw)>10000||!valid_vitals(vitals))return false;
        auto &record=residents_[identity-1];if(record.state>=2)return false;
        int previous=cell(record.position);record.position=position;record.yaw=yaw;record.vitals=vitals;record.state=!vitals.is_empty()&&vitals.decode_float(0)==0?2:1;
        if(cell(position)!=previous||record.state==2){
            auto &bucket=cells_[previous];bucket.erase(std::remove(bucket.begin(),bucket.end(),int(identity-1)),bucket.end());
            if(record.state<2)cells_[cell(position)].push_back(identity-1);
        }
        revision_++;return true;
    }
    bool exclude(int64_t identity){
        if(identity<1||identity>int64_t(residents_.size())||residents_[identity-1].state!=0)return false;
        auto &record=residents_[identity-1];record.state=3;auto &bucket=cells_[cell(record.position)];bucket.erase(std::remove(bucket.begin(),bucket.end(),int(identity-1)),bucket.end());revision_++;return true;
    }
    int64_t add_resident(godot::Vector3 position,double yaw,const godot::PackedByteArray &vitals){
        if(seed_<0||residents_.size()>=2756||!valid_position(position)||!std::isfinite(yaw)||std::abs(yaw)>10000||vitals.is_empty()||!valid_vitals(vitals)||vitals.decode_float(0)<=0)return 0;
        const int identity=int(residents_.size())+1;
        residents_.push_back({position,float(yaw),1,vitals});cells_[cell(position)].push_back(identity-1);revision_++;return identity;
    }
    godot::PackedByteArray capture_snapshot()const{
        godot::PackedByteArray out;if(seed_<0)return out;
        out.resize(32+residents_.size()*84);out.fill(0);out.encode_u32(0,0x31505a54);out.encode_u32(4,residents_.size()==2500?1:2);out.encode_u32(8,seed_);out.encode_u32(12,residents_.size());
        for(int axis=0;axis<3;axis++)out.encode_float(16+axis*4,sanctuary_[axis]);
        for(int item=0;item<int(residents_.size());item++){
            const auto &record=residents_[item];int at=32+item*84;
            for(int axis=0;axis<3;axis++)out.encode_float(at+axis*4,record.position[axis]);
            out.encode_float(at+12,record.yaw);out.encode_u32(at+16,record.state);out.encode_u32(at+20,record.vitals.size());
            for(int byte=0;byte<record.vitals.size();byte++)out.set(at+24+byte,record.vitals[byte]);
        }
        return out;
    }
    bool validate_snapshot(const godot::PackedByteArray &bytes)const{
        if(bytes.is_empty())return true;
        if(bytes.size()<32||bytes.decode_u32(0)!=0x31505a54||bytes.decode_u32(8)>2147483647||bytes.decode_u32(28)!=0)return false;
        const uint32_t version=bytes.decode_u32(4),count=bytes.decode_u32(12);
        if(count<2500||count>2756||bytes.size()!=32+count*84||!((version==1&&count==2500)||(version==2&&count>2500)))return false;
        if(!valid_position({float(bytes.decode_float(16)),float(bytes.decode_float(20)),float(bytes.decode_float(24))}))return false;
        for(uint32_t item=0;item<count;item++){
            int at=32+item*84;uint32_t state=bytes.decode_u32(at+16),size=bytes.decode_u32(at+20);double yaw=bytes.decode_float(at+12);
            if(!valid_position({float(bytes.decode_float(at)),float(bytes.decode_float(at+4)),float(bytes.decode_float(at+8))})||!std::isfinite(yaw)||std::abs(yaw)>10000||state>3||(size!=0&&size!=60))return false;
            if(!valid_vitals(bytes.slice(at+24,at+24+size)))return false;
            if(state==2&&(size!=60||bytes.decode_float(at+24)!=0))return false;
            if(state!=2&&size&&bytes.decode_float(at+24)<=0)return false;
            if((state==0||state==3)&&size)return false;
            if(size==0)for(int byte=0;byte<60;byte++)if(bytes[at+24+byte])return false;
        }
        return true;
    }
    bool restore_snapshot(const godot::PackedByteArray &bytes){
        if(!validate_snapshot(bytes))return false;
        residents_.clear();seed_=-1;sanctuary_={};
        if(!bytes.is_empty()){
            seed_=bytes.decode_u32(8);sanctuary_={float(bytes.decode_float(16)),float(bytes.decode_float(20)),float(bytes.decode_float(24))};residents_.resize(bytes.decode_u32(12));
            for(int item=0;item<int(residents_.size());item++){
                int at=32+item*84;auto &record=residents_[item];record.position={float(bytes.decode_float(at)),float(bytes.decode_float(at+4)),float(bytes.decode_float(at+8))};
                record.yaw=bytes.decode_float(at+12);record.state=bytes.decode_u32(at+16);record.vitals=bytes.slice(at+24,at+24+bytes.decode_u32(at+20));
            }
        }
        index();revision_++;return true;
    }
    godot::Dictionary statistics()const{godot::Dictionary out;out["seed"]=seed_;out["slots"]=residents_.size();out["revision"]=revision_;return out;}
};
}
