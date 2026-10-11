// SPDX-License-Identifier: 0BSD
#include "water_topology.hpp"
#include <godot_cpp/classes/time.hpp>
#include <algorithm>
using namespace godot;
namespace terraforest {
bool NativeWaterTopology::begin_join(const Array &regions){
    if(source.is_valid()||regions.size()<1||regions.size()>8)return false;
    std::vector<Ref<NativeWaterTopology>> staged;uint32_t cells=0,nodes=0,links=0;
    for(int i=0;i<regions.size();++i){
        const Ref<NativeWaterTopology> p=regions[i];
        if(p.is_null()||p->status!=1||p->joined)return false;
        if(i&&p->source!=staged[0]->source)return false;
        for(const auto &q:staged){
            bool overlap=true;
            for(int a=0;a<3;++a)if(p->first[a]>=q->first[a]+q->extent[a]||q->first[a]>=p->first[a]+p->extent[a])overlap=false;
            if(overlap)return false;
        }
        cells+=p->count;nodes+=p->node_count;links+=p->edge_count;
        if(cells>4096||nodes>24576||links>98304)return false;
        staged.push_back(p);
    }
    source=staged[0]->source;pieces.swap(staged);positions.resize(pieces.size(),0);
    count=cells;ids.resize(nodes);floors.resize(nodes);edges.resize(links*3);edge_heap.reserve(links);
    joined=true;status=0;return true;
}
Dictionary NativeWaterTopology::advance_join(int64_t budget){
    int64_t work=0;
    if(!joined||budget<1||budget>2048){Dictionary out=statistics();out["ok"]=false;out["work_units"]=work;return out;}
    const uint64_t start=Time::get_singleton()->get_ticks_usec();
    auto later=[](const std::array<int32_t,3> &a,const std::array<int32_t,3> &b){return a>b;};
    while(status==0&&work<budget){
        ++work;++join_work;
        if(join_phase==0){
            int chosen=-1;
            for(int i=0;i<int(pieces.size());++i)if(positions[i]<pieces[i]->ids.size()&&(chosen<0||pieces[i]->ids[positions[i]]<pieces[chosen]->ids[positions[chosen]]))chosen=i;
            if(chosen<0){join_phase=1;continue;}
            const auto &p=*pieces[chosen].ptr();const int at=positions[chosen]++;
            ids.set(node_count,p.ids[at]);floors.set(node_count++,p.floors[at]);
        }else if(join_phase==1){
            if(piece_cursor==int(pieces.size())){join_phase=2;continue;}
            const auto &p=*pieces[piece_cursor].ptr();
            if(edge_cursor==p.edges.size()){++piece_cursor;edge_cursor=0;continue;}
            edge_heap.push_back({p.edges[edge_cursor],p.edges[edge_cursor+1],p.edges[edge_cursor+2]});edge_cursor+=3;
            std::push_heap(edge_heap.begin(),edge_heap.end(),later);
        }else{
            if(edge_heap.empty()){
                edges.resize(edge_count*3);cursor=count;status=1;pieces.clear();positions.clear();break;
            }
            std::pop_heap(edge_heap.begin(),edge_heap.end(),later);const auto edge=edge_heap.back();edge_heap.pop_back();
            if(edge[0]==last_edge[0]&&edge[1]==last_edge[1]){
                if(edge[2]!=last_edge[2])status=-2; // Same immutable source must agree on a shared face.
            }else{
                for(int k=0;k<3;++k)edges.set(edge_count*3+k,edge[k]);++edge_count;last_edge=edge;
                const bool a=std::binary_search(ids.ptr(),ids.ptr()+node_count,edge[0]),b=std::binary_search(ids.ptr(),ids.ptr()+node_count,edge[1]);
                if(!a||!b)++portals;
            }
        }
        if(work%32==0&&Time::get_singleton()->get_ticks_usec()-start>=2000)break;
    }
    Dictionary out=statistics();out["ok"]=status>=0;out["work_units"]=work;
    out["join_scratch_bytes"]=int64_t(edge_heap.capacity()*sizeof(std::array<int32_t,3>));return out;
}
}
