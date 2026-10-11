// SPDX-License-Identifier: 0BSD
#include "water_settling.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <algorithm>
using namespace godot;
namespace terraforest {
void NativeWaterSettling::_bind_methods(){
    ClassDB::bind_method(D_METHOD("configure","levels_mm","profiles_ml","merges"),&NativeWaterSettling::configure);
    ClassDB::bind_method(D_METHOD("configure_forest","levels_mm","profiles_ml","merges"),&NativeWaterSettling::configure_forest);
    ClassDB::bind_method(D_METHOD("begin_add","leaf","amount_ml"),&NativeWaterSettling::begin_add);
    ClassDB::bind_method(D_METHOD("begin_remove","leaf","amount_ml"),&NativeWaterSettling::begin_remove);
    ClassDB::bind_method(D_METHOD("advance","event_budget"),&NativeWaterSettling::advance);
    ClassDB::bind_method(D_METHOD("statistics"),&NativeWaterSettling::statistics);
    ClassDB::bind_method(D_METHOD("inspect","leaf"),&NativeWaterSettling::inspect);
}
bool NativeWaterSettling::configure(const PackedInt64Array &levels,const Array &profiles,const PackedInt32Array &merges){return configure_impl(levels,profiles,merges,false);}
bool NativeWaterSettling::configure_forest(const PackedInt64Array &levels,const Array &profiles,const PackedInt32Array &merges){return configure_impl(levels,profiles,merges,true);}
bool NativeWaterSettling::configure_impl(const PackedInt64Array &levels,const Array &profiles,const PackedInt32Array &merges,bool forest){
    if(root>=0||profiles.size()<1||profiles.size()>4096||levels.size()<2||levels.size()>256||merges.size()%4||merges.size()>(profiles.size()-1)*4||(!forest&&merges.size()!=(profiles.size()-1)*4))return false;
    for(int i=0;i<levels.size();++i)if(levels[i]<-100000000||levels[i]>100000000||(i&&levels[i]<=levels[i-1]))return false;
    std::vector<Node> staged;staged.reserve(profiles.size()*2-1);
    for(int i=0;i<profiles.size();++i){
        if(profiles[i].get_type()!=Variant::PACKED_INT64_ARRAY)return false;
        const PackedInt64Array p=profiles[i];if(p.size()!=levels.size()||p[0]!=0)return false;
        Node node;node.entry=i;node.merge=levels[0];node.profile.resize(p.size());
        for(int j=0;j<p.size();++j){if(p[j]<0||p[j]>maximum||(j&&p[j]<p[j-1]))return false;node.profile[j]=p[j];}
        staged.push_back(std::move(node));
    }
    for(int i=0;i<merges.size();i+=4){
        const int a=merges[i],b=merges[i+1],height=merges[i+2],entry=merges[i+3],id=staged.size();
        if(a<0||b<0||a>=id||b>=id||a==b||staged[a].parent>=0||staged[b].parent>=0||height<levels[0]||height>levels[levels.size()-1]||height<staged[a].merge||height<staged[b].merge||entry<0||entry>=profiles.size())return false;
        Node node;node.left=a;node.right=b;node.merge=height;node.entry=entry;node.profile.resize(levels.size());
        for(int j=0;j<levels.size();++j){if(staged[a].profile[j]>maximum-staged[b].profile[j])return false;node.profile[j]=staged[a].profile[j]+staged[b].profile[j];}
        staged[a].parent=id;staged[b].parent=id;
        auto capacity_at=[&](const Node &child){
            int hi=0;while(hi<levels.size()&&levels[hi]<height)++hi;
            if(hi==0)return child.profile[0];
            const int64_t span=levels[hi]-levels[hi-1],offset=height-levels[hi-1];
            const __int128 product=__int128(child.profile[hi]-child.profile[hi-1])*offset;
            return child.profile[hi-1]+int64_t(product/span);
        };
        staged[a].capacity=capacity_at(staged[a]);staged[b].capacity=capacity_at(staged[b]);
        node.base=staged[a].capacity+staged[b].capacity;staged.push_back(std::move(node));
    }
    const int r=staged.size()-1;int roots=0;
    for(auto &node:staged)if(node.parent<0){node.capacity=node.profile.back();++roots;}
    std::vector<int> ownership(profiles.size());
    // Validate a connected, bounded-depth tree and each spill entry's ownership.
    for(int n=0;n<int(staged.size());++n){
        int at=n,depth=0;while(staged[at].parent>=0&&depth<=64){at=staged[at].parent;++depth;}
        if((!forest&&at!=r)||depth>64||staged[n].capacity<staged[n].base)return false;
        if(n<profiles.size())ownership[n]=at;
        at=staged[n].entry;depth=0;while(at!=n&&staged[at].parent>=0&&depth<=64){at=staged[at].parent;++depth;}
        if(at!=n)return false;
    }
    leaf_roots.swap(ownership);root_count=roots;nodes.swap(staged);heights.assign(levels.ptr(),levels.ptr()+levels.size());leaves=profiles.size();root=r;frames.reserve(65);return true;
}
int NativeWaterSettling::active_node(int leaf,int stop) const {
    int chosen=leaf;
    for(int at=leaf;at>=0;at=nodes[at].parent){if(nodes[at].local>0)chosen=at;if(at==stop)break;}
    return chosen;
}
void NativeWaterSettling::change(int node,int64_t amount){
    total_ml+=amount;
    nodes[node].local+=amount;
    for(int at=node;at>=0;at=nodes[at].parent)nodes[at].total+=amount;
}
bool NativeWaterSettling::begin_add(int64_t leaf,int64_t amount){
    if(root<0||mode||leaf<0||leaf>=leaves||amount<=0||amount>maximum-total_ml)return false;
    source=leaf;requested=pending=amount;moved=events=0;mode=1;
    const int target=leaf_roots[leaf];frames.push_back({target,active_node(leaf,target),amount});return true;
}
bool NativeWaterSettling::begin_remove(int64_t leaf,int64_t amount){
    if(root<0||mode||leaf<0||leaf>=leaves||amount<=0||amount>maximum)return false;
    source=leaf;requested=pending=amount;moved=events=0;mode=2;return true;
}
void NativeWaterSettling::return_frame(int64_t remainder){
    frames.pop_back();
    if(frames.empty()){pending=remainder;mode=0;return;}
    frames.back().remaining=remainder;
}
Dictionary NativeWaterSettling::advance(int64_t budget){
    if(budget<1||budget>2048){Dictionary out=statistics();out["ok"]=false;out["work_events"]=0;return out;}
    int64_t work=0;
    while(mode&&work<budget){
        ++work;++events;
        if(mode==2){
            const int at=active_node(source,leaf_roots[source]);const int64_t take=std::min(pending,nodes[at].local);
            change(at,-take);moved+=take;pending-=take;
            if(!pending||!take)mode=0;
            continue;
        }
        Frame &f=frames.back();
        if(!f.remaining){return_frame(0);continue;}
        Node &node=nodes[f.node];
        // A frame reaches an internal node only after both children filled to
        // this connection's elevation. Local volume is the merged upper layer.
        const int64_t take=std::min(f.remaining,node.capacity-node.total);
        change(f.node,take);f.remaining-=take;pending-=take;moved+=take;
        if(!f.remaining||f.node==f.target){const auto remainder=f.remaining;return_frame(remainder);continue;}
        const int parent=node.parent,sibling=nodes[parent].left==f.node?nodes[parent].right:nodes[parent].left;
        const int64_t remainder=f.remaining;
        f.node=parent;f.remaining=0;
        frames.push_back({sibling,active_node(nodes[sibling].entry,sibling),remainder});
    }
    Dictionary out=statistics();out["ok"]=root>=0;out["work_events"]=work;return out;
}
Dictionary NativeWaterSettling::statistics() const {
    Dictionary out;out["ready"]=root>=0;out["busy"]=mode!=0;out["total_ml"]=total_ml;
    out["requested_ml"]=requested;out["pending_ml"]=pending;out["moved_ml"]=moved;out["events"]=events;
    out["roots"]=root_count;out["nodes"]=int64_t(nodes.size());out["frames"]=int64_t(frames.size());out["profile_bytes"]=int64_t(nodes.size()*heights.size()*sizeof(int64_t));return out;
}
Dictionary NativeWaterSettling::inspect(int64_t leaf) const {
    Dictionary out;out["ok"]=false;
    if(leaf<0||leaf>=leaves||mode)return out;
    const int at=active_node(leaf,leaf_roots[leaf]);const Node &node=nodes[at];
    const auto upper=std::lower_bound(node.profile.begin(),node.profile.end(),node.total);
    size_t j=upper-node.profile.begin();double level=heights[0];
    if(j>=heights.size())level=heights.back();
    else if(j){const double ratio=double(node.total-node.profile[j-1])/double(node.profile[j]-node.profile[j-1]);level=heights[j-1]+ratio*(heights[j]-heights[j-1]);}
    if(node.left>=0)level=std::max(level,double(node.merge));
    out["ok"]=true;out["component"]=at;out["level_mm"]=level;out["component_amount_ml"]=node.total;return out;
}
}
