// SPDX-License-Identifier: 0BSD
#include "water_remap_plan.hpp"
#include "water_geometry.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/classes/time.hpp>
using namespace godot;
namespace terraforest {
void NativeWaterRemapPlan::_bind_methods(){
    ClassDB::bind_method(D_METHOD("begin","source","destination"),&NativeWaterRemapPlan::begin);
    ClassDB::bind_method(D_METHOD("advance","work_budget"),&NativeWaterRemapPlan::advance);
    ClassDB::bind_method(D_METHOD("statistics"),&NativeWaterRemapPlan::statistics);
    ClassDB::bind_method(D_METHOD("plan"),&NativeWaterRemapPlan::plan);
    ClassDB::bind_method(D_METHOD("begin_settlement"),&NativeWaterRemapPlan::begin_settlement);
    ClassDB::bind_method(D_METHOD("advance_settlement","work_budget"),&NativeWaterRemapPlan::advance_settlement);
    ClassDB::bind_method(D_METHOD("commit"),&NativeWaterRemapPlan::commit);
}
bool NativeWaterRemapPlan::current() const {
    return source.is_valid()&&destination.is_valid()&&source->water_revision==source_revision&&
        destination->water_revision==destination_revision&&destination->current();
}
void NativeWaterRemapPlan::fail(const char *why){status=-2;error=why;}
bool NativeWaterRemapPlan::begin(const Ref<NativeWaterNetwork> &a,const Ref<NativeWaterNetwork> &b){
    if(status!=-1||a.is_null()||b.is_null()||a==b||a->status!=1||b->status!=1||!b->current())return false;
    if(a->registry->world!=b->registry->world||a->registry->spacing!=b->registry->spacing)return false;
    const Dictionary sa=a->solver->statistics(),sb=b->solver->statistics();
    if(bool(sa["busy"])||bool(sb["busy"])||int64_t(sb["total_ml"])!=0)return false;
    // A stale source is intentional: its pinned geometry describes water before the edit.
    source=a;destination=b;source_revision=a->water_revision;destination_revision=b->water_revision;
    source_ml=sa["total_ml"];
    if(source_ml==0){status=1;phase=7;return true;}
    int offset=0;for(const auto &p:a->pieces){route_offsets.push_back(offset);offset+=p.profiles->topology->ids.size();}
    states.resize(a->global_leaves);status=0;return true;
}
void NativeWaterRemapPlan::accumulate(int component,int target,double volume){
    if(volume<=0)return;
    const auto key=std::make_pair(component,target);auto at=overlaps.find(key);
    if(at==overlaps.end()){
        if(overlaps.size()>=65536){fail("Geometric remap exceeds the sparse overlap limit.");return;}
        at=overlaps.emplace(key,Sum{}).first;
    }
    at->second.add(volume);
}
int NativeWaterRemapPlan::neighbour_slot(const Displaced &node,int face) const {
    const auto &p=source->pieces[node.piece];const auto &g=*p.profiles->topology.ptr();const auto view=g.view();
    const int id=g.ids[node.index],cell=id/6,t=id%6;
    const Vector3i local(cell%view.size.x,(cell/view.size.x)%view.size.y,cell/(view.size.x*view.size.y));
    const auto link=lake_links()[t][face];
    const Vector3i world=local+g.field->origin+Vector3i(link.x,link.y,link.z);
    auto floor_region=[](int v){return (v-(v<0?15:0))/16;};
    const auto found=source->indices.find({floor_region(world.x),floor_region(world.y),floor_region(world.z)});
    if(found==source->indices.end())return -1;
    const auto &other=source->pieces[found->second];const auto &ng=*other.profiles->topology.ptr();const auto nv=ng.view();
    const Vector3i nl=world-ng.field->origin;const int nid=nv.cell(nl.x,nl.y,nl.z)*6+link.t;
    const auto begin=ng.ids.ptr(),end=begin+ng.ids.size(),at=std::lower_bound(begin,end,nid);
    if(at==end||*at!=nid)return -1;
    const int index=at-begin,slot=route_offsets[found->second]+index;if(routes[slot]==-1)return -1;
    const auto state=states[source->mapping[other.offset+other.profiles->basins->owners[index]]];
    if(state.component!=node.component)return -1;
    // Shared face must contain positive old void strictly below the old water head.
    double height[3],density[3];int n=0;
    for(int k=0;k<4;++k)if(k!=face){const auto c=lake_corner(lake_tets[t][k]);const auto v=local+c;
        height[n]=view.origin.y+(local.y+c.y)*view.spacing;density[n++]=view.density[view.node(v.x,v.y,v.z)];}
    double bottom=INFINITY;
    for(int a=0;a<3;++a)if(density[a]>0){
        bottom=std::min(bottom,height[a]);
        for(int b=0;b<3;++b)if(density[b]<=0){const double weight=density[a]/(density[a]-density[b]);bottom=std::min(bottom,height[a]+weight*(height[b]-height[a]));}
    }
    return bottom<state.level?slot:-1;
}
void NativeWaterRemapPlan::unit(){
    if(phase==0){
        if(cursor==source->global_leaves){phase=1;cursor=0;return;}
        const Dictionary s=source->solver->inspect(cursor);
        const int component=s["component"];const int64_t amount=s["component_amount_ml"];
        states[cursor++]={component,double(s["level_mm"])/1000.0};
        if(amount>0)components[component].amount=amount;
        return;
    }
    if(phase==1){
        if(piece==int(source->pieces.size())){phase=2;return;}
        const auto &p=source->pieces[piece];const auto &g=*p.profiles->topology.ptr();
        if(cursor==g.ids.size()){++piece;cursor=0;return;}
        const int index=cursor++,id=g.ids[index],cell=id/6,t=id%6;routes.push_back(-1);
        const int owner=source->mapping[p.offset+p.profiles->basins->owners[index]];
        const auto state=states[owner];auto comp=components.find(state.component);if(comp==components.end())return;
        const auto old=g.view();const Vector3i local(cell%old.size.x,(cell/old.size.x)%old.size.y,cell/(old.size.x*old.size.y));
        const Vector3i world=local+g.field->origin;
        const auto found=destination->indices.find({p.coordinate.x,p.coordinate.y,p.coordinate.z});
        int target=-1;WaterDensityView fresh;Vector3i new_local;
        if(found!=destination->indices.end()){
            const auto &q=destination->pieces[found->second];const auto &ng=*q.profiles->topology.ptr();
            const int32_t address[]={world.x,world.y,world.z,t};const int destination_owner=destination->owner_at(q,address);
            if(destination_owner>=0){target=destination->mapping[destination_owner];fresh=ng.view();new_local=world-ng.field->origin;}
        }
        water_clip::Tet input;
        for(int k=0;k<4;++k){const auto c=lake_corner(lake_tets[t][k]);const auto v=local+c;
            input[k]={double(c.x),double(c.y),double(c.z),double(old.density[old.node(v.x,v.y,v.z)]),0};
            if(target>=0){const auto n=new_local+c;input[k].next=fresh.density[fresh.node(n.x,n.y,n.z)];}
        }
        const double fill=(state.level-old.origin.y)/old.spacing-local.y;
        const double ceiling=target>=0?(fresh.ceiling-old.origin.y)/old.spacing-local.y:0;
        double volume=0,surviving=0;std::array<water_clip::Tet,3> air,wet,remaining,limited;
        const int na=water_clip::clip(input,air,true,0);
        for(int a=0;a<na;++a){const int nw=water_clip::clip(air[a],wet,false,fill);
            for(int w=0;w<nw;++w){volume+=water_clip::volume(wet[w]);if(target<0)continue;
                const int nr=water_clip::clip_field(wet[w],remaining,2,0);
                for(int r=0;r<nr;++r){const int nl=water_clip::clip(remaining[r],limited,false,ceiling);
                    for(int l=0;l<nl;++l)surviving+=water_clip::volume(limited[l]);}
            }
        }
        if(surviving>volume+1e-10){fail("Clipped overlap exceeds original wet volume.");return;}
        surviving=std::min(volume,surviving);comp->second.volume.add(volume);
        measured_volume.add(volume*old.spacing*old.spacing*old.spacing*1000000.0);
        if(volume<=0)return;
        const int slot=route_offsets[piece]+index;
        if(surviving>0){
            // The wet and replacement half-spaces within a tetrahedron are convex.
            // Water removed here can reach this surviving portion locally.
            routes[slot]=target;accumulate(state.component,target,volume);
            routed_volume.add((volume-surviving)*old.spacing*old.spacing*old.spacing*1000000.0);
        }else{
            const int node=displaced.size();routes[slot]=-node-2;
            displaced.push_back({piece,index,state.component,slot,-1,volume});
        }
        return;
    }
    if(phase==2){
        if(route_cursor==int(displaced.size())){phase=3;route_cursor=0;return;}
        auto &node=displaced[route_cursor++];
        for(int face=0;face<4;++face){
            const int slot=neighbour_slot(node,face);node.neighbours[face]=slot;
            if(slot>=0&&routes[slot]>=0&&(node.seed<0||routes[slot]<node.seed))node.seed=routes[slot];
        }
        return;
    }
    if(phase==3){
        if(route_cursor==int(displaced.size())){phase=4;route_cursor=0;return;}
        const int index=route_cursor++;const auto &node=displaced[index];
        if(node.seed>=0){routes[node.slot]=node.seed;queue.push_back(index);}return;
    }
    if(phase==4){
        if(queue.empty()){phase=5;return;}
        const auto &node=displaced[queue.front()];queue.pop_front();
        for(int slot:node.neighbours)if(slot>=0&&routes[slot]<-1){
            const int index=-routes[slot]-2;routes[slot]=routes[node.slot];queue.push_back(index);
        }
        return;
    }
    if(phase==5){
        if(route_cursor==int(displaced.size())){phase=6;next=overlaps.begin();return;}
        const auto &node=displaced[route_cursor++];const int target=routes[node.slot];
        accumulate(node.component,target>=0?target:-1,node.volume);
        if(target>=0){const double scale=source->registry->spacing;routed_volume.add(node.volume*scale*scale*scale*1000000.0);}
        return;
    }
    if(phase==6){
        if(next==overlaps.end()){
            if(mapped_ml+displaced_ml!=source_ml){fail("Some canonical water has no resolved geometric measure.");return;}
            status=1;phase=7;return;
        }
        const auto key=next->first;const double weight=next->second.value;auto &comp=components[key.first];++next;
        comp.cumulative+=weight;
        const bool last=next==overlaps.end()||next->first.first!=key.first;
        if(comp.volume.value<=0){fail("Nonzero water has zero measured volume.");return;}
        // Normalize profile interpolation error per old connected wet component.
        // Cumulative rounding plus an exact final residual conserves every integer ml.
        const long double fraction=std::min(1.0L,(long double)comp.cumulative/comp.volume.value);
        const int64_t cumulative=last?comp.amount:std::min(comp.amount,int64_t(std::llround(fraction*comp.amount)));
        const int64_t amount=cumulative-comp.assigned;if(amount<0){fail("Nonmonotonic geometric apportionment.");return;}
        comp.assigned=cumulative;
        if(amount){transfers.push_back(key.first);transfers.push_back(key.second);transfers.push_back(amount);
            if(key.second<0)displaced_ml+=amount;else mapped_ml+=amount;}
    }
}
Dictionary NativeWaterRemapPlan::advance(int64_t budget){
    int64_t work=0;if(budget<1||budget>2048){Dictionary out=statistics();out["ok"]=false;out["work_units"]=0;return out;}
    if(status==0&&!current())fail("Water or destination geometry changed during remapping.");
    const uint64_t start=Time::get_singleton()->get_ticks_usec();
    while(status==0&&work<budget){unit();++work;++work_total;if(work%16==0&&Time::get_singleton()->get_ticks_usec()-start>=2000)break;}
    Dictionary out=statistics();out["ok"]=status>=0&&current();out["work_units"]=work;return out;
}
bool NativeWaterRemapPlan::begin_settlement(){
    if(status!=1||settlement_status!=-1||!current())return false;
    const auto &empty=*destination->solver.ptr();
    staged.instantiate();staged->heights=empty.heights;staged->leaf_roots=empty.leaf_roots;
    staged->leaves=empty.leaves;staged->root_count=empty.root_count;
    staged->nodes.reserve(empty.nodes.size());staged->frames.reserve(65);
    unresolved_ml=displaced_ml;settlement_status=0;return true;
}
Dictionary NativeWaterRemapPlan::advance_settlement(int64_t budget){
    int64_t work=0;
    if(budget<1||budget>2048){Dictionary out=statistics();out["ok"]=false;out["work_units"]=0;return out;}
    if(settlement_status==0&&!current()){settlement_status=-2;error="Water or ownership changed during private settlement.";}
    const uint64_t start=Time::get_singleton()->get_ticks_usec();
    while(settlement_status==0&&work<budget){
        ++work;++settlement_work;
        if(settlement_phase==0){
            const auto &empty=*destination->solver.ptr();
            if(settlement_cursor<int(empty.nodes.size())){
                staged->nodes.push_back(empty.nodes[settlement_cursor++]);
                staged->nodes.back().total=staged->nodes.back().local=0;
            }else{staged->root=empty.root;settlement_cursor=0;settlement_phase=1;}
        }else if(staged->mode){
            staged->advance(1);
            if(!staged->mode)unresolved_ml+=staged->pending;
        }else if(settlement_cursor<transfers.size()){
            const int target=transfers[settlement_cursor+1];const int64_t amount=transfers[settlement_cursor+2];settlement_cursor+=3;
            if(target>=0&&!staged->begin_add(target,amount)){settlement_status=-2;error="Replacement solver rejected a conserved allocation.";}
        }else{
            if(staged->total_ml+unresolved_ml!=source_ml){settlement_status=-2;error="Private settlement failed conservation.";}
            else settlement_status=1;
        }
        if(work%16==0&&Time::get_singleton()->get_ticks_usec()-start>=2000)break;
    }
    Dictionary out=statistics();out["ok"]=settlement_status>=0&&current();out["work_units"]=work;return out;
}
bool NativeWaterRemapPlan::commit(){
    if(status!=1||settlement_status!=1||!current()||unresolved_ml||staged->mode||staged->total_ml!=source_ml)return false;
    // Serialized no-callback commit. Keep retired allocations alive here so destructors
    // cannot turn publication into a bulk free on the frame-critical path.
    previous_source=source->solver;previous_destination=destination->solver;
    destination->solver=staged;staged.unref();++destination->water_revision;
    source->solver.unref();source->status=2;++source->water_revision;
    settlement_status=2;return true;
}
Dictionary NativeWaterRemapPlan::statistics() const {
    Dictionary out;out["status"]=status;out["phase"]=phase;out["current"]=current();out["work_units_total"]=work_total;
    out["settlement_status"]=settlement_status;out["settlement_work_total"]=settlement_work;out["unresolved_ml"]=unresolved_ml;
    out["staged_ml"]=staged.is_valid()?staged->total_ml:int64_t(0);
    out["source_ml"]=source_ml;out["mapped_ml"]=mapped_ml;out["displaced_ml"]=displaced_ml;
    out["routing_nodes"]=int64_t(displaced.size());out["routing_slots"]=int64_t(routes.size());out["routed_geometric_ml"]=routed_volume.value;
    out["geometric_source_ml"]=measured_volume.value;out["profile_geometry_difference_ml"]=source_ml-measured_volume.value;
    out["overlap_entries"]=int64_t(overlaps.size());out["error"]=error;return out;
}
Dictionary NativeWaterRemapPlan::plan() const {
    Dictionary out=statistics();out["ok"]=status==1&&current();if(bool(out["ok"]))out["transfers"]=transfers;return out;
}
}
