// SPDX-License-Identifier: 0BSD
#include "regional_water.hpp"
#include "water_spill_hierarchy.hpp"
#include "water_volume_query.hpp"
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/classes/worker_thread_pool.hpp>
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
    auto began=Time::get_singleton()->get_ticks_usec();
    auto mark=[&](int i){auto now=Time::get_singleton()->get_ticks_usec();prism_us[i]+=now-began;began=now;};
    auto defer=[&](const char *why){prism_fallback=why;return SpanResult::fallback;};
    struct Block {W::Region *region=nullptr;std::array<int,512> owner;};
    struct Prism {Vector3i p,size;int shape;Block *block;uint64_t before=0,after=0;double fraction=0;};
    Vector3i low(500,64,500),high,source;
    double upper=-1;
    std::unordered_set<uint64_t> wet_boundary;
    Vector3i pinned_cell;
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
            Vector3i p=base+Vector3i(i%8,(i/8)%8,i/64);
            auto pin=[&](int x,int z){
                wet_boundary.insert(W::key({x,0,z}));pinned_cell=p;
            };
            if(west&&i%8==0)pin(coord.x-1,coord.z);
            if(east&&i%8==7)pin(coord.x+1,coord.z);
            if(north&&i/64==0)pin(coord.x,coord.z-1);
            if(south&&i/64==7)pin(coord.x,coord.z+1);
            if((p.y+1)*.5<=upper)continue;
            double head=p.y*.5+W::profile(r,i).head(r.water[i])*.001;
            if(head>upper){source=p;upper=head;}
        }
    }
    if(upper<0)return defer("no water");
    if(!wet_boundary.empty()&&!private_rounds)return defer("initial wet boundary survey");
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
    // Horizontal cells with the same flat floor communicate before either
    // can retain a millilitre. Represent their shared area by one storage
    // curve. A sloping or incomplete contact keeps its own exact profile.
    std::map<std::pair<double,bool>,int> flat_shapes;
    auto flat_id=[&](WaterCellProfile shape){
        if(shape.solid||shape.ceiling!=500)return -1;
        double level=shape.floor[0];
        for(auto h:shape.floor)if(h!=level)return -1;
        if(shape.contact){
            if(shape.minimum()!=level||shape.maximum()!=level||shape.mean()!=level)return -1;
            shape.contact=nullptr;
        }
        auto [it,fresh]=flat_shapes.try_emplace({level,shape.open_bottom},int(shapes.size()));
        if(fresh)shapes.push_back(shape);
        return it->second;
    };
    std::vector<Prism> nodes;
    for(auto &[key,live]:store.regions){
        if(cancelled.load())return defer("cancelled");
        auto &block=blocks.emplace_back();block.region=&live;block.owner.fill(closed);
        const Vector3i coord=W::position(key),base=coord*8;
        lookup[slot(coord)]=&block;
        const auto &r=static_cast<const W::Region&>(live);
        auto &ids=block.owner;
        const int layers=std::clamp(int(std::ceil(upper*2.))-base.y,0,8);
        if(!layers||r.brick_geometry==WaterBrickGeometry::solid)continue;
        if(r.brick_geometry==WaterBrickGeometry::air){
            if(nodes.size()>=hierarchy_cell_limit)return defer("leaf budget");
            const int id=int(nodes.size());
            uint64_t before=0;
            for(int z=0;z<8;++z){
                std::fill_n(ids.begin()+z*64,8*layers,id);
                if(!r.water.is_initial_zero())before=std::accumulate(r.water.begin()+z*64,r.water.begin()+z*64+8*layers,before);
            }
            nodes.push_back({base,{8,layers,8},air,&block,before});continue;
        }
        for(int i=0;i<512;++i){
            const Vector3i p=base+Vector3i(i%8,(i/8)%8,i/64);
            if(!W::in_domain(p)||p.y*.5>=upper||r.floor[i]==r.ceiling[i])continue;
            auto shape=W::profile(r,i);
            if(shape.is_full_air()){ids[i]=air;continue;}
            if(shape.volume((upper-p.y*.5)*1000.)<=0)continue;
            int band=flat_id(shape);
            if(band>=0){ids[i]=-3-band;continue;}
            if(nodes.size()>=hierarchy_cell_limit)return defer("leaf budget");
            ids[i]=int(nodes.size());
            nodes.push_back({p,{1,1,1},int(shapes.size()),&block,r.water[i]});
            shapes.push_back(shape);
        }
        for(int z=0;z<8;++z)for(int y=0;y<8;++y)for(int x=0;x<8;++x){
            const int first=x+8*y+64*z;
            const int category=ids[first];
            if(category>=closed)continue;
            int h=1,w=1,d=1;
            if(category==air)while(y+h<8&&ids[first+8*h]==air)++h;
            auto column=[&](int i){for(int j=0;j<h;++j)if(ids[i+8*j]!=category)return false;return true;};
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
            nodes.push_back({base+Vector3i(x,y,z),{w,h,d},category==air?air:-3-category,&block,before});
        }
    }
    mark(0);
    const int source_id=lookup_block(source)->owner[W::index(source)];
    if(source_id<0)return defer("source is closed");
    // Visit faces of wet-connected prisms only. Coalesce the parallel edges
    // between each pair at the lowest actual connecting face elevation.
    const Vector3i dir[]={{0,-1,0},{1,0,0},{-1,0,0},{0,0,1},{0,0,-1},{0,1,0}};
    const int axes[]={1,0,0,2,2,1};
    std::vector<int> body{source_id},order(nodes.size(),-1);
    order[source_id]=0;
    std::vector<WaterSpillEdge> edges;
    W::WetFrontier frontier;
    bool open=false;
    uint64_t quantity=0;size_t cells=0;
    auto depth=[&](int y){return std::clamp((upper-y*.5)*1000.,0.,500.);};
    struct Links {
        struct Passage {int neighbor;double height;};
        std::vector<Passage> passages;
        std::vector<std::pair<Vector3i,int>> exits;
        bool open=false;
    };
    auto collect=[&](size_t at,Links &links){
        const auto &a=nodes[body[at]];
        const auto &shape=a.shape==air?clear:shapes[a.shape];
        // A prism has at most 384 exterior faces. Small prisms search their
        // short encounter list directly. Larger faces coalesce through a
        // lane-private index, preserving the first encounter for equal sills.
        const bool indexed=a.size.x*a.size.y*a.size.z>4;
        std::array<int16_t,512> slots;
        if(indexed)slots.fill(-1);
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
                    links.open=true;
                    if(!links.exits.empty()&&links.exits.back().second==d)continue;
                    const auto c=W::position(W::region_key(q));
                    for(const auto &[lo,hi]:wide_edit_bounds)if(c==c.clamp(lo,hi)){
                        links.exits.emplace_back(p,d);break;
                    }
                    continue;
                }
                const int bid=b->owner[W::index(q)];
                if(bid<0)continue;
                const auto &n=nodes[bid];
                // When u is vertical this is the lowest shared face layer.
                i=std::min(a.size[u],n.p[u]+n.size[u]-face[u]);
                if(order[bid]>=0&&order[bid]<=int(at))continue;
                double sill=std::max(p.y,q.y)*.5;
                unsigned bucket=(uint32_t(bid)*2654435761u)>>23;
                int previous=-1;
                if(indexed){
                    while(slots[bucket]>=0&&links.passages[slots[bucket]].neighbor!=bid)bucket=(bucket+1)&511;
                    previous=slots[bucket];
                }else{
                    for(size_t pos=0;pos<links.passages.size();++pos)if(links.passages[pos].neighbor==bid){previous=int(pos);break;}
                }
                if(previous>=0&&links.passages[previous].height<=sill+2e-9)continue;
                const auto &other=n.shape==air?clear:shapes[n.shape];
                const int side=dir[d][axis]>0?1:0;
                if(axis!=1&&!shape.solid&&!other.solid&&!(shape.is_full_air()&&other.is_full_air())){
                    double floor;
                    if(!WaterCellProfile::floor_passage(shape,depth(p.y),other,depth(q.y),axis,side,floor))continue;
                    sill+=.001*floor;
                }else{
                    if(!WaterCellProfile::connected(shape,depth(p.y),other,depth(q.y),d))continue;
                    if(axis!=1&&(shape.solid||other.solid))sill+=.001*WaterCellProfile::clipped_spill_height(shape,other,axis,side);
                }
                sill=std::min(upper,sill+2e-9);
                if(previous>=0)links.passages[previous].height=std::min(links.passages[previous].height,sill);
                else{
                    if(indexed)slots[bucket]=int16_t(links.passages.size());
                    links.passages.push_back({bid,sill});
                }
            }
        }
    };
    // Capture the currently reached wave. Workers read only proved owners
    // and immutable geometry. Discovery, outlet selection and remainder
    // ordering commit in the original breadth-first order after the join.
    // Never speculate across dry islands or retain a second full-body graph.
    constexpr size_t wave_limit=128;
    // Charge up to 512 passages, six exits and allocator slack per lane
    // record against spare graph capacity in the existing reservation.
    const auto spare=hierarchy_cell_limit-nodes.size();
    const size_t available=std::min<size_t>(wave_limit,spare/10);
    if(!available)return defer("face scratch budget");
    std::vector<Links> wave(available);
    for(size_t first=0;first<body.size();){
        if(cancelled.load())return defer("cancelled");
        const auto count=std::min(available,body.size()-first);
        auto work=[&](uint32_t i){if(!cancelled.load())collect(first+i,wave[i]);};
        auto lane=[](void *context,uint32_t i){(*static_cast<decltype(work)*>(context))(i);};
        auto *pool=WorkerThreadPool::get_singleton();
        const auto task=count>=48&&nodes.size()>=2048?pool->add_native_group_task(lane,&work,int(count),3,true,"Water spill faces"):-1;
        if(task>=0)pool->wait_for_group_task_completion(task);
        else for(size_t i=0;i<count;++i)work(uint32_t(i));
        if(cancelled.load())return defer("cancelled");
        for(size_t i=0;i<count;++i){
            const size_t at=first+i;const auto &a=nodes[body[at]];
            quantity+=a.before;cells+=a.size.x*a.size.y*a.size.z;
            auto &result=wave[i];open|=result.open;
            for(const auto &[p,d]:result.exits)frontier.entries.try_emplace(W::region_key(p+dir[d]),p,d);
            if(edges.size()+result.passages.size()>6*hierarchy_cell_limit)return defer("edge budget");
            for(const auto &passage:result.passages){
                auto &id=order[passage.neighbor];
                if(id<0){id=int(body.size());body.push_back(passage.neighbor);}
                edges.push_back({int(at),id,passage.height});
            }
            result.open=false;result.exits.clear();result.passages.clear();
        }
        first+=count;
    }
    mark(1);prism_nodes=body.size();prism_edges=edges.size();
    if(!frontier.entries.empty()){
        frontier.head=upper;wet_frontier=std::move(frontier);
        for(const auto &it:wet_frontier.entries)required.push_back(it.first);
        return SpanResult::dependencies;
    }
    if(quantity!=store.total)return defer("separate wet components");
    std::vector<Prism> leaves;leaves.reserve(body.size());
    for(int id:body)leaves.push_back(nodes[id]);
    std::vector<WaterVolumeQuery> queries;queries.reserve(shapes.size());
    for(const auto &shape:shapes)queries.emplace_back(shape);
    auto capacity=[&](int id)->uint64_t{
        auto &p=leaves[id];return (p.shape==air?125000ULL*p.size.y:queries[p.shape].capacity())*p.size.x*p.size.z;
    };
    auto volume=[&](int id,double head){
        auto &p=leaves[id];const double h=(head-p.p.y*.5)*1000.;
        if(p.shape==air)return std::clamp(h*250.,0.,125000.*p.size.y)*p.size.x*p.size.z;
        return std::clamp(queries[p.shape].volume(h),0.,double(queries[p.shape].capacity()))*p.size.x*p.size.z;
    };
    auto integral=[&](int id,double head){return uint64_t(std::floor(volume(id,head)));};
    if(open&&!wet_boundary.empty()){
        // The local boundary pins existing outer columns. If they can share
        // a single transient head, the weighted solve owns that transition.
        // Prove disconnected wet pockets before switching to the spill tree.
        // Relax every transition constraint outward, so a negative reachability
        // result holds for the exact cell heights and integer rounding as well.
        std::vector<double> weight(leaves.size(),1.),top(leaves.size());
        for(size_t i=0;i<leaves.size();++i){
            const auto &p=leaves[i];const auto coord=W::position(W::region_key(p.p));
            double distance=3.5;
            for(int z=coord.z-1;z<=coord.z+1;++z)for(int x=coord.x-1;x<=coord.x+1;++x){
                if(x<0||z<0||!wet_boundary.count(W::key({x,0,z})))continue;
                double dx=std::max({0.,x*4.-(p.p.x+p.size.x-.5)*.5,(p.p.x+.5)*.5-(x+1)*4.});
                double dz=std::max({0.,z*4.-(p.p.z+p.size.z-.5)*.5,(p.p.z+.5)*.5-(z+1)*4.});
                distance=std::min(distance,std::hypot(dx,dz));
            }
            const double t=std::clamp((distance-.5)/3.,0.,1.);
            weight[i]=t*t*(3.-2.*t);
        }
        const int pinned_owner=lookup_block(pinned_cell)->owner[W::index(pinned_cell)];
        if(pinned_owner<0)return defer("fixed owner has no air");
        const auto pin=order[pinned_owner];
        if(pin<0)return defer("fixed owner outside body");
        double bottom=0,ceiling=upper;
        for(int n=0;n<18;++n){
            double trial=(bottom+ceiling)*.5,available=0;
            for(size_t i=0;i<leaves.size();++i)if(weight[i]==1.)available+=volume(int(i),trial);
            if(available>double(quantity+cells))ceiling=trial;else bottom=trial;
        }
        // Enlarge by the remainder of a cell so rounding up a nearly dry
        // sliver by one millilitre can never falsely isolate a basin.
        for(size_t i=0;i<leaves.size();++i)
            top[i]=std::ceil((upper+(ceiling-upper)*weight[i])*2.)*.5+.00001;
        std::vector<int> roots(leaves.size());std::iota(roots.begin(),roots.end(),0);
        auto root=[&](int a){while(roots[a]!=a){roots[a]=roots[roots[a]];a=roots[a];}return a;};
        for(const auto &edge:edges)if(edge.level<=std::min(top[edge.a],top[edge.b]))
            roots[root(edge.a)]=root(edge.b);
        const int component=root(pin);
        double reachable=0;
        for(size_t i=0;i<leaves.size();++i)if(root(int(i))==component)
            reachable+=volume(int(i),top[i]);
        if(reachable+double(cells)>=double(quantity))return defer("connected pinned transition");
    }
    mark(2);
    const char *reason=nullptr;int64_t exchange=0;
    if(!distribute_basin_water(leaves,edges,-1,upper,quantity,exchange,volume,capacity,integral,cancelled,[](int){},reason,56))
        return defer(reason);
    mark(3);if(cancelled.load())return defer("cancelled");
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
    mark(4);prism_fallback=nullptr;
    return SpanResult::settled;
}
}
