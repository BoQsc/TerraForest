// SPDX-License-Identifier: 0BSD
#include "regional_water.hpp"
#include "water_spill_hierarchy.hpp"
#include "water_volume_query.hpp"
#include <algorithm>
#include <limits>

using namespace godot;
namespace terraforest {

// Every point of a rectangular air volume communicates with every other
// point below a common head. Replace its internal faces with one storage
// curve. Irregular terrain, roofs and structure faces keep their own profile.
NativeWaterEquilibriumJob::SpanResult NativeWaterEquilibriumJob::settle_wide_prisms(){
    using W=NativeRegionalWater;
    auto &store=*frozen.ptr();
    auto defer=[&](const char *why){prism_fallback=why;return SpanResult::fallback;};
    struct Block {W::Region *region=nullptr;std::array<int,512> owner;};
    struct Prism {Vector3i p,size;int shape;Block *block;uint64_t before=0,after=0;double fraction=0;};
    Vector3i low(500,64,500),high,source;
    double upper=-1;
    for(const auto &[key,r]:store.regions){
        if(r.ocean_state||!r.valid)return defer("reservoir or unknown occupancy");
        const Vector3i coord=W::position(key),base=coord*8;
        low=low.min(coord);high=high.max(coord);
        if(r.water.is_initial_zero())continue;
        const bool west=coord.x>0&&!store.regions.count(W::key(coord+Vector3i(-1,0,0)));
        const bool east=coord.x<499&&!store.regions.count(W::key(coord+Vector3i(1,0,0)));
        const bool north=coord.z>0&&!store.regions.count(W::key(coord+Vector3i(0,0,-1)));
        const bool south=coord.z<499&&!store.regions.count(W::key(coord+Vector3i(0,0,1)));
        for(int i=0;i<512;++i)if(r.water[i]){
            if((west&&i%8==0)||(east&&i%8==7)||(north&&i/64==0)||(south&&i/64==7))
                return defer("pinned wet boundary");
            Vector3i p=base+Vector3i(i%8,(i/8)%8,i/64);
            if((p.y+1)*.5<=upper)continue;
            double head=p.y*.5+W::profile(r,i).head(r.water[i])*.001;
            if(head>upper){source=p;upper=head;}
        }
    }
    if(upper<0)return defer("no water");
    const Vector3i extent=high-low+Vector3i(1,1,1);
    const size_t slots=size_t(extent.x)*extent.y*extent.z;
    if(slots>4*store.regions.size()||slots>32768)return defer("sparse bounds");
    std::vector<Block*> lookup(slots);
    std::vector<Block> blocks;blocks.reserve(store.regions.size());
    auto slot=[&](Vector3i p){p-=low;return p.x+extent.x*(p.y+extent.y*p.z);};
    auto lookup_block=[&](Vector3i p)->Block*{
        const Vector3i coord(p.x>>3,p.y>>3,p.z>>3);
        if(coord.x<low.x||coord.y<low.y||coord.z<low.z||coord.x>high.x||coord.y>high.y||coord.z>high.z)return nullptr;
        return lookup[slot(coord)];
    };
    constexpr int air=-2,closed=-1;
    const WaterCellProfile clear;
    std::vector<WaterCellProfile> shapes;
    std::vector<Prism> nodes;
    for(auto &[key,live]:store.regions){
        if(cancelled.load())return defer("cancelled");
        auto &block=blocks.emplace_back();block.region=&live;block.owner.fill(closed);
        const Vector3i coord=W::position(key),base=coord*8;
        lookup[slot(coord)]=&block;
        const auto &r=static_cast<const W::Region&>(live);
        auto &ids=block.owner;
        for(int i=0;i<512;++i){
            const Vector3i p=base+Vector3i(i%8,(i/8)%8,i/64);
            if(!W::in_domain(p)||p.y*.5>=upper||r.floor[i]==r.ceiling[i])continue;
            auto shape=W::profile(r,i);
            if(shape.is_full_air()){ids[i]=air;continue;}
            if(shape.volume((upper-p.y*.5)*1000.)<=0)continue;
            if(nodes.size()>=hierarchy_cell_limit)return defer("leaf budget");
            ids[i]=int(nodes.size());
            nodes.push_back({p,{1,1,1},int(shapes.size()),&block,r.water[i]});
            shapes.push_back(shape);
        }
        for(int z=0;z<8;++z)for(int y=0;y<8;++y)for(int x=0;x<8;++x){
            const int first=x+8*y+64*z;
            if(ids[first]!=air)continue;
            int h=1,w=1,d=1;
            while(y+h<8&&ids[first+8*h]==air)++h;
            auto column=[&](int i){for(int j=0;j<h;++j)if(ids[i+8*j]!=air)return false;return true;};
            while(x+w<8&&column(first+w))++w;
            while(z+d<8){
                bool row=true;
                for(int dx=0;dx<w&&row;++dx)row=column(first+dx+64*d);
                if(!row)break;
                ++d;
            }
            if(nodes.size()>=hierarchy_cell_limit)return defer("leaf budget");
            int id=int(nodes.size());uint64_t before=0;
            for(int dz=0;dz<d;++dz)for(int dy=0;dy<h;++dy)for(int dx=0;dx<w;++dx){
                int i=first+dx+8*dy+64*dz;ids[i]=id;before+=r.water[i];
            }
            nodes.push_back({base+Vector3i(x,y,z),{w,h,d},air,&block,before});
        }
    }
    const int source_id=lookup_block(source)->owner[W::index(source)];
    if(source_id<0)return defer("source is closed");
    // Visit faces of wet-connected prisms only. Coalesce the parallel edges
    // between each pair at the lowest actual connecting face elevation.
    const Vector3i dir[]={{0,-1,0},{1,0,0},{-1,0,0},{0,0,1},{0,0,-1},{0,1,0}};
    const int axes[]={1,0,0,2,2,1};
    std::vector<int> body{source_id},order(nodes.size(),-1),touched;
    order[source_id]=0;
    std::vector<double> least(nodes.size(),std::numeric_limits<double>::infinity());
    std::vector<WaterSpillEdge> edges;
    W::WetFrontier frontier;
    bool open=false,pinned=false;
    uint64_t quantity=0;size_t cells=0;
    auto depth=[&](int y){return std::clamp((upper-y*.5)*1000.,0.,500.);};
    for(size_t at=0;at<body.size();++at){
        if((at%128)==0&&cancelled.load())return defer("cancelled");
        auto &a=nodes[body[at]];
        quantity+=a.before;cells+=a.size.x*a.size.y*a.size.z;
        const auto &shape=a.shape==air?clear:shapes[a.shape];
        for(int d=0;d<6;++d){
            int axis=axes[d],u=(axis+1)%3,v=(axis+2)%3;
            Vector3i face=a.p;
            if(dir[d][axis]>0)face[axis]+=a.size[axis]-1;
            for(int j=0;j<a.size[v];++j)for(int i=0;i<a.size[u];){
                auto p=face;p[u]+=i;p[v]+=j;++i;
                auto q=p+dir[d];
                if(!W::in_domain(q)||q.y*.5>=upper)continue;
                auto *b=lookup_block(q);
                if(!b){
                    if(!WaterCellProfile::connected(shape,depth(p.y),clear,depth(q.y),d))continue;
                    open=true;
                    if(axis!=1&&a.before)pinned=true;
                    const auto k=W::region_key(q);
                    if(frontier.entries.count(k))continue;
                    const auto c=W::position(k);
                    for(const auto &[lo,hi]:wide_edit_bounds)if(c==c.clamp(lo,hi)){
                        frontier.entries.emplace(k,std::make_pair(p,d));break;
                    }
                    continue;
                }
                const int bid=b->owner[W::index(q)];
                if(bid<0)continue;
                const auto &n=nodes[bid];
                // When u is vertical this is the lowest shared face layer.
                i=std::min(a.size[u],n.p[u]+n.size[u]-face[u]);
                if(order[bid]>=0&&order[bid]<=int(at))continue;
                const auto &other=n.shape==air?clear:shapes[n.shape];
                if(!WaterCellProfile::connected(shape,depth(p.y),other,depth(q.y),d))continue;
                if(order[bid]<0){order[bid]=int(body.size());body.push_back(bid);}
                double sill=std::max(p.y,q.y)*.5;
                if(axis!=1&&(a.shape!=air||n.shape!=air)){
                    int side=dir[d][axis]>0?1:0;
                    sill+=.001*((shape.solid||other.solid)?WaterCellProfile::clipped_spill_height(shape,other,axis,side):
                        WaterCellProfile::floor_spill_height(shape,other,axis,side));
                }
                if(!std::isfinite(least[bid]))touched.push_back(bid);
                least[bid]=std::min(least[bid],std::min(upper,sill+2e-9));
            }
        }
        if(edges.size()+touched.size()>6*hierarchy_cell_limit)return defer("edge budget");
        for(int id:touched){
            edges.push_back({int(at),order[id],least[id]});
            least[id]=std::numeric_limits<double>::infinity();
        }
        touched.clear();
    }
    prism_nodes=body.size();prism_edges=edges.size();
    if(!frontier.entries.empty()){
        frontier.head=upper;wet_frontier=std::move(frontier);
        for(const auto &it:wet_frontier.entries)required.push_back(it.first);
        return SpanResult::dependencies;
    }
    if(pinned||quantity!=store.total)return defer(pinned?"pinned wet boundary":"separate wet components");
    std::vector<Prism> leaves;leaves.reserve(body.size());
    for(int id:body)leaves.push_back(nodes[id]);
    std::vector<WaterVolumeQuery> queries;queries.reserve(shapes.size());
    for(const auto &shape:shapes)queries.emplace_back(shape);
    auto capacity=[&](int id)->uint64_t{
        auto &p=leaves[id];return p.shape==air?125000ULL*p.size.x*p.size.y*p.size.z:queries[p.shape].capacity();
    };
    auto volume=[&](int id,double head){
        auto &p=leaves[id];const double h=(head-p.p.y*.5)*1000.;
        if(p.shape==air)return std::clamp(h*250.,0.,125000.*p.size.y)*p.size.x*p.size.z;
        return std::clamp(queries[p.shape].volume(h),0.,double(capacity(id)));
    };
    auto integral=[&](int id,double head){return uint64_t(std::floor(volume(id,head)));};
    const char *reason=nullptr;int64_t exchange=0;
    if(!distribute_basin_water(leaves,edges,-1,upper,quantity,exchange,volume,capacity,integral,cancelled,[](int){},reason,56))
        return defer(reason);
    if(cancelled.load())return defer("cancelled");
    std::unordered_set<uint64_t> dirty;
    for(const auto &p:leaves){
        const int columns=p.size.x*p.size.z,base=W::index(p.p);
        auto &r=*p.block->region;const auto &old=static_cast<const W::Region&>(r).water;
        bool changed=false;
        for(int z=0;z<p.size.z;++z)for(int x=0;x<p.size.x;++x){
            uint64_t column=p.after/columns+(uint64_t(x+p.size.x*z)<p.after%columns);
            for(int y=0;y<p.size.y;++y){
                auto amount=std::min<uint64_t>(column,125000);column-=amount;
                const int i=base+x+8*y+64*z;
                if(old[i]!=amount){r.water[i]=amount;changed=true;}
            }
        }
        if(changed)dirty.insert(W::region_key(p.p));
    }
    changed_regions.assign(dirty.begin(),dirty.end());
    for(auto &[k,r]:store.regions)r.settle_pending=false;
    if(!open){closed_basins=1;closed_basin_ml=quantity;}
    visited_cells=wide_cells=cells;wide_basin_leaves=wide_spans=body.size();
    prism_fallback=nullptr;
    return SpanResult::settled;
}
}
