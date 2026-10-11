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
