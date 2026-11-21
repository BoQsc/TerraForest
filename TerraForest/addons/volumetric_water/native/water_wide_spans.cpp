// SPDX-License-Identifier: 0BSD
#include "regional_water.hpp"
#include "water_spill_hierarchy.hpp"
#include "water_volume_query.hpp"
#include <algorithm>
#include <cmath>
#include <limits>

using namespace godot;
namespace terraforest {

// In a vertical run of unobstructed cells, capacity is a linear function
// between the bottom and top. Slopes, roofs and structure contacts remain
// individual cells and use the production profile for both volume and faces.
NativeWaterEquilibriumJob::SpanResult NativeWaterEquilibriumJob::settle_wide_spans(){
    using W=NativeRegionalWater;
    auto &store=*frozen.ptr();
    auto fallback=[&](const char *why){wide_fallback=why;return SpanResult::fallback;};
    using Key=uint64_t;
    struct Block {
        const W::Region *region;
        std::array<int,512> ids;
    };
    struct Span {
        Vector3i base;
        unsigned length;
        bool air;
        uint64_t before,after;
        double weight=1,fraction=0;
    };
    std::unordered_map<Key,Block> blocks;
    std::vector<Span> spans;
    Vector3i source;
    double upper=-1;
    for(const auto &[k,r]:store.regions){
        if(r.ocean_state||!r.valid)return fallback("reservoir or unknown occupancy");
        const auto base=W::position(k)*8;
        for(int i=0;i<512;++i)if(r.water[i]){
            auto shape=W::profile(r,i);
            const double head=(base.y+(i/8)%8)*.5+shape.head(r.water[i])*.001;
            if(head>upper){upper=head;source=base+Vector3i(i%8,(i/8)%8,i/64);}
        }
    }
    if(upper<0)return SpanResult::fallback;
    const double epsilon=std::numeric_limits<double>::epsilon();
    for(const auto &[k,r]:store.regions){
        if(cancelled.load())return SpanResult::fallback;
        auto &block=blocks[k];block.region=&r;block.ids.fill(-1);
        const auto base=W::position(k)*8;
        for(int z=0;z<8;++z)for(int x=0;x<8;++x){
            int previous=-1;
            for(int y=0;y<8;++y){
                const int i=x+8*y+64*z;
                if((base.y+y)*.5>=upper)break;
                if(!W::in_domain(base+Vector3i(x,y,z))||r.floor[i]==r.ceiling[i]){previous=-1;continue;}
                auto shape=W::profile(r,i);
                bool air=shape.is_full_air();
                if(!air&&shape.volume((upper-(base.y+y)*.5)*1000.)<=0){previous=-1;continue;}
                if(air&&previous>=0&&spans[previous].air){
                    ++spans[previous].length;
                    spans[previous].before+=r.water[i];
                }else{
                    if(spans.size()>=cell_limit)return fallback("span memory budget");
                    previous=int(spans.size());
                    spans.push_back({base+Vector3i(x,y,z),1,air,r.water[i],0});
                }
                block.ids[i]=previous;
            }
        }
    }
    const Vector3i directions[]={{0,-1,0},{1,0,0},{-1,0,0},{0,0,1},{0,0,-1},{0,1,0}};
    const WaterCellProfile air;
    auto shape_at=[&](const Span &s,const Block &b){return s.air?air:W::profile(*b.region,W::index(s.base));};
    std::unordered_set<Key> missing;
    bool open_boundary=false;
    auto eligible=[&](const Vector3i &p){
        for(const auto &[lo,hi]:wide_edit_bounds)if(p==p.clamp(lo,hi))return true;
        return false;
    };
    enum class Passage { upper, wet, drain };
    auto flood=[&](std::vector<int> queue,Passage passage,std::vector<unsigned char> &seen){
        const bool installed=passage==Passage::wet;
        for(int id:queue)seen[id]=1;
        auto depth=[&](const Span &s,int y,const WaterCellProfile &shape){
            if(!installed)return std::clamp((upper-y*.5)*1000.,0.,500.);
            if(s.air)return std::clamp(double(s.after)/250.-(y-s.base.y)*500.,0.,500.);
            return s.after?shape.head(s.after):0.;
        };
        for(size_t j=0;j<queue.size();++j){
            if((j%256)==0&&cancelled.load())break;
            const auto &s=spans[queue[j]];const auto bk=W::region_key(s.base);
            const auto &block=blocks.at(bk);const auto a=shape_at(s,block);
            for(int d=0;d<6;++d){
                int y=d==5?s.length-1:0;
                const int end=d==0?1:int(s.length);
                while(y<end){
                    const auto p=s.base+Vector3i(0,y,0),q=p+directions[d];++y;
                    if(!W::in_domain(q)||q.y*.5>=upper)continue;
                    const Key neighbor=W::region_key(q);
                    const Block *b=&block;
                    if(neighbor!=bk){
                        auto it=blocks.find(neighbor);
                        if(it==blocks.end()){
                            if(passage==Passage::upper&&WaterCellProfile::connected(a,depth(s,p.y,a),air,std::clamp((upper-q.y*.5)*1000.,0.,500.),d)){
                                open_boundary=true;
                                if(eligible(W::position(neighbor)))missing.insert(neighbor);
                            }
                            continue;
                        }
                        b=&it->second;
                    }
                    int id=b->ids[W::index(q)];
                    if(id<0)continue;
                    const auto &other=spans[id];
                    // At a fixed pair of column heads the lowest shared layer
                    // is the wettest. Higher cells in the same two air runs
                    // cannot open a passage if this layer is dry.
                    if(d>=1&&d<=4)y=std::min(end,int(other.base.y+other.length)-s.base.y);
                    if(seen[id])continue;
                    const auto c=shape_at(other,*b);
                    if(WaterCellProfile::connected(a,depth(s,p.y,a),c,depth(other,q.y,c),d)){
                        if(passage==Passage::drain){
                            // From a certified receiver, admit a dry donor if
                            // it can drain through this face with at most the
                            // scalar solver's one ml of rounding residue.
                            double spill=std::max(p.y,q.y)*.5;
                            if(d!=0&&d!=5){
                                int axis=d<=2?0:2,side=d==1||d==3?1:0;
                                double sill=(a.solid||c.solid)?WaterCellProfile::clipped_spill_height(a,c,axis,side):
                                    WaterCellProfile::floor_spill_height(a,c,axis,side);
                                spill=p.y*.5+sill*.001;
                            }
                            double height=std::min(upper,spill+2e-9)-other.base.y*.5;
                            double retained=other.air?std::clamp(height*250000.,0.,125000.*other.length):c.volume(height*1000.);
                            if(retained>1.)continue;
                        }
                        seen[id]=1;queue.push_back(id);
                    }
                }
            }
        }
        return queue;
    };
    auto source_id=blocks.at(W::region_key(source)).ids[W::index(source)];
    if(source_id<0)return SpanResult::fallback;
    std::vector<unsigned char> reached(spans.size());
    auto body=flood({source_id},Passage::upper,reached);
    if(cancelled.load())return SpanResult::fallback;
    wide_spans=body.size();wide_cells=0;
    for(int i:body)wide_cells+=spans[i].length;
    if(!missing.empty()){
        required.assign(missing.begin(),missing.end());return SpanResult::dependencies;
    }
    uint64_t quantity=0;
    for(int i:body)quantity+=spans[i].before;
    // Disconnected lakes and spilling or perched pools require their own
    // levels. The general solver remains their owner.
    if(!quantity||quantity!=store.total)return fallback("multiple wet components");
    double low=upper;
    // Pin the transient to water that continues across the snapshot edge.
    // An exposed dry edge supplies no head. Pinning it to the highest donor
    // would create a raised ring around a freshly excavated basin.
    std::unordered_set<Key> wet_boundary;
    if(open_boundary)for(int i:body){
        const auto &s=spans[i];if(!s.before)continue;
        auto owner=W::position(W::region_key(s.base));
        for(int d=1;d<=4;++d){
            auto neighbor=W::position(W::region_key(s.base+directions[d]));
            if(neighbor==owner||blocks.count(W::key(neighbor)))continue;
            wet_boundary.insert(W::key(Vector3i(neighbor.x,0,neighbor.z)));
        }
    }
    for(int i:body){
        auto &s=spans[i];low=std::min(low,s.base.y*.5);
        if(wet_boundary.empty())continue;
        double distance=3.5;auto owner=W::position(W::region_key(s.base));
        for(int dz=-1;dz<=1;++dz)for(int dx=-1;dx<=1;++dx){
            const int x=owner.x+dx,z=owner.z+dz;
            if(x<0||z<0||!wet_boundary.count(W::key(Vector3i(x,0,z))))continue;
            double px=(s.base.x+.5)*.5,pz=(s.base.z+.5)*.5;
            double ex=std::max({x*4.-px,0.,px-(x+1)*4.}),ez=std::max({z*4.-pz,0.,pz-(z+1)*4.});
            distance=std::min(distance,std::hypot(ex,ez));
        }
        double t=std::clamp((distance-.5)/3.,0.,1.);s.weight=t*t*(3.-2.*t);
        if(s.weight==0&&s.air){
            const auto &r=*blocks.at(W::region_key(s.base)).region;
            for(unsigned y=0;y<s.length;++y){
                uint64_t filled=std::clamp<int64_t>(int64_t(s.before)-125000LL*y,0,125000);
                if(r.water[W::index(s.base)+8*y]!=filled)return fallback("fixed boundary has interrupted column");
            }
        }
    }
    auto volume=[&](const Span &s,double head){
        if(s.weight==0)return double(s.before);
        const double depth=(upper+(head-upper)*s.weight-s.base.y*.5)*1000.;
        if(s.air)return std::clamp(depth*250.,0.,125000.*s.length);
        auto shape=shape_at(s,blocks.at(W::region_key(s.base)));
        return std::clamp(shape.volume(depth),0.,double(shape.capacity()));
    };
    // Each boundary weight gives its columns the same head. Sum complete
    // layers once. Only clipped cells in the current surface layer need an
    // exact volume query during root finding.
    struct CapacityBand {
        std::array<int,513> air_count{};
        std::array<double,513> below{};
        std::unordered_map<int,std::vector<int>> cut;
    };
    std::map<double,CapacityBand> bands;
    uint64_t fixed=0;
    for(int i:body){
        const auto &s=spans[i];
        if(s.weight==0){fixed+=s.before;continue;}
        auto &band=bands[s.weight];
        int y=s.base.y;
        if(s.air){
            ++band.air_count[y];--band.air_count[y+s.length];
        }else{
            auto shape=shape_at(s,blocks.at(W::region_key(s.base)));
            band.below[y+1]+=std::min(double(shape.capacity()),shape.volume(500.));
            band.cut[y].push_back(i);
        }
    }
    for(auto &[weight,band]:bands){
        int count=0;
        for(int y=0;y<512;++y){
            count+=band.air_count[y];band.air_count[y]=count;
            band.below[y+1]+=band.below[y]+125000.*count;
        }
    }
    auto total_at=[&](double head){
        double value=double(fixed);
        for(const auto &[weight,band]:bands){
            double level=std::clamp(upper+(head-upper)*weight,0.,256.);
            int y=std::min(511,int(std::floor(level*2.)));
            value+=band.below[y]+(level-y*.5)*250000.*band.air_count[y];
            auto cut=band.cut.find(y);
            if(cut!=band.cut.end())for(int i:cut->second)value+=volume(spans[i],head);
        }
        return value;
    };
    for(int i=0;i<32&&total_at(low)>double(quantity);++i)low=upper-std::max(1.,2*(upper-low));
    if(total_at(low)>double(quantity)||total_at(upper)+1e-6<double(quantity))return fallback("finite volume outside compact capacity");
    double high=upper;
    for(int i=0;i<64;++i){
        if(cancelled.load())return SpanResult::fallback;
        double mid=(high+low)*.5;
        if(total_at(mid)<double(quantity))low=mid;else high=mid;
        if((high-low)*std::max<size_t>(1,body.size())*250000.<.05||high-low<=epsilon)break;
    }
    uint64_t assigned=0;std::vector<int> fractions;
    for(int i:body){
        auto &s=spans[i];double v=volume(s,high);s.after=uint64_t(std::floor(v));
        assigned+=s.after;s.fraction=v-s.after;
        if(s.fraction>0)fractions.push_back(i);
    }
    if(assigned>quantity||quantity-assigned>fractions.size())return fallback("integer volume rounding");
    std::sort(fractions.begin(),fractions.end(),[&](int a,int b){
        if(spans[a].fraction!=spans[b].fraction)return spans[a].fraction>spans[b].fraction;
        return W::key(spans[a].base)<W::key(spans[b].base);
    });
    for(size_t j=0;j<quantity-assigned;++j)++spans[fractions[j]].after;
    auto first=std::find_if(body.begin(),body.end(),[&](int i){return spans[i].after>0;});
    if(first==body.end())return SpanResult::fallback;
    std::vector<unsigned char> wet(spans.size());
    auto receivers=flood({*first},Passage::wet,wet);
    bool separate_pools=false,needs_drain=false;
    for(int i:body){
        if(spans[i].after&&!wet[i])separate_pools=true;
        if(spans[i].before&&!wet[i])needs_drain=true;
    }
    if(!separate_pools&&needs_drain){
        flood(std::move(receivers),Passage::drain,wet);
        separate_pools=std::any_of(body.begin(),body.end(),[&](int i){return spans[i].before&&!wet[i];});
    }
    if(separate_pools){
        // At every elevation, horizontally adjacent clear columns with the
        // same bottom and top have one communicating storage volume. Collapse
        // those faces before allocating the spill tree. Shaped cells stay
        // independent leaves, even when their capacities happen to match.
        struct Pool {
            int first,count=0;
            uint64_t before=0,after=0;
            double fraction=0;
        };
        std::vector<Pool> pools;
        std::vector<int> owner(spans.size(),-1),next(spans.size(),-1),pending;
        auto find_span=[&](const Vector3i &p){
            if(!W::in_domain(p))return -1;
            auto block=blocks.find(W::region_key(p));
            return block==blocks.end()?-1:block->second.ids[W::index(p)];
        };
        for(int seed:body){
            if(owner[seed]>=0)continue;
            if(pools.size()>=hierarchy_cell_limit)return fallback("compact basin leaf budget");
            int id=int(pools.size());
            pools.push_back({-1});
            auto &pool=pools.back();
            pending={seed};owner[seed]=id;
            for(size_t at=0;at<pending.size();++at){
                int i=pending[at];const auto &s=spans[i];
                next[i]=pool.first;pool.first=i;++pool.count;pool.before+=s.before;
                if(!s.air)continue;
                for(int d=1;d<=4;++d){
                    int j=find_span(s.base+directions[d]);
                    if(j<0||!reached[j]||owner[j]>=0)continue;
                    const auto &n=spans[j];
                    if(n.air&&n.base.y==s.base.y&&n.length==s.length){owner[j]=id;pending.push_back(j);}
                }
            }
        }
        wide_basin_leaves=pools.size();
        std::vector<WaterCellProfile> shapes;shapes.reserve(pools.size());
        for(const auto &pool:pools){
            const auto &s=spans[pool.first];
            shapes.push_back(shape_at(s,blocks.at(W::region_key(s.base))));
        }
        std::vector<WaterVolumeQuery> queries;queries.reserve(shapes.size());
        for(const auto &shape:shapes)queries.emplace_back(shape);
        std::vector<WaterSpillEdge> edges;
        std::vector<int> touched;
        std::vector<double> least(pools.size(),std::numeric_limits<double>::infinity());
        for(int id=0;id<int(pools.size());++id){
            if(cancelled.load())return SpanResult::fallback;
            for(int i=pools[id].first;i>=0;i=next[i]){
                const auto &s=spans[i];const auto &a=shapes[id];
                for(int d=0;d<6;++d){
                    int y=d==5?int(s.length)-1:0,end=d==0?1:int(s.length);
                    while(y<end){
                        auto p=s.base+Vector3i(0,y++,0),q=p+directions[d];
                        int j=find_span(q);
                        if(j<0)continue;
                        const auto &other=spans[j];
                        if(d>=1&&d<=4)y=std::min(end,int(other.base.y+other.length)-s.base.y);
                        int neighbor=owner[j];if(neighbor<=id)continue;
                        const auto &c=shapes[neighbor];
                        double ah=std::clamp((upper-p.y*.5)*1000.,0.,500.),bh=std::clamp((upper-q.y*.5)*1000.,0.,500.);
                        if(!WaterCellProfile::connected(a,ah,c,bh,d))continue;
                        double spill=std::max(p.y,q.y)*.5;
                        if(d>=1&&d<=4&&(!s.air||!other.air)){
                            int axis=d<=2?0:2,side=d==1||d==3?1:0;
                            spill+=(a.solid||c.solid?WaterCellProfile::clipped_spill_height(a,c,axis,side):
                                WaterCellProfile::floor_spill_height(a,c,axis,side))*.001;
                        }
                        if(!std::isfinite(least[neighbor]))touched.push_back(neighbor);
                        least[neighbor]=std::min(least[neighbor],std::min(upper,spill+2e-9));
                    }
                }
            }
            if(edges.size()+touched.size()>6*hierarchy_cell_limit)return fallback("compact spill edge budget");
            for(int neighbor:touched){
                edges.push_back({id,neighbor,least[neighbor]});
                least[neighbor]=std::numeric_limits<double>::infinity();
            }
            touched.clear();
        }
        auto capacity=[&](int i)->uint64_t{
            auto &s=spans[pools[i].first];
            return s.air?uint64_t(125000)*s.length*pools[i].count:queries[i].capacity();
        };
        auto stored=[&](int i,double h){
            auto &s=spans[pools[i].first];
            double depth=(h-s.base.y*.5)*1000.;
            if(s.air)return std::clamp(depth*250.,0.,125000.*s.length)*pools[i].count;
            return std::clamp(queries[i].volume(depth),0.,double(capacity(i)));
        };
        auto integral=[&](int i,double h){return uint64_t(std::floor(stored(i,h)));};
        int64_t exchange=0;
        // One wide pool can hold thousands of columns at the same level.
        // Resolve its common head down to double precision before integer allocation.
        const char *failure=nullptr;
        if(!distribute_basin_water(pools,edges,-1,upper,quantity,exchange,stored,capacity,integral,cancelled,[](int){},failure,56)){
            return fallback(failure);
        }
        for(const auto &pool:pools){
            uint64_t each=pool.after/pool.count,remainder=pool.after%pool.count;
            for(int i=pool.first;i>=0;i=next[i]){
                spans[i].after=each+(remainder>0);
                if(remainder)--remainder;
            }
        }
    }
    if(cancelled.load())return SpanResult::fallback;
    std::unordered_set<Key> dirty;
    for(int i:body){
        const auto &s=spans[i];const auto k=W::region_key(s.base);
        auto &r=store.regions.at(k);const auto &old=static_cast<const W::Region &>(r).water;
        for(unsigned y=0;y<s.length;++y){
            auto amount=s.air?uint64_t(std::clamp<int64_t>(int64_t(s.after)-125000LL*y,0,125000)):s.after;
            int cell=W::index(s.base)+8*y;
            if(old[cell]!=amount){r.water[cell]=amount;dirty.insert(k);}
        }
    }
    changed_regions.assign(dirty.begin(),dirty.end());
    for(auto &[k,r]:store.regions)r.settle_pending=false;
    if(!open_boundary){closed_basins=1;closed_basin_ml=quantity;}
    visited_cells=wide_cells;
    return SpanResult::settled;
}
}
