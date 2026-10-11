// SPDX-License-Identifier: 0BSD
#include "water_network.hpp"
#include "water_geometry.hpp"
#include <cmath>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/classes/time.hpp>
#include <algorithm>
using namespace godot;
namespace terraforest {
void NativeWaterNetwork::_bind_methods(){
    ClassDB::bind_method(D_METHOD("ray_probe","from","to","wet_only"), &NativeWaterNetwork::ray_probe);
    ClassDB::bind_method(D_METHOD("capture_state"), &NativeWaterNetwork::capture_state);
    ClassDB::bind_method(D_METHOD("restore_state","bytes"), &NativeWaterNetwork::restore_state);
    ClassDB::bind_method(D_METHOD("fill_to_level","point","level_mm"), &NativeWaterNetwork::fill_to_level);
    ClassDB::bind_method(D_METHOD("transfer_litre","point","pour","inventory","slot","revision"), &NativeWaterNetwork::transfer_litre);
    ClassDB::bind_method(D_METHOD("begin","registry","regional_profiles"),&NativeWaterNetwork::begin);
    ClassDB::bind_method(D_METHOD("advance","work_budget"),&NativeWaterNetwork::advance);
    ClassDB::bind_method(D_METHOD("begin_add","coordinate","local_leaf","amount_ml"),&NativeWaterNetwork::begin_add);
    ClassDB::bind_method(D_METHOD("begin_remove","coordinate","local_leaf","amount_ml"),&NativeWaterNetwork::begin_remove);
    ClassDB::bind_method(D_METHOD("advance_settling","event_budget"),&NativeWaterNetwork::advance_settling);
    ClassDB::bind_method(D_METHOD("inspect","coordinate","local_leaf"),&NativeWaterNetwork::inspect);
    ClassDB::bind_method(D_METHOD("probe","point"),&NativeWaterNetwork::probe);
    ClassDB::bind_method(D_METHOD("statistics"),&NativeWaterNetwork::statistics);
}
bool NativeWaterNetwork::begin(const Ref<NativeWaterRegions> &owners,const Array &profiles){
    if(status!=-1||owners.is_null()||profiles.is_empty()||profiles.size()>64)return false;
    std::vector<Piece> staged;int leaves=0,links=0;PackedInt64Array heights;
    for(int i=0;i<profiles.size();++i){
        const Ref<NativeWaterProfiles> p=profiles[i];
        if(p.is_null()||p->status!=1||p->topology->field.is_null())return false;
        const auto &g=*p->topology.ptr();const auto origin=g.field->origin+g.first;
        if(g.extent!=Vector3i(16,16,16)||origin.x%16||origin.y%16||origin.z%16)return false;
        const Vector3i coordinate=origin/16;const Key k={coordinate.x,coordinate.y,coordinate.z};const auto it=owners->regions.find(k);
        if(it==owners->regions.end()||!it->second.ready||it->second.graph!=p->topology)return false;
        for(const auto &entry:staged)if(entry.coordinate==coordinate)return false;
        if(i&&p->levels!=heights)return false;
        heights=p->levels;leaves+=p->leaves;links+=p->basins->merges.size()/4+g.portals;
        if(leaves>4096||links>98304)return false;
        staged.push_back({coordinate,it->second.generation,0,p});
    }
    std::sort(staged.begin(),staged.end(),[](const Piece &a,const Piece &b){return Key{a.coordinate.x,a.coordinate.y,a.coordinate.z}<Key{b.coordinate.x,b.coordinate.y,b.coordinate.z};});
    registry=owners;pieces.swap(staged);levels=heights;local_leaves=leaves;
    int offset=0;for(int i=0;i<int(pieces.size());++i){auto &p=pieces[i];p.offset=offset;offset+=p.profiles->leaves;indices[{p.coordinate.x,p.coordinate.y,p.coordinate.z}]=i;}
    ids.resize(leaves);floors.resize(leaves);edges.resize(links*3);status=0;return true;
}
bool NativeWaterNetwork::current() const {
    if(status==2||registry.is_null())return false;
    for(const auto &p:pieces){const auto it=registry->regions.find({p.coordinate.x,p.coordinate.y,p.coordinate.z});
        if(it==registry->regions.end()||!it->second.ready||it->second.generation!=p.generation||it->second.graph!=p.profiles->topology)return false;
    }return true;
}
void NativeWaterNetwork::fail(const char *why){status=-2;error=why;}
int NativeWaterNetwork::owner_at(const Piece &p,const int32_t *address) const {
    const auto &g=*p.profiles->topology.ptr();const auto view=g.view();const Vector3i local=Vector3i(address[0],address[1],address[2])-g.field->origin;
    for(int a=0;a<3;++a)if(local[a]<0||local[a]>=view.size[a])return -1;
    const int id=view.cell(local.x,local.y,local.z)*6+address[3];const int32_t *at=std::lower_bound(g.ids.ptr(),g.ids.ptr()+g.ids.size(),id);
    if(at==g.ids.ptr()+g.ids.size()||*at!=id)return -1;
    return p.offset+p.profiles->basins->owners[at-g.ids.ptr()];
}
void NativeWaterNetwork::unit(){
    if(phase<3){
        if(piece==int(pieces.size())){++phase;piece=0;cursor=0;return;}
        const auto &p=pieces[piece];const auto &b=*p.profiles->basins.ptr();
        if(phase==0){
            if(cursor==p.profiles->leaves){++piece;cursor=0;return;}
            ids.set(p.offset+cursor,p.offset+cursor);floors.set(p.offset+cursor,b.leaf_floors[cursor]);++cursor;return;
        }
        if(phase==1){
            if(cursor==b.merges.size()){++piece;cursor=0;return;}
            auto entry=[&](int node){return node<p.profiles->leaves?node:b.merges[(node-p.profiles->leaves)*4+3];};
            const int a=p.offset+entry(b.merges[cursor]),d=p.offset+entry(b.merges[cursor+1]);
            edges.set(edge_count*3,std::min(a,d));edges.set(edge_count*3+1,std::max(a,d));edges.set(edge_count*3+2,b.merges[cursor+2]);++edge_count;cursor+=4;return;
        }
        const auto &g=*p.profiles->topology.ptr();
        if(cursor==int(g.portals)){++piece;cursor=0;return;}
        const Dictionary gate=registry->inspect_port(p.coordinate,p.generation,cursor);
        if(!bool(gate.get("connected",false))){fail("A region boundary is unresolved or geometrically incompatible.");return;}
        const Vector3i peer=gate["neighbour"];const auto found=indices.find({peer.x,peer.y,peer.z});
        if(found==indices.end()){fail("A connected neighbour is missing from the compiled set.");return;}
        const int32_t *row=g.world_ports.ptr()+cursor++*9;
        const int a=owner_at(p,row),d=owner_at(pieces[found->second],row+4);
        if(a<0||d<0){fail("Boundary endpoint lacks a compiled local storage owner.");return;}
        if(a<d){edges.set(edge_count*3,a);edges.set(edge_count*3+1,d);edges.set(edge_count*3+2,row[8]);++edge_count;}
        return;
    }
    if(phase==3){
        if(hierarchy.is_null()){
            edges.resize(edge_count*3);Dictionary graph;graph["ids"]=ids;graph["floors_mm"]=floors;graph["edges"]=edges;
            hierarchy.instantiate();if(!hierarchy->begin(graph)){fail("Compressed graph exceeds hierarchy limits.");return;}return;
        }
        if(hierarchy->status==0){hierarchy->unit();++hierarchy->events;return;}
        if(hierarchy->status!=1||hierarchy->max_depth>64){fail("Compiled hierarchy is invalid or exceeds solver depth.");return;}
        if(cursor<hierarchy->merges.size()){
            const int64_t height=hierarchy->merges[cursor+2];cursor+=4;
            if(!std::binary_search(levels.ptr(),levels.ptr()+levels.size(),height))fail("A shared spill elevation requires an exact common storage anchor.");
            return;
        }
        mapping=hierarchy->owners;global_leaves=hierarchy->leaf_count;rows.resize(global_leaves);phase=4;cursor=0;return;
    }
    if(phase==4){
        if(cursor==global_leaves){phase=5;piece=0;cursor=0;anchor=0;return;}
        rows[cursor].resize(levels.size());rows[cursor].fill(0);++cursor;return;
    }
    if(phase==5){
        if(piece==int(pieces.size())){phase=6;return;}
        const auto &p=pieces[piece];
        if(cursor==p.profiles->leaves){++piece;cursor=0;return;}
        auto &row=rows[mapping[p.offset+cursor]];const int64_t value=p.profiles->rows[cursor][anchor];
        if(row[anchor]>9007199254740991LL-value){fail("Combined capacity exceeds exact integer range.");return;}
        row.set(anchor,row[anchor]+value);if(++anchor==levels.size()){anchor=0;++cursor;}return;
    }
    if(phase==6){
        Array profiles;profiles.resize(global_leaves);for(int i=0;i<global_leaves;++i)profiles[i]=rows[i];
        solver.instantiate();if(!solver->configure_forest(levels,profiles,hierarchy->merges)){solver.unref();fail("Compiled storage cannot configure finite settling.");return;}
        rows.clear();hierarchy.unref();ids.clear();floors.clear();edges.clear();status=1;phase=7;
    }
}
Dictionary NativeWaterNetwork::advance(int64_t budget){
    int64_t work=0;
    if(budget<1||budget>2048){Dictionary out=statistics();out["ok"]=false;out["work_units"]=work;return out;}
    if(status==0&&!current())fail("Region generation changed during compilation.");
    const uint64_t begun=Time::get_singleton()->get_ticks_usec();
    while(status==0&&work<budget){unit();++work;++work_total;if(work%32==0&&Time::get_singleton()->get_ticks_usec()-begun>=2000)break;}
    Dictionary out=statistics();out["ok"]=status>=0&&current();out["work_units"]=work;return out;
}
int NativeWaterNetwork::target(const Vector3i &coordinate,int64_t leaf) const {
    if(status!=1||!current())return -1;const auto it=indices.find({coordinate.x,coordinate.y,coordinate.z});if(it==indices.end())return -1;
    const auto &p=pieces[it->second];if(leaf<0||leaf>=p.profiles->leaves)return -1;return mapping[p.offset+leaf];
}
bool NativeWaterNetwork::begin_add(const Vector3i &coordinate,int64_t leaf,int64_t amount){const int id=target(coordinate,leaf);if(id<0||!solver->begin_add(id,amount))return false;++water_revision;return true;}
bool NativeWaterNetwork::begin_remove(const Vector3i &coordinate,int64_t leaf,int64_t amount){const int id=target(coordinate,leaf);if(id<0||!solver->begin_remove(id,amount))return false;++water_revision;return true;}
Dictionary NativeWaterNetwork::advance_settling(int64_t budget){
    if(status!=1||!current()){Dictionary out;if(solver.is_valid())out=solver->statistics();out["ok"]=false;out["work_events"]=0;return out;}
    Dictionary out=solver->advance(budget);if(int64_t(out.get("work_events",0))>0)++water_revision;return out;
}
Dictionary NativeWaterNetwork::inspect(const Vector3i &coordinate,int64_t leaf) const {
    const int id=target(coordinate,leaf);if(id>=0)return solver->inspect(id);Dictionary out;out["ok"]=false;return out;
}
Dictionary NativeWaterNetwork::probe(const Vector3 &point) const {
    Dictionary out;out["ok"]=false;out["wet"]=false;
    if(status!=1||!current())return out;
    for(int a=0;a<3;++a)if(!std::isfinite(point[a])||std::abs(point[a])>100000)return out;
    // Refuse every spatial result during a partially applied pour or withdrawal.
    if(bool(solver->statistics()["busy"]))return out;
    const Vector3 grid=point/double(registry->spacing);
    const Vector3i cell(grid.floor());
    const Vector3i coordinate((grid/16.0).floor());
    const auto it=indices.find({coordinate.x,coordinate.y,coordinate.z});
    if(it==indices.end())return out;
    const auto &p=pieces[it->second];const auto &g=*p.profiles->topology.ptr();const auto view=g.view();
    const Vector3i local=cell-g.field->origin;float weights[4];const int tet=lake_tetra(grid-Vector3(cell),weights);
    double density=0;
    for(int k=0;k<4;++k){const auto c=local+lake_corner(lake_tets[tet][k]);density+=weights[k]*view.density[view.node(c.x,c.y,c.z)];}
    out["ok"]=true;out["region"]=coordinate;
    if(density<=0)return out;
    const int32_t address[]={cell.x,cell.y,cell.z,tet};const int owner=owner_at(p,address);
    if(owner<0)return out; // Positive air above the compiled ceiling has no water owner.
    const Dictionary state=solver->inspect(mapping[owner]);
    if(!bool(state.get("ok",false))){out["ok"]=false;return out;}
    const double level=double(state["level_mm"])/1000.0;
    const bool wet=int64_t(state["component_amount_ml"])>0&&point.y<level;
    out["wet"]=wet;out["level_m"]=level;out["depth_m"]=wet?level-point.y:0.0;
    out["local_leaf"]=owner-p.offset;out["component"]=state["component"];
    return out;
}
Dictionary NativeWaterNetwork::statistics() const {
    Dictionary out;out["status"]=status;out["phase"]=phase;out["current"]=current();out["regions"]=int64_t(pieces.size());out["local_leaves"]=local_leaves;out["global_leaves"]=global_leaves;
    out["retired"]=status==2;out["owned_ml"]=(status==1&&solver.is_valid())?int64_t(solver->statistics()["total_ml"]):int64_t(0);
    out["work_units_total"]=work_total;out["error"]=error;if(solver.is_valid())out["water"]=solver->statistics();return out;
}
}

namespace terraforest {
// Stable geometry signature prevents applying quantities to a different hierarchy.
static uint64_t mix_water(uint64_t h,uint64_t v){for(int i=0;i<8;++i){h^=(v>>(i*8))&255;h*=1099511628211ULL;}return h;}
PackedByteArray NativeWaterNetwork::capture_state() const {
    PackedByteArray out;if(status!=1||solver.is_null()||solver->mode)return out;
    uint64_t hash=1469598103934665603ULL;
    for(auto h:solver->heights)hash=mix_water(hash,h);
    for(const auto &n:solver->nodes){hash=mix_water(hash,n.parent);hash=mix_water(hash,n.left);hash=mix_water(hash,n.right);hash=mix_water(hash,n.entry);hash=mix_water(hash,n.merge);hash=mix_water(hash,n.capacity);for(auto v:n.profile)hash=mix_water(hash,v);}
    out.resize(24+solver->nodes.size()*8);out.encode_u32(0,0x31514657);out.encode_u32(4,solver->nodes.size());out.encode_u64(8,hash);out.encode_u64(16,solver->total_ml);
    for(int i=0;i<int(solver->nodes.size());++i)out.encode_u64(24+i*8,solver->nodes[i].local);return out;
}
bool NativeWaterNetwork::restore_state(const PackedByteArray &bytes){
    if(status!=1||!current()||solver->mode)return false;
    const auto empty=capture_state();if(bytes.size()!=empty.size()||bytes.size()<24||bytes.decode_u32(0)!=0x31514657||bytes.decode_u32(4)!=solver->nodes.size()||bytes.decode_u64(8)!=empty.decode_u64(8))return false;
    auto staged=solver->nodes;int64_t total=0;
    for(int i=0;i<int(staged.size());++i){auto &n=staged[i];const uint64_t local=bytes.decode_u64(24+i*8);if(local>uint64_t(n.capacity-n.base)||local>uint64_t(9007199254740991LL-total))return false;n.local=local;n.total=local;total+=local;
        if(n.left>=0){n.total+=staged[n.left].total+staged[n.right].total;if(local&&(staged[n.left].total!=staged[n.left].capacity||staged[n.right].total!=staged[n.right].capacity))return false;}
        if(n.total>n.capacity)return false;
    }
    if(uint64_t(total)!=bytes.decode_u64(16))return false;solver->nodes.swap(staged);solver->total_ml=total;++water_revision;return true;
}
bool NativeWaterNetwork::fill_to_level(const Vector3 &point,int64_t height){
    if(status!=1||!current()||solver->mode||solver->total_ml)return false;
    const Dictionary p=probe(point);if(!p.has("local_leaf"))return false;
    const int leaf=target(p["region"],p["local_leaf"]);int at=leaf;
    while(solver->nodes[at].parent>=0&&solver->nodes[solver->nodes[at].parent].merge<=height)at=solver->nodes[at].parent;
    auto it=std::lower_bound(solver->heights.begin(),solver->heights.end(),height);if(it==solver->heights.end()||*it!=height)return false;
    const int64_t amount=solver->nodes[at].profile[it-solver->heights.begin()];
    return amount==0||begin_add(p["region"],p["local_leaf"],amount);
}
bool NativeWaterNetwork::transfer_litre(const Vector3 &point,bool pour,Object *inventory,int64_t slot,int64_t revision){
    if(!inventory||!inventory->has_method("exchange_bucket")||status!=1||!current()||solver->mode)return false;
    const Dictionary p=probe(point);if(!p.has("local_leaf")||(!pour&&!bool(p["wet"])))return false;
    const int leaf=target(p["region"],p["local_leaf"]);
    // Stage only mutable quantities: the geometry/profiles remain shared and untouched.
    std::vector<std::pair<int64_t,int64_t>> previous;previous.reserve(solver->nodes.size());for(const auto &n:solver->nodes)previous.push_back({n.local,n.total});
    const int64_t old_total=solver->total_ml;
    const bool begun=pour?solver->begin_add(leaf,1000):solver->begin_remove(leaf,1000);
    if(!begun)return false;
    // A 4096-leaf bounded hierarchy needs fewer than 32768 events for one transaction.
    for(int i=0;i<16&&solver->mode;++i)solver->advance(2048);
    bool accepted=!solver->mode&&solver->moved==1000;
    if(accepted)accepted=bool(inventory->call("exchange_bucket",slot,pour,revision));
    if(!accepted){for(int i=0;i<int(previous.size());++i){solver->nodes[i].local=previous[i].first;solver->nodes[i].total=previous[i].second;}solver->total_ml=old_total;solver->mode=0;solver->frames.clear();solver->pending=solver->requested=solver->moved=0;return false;}
    ++water_revision;return true;
}
}

namespace terraforest {
Dictionary NativeWaterNetwork::ray_probe(const Vector3 &from,const Vector3 &to,bool wet_only) const {
 Dictionary out;if(!from.is_finite()||!to.is_finite()||from.distance_to(to)>5)return out;
 for(int i=0;i<=100;++i){const Vector3 point=from.lerp(to,double(i)/100);Dictionary p=probe(point);
  if(p.has("local_leaf")&&(!wet_only||bool(p["wet"]))){p["point"]=point;return p;}}
 return out;
}
}
