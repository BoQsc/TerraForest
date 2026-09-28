#include "block_prefab.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <algorithm>
#include <tuple>

namespace terraforest {
void NativeBlockPrefab::_bind_methods() {
    ClassDB::bind_method(D_METHOD("configure","records"),&NativeBlockPrefab::configure);
    ClassDB::bind_method(D_METHOD("set_records","records"),&NativeBlockPrefab::set_records);
    ClassDB::bind_method(D_METHOD("get_records"),&NativeBlockPrefab::get_records);
    ClassDB::bind_method(D_METHOD("get_cell_count"),&NativeBlockPrefab::get_cell_count);
    ClassDB::bind_method(D_METHOD("get_bounds"),&NativeBlockPrefab::get_bounds);
    ClassDB::bind_method(D_METHOD("placement_bounds","origin","quarter_turns"),&NativeBlockPrefab::placement_bounds);
    ADD_PROPERTY(PropertyInfo(Variant::PACKED_INT32_ARRAY,"records"),"set_records","get_records");
}
bool NativeBlockPrefab::configure(const PackedInt32Array &records) {
    if(records.size()%4||records.size()>4*262144)return false;
    std::vector<PrefabCell> staged;
    staged.reserve(records.size()/4);
    Vector3 lo(4096,4096,4096),hi(-4096,-4096,-4096);
    for(int64_t i=0;i<records.size();i+=4) {
        int x=records[i],y=records[i+1],z=records[i+2],w=records[i+3];
        if(x<-4095||x>4095||y<-4095||y>4095||z<-4095||z>4095||w<=0||w>=128||(w&7)>5||(w&7)==0)return false;
        staged.push_back({x,y,z,w});
        for(int a=0;a<3;a++) {lo[a]=std::min(lo[a],float(records[i+a]));hi[a]=std::max(hi[a],float(records[i+a]+1));}
    }
    auto less=[](const PrefabCell &a,const PrefabCell &b){return std::tie(a.x,a.y,a.z)<std::tie(b.x,b.y,b.z);};
    std::sort(staged.begin(),staged.end(),less);
    for(size_t i=1;i<staged.size();i++)if(!less(staged[i-1],staged[i]))return false;
    cells=std::move(staged);bounds=cells.empty()?AABB():AABB(lo,hi-lo);emit_changed();return true;
}
void NativeBlockPrefab::set_records(const PackedInt32Array &records) {
    ERR_FAIL_COND_MSG(!configure(records),"Invalid block prefab records; previous asset preserved");
}
PackedInt32Array NativeBlockPrefab::get_records() const {
    PackedInt32Array out;out.resize(cells.size()*4);int i=0;
    for(const auto &c:cells) {out.set(i++,c.x);out.set(i++,c.y);out.set(i++,c.z);out.set(i++,c.word);}
    return out;
}
AABB NativeBlockPrefab::placement_bounds(Vector3i origin,int turns) const {
    if(turns<0||turns>3||cells.empty())return AABB();
    Vector3 lo=bounds.position,hi=bounds.get_end();
    // Integer cell rotation about the centre of local cell (0,0,0).
    for(int r=0;r<turns;r++) {Vector3 old=lo;lo=Vector3(1-hi.z,lo.y,old.x);hi=Vector3(1-old.z,hi.y,hi.x);}
    return AABB(Vector3(origin)+lo,hi-lo);
}
}
