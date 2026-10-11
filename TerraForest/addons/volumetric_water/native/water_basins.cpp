// SPDX-License-Identifier: 0BSD
#include "water_basins.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/classes/time.hpp>
#include <algorithm>
using namespace godot;
namespace terraforest {
bool NativeWaterBasins::later(const Event &a,const Event &b){
    if(a.height!=b.height)return a.height>b.height;
    if(a.type!=b.type)return a.type>b.type;
    if(a.a!=b.a)return a.a>b.a;
    return a.b>b.b;
}
void NativeWaterBasins::_bind_methods(){
    ClassDB::bind_method(D_METHOD("begin","graph"),&NativeWaterBasins::begin);
    ClassDB::bind_method(D_METHOD("advance","work_budget"),&NativeWaterBasins::advance);
    ClassDB::bind_method(D_METHOD("statistics"),&NativeWaterBasins::statistics);
    ClassDB::bind_method(D_METHOD("hierarchy"),&NativeWaterBasins::hierarchy);
}
bool NativeWaterBasins::begin(const Dictionary &graph){
    if(status!=-1||!graph.has("ids")||!graph.has("floors_mm")||!graph.has("edges"))return false;
    for(const char *key:{"ids","floors_mm","edges"})if(Variant(graph[key]).get_type()!=Variant::PACKED_INT32_ARRAY)return false;
    PackedInt32Array ni=graph["ids"],nf=graph["floors_mm"],ne=graph["edges"];
    if(ni.is_empty()||ni.size()>24576||nf.size()!=ni.size()||ne.size()%3||ne.size()>98304*3)return false;
    ids=ni;floors=nf;edges=ne;
    const int n=ids.size();
    parent.resize(n,-1);sizes.resize(n,1);basin.resize(n,-1);owner.resize(n,-1);
    heads.resize(n,-1);adjacency.reserve(edges.size()/3*2);drain_queue.reserve(n);
    activated.reserve(n);heap.reserve(n+edges.size()/3);drafts.reserve(8191);remap.resize(8191,-1);
    owners.resize(n);leaf_floors.resize(4096);merges.resize(4095*4);roots.resize(4096);ports.resize(edges.size());
    status=0;phase=0;cursor=0;return true;
}
int NativeWaterBasins::locate(int id) const {
    const int *begin=ids.ptr(),*end=begin+ids.size(),*it=std::lower_bound(begin,end,id);
    return it!=end&&*it==id?int(it-begin):-1;
}
int NativeWaterBasins::find(int n){
    int root=n;while(parent[root]!=root)root=parent[root];
    while(parent[n]!=n){const int next=parent[n];parent[n]=root;n=next;}return root;
}
void NativeWaterBasins::fail(const char *reason){status=-2;error=reason;}
void NativeWaterBasins::unit(){
    if(phase==0){ // Validate sorted identity and add node activation events incrementally.
        if(cursor==ids.size()){phase=1;cursor=0;return;}
        const int i=cursor++;
        if(ids[i]<0||(i&&ids[i]<=ids[i-1])){fail("Node IDs must be nonnegative and strictly increasing.");return;}
        heap.push_back({floors[i],0,i,-1});std::push_heap(heap.begin(),heap.end(),later);return;
    }
    if(phase==1){
        if(cursor==edges.size()){phase=2;cursor=0;return;}
        const int a=edges[cursor],b=edges[cursor+1],h=edges[cursor+2];cursor+=3;
        if(a<0||a>=b){fail("Edges require ordered, distinct, nonnegative IDs.");return;}
        const int ia=locate(a),ib=locate(b);
        if((ia<0&&ib<0)||(ia>=0&&h<floors[ia])||(ib>=0&&h<floors[ib])){fail("Opening lies below a node floor, or neither endpoint belongs to this region.");return;}
        if(ia<0||ib<0){ports.set(port_count*3,a);ports.set(port_count*3+1,b);ports.set(port_count*3+2,h);++port_count;return;}
        adjacency.push_back({ib,heads[ia],h});heads[ia]=int(adjacency.size())-1;
        adjacency.push_back({ia,heads[ib],h});heads[ib]=int(adjacency.size())-1;
        heap.push_back({h,1,ia,ib});std::push_heap(heap.begin(),heap.end(),later);return;
    }
    if(phase==2){
        // Finish every edge on a plateau before assigning newly exposed geometry.
        if(has_level&&(heap.empty()||heap.front().height!=level)){phase=3;cursor=0;return;}
        if(heap.empty()){phase=10;cursor=0;return;}
        std::pop_heap(heap.begin(),heap.end(),later);const Event e=heap.back();heap.pop_back();
        level=e.height;has_level=true;
        if(e.type==0){parent[e.a]=e.a;activated.push_back(e.a);return;}
        int a=find(e.a),b=find(e.b);if(a==b)return;
        int ba=basin[a],bb=basin[b],joined=ba<0?bb:ba;
        if(ba>=0&&bb>=0){
            if(drafts.size()>=8191){fail("Basin hierarchy exceeds regional node limit.");return;}
            drafts[ba].entry=owner[e.a]>=0?owner[e.a]:drafts[ba].rep;
            drafts[bb].entry=owner[e.b]>=0?owner[e.b]:drafts[bb].rep;
            Draft d;d.left=ba;d.right=bb;d.height=level;d.rep=std::min(drafts[ba].rep,drafts[bb].rep);d.entry=d.rep;
            d.depth=1+std::max(drafts[ba].depth,drafts[bb].depth);max_depth=std::max(max_depth,d.depth);
            joined=drafts.size();drafts[ba].parent=joined;drafts[bb].parent=joined;drafts.push_back(d);
        }
        if(sizes[a]<sizes[b])std::swap(a,b);
        parent[b]=a;sizes[a]+=sizes[b];basin[a]=joined;return;
    }
    if(phase==3){
        if(cursor==int(activated.size())){phase=7;cursor=0;edge_scan=-1;return;}
        const int i=activated[cursor++],r=find(i);
        if(basin[r]<0){
            if(leaf_count>=4096||drafts.size()>=8191){fail("Region contains more than 4096 local minima.");return;}
            Draft d;d.height=level;d.rep=d.entry=drafts.size();basin[r]=drafts.size();drafts.push_back(d);++leaf_count;
        }
        // A single-minimum component has unambiguous drainage. Merged components
        // need local descent labels, not the root representative for every air cell.
        if(drafts[basin[r]].left<0){owner[i]=drafts[basin[r]].rep;drain_queue.push_back(i);}return;
    }
    if(phase==7){ // Seed each newly active cell from its already-labelled lower neighbours.
        if(cursor==int(activated.size())){phase=8;queue_cursor=0;edge_scan=-1;return;}
        const int i=activated[cursor];
        if(owner[i]>=0){++cursor;return;}
        if(edge_scan<0){edge_scan=heads[i];best_owner=-1;best_floor=INT32_MAX;}
        if(edge_scan>=0){
            const auto e=adjacency[edge_scan];edge_scan=e.next;
            if(e.height<=level&&floors[e.node]<level&&owner[e.node]>=0&&
               (floors[e.node]<best_floor||(floors[e.node]==best_floor&&(best_owner<0||owner[e.node]<best_owner)))){best_owner=owner[e.node];best_floor=floors[e.node];}
        }
        if(edge_scan<0){if(best_owner>=0){owner[i]=best_owner;drain_queue.push_back(i);}++cursor;}
        return;
    }
    if(phase==8){ // Multi-source breadth-first descent across equal-height air cells.
        if(queue_cursor==int(drain_queue.size())){phase=9;cursor=0;return;}
        const int i=drain_queue[queue_cursor];if(edge_scan<0)edge_scan=heads[i];
        if(edge_scan>=0){const auto e=adjacency[edge_scan];edge_scan=e.next;
            if(e.height<=level&&floors[e.node]==level&&owner[e.node]<0){owner[e.node]=owner[i];drain_queue.push_back(e.node);}
        }
        if(edge_scan<0)++queue_cursor;
        return;
    }
    if(phase==9){
        if(cursor==int(activated.size())){activated.clear();drain_queue.clear();has_level=false;phase=2;return;}
        if(owner[activated[cursor++]]<0)fail("Activated air lacks a downhill storage owner.");return;
    }
    if(phase==10){ // Choose actual cross-catchment faces as entry witnesses for each merge.
        if(cursor==edges.size()||max_depth>64){phase=4;cursor=0;return;}
        const int ia=locate(edges[cursor]),ib=locate(edges[cursor+1]),height=edges[cursor+2];cursor+=3;
        if(ia<0||ib<0)return;
        const int oa=owner[ia],ob=owner[ib];if(oa==ob)return;
        int a=oa,b=ob;
        while(a!=b&&a>=0&&b>=0){if(a<b)a=drafts[a].parent;else b=drafts[b].parent;}
        if(a<0||b<0||drafts[a].height!=height)return;
        auto &merge=drafts[a];const int first=edges[cursor-3],second=edges[cursor-2];
        if(first>merge.witness_a||(first==merge.witness_a&&second>=merge.witness_b))return;
        int ca=oa,cb=ob;while(drafts[ca].parent!=a)ca=drafts[ca].parent;while(drafts[cb].parent!=a)cb=drafts[cb].parent;
        merge.witness_a=first;merge.witness_b=second;drafts[ca].entry=oa;drafts[cb].entry=ob;return;
    }
    if(phase==4){ // Leaves precede internal nodes in the public solver-compatible numbering.
        if(cursor==int(drafts.size())){phase=5;cursor=0;return;}
        const int i=cursor++;remap[i]=drafts[i].left<0?root_count++:leaf_count+merge_count++;return;
    }
    if(phase==5){
        if(cursor==int(drafts.size())){phase=6;cursor=0;root_count=0;return;}
        const int i=cursor++;const Draft &d=drafts[i];const int id=remap[i];
        if(d.left<0)leaf_floors.set(id,d.height);
        else {const int offset=(id-leaf_count)*4;merges.set(offset,remap[d.left]);merges.set(offset+1,remap[d.right]);merges.set(offset+2,d.height);merges.set(offset+3,remap[d.entry]);}
        return;
    }
    if(phase==6){
        if(cursor==ids.size()){
            leaf_floors.resize(leaf_count);merges.resize(merge_count*4);roots.resize(root_count);ports.resize(port_count*3);
            // Only the compact published arrays are needed after compilation.
            std::vector<Event>().swap(heap);std::vector<Draft>().swap(drafts);std::vector<Adjacent>().swap(adjacency);
            for(auto *v:{&parent,&sizes,&basin,&owner,&activated,&remap,&heads,&drain_queue})std::vector<int>().swap(*v);
            status=1;phase=11;return;
        }
        const int i=cursor++;owners.set(i,remap[owner[i]]);
        if(parent[i]==i)roots.set(root_count++,remap[basin[i]]);return;
    }
}
Dictionary NativeWaterBasins::advance(int64_t budget){
    int64_t work=0;
    if(budget<1||budget>2048){Dictionary out=statistics();out["ok"]=false;out["work_units"]=work;return out;}
    const uint64_t start=Time::get_singleton()->get_ticks_usec();
    while(status==0&&work<budget){unit();++work;++events;if(work%32==0&&Time::get_singleton()->get_ticks_usec()-start>=2000)break;}
    Dictionary out=statistics();out["ok"]=status>=0;out["work_units"]=work;return out;
}
Dictionary NativeWaterBasins::statistics() const {
    Dictionary out;out["status"]=status;out["phase"]=phase;out["nodes"]=ids.size();out["leaves"]=leaf_count;out["merges"]=merge_count;
    out["portals"]=port_count;out["roots"]=status==1?root_count:0;out["max_depth"]=max_depth;out["work_units_total"]=events;out["error"]=error;
    out["buffer_bytes"]=int64_t((ids.size()+floors.size()+edges.size()+owners.size()+leaf_floors.size()+merges.size()+roots.size()+ports.size())*sizeof(int32_t)
        +(parent.capacity()+sizes.capacity()+basin.capacity()+owner.capacity()+activated.capacity()+remap.capacity())*sizeof(int)
        +heap.capacity()*sizeof(Event)+drafts.capacity()*sizeof(Draft)+adjacency.capacity()*sizeof(Adjacent)+(heads.capacity()+drain_queue.capacity())*sizeof(int));return out;
}
Dictionary NativeWaterBasins::hierarchy() const {
    Dictionary out;out["ok"]=status==1;if(status!=1)return out;
    out["ids"]=ids;out["owners"]=owners;out["leaf_floors_mm"]=leaf_floors;out["merges"]=merges;out["roots"]=roots;out["portals"]=ports;
    out["requires_stitching"]=port_count>0;out["settling_compatible"]=port_count==0&&root_count==1&&max_depth<=64;
    return out;
}
}
