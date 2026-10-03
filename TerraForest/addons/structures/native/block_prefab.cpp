#include "block_prefab.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/classes/ref.hpp>
#include <algorithm>
#include <tuple>
#include <map>

namespace terraforest {
void NativeBlockPrefab::_bind_methods() {
    ClassDB::bind_method(D_METHOD("configure","records"),&NativeBlockPrefab::configure);
    ClassDB::bind_method(D_METHOD("compose","sources","placements"),&NativeBlockPrefab::compose);
    ClassDB::bind_method(D_METHOD("compose_frontage","sources","lots_per_side","street_width","gap","seed"),&NativeBlockPrefab::compose_frontage);
    ClassDB::bind_method(D_METHOD("set_records","records"),&NativeBlockPrefab::set_records);
    ClassDB::bind_method(D_METHOD("get_records"),&NativeBlockPrefab::get_records);
    ClassDB::bind_method(D_METHOD("get_cell_count"),&NativeBlockPrefab::get_cell_count);
    ClassDB::bind_method(D_METHOD("get_bounds"),&NativeBlockPrefab::get_bounds);
    ClassDB::bind_method(D_METHOD("placement_bounds","origin","quarter_turns"),&NativeBlockPrefab::placement_bounds);
    ClassDB::bind_method(D_METHOD("foundation_samples","origin","quarter_turns","max_base_y"),&NativeBlockPrefab::foundation_samples);
    ADD_PROPERTY(PropertyInfo(Variant::PACKED_INT32_ARRAY,"records"),"set_records","get_records");
}
bool NativeBlockPrefab::configure(const PackedInt32Array &records) {
    if(records.size()%4||records.size()>4*262144)return false;
    std::vector<PrefabCell> staged;
    staged.reserve(records.size()/4);
    Vector3 lo(4096,4096,4096),hi(-4096,-4096,-4096);
    for(int64_t i=0;i<records.size();i+=4) {
        int x=records[i],y=records[i+1],z=records[i+2],w=records[i+3];
        if(x<-4095||x>4095||y<-4095||y>4095||z<-4095||z>4095||w<=0||w>=128||(w&7)>6||(w&7)==0)return false;
        staged.push_back({x,y,z,w});
        for(int a=0;a<3;a++) {lo[a]=std::min(lo[a],float(records[i+a]));hi[a]=std::max(hi[a],float(records[i+a]+1));}
    }
    auto less=[](const PrefabCell &a,const PrefabCell &b){return std::tie(a.x,a.y,a.z)<std::tie(b.x,b.y,b.z);};
    std::sort(staged.begin(),staged.end(),less);
    for(size_t i=1;i<staged.size();i++)if(!less(staged[i-1],staged[i]))return false;
    // Compute once on authoring changes, not by scanning every floor per preview.
    // Each occupied X/Z column contributes its lowest cell, including stepped bases.
    std::map<std::pair<int,int>,PrefabCell> columns;
    for(const auto &c:staged) {
        auto key=std::make_pair(c.x,c.z);
        auto found=columns.find(key);
        if(found==columns.end()||c.y<found->second.y)columns[key]=c;
    }
    std::vector<PrefabCell> footprint;footprint.reserve(columns.size());
    for(const auto &entry:columns)footprint.push_back(entry.second);
    foundation_columns=std::move(footprint);
    cells=std::move(staged);bounds=cells.empty()?AABB():AABB(lo,hi-lo);emit_changed();return true;
}
PackedVector3Array NativeBlockPrefab::foundation_samples(Vector3i origin,int turns,int max_base_y) const {
    PackedVector3Array out;
    if(turns<0||turns>3||max_base_y<-4095||max_base_y>4095)return out;
    for(int a=0;a<3;++a)if(origin[a]<-1044480||origin[a]>1044480)return out;
    int count=0;
    for(const auto &c:foundation_columns)if(c.y<=max_base_y)++count;
    out.resize(count);int i=0;
    for(const auto &c:foundation_columns) {
        // The author/planner explicitly selects the foundation band; roof eaves
        // and balconies must not become artificial ground-support requirements.
        if(c.y>max_base_y)continue;
        int x=c.x,z=c.z;
        for(int r=0;r<turns;++r){int old=x;x=-z;z=old;}
        // Cell-centred probe 0.25 m below the base. Sampling is a site-screening
        // input, not a proof that arbitrary slopes/overhangs are structurally safe.
        out.set(i++,Vector3(origin.x+x+0.5f,origin.y+c.y-0.25f,origin.z+z+0.5f));
    }
    return out;
}
void NativeBlockPrefab::set_records(const PackedInt32Array &records) {
    ERR_FAIL_COND_MSG(!configure(records),"Invalid block prefab records; previous asset preserved");
}
bool NativeBlockPrefab::compose(const Array &sources,const PackedInt32Array &placements) {
    // Each placement is [source index, x, y, z, quarter turns]. Flatten once in
    // native code; the resulting asset uses the existing chunked world pipeline.
    if(sources.is_empty()||sources.size()>256||placements.is_empty()||placements.size()%5||placements.size()>4096*5)return false;
    std::vector<Ref<NativeBlockPrefab>> assets;
    for(int64_t i=0;i<sources.size();++i) {
        if(sources[i].get_type()!=Variant::OBJECT)return false;
        Ref<NativeBlockPrefab> asset=sources[i];
        if(asset.is_null()||asset->cells.empty())return false;
        assets.push_back(asset);
    }
    int64_t count=0;
    for(int64_t i=0;i<placements.size();i+=5) {
        int index=placements[i],turns=placements[i+4];
        if(index<0||index>=int(assets.size())||turns<0||turns>3)return false;
        count+=assets[index]->cells.size();
        if(count>262144)return false;
    }
    PackedInt32Array records;records.resize(count*4);int64_t at=0;
    for(int64_t i=0;i<placements.size();i+=5) {
        const int turns=placements[i+4];
        for(const auto &c:assets[placements[i]]->cells) {
            int64_t x=c.x,y=int64_t(c.y)+placements[i+2],z=c.z;
            for(int r=0;r<turns;++r){int64_t old=x;x=-z;z=old;}
            x+=placements[i+1];z+=placements[i+3];
            if(x<-4095||x>4095||y<-4095||y>4095||z<-4095||z>4095)return false;
            records.set(at++,int32_t(x));records.set(at++,int32_t(y));records.set(at++,int32_t(z));
            records.set(at++,(c.word&~24)|((((c.word>>3)+turns)&3)<<3));
        }
    }
    // configure rejects any duplicated cells and commits only after validation;
    // this remains safe when this resource also occurs among the sources.
    return configure(records);
}
bool NativeBlockPrefab::compose_frontage(const Array &sources,int64_t lots,int64_t street,int64_t gap,int64_t seed) {
    // v1: paired lots on a straight street; authored prefab fronts face +Z.
    // Derive each choice from its ordinal, not an advancing global RNG.
    if(sources.is_empty()||sources.size()>256||lots<1||lots>64||street<4||street>64||street%2||gap<1||gap>32||seed<0||seed>0xffffffffLL)return false;
    std::vector<Ref<NativeBlockPrefab>> assets;
    for(int i=0;i<sources.size();++i){
        if(sources[i].get_type()!=Variant::OBJECT)return false;
        Ref<NativeBlockPrefab> asset=sources[i];
        if(asset.is_null()||asset->cells.empty())return false;
        assets.push_back(asset);
    }
    PackedInt32Array placements;placements.resize(lots*2*5);
    int x=0,at=0;int64_t total=0;
    for(int lot=0;lot<lots;++lot){
        int width=0;
        for(int side=0;side<2;++side){
            uint32_t h=uint32_t(seed)^uint32_t(lot*2+side+1)*0x9e3779b9u;
            h^=h>>16;h*=0x85ebca6bu;h^=h>>13;h*=0xc2b2ae35u;h^=h>>16;
            int index=int(h%assets.size()),turns=side*2;
            total+=assets[index]->cells.size();if(total>262144)return false;
            AABB b=assets[index]->placement_bounds(Vector3i(),turns);
            int z=side==0?-int(street/2+gap)-int(b.get_end().z):int(street/2+gap)-int(b.position.z);
            placements.set(at++,index);placements.set(at++,x-int(b.position.x));
            placements.set(at++,-int(b.position.y));placements.set(at++,z);placements.set(at++,turns);
            width=std::max(width,int(b.size.x));
        }
        x+=width+int(gap);
    }
    return compose(sources,placements); // Existing transactional cell validation.
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
