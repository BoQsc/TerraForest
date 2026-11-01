// SPDX-License-Identifier: 0BSD
#include "combat_state.hpp"
#include "../../structures/native/block_word.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <map>
#include <tuple>
#include <queue>
#include <cmath>
#include <algorithm>
namespace terraforest {
using namespace godot;
static bool valid_records(const PackedInt32Array &r);
void NativeCombatState::_bind_methods(){
    ClassDB::bind_method(D_METHOD("get_rounds"),&NativeCombatState::get_rounds);
    ClassDB::bind_method(D_METHOD("take_round"),&NativeCombatState::take_round);
    ClassDB::bind_method(D_METHOD("load_rounds","count"),&NativeCombatState::load_rounds);
    ClassDB::bind_method(D_METHOD("integrity_enabled"),&NativeCombatState::integrity_enabled);
    ClassDB::bind_method(D_METHOD("set_integrity_enabled","enabled"),&NativeCombatState::set_integrity_enabled);
    ClassDB::bind_method(D_METHOD("capture_storage_snapshot"),&NativeCombatState::capture_storage_snapshot);
    ClassDB::bind_method(D_METHOD("validate_snapshot","bytes"),&NativeCombatState::validate_snapshot);
    ClassDB::bind_method(D_METHOD("restore_storage_snapshot","bytes"),&NativeCombatState::restore_storage_snapshot);
    ClassDB::bind_method(D_METHOD("set_blast_jobs","jobs"),&NativeCombatState::set_blast_jobs);
    ClassDB::bind_method(D_METHOD("get_blast_jobs"),&NativeCombatState::get_blast_jobs);
    ClassDB::bind_method(D_METHOD("support_probes","records","origin"),&NativeCombatState::support_probes);
    ClassDB::bind_method(D_METHOD("unsupported","records","origin","size","density"),&NativeCombatState::unsupported);
    ClassDB::bind_method(D_METHOD("blast_cells","records","origin","center","radius"),&NativeCombatState::blast_cells);
}
PackedByteArray NativeCombatState::capture_storage_snapshot() const {
    int bytes=20;for(auto &job:blasts)bytes+=20+job.records.size()*4;
    PackedByteArray b;b.resize(bytes);b.encode_u32(0,0x31434654);b.encode_u32(4,2);b.encode_u32(8,rounds);b.encode_u32(12,integrity?1:0);b.encode_u32(16,blasts.size());
    int at=20;for(auto &job:blasts){for(int axis=0;axis<3;axis++)b.encode_float(at+axis*4,job.center[axis]);b.encode_u32(at+12,job.offset);b.encode_u32(at+16,job.records.size());at+=20;for(int word:job.records){b.encode_s32(at,word);at+=4;}}return b;
}
static bool decode_jobs(const PackedByteArray &b,std::vector<CombatBlast> *out){
    if(b.size()<16||b.size()>600000||b.decode_u32(0)!=0x31434654||b.decode_u32(8)>30||b.decode_u32(12)>1)return false;
    if(b.decode_u32(4)==1)return b.size()==16;
    if(b.decode_u32(4)!=2||b.size()<20||b.decode_u32(16)>32)return false;
    int at=20,total=0;for(unsigned i=0;i<b.decode_u32(16);i++){
        if(at+20>b.size())return false;CombatBlast job;for(int axis=0;axis<3;axis++)job.center[axis]=b.decode_float(at+axis*4);
        auto offset=b.decode_u32(at+12),count=b.decode_u32(at+16);at+=20;
        if(!job.center.is_finite()||count>32768*4||count%4||offset>count||offset%4||at+int64_t(count)*4>b.size()||(total+=count)>131072)return false;
        job.offset=offset;job.records.resize(count);for(unsigned n=0;n<count;n++,at+=4)job.records.set(n,b.decode_s32(at));
        if(!valid_records(job.records))return false;if(out)out->push_back(std::move(job));
    }return at==b.size();
}
bool NativeCombatState::validate_snapshot(const PackedByteArray &b) const {return decode_jobs(b,nullptr);}
bool NativeCombatState::restore_storage_snapshot(const PackedByteArray &b){std::vector<CombatBlast> staged;if(!decode_jobs(b,&staged))return false;rounds=b.decode_u32(8);integrity=b.decode_u32(12)!=0;blasts.swap(staged);return true;}
bool NativeCombatState::set_blast_jobs(const Array &jobs){
    if(jobs.size()>32)return false;std::vector<CombatBlast> staged;int total=0;
    for(int i=0;i<jobs.size();i++){
        if(jobs[i].get_type()!=Variant::DICTIONARY)return false;Dictionary value=jobs[i];
        if(value.get("center",Variant()).get_type()!=Variant::VECTOR3||value.get("records",Variant()).get_type()!=Variant::PACKED_INT32_ARRAY||value.get("offset",Variant()).get_type()!=Variant::INT)return false;
        CombatBlast job;job.center=value["center"];job.records=value["records"];int64_t offset=value["offset"];
        if(!job.center.is_finite()||!valid_records(job.records)||offset<0||offset>job.records.size()||offset%4||(total+=job.records.size())>131072)return false;
        job.offset=offset;staged.push_back(std::move(job));
    }blasts.swap(staged);return true;
}
Array NativeCombatState::get_blast_jobs() const {Array out;for(auto &job:blasts){Dictionary value;value["center"]=job.center;value["records"]=job.records;value["offset"]=job.offset;out.append(value);}return out;}
static bool valid_records(const PackedInt32Array &r){
    if(r.size()%4||r.size()>32768*4)return false;
    for(int i=0;i<r.size();i+=4)if(!valid_block_word(r[i+3])||!r[i+3]||std::abs(int64_t(r[i]))>1048575||std::abs(int64_t(r[i+1]))>1048575||std::abs(int64_t(r[i+2]))>1048575)return false;
    return true;
}
PackedVector3Array NativeCombatState::support_probes(const PackedInt32Array &r,Vector3i origin) const {
    PackedVector3Array points;if(!valid_records(r))return points;
    points.resize(r.size()/4);for(int i=0;i<r.size();i+=4)points.set(i/4,Vector3(origin)+Vector3(r[i]+.5,r[i+1]-.08,r[i+2]+.5));return points;
}
PackedInt32Array NativeCombatState::unsupported(const PackedInt32Array &r,Vector3i origin,Vector3i size,const PackedFloat32Array &density) const {
    PackedInt32Array out;if(!valid_records(r)||density.size()!=r.size()/4||size.x<1||size.y<1||size.z<1||size.x>64||size.y>64||size.z>64)return out;
    using Key=std::tuple<int,int,int>;std::map<Key,int> index;
    const int n=r.size()/4;std::vector<int> strength(n,-1);std::priority_queue<std::pair<int,int>> queue;
    constexpr int capacity[4]={16,20,24,32},lateral[4]={4,3,3,2};
    for(int i=0;i<n;i++){
        const int x=r[i*4],y=r[i*4+1],z=r[i*4+2];
        if(x<0||y<0||z<0||x>=size.x||y>=size.y||z>=size.z||!std::isfinite(density[i])||!index.emplace(Key(x,y,z),i).second)return {};
        // Boundary cells are conservatively anchored: a bounded query must not
        // demolish a connection whose continuation lies outside its resident box.
        if(density[i]<0||x==0||y==0||z==0||x==size.x-1||y==size.y-1||z==size.z-1){strength[i]=capacity[block_material(r[i*4+3])];queue.push({strength[i],i});}
    }
    constexpr int axes[6][3]={{1,0,0},{-1,0,0},{0,1,0},{0,-1,0},{0,0,1},{0,0,-1}};
    while(!queue.empty()){
        auto [value,i]=queue.top();queue.pop();if(value!=strength[i])continue;
        for(auto &d:axes){auto at=index.find(Key(r[i*4]+d[0],r[i*4+1]+d[1],r[i*4+2]+d[2]));if(at==index.end())continue;
            int j=at->second,material=block_material(r[j*4+3]);
            int remaining=std::min(capacity[material],value-(d[1]!=0?1:lateral[material]));
            if(remaining>=0&&remaining>strength[j]){strength[j]=remaining;queue.push({remaining,j});}
        }
    }
    for(int i=0;i<n;i++)if(strength[i]<0){out.append(origin.x+r[i*4]);out.append(origin.y+r[i*4+1]);out.append(origin.z+r[i*4+2]);out.append(r[i*4+3]);}return out;
}
PackedInt32Array NativeCombatState::blast_cells(const PackedInt32Array &r,Vector3i origin,Vector3 center,double radius) const {
    PackedInt32Array out;if(!valid_records(r)||!center.is_finite()||!std::isfinite(radius)||radius<.5||radius>8)return out;
    for(int i=0;i<r.size();i+=4){Vector3 p=Vector3(origin)+Vector3(r[i]+.5,r[i+1]+.5,r[i+2]+.5);if(p.distance_squared_to(center)>radius*radius)continue;
        out.append(origin.x+r[i]);out.append(origin.y+r[i+1]);out.append(origin.z+r[i+2]);out.append(r[i+3]);}return out;
}
}
