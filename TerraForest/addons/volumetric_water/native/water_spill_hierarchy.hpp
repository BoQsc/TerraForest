// SPDX-License-Identifier: 0BSD
#pragma once
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <numeric>
#include <vector>

namespace terraforest {
struct WaterSpillEdge {int a,b;double level;};

// Both cell and span graphs retain each basin's water below its outlet.
// Only their graph construction and geometric capacity evaluators differ.
template<class Cells,class Volume,class Capacity,class Integral,class Cancel,class Mark,class Reason>
bool distribute_basin_water(Cells &cells,std::vector<WaterSpillEdge> &edges,int sink,double upper,
    uint64_t &quantity,int64_t &ocean_exchange_ml,Volume volume_at,Capacity capacity,Integral integral_at,
    const Cancel &cancelled,Mark mark,Reason &reason,int level_iterations=32){
    struct Basin {int left=-1,right=-1,parent=-1,begin=0,end=0;double level=0;uint64_t capacity=0,quantity=0,excess=0,extra=0;bool outlet=false;};
    static_assert(sizeof(Basin)<=80,"Recheck hierarchy reservation when a basin grows");
    std::stable_sort(edges.begin(),edges.end(),[](const WaterSpillEdge &a,const WaterSpillEdge &b){return a.level<b.level;});
    const size_t leaves=cells.size()+(sink>=0?1:0);
    std::vector<Basin> tree(leaves);tree.reserve(leaves*2);
    if(sink>=0)tree[sink].outlet=true;
    std::vector<int> roots(leaves);std::iota(roots.begin(),roots.end(),0);
    auto root=[&](int i){int r=i;while(roots[r]!=r)r=roots[r];while(roots[i]!=i){int next=roots[i];roots[i]=r;i=next;}return r;};
    for(const auto &edge:edges){
        int a=root(edge.a),b=root(edge.b);if(a==b)continue;
        int id=int(tree.size());tree.push_back({a,b,-1,0,0,edge.level});
        tree[id].outlet=tree[a].outlet||tree[b].outlet;
        tree[a].parent=id;tree[b].parent=id;roots.push_back(id);roots[a]=roots[b]=id;
    }
    const int trunk=root(0);
    for(size_t i=1;i<cells.size();++i)if(root(i)!=trunk){reason="Unavailable basin connection";return false;}
    // Store one leaf ordering, not a copied cell list at every
    // hierarchy node. Work is separately bounded for steep trees.
    std::vector<int> order,stack{trunk};order.reserve(cells.size());
    while(!stack.empty()){int id=stack.back();stack.pop_back();
        if(id<0){id=-id-1;tree[id].end=int(order.size());continue;}
        tree[id].begin=int(order.size());
        if(tree[id].left<0){if(id!=sink)order.push_back(id);tree[id].end=int(order.size());}
        else{stack.push_back(-id-1);stack.push_back(tree[id].right);stack.push_back(tree[id].left);}
    }
    uint64_t work=0;
    // Retire saturated leaves from ancestor capacity evaluations.
    // Deep interior cells then contribute a cached integer volume,
    // rather than being rescanned at every shoreline spill height.
    std::vector<std::vector<int>> active(tree.size());
    std::vector<uint64_t> saturated(tree.size());
    for(size_t id=0;id<tree.size();++id){
        auto &node=tree[id];double top=node.parent<0?upper:tree[node.parent].level;
        if(node.outlet){node.capacity=node.left<0?0:tree[node.left].capacity+tree[node.right].capacity;continue;}
        if(node.left<0)active[id].push_back(int(id));
        else{
            saturated[id]=saturated[node.left]+saturated[node.right];
            // All finite descendants together own at most quantity ml.
            // Capacity strictly above that amount can never be filled, even
            // if the entire body drains into this subtree. Since ancestor
            // spill levels only rise, this certificate is permanent. Keep
            // one extra ml so the routing pass cannot treat it as full.
            if(sink<0&&tree[node.left].capacity+tree[node.right].capacity>quantity){
                node.capacity=quantity+1;
                std::vector<int>().swap(active[node.left]);
                std::vector<int>().swap(active[node.right]);
                continue;
            }
            int a=node.left,b=node.right;
            if(active[a].size()<active[b].size())std::swap(a,b);
            active[id]=std::move(active[a]);
            active[id].insert(active[id].end(),active[b].begin(),active[b].end());
            std::vector<int>().swap(active[b]);
            if(top==node.level){node.capacity=tree[node.left].capacity+tree[node.right].capacity;continue;}
        }
        uint64_t partial=0;size_t retained=0;
        for(int i:active[id]){
            if(++work>4000000||cancelled.load()){reason="Basin hierarchy work budget exceeded";return false;}
            uint64_t volume=integral_at(i,top);
            if(volume==capacity(i))saturated[id]+=volume;
            else{partial+=volume;active[id][retained++]=i;}
        }
        active[id].resize(retained);node.capacity=saturated[id]+partial;
    }
    mark(6);
    // Record incoming overflow once per node. Descendant routing
    // is deferred to the final top-down pass, avoiding quadratic
    // repeated descent through a long shoreline merge tree.
    for(size_t id=0;id<tree.size();++id){
        auto &node=tree[id];uint64_t incoming=0;
        if(node.left<0)incoming=int(id)==sink?0:cells[id].before;
        else{node.quantity=tree[node.left].quantity+tree[node.right].quantity;incoming=tree[node.left].excess+tree[node.right].excess;}
        if(node.quantity>node.capacity){reason="Inconsistent basin capacity";return false;}
        uint64_t retained=node.outlet?0:std::min(incoming,node.capacity-node.quantity);node.excess=incoming-retained;
        node.quantity+=retained;if(node.left>=0)node.extra=retained;
        if(node.outlet&&node.excess){ocean_exchange_ml-=int64_t(node.excess);quantity-=node.excess;node.excess=0;}
    }
    if(tree[trunk].excess||tree[trunk].quantity!=quantity){reason="Basin exceeds available receiving space";return false;}
    mark(7);
    stack={trunk};
    while(!stack.empty()){
        int id=stack.back();stack.pop_back();auto &node=tree[id];
        if(node.left<0){if(id!=sink)cells[id].after=node.quantity;continue;}
        auto &left=tree[node.left];auto &right=tree[node.right];
        if(node.outlet){stack.push_back(node.right);stack.push_back(node.left);continue;}
        if(node.quantity<left.capacity+right.capacity){
            uint64_t a=std::min(node.extra,left.capacity-left.quantity);
            uint64_t b=node.extra-a;
            if(b>right.capacity-right.quantity){reason="Basin overflow routing exceeds capacity";return false;}
            left.quantity+=a;left.extra+=a;right.quantity+=b;right.extra+=b;
            stack.push_back(node.right);stack.push_back(node.left);continue;
        }
        double a=node.level,b=node.parent<0?upper:tree[node.parent].level;
        for(int iteration=0;iteration<level_iterations;++iteration){double m=(a+b)*.5,volume=0;
            if(m==a||m==b)break;
            for(int at=node.begin;at<node.end;++at){int i=order[at];volume+=volume_at(i,m);}
            if(volume<double(node.quantity))a=m;else b=m;
        }
        uint64_t filled=0;std::vector<int> fractions;
        for(int at=node.begin;at<node.end;++at){int i=order[at];auto &c=cells[i];double v=volume_at(i,b);
            c.after=uint64_t(std::max(0.,std::floor(v)));c.fraction=v-c.after;filled+=c.after;fractions.push_back(i);}
        // Node capacity is the sum of integer leaf capacities. At a
        // sill, remove rounding surplus without changing the total.
        std::stable_sort(fractions.begin(),fractions.end(),[&](int a,int b){return cells[a].fraction>cells[b].fraction;});
        if(filled>node.quantity){for(auto at=fractions.rbegin();at!=fractions.rend()&&filled>node.quantity;++at)if(cells[*at].after){--cells[*at].after;--filled;}}
        else for(int i:fractions)if(filled<node.quantity&&cells[i].after<capacity(i)){++cells[i].after;++filled;}
        if(filled!=node.quantity){reason="Basin remainder exceeds bounded rounding";return false;}
    }
    return true;
}
}
