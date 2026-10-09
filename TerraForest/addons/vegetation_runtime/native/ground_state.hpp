// SPDX-License-Identifier: 0BSD
#pragma once
#include "scatter.hpp"
#include <map>
#include <set>
#include <array>
#include <cstring>
namespace terraforest {
// Main-thread mutations/capture. Snapshot validation is pure for archive workers.
class NativeGroundCoverState : public RefCounted {
    GDCLASS(NativeGroundCoverState, RefCounted)
    static constexpr uint64_t MAGIC=0x315453444e554f47ULL; // GOUNDST1
    static constexpr int64_t NATURAL_LIMIT=63*63*64;
    static constexpr int64_t AUTHORED_FIRST=int64_t(1)<<32;
    static constexpr size_t PLACED_LIMIT=100000, CELL_LIMIT=256;
    struct Placement {int species;std::array<float,12> t;};
    std::set<int64_t> removed;
    std::map<int64_t,Placement> placed;
    std::map<int,std::set<int64_t>> cells;
    int64_t seed=-1, generator=0, next_id=AUTHORED_FIRST;
    mutable bool dirty=true;
    mutable PackedByteArray cache;
    static uint64_t read(const uint8_t *p){uint64_t v=0;for(int i=0;i<8;++i)v|=uint64_t(p[i])<<(i*8);return v;}
    static void write(uint8_t *p,uint64_t v){for(int i=0;i<8;++i)p[i]=uint8_t(v>>(i*8));}
    static float read_float(const uint8_t *p){uint32_t v=0;for(int i=0;i<4;++i)v|=uint32_t(p[i])<<(i*8);float out;std::memcpy(&out,&v,4);return out;}
    static void write_float(uint8_t *p,float v){uint32_t bits;std::memcpy(&bits,&v,4);for(int i=0;i<4;++i)p[i]=uint8_t(bits>>(i*8));}
    static int cell(const Placement &p){return int(std::floor(p.t[11]/32))*63+int(std::floor(p.t[3]/32));}
    static bool valid(const Placement &p){
        if(p.species<0||p.species>2)return false;
        for(float v:p.t)if(!std::isfinite(v))return false;
        if(p.t[3]<2||p.t[3]>=1998||p.t[11]<2||p.t[11]>=1998||p.t[7]<-1||p.t[7]>257)return false;
        Basis b(Vector3(p.t[0],p.t[4],p.t[8]),Vector3(p.t[1],p.t[5],p.t[9]),Vector3(p.t[2],p.t[6],p.t[10]));
        if(std::abs(b.determinant())<0.001)return false;
        for(int i=0;i<3;++i){float length=b.get_column(i).length_squared();if(length<.01f||length>16.f)return false;}
        return true;
    }
protected:
    static void _bind_methods(){
        ClassDB::bind_method(D_METHOD("bind_world","seed","generator"),&NativeGroundCoverState::bind_world);
        ClassDB::bind_method(D_METHOD("profile"),&NativeGroundCoverState::profile);
        ClassDB::bind_method(D_METHOD("contains","id"),&NativeGroundCoverState::contains);
        ClassDB::bind_method(D_METHOD("mark","id"),&NativeGroundCoverState::mark);
        ClassDB::bind_method(D_METHOD("unmark","id"),&NativeGroundCoverState::unmark);
        ClassDB::bind_method(D_METHOD("mask","ids"),&NativeGroundCoverState::mask);
        ClassDB::bind_method(D_METHOD("add","species","transform"),&NativeGroundCoverState::add);
        ClassDB::bind_method(D_METHOD("erase","id"),&NativeGroundCoverState::erase);
        ClassDB::bind_method(D_METHOD("query","cell"),&NativeGroundCoverState::query);
        ClassDB::bind_method(D_METHOD("sample_transforms","cell"),&NativeGroundCoverState::sample_transforms);
        ClassDB::bind_method(D_METHOD("query_filtered","cell","blocked","water"),&NativeGroundCoverState::query_filtered);
        ClassDB::bind_method(D_METHOD("capture_storage_snapshot"),&NativeGroundCoverState::capture_storage_snapshot);
        ClassDB::bind_method(D_METHOD("validate_snapshot","data"),&NativeGroundCoverState::validate_snapshot);
        ClassDB::bind_method(D_METHOD("restore_storage_snapshot","data"),&NativeGroundCoverState::restore_storage_snapshot);
    }
public:
    bool bind_world(int64_t p_seed,int64_t p_generator){
        if(p_seed<0||p_seed>INT32_MAX||p_generator!=1)return false;
        if(seed>=0)return seed==p_seed&&generator==p_generator;
        seed=p_seed;generator=p_generator;dirty=true;return true;
    }
    Dictionary profile() const {Dictionary d;d["seed"]=seed;d["generator"]=generator;d["removed"]=int64_t(removed.size());d["placed"]=int64_t(placed.size());return d;}
    bool contains(int64_t id) const{return removed.count(id)!=0;}
    bool mark(int64_t id){if(seed<0||id<1||id>NATURAL_LIMIT)return false;bool ok=removed.insert(id).second;dirty|=ok;return ok;}
    bool unmark(int64_t id){bool ok=removed.erase(id)!=0;dirty|=ok;return ok;}
    PackedByteArray mask(const PackedInt64Array &ids) const{
        PackedByteArray out;if(ids.size()>64)return out;out.resize(ids.size());
        for(int64_t i=0;i<ids.size();++i)out.set(i,contains(ids[i])?1:0);return out;
    }
    int64_t add(int64_t species,const Transform3D &transform){
        if(seed<0||species<0||species>2||placed.size()>=PLACED_LIMIT||next_id==INT64_MAX)return 0;
        Placement p;p.species=int(species);
        for(int r=0;r<3;++r){for(int c=0;c<3;++c)p.t[r*4+c]=transform.basis[r][c];p.t[r*4+3]=transform.origin[r];}
        if(!valid(p))return 0;
        int key=cell(p);auto owner=cells.find(key);if(owner!=cells.end()&&owner->second.size()>=CELL_LIMIT)return 0;
        int64_t id=next_id++;placed.emplace(id,p);cells[key].insert(id);dirty=true;return id;
    }
    bool erase(int64_t id){
        auto found=placed.find(id);if(found==placed.end())return false;
        int key=cell(found->second);auto &owner=cells.at(key);owner.erase(id);if(owner.empty())cells.erase(key);
        placed.erase(found);dirty=true;return true;
    }
    Array query(Vector2i key) const{
        Array out;PackedInt64Array ids[3];PackedFloat32Array transforms[3];
        if(key.x<0||key.y<0||key.x>=63||key.y>=63)return out;
        auto found=cells.find(key.y*63+key.x);
        if(found!=cells.end())for(auto id:found->second){const auto &p=placed.at(id);ids[p.species].append(id);for(float v:p.t)transforms[p.species].append(v);}
        for(int i=0;i<3;++i){Dictionary d;d["ids"]=ids[i];d["transforms"]=transforms[i];out.append(d);}return out;
    }
    TypedArray<Transform3D> sample_transforms(Vector2i key) const{
        TypedArray<Transform3D> out;
        if(key.x<0||key.y<0||key.x>=63||key.y>=63)return out;
        auto found=cells.find(key.y*63+key.x);if(found==cells.end())return out;
        for(int species=0;species<3;++species)for(auto id:found->second){
            const auto &p=placed.at(id);if(p.species!=species)continue;
            Transform3D t;for(int r=0;r<3;++r){for(int c=0;c<3;++c)t.basis[r][c]=p.t[r*4+c];t.origin[r]=p.t[r*4+3];}out.append(t);
        }
        return out;
    }
    Array query_filtered(Vector2i key,const PackedByteArray &blocked,const PackedByteArray &water) const{
        if(key.x<0||key.y<0||key.x>=63||key.y>=63)return Array();
        auto found=cells.find(key.y*63+key.x);size_t count=found==cells.end()?0:found->second.size();
        if(blocked.size()!=int64_t(count)||water.size()!=int64_t(count))return Array();
        Array out;size_t index=0;
        for(int species=0;species<3;++species){
            PackedInt64Array ids;PackedFloat32Array transforms;
            if(found!=cells.end())for(auto id:found->second){
                const auto &p=placed.at(id);if(p.species!=species)continue;
                bool excluded=blocked[index]||water[index];++index;if(excluded)continue;
                ids.append(id);for(float v:p.t)transforms.append(v);
            }
            Dictionary row;row["ids"]=ids;row["transforms"]=transforms;out.append(row);
        }
        return out;
    }
    PackedByteArray capture_storage_snapshot() const{
        if(!dirty)return cache;
        PackedByteArray data;data.resize(64+removed.size()*8+placed.size()*64);auto *p=data.ptrw();
        write(p,MAGIC);write(p+8,1);write(p+16,uint64_t(seed));write(p+24,generator);write(p+32,next_id);write(p+40,removed.size());write(p+48,placed.size());write(p+56,0);
        size_t offset=64;for(auto id:removed){write(p+offset,id);offset+=8;}
        for(const auto &entry:placed){write(p+offset,entry.first);write(p+offset+8,entry.second.species);for(int i=0;i<12;++i)write_float(p+offset+16+i*4,entry.second.t[i]);offset+=64;}
        cache=data;dirty=false;return cache;
    }
    bool validate_snapshot(const PackedByteArray &data) const{
        if(data.size()<64||data.size()>int64_t(64+NATURAL_LIMIT*8+PLACED_LIMIT*64))return false;
        const auto *p=data.ptr();uint64_t s=read(p+16),g=read(p+24),next=read(p+32),nr=read(p+40),np=read(p+48);
        if(read(p)!=MAGIC||read(p+8)!=1||read(p+56)!=0||nr>NATURAL_LIMIT||np>PLACED_LIMIT||next<AUTHORED_FIRST||next>INT64_MAX||data.size()!=int64_t(64+nr*8+np*64))return false;
        if(s==UINT64_MAX){if(g||nr||np||next!=AUTHORED_FIRST)return false;}else if(s>INT32_MAX||g!=1)return false;
        uint64_t previous=0;size_t offset=64;
        for(uint64_t i=0;i<nr;++i){uint64_t id=read(p+offset);if(id<=previous||id>NATURAL_LIMIT)return false;previous=id;offset+=8;}
        std::map<int,size_t> counts;previous=AUTHORED_FIRST-1;
        for(uint64_t i=0;i<np;++i){
            uint64_t id=read(p+offset),species=read(p+offset+8);if(id<=previous||id>=next||species>2)return false;
            Placement value;value.species=int(species);for(int j=0;j<12;++j)value.t[j]=read_float(p+offset+16+j*4);
            if(!valid(value)||++counts[cell(value)]>CELL_LIMIT)return false;
            previous=id;offset+=64;
        }
        return true;
    }
    bool restore_storage_snapshot(const PackedByteArray &data){
        if(!validate_snapshot(data))return false;
        std::set<int64_t> staged_removed;std::map<int64_t,Placement> staged_placed;std::map<int,std::set<int64_t>> staged_cells;
        const auto *p=data.ptr();size_t offset=64;
        for(uint64_t i=0;i<read(p+40);++i){staged_removed.insert(int64_t(read(p+offset)));offset+=8;}
        for(uint64_t i=0;i<read(p+48);++i){int64_t id=int64_t(read(p+offset));Placement value;value.species=int(read(p+offset+8));for(int j=0;j<12;++j)value.t[j]=read_float(p+offset+16+j*4);staged_placed.emplace(id,value);staged_cells[cell(value)].insert(id);offset+=64;}
        removed.swap(staged_removed);placed.swap(staged_placed);cells.swap(staged_cells);
        seed=read(p+16)==UINT64_MAX?-1:int64_t(read(p+16));generator=int64_t(read(p+24));next_id=int64_t(read(p+32));cache=data;dirty=false;return true;
    }
};
}
