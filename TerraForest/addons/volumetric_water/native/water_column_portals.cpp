// SPDX-License-Identifier: 0BSD
#include "regional_water.hpp"
#include "water_spill_hierarchy.hpp"
#include "water_storage_groups.hpp"
#include "water_column_tiles.hpp"
#include "water_volume_query.hpp"
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/classes/worker_thread_pool.hpp>
#include <algorithm>
#include <numeric>

using namespace godot;
namespace terraforest {

// A vertical interval stores its exact clipped tiers and a prefix of their
// capacities. A side portal joins two intervals at their lowest common open
// face. Its graph size depends on floors, roofs and pockets in the footprint.
// A deeper open shaft adds storage without adding a node per half metre.
NativeWaterEquilibriumJob::SpanResult NativeWaterEquilibriumJob::settle_column_portals(){
    using W=NativeRegionalWater;
    auto &store=*frozen.ptr();
    const bool local_belt=wide_edit_bounds.empty();
    const auto began=Time::get_singleton()->get_ticks_usec();
    uint64_t phase_start=began;
    auto mark=[&](int index){auto now=Time::get_singleton()->get_ticks_usec();column_phases[index]=now-phase_start;phase_start=now;};
    auto defer=[&](const char *reason){column_fallback=reason;return SpanResult::fallback;};
    Vector3i lo(500,64,500),hi,source,pin;
    double upper=-1;
    std::unordered_set<uint64_t> pinned;
    for(const auto &[k,r]:store.regions){
        if(!r.valid||r.ocean_state)return defer("unsurveyed or sea");
        auto b=W::position(k);lo=lo.min(b);hi=hi.max(b);
        if(r.water.is_initial_zero())continue;
        const bool west=b.x>0&&!store.regions.count(W::key(b+Vector3i(-1,0,0)));
        const bool east=b.x<499&&!store.regions.count(W::key(b+Vector3i(1,0,0)));
        const bool north=b.z>0&&!store.regions.count(W::key(b+Vector3i(0,0,-1)));
        const bool south=b.z<499&&!store.regions.count(W::key(b+Vector3i(0,0,1)));
        for(int i=0;i<512;++i)if(r.water[i]){
            const auto p=b*8+Vector3i(i%8,(i/8)%8,i/64);
            auto boundary=[&](int x,int z){pin=p;pinned.insert(W::key({x,0,z}));};
            if(west&&i%8==0)boundary(b.x-1,b.z);
            if(east&&i%8==7)boundary(b.x+1,b.z);
            if(north&&i/64==0)boundary(b.x,b.z-1);
            if(south&&i/64==7)boundary(b.x,b.z+1);
            if((p.y+1)*.5<=upper)continue;
            double h=p.y*.5+W::profile(r,i).head(r.water[i])*.001;
            if(h>upper){upper=h;source=p;}
        }
    }
    if(upper<0||(!local_belt&&(hi.y-lo.y<2||(!pinned.empty()&&!private_rounds))))return defer("initial or shallow footprint");
    const auto extent=hi-lo+Vector3i(1,1,1);
    const size_t slots=size_t(extent.x)*extent.y*extent.z,area=size_t(extent.x)*extent.z*64;
    if(slots>32768||slots>4*store.regions.size()||area>hierarchy_cell_limit)return defer("sparse footprint");
    if(local_belt){
        pinned.clear();
        const int surface_layer=int(std::floor((upper-1e-5)*.25));
        for(int z=std::max(0,lo.z-1);z<=std::min(499,hi.z+1);++z)
            for(int x=std::max(0,lo.x-1);x<=std::min(499,hi.x+1);++x)
                if(!store.regions.count(W::key({x,surface_layer,z})))pinned.insert(W::key({x,0,z}));
    }
    std::vector<W::Region*> blocks(slots);
    auto block_id=[&](Vector3i b){b-=lo;return b.x+extent.x*(b.y+extent.y*b.z);};
    for(auto &[k,r]:store.regions)blocks[block_id(W::position(k))]=&r;
    auto locate=[&](Vector3i p)->W::Region*{
        Vector3i b(p.x>>3,p.y>>3,p.z>>3);
        if(b!=b.clamp(lo,hi))return nullptr;
        return blocks[block_id(b)];
    };
    struct Tier {int y,end,shape,room;uint64_t below,capacity;};
    struct Room {int first,end,column;uint64_t capacity=0,before=0,after=0;double fraction=0;};
    struct Column {int begin=0,end=0;double weight=1;};
    struct Stripe {
        std::vector<Tier> tiers;std::vector<Room> rooms;std::vector<WaterCellProfile> shapes;
        const char *failure=nullptr;
    };
    const int lanes=area>=4096?4:1;
    std::vector<Stripe> stripes(lanes);
    std::vector<Column> columns(area);
    const WaterCellProfile air;
    const int width=extent.x*8,top=std::min((hi.y+1)*8,int(std::ceil(upper*2.)));
    auto xyz=[&](int c,int y){return Vector3i(lo.x*8+c%width,y,lo.z*8+c/width);};
    // Contract a 4 m square of communicating half-metre columns before
    // generating intervals and portals. A roof or a second horizontal
    // interval remains a separate room at its real elevation. A varying
    // bed, structure or boundary blend keeps its original columns.
    std::vector<int> representative(area);
    std::iota(representative.begin(),representative.end(),0);
    std::vector<uint8_t> side(area,1);
    using Identity=std::array<uintptr_t,6>;
    std::map<Identity,bool> geometry_tiles;
    auto flat_tile=[&](const W::Region &r){
        if(r.brick_geometry!=WaterBrickGeometry::mixed)return true;
        Identity id{uintptr_t(r.floor.begin()),uintptr_t(r.ceiling.begin()),uintptr_t(r.density.begin()),
                    uintptr_t(r.contacts.get()),uintptr_t(r.structures.get()),uintptr_t(r.has_density)};
        auto [it,fresh]=geometry_tiles.emplace(id,false);
        if(!fresh)return it->second;
        for(int y=0;y<8;++y){
            WaterFlatTier first;
            for(int z=0;z<8;++z)for(int x=0;x<8;++x){
                int i=x+8*y+64*z;WaterFlatTier tier;
                if(r.floor[i]==r.ceiling[i])tier.closed=true;
                else if(!tier.read(W::profile(r,i)))return false;
                if(!x&&!z)first=tier;
                else if(!(tier==first))return false;
            }
        }
        return it->second=true;
    };
    size_t tile_count=0;
    if(!local_belt&&store.regions.size()>=128)for(int z=0;z<extent.z;++z)for(int x=0;x<extent.x;++x){
        bool uniform=true,present=false;
        for(int dz=-1;dz<=1&&uniform;++dz)for(int dx=-1;dx<=1;++dx){
            int px=x+lo.x+dx,pz=z+lo.z+dz;
            if(px>=0&&pz>=0&&pinned.count(W::key({px,0,pz}))){uniform=false;break;}
        }
        for(int y=lo.y;uniform&&y*8<top;++y){
            const W::Region *r=blocks[block_id({x+lo.x,y,z+lo.z})];
            if(r){present=true;uniform=flat_tile(*r);}
        }
        if(!uniform||!present)continue;
        const int first=x*8+width*z*8;
        side[first]=8;++tile_count;
        for(int dz=0;dz<8;++dz)for(int dx=0;dx<8;++dx)representative[first+dx+width*dz]=first;
    }
    auto prepare=[&](uint32_t lane_id){
        auto &lane=stripes[lane_id];
        auto &tiers=lane.tiers;auto &rooms=lane.rooms;auto &shapes=lane.shapes;
        const size_t budget=hierarchy_cell_limit/lanes;
        auto fail=[&](const char *message){lane.failure=message;};
        auto geometry=[&](int shape)->const WaterCellProfile&{return shape<0?air:shapes[shape];};
        for(int c=int(area*lane_id/lanes);c<int(area*(lane_id+1)/lanes);++c){
            if(representative[c]!=c)continue;
            if(cancelled.load())return fail("cancelled");
            auto &col=columns[c];col.begin=int(tiers.size());
            auto p=xyz(c,lo.y*8);
            const int x=p.x,z=p.z;
            double distance=3.5;
            if(!pinned.empty())for(int dz=-1;dz<=1;++dz)for(int dx=-1;dx<=1;++dx){
                int bx=(x>>3)+dx,bz=(z>>3)+dz;
                if(bx<0||bz<0||!pinned.count(W::key({bx,0,bz})))continue;
                double ex=std::max({0.,bx*4.-(x+.5)*.5,(x+.5)*.5-(bx+1)*4.});
                double ez=std::max({0.,bz*4.-(z+.5)*.5,(z+.5)*.5-(bz+1)*4.});
                distance=std::min(distance,std::hypot(ex,ez));
            }
            const double t=std::clamp((distance-.5)/3.,0.,1.);
            col.weight=t*t*(3-2*t);
            for(;p.y<top;){
                const auto *r=locate(p);
                const int stop=std::min(top,(p.y|7)+1);
                if(!r||r->brick_geometry==WaterBrickGeometry::solid){p.y=stop;continue;}
                for(;p.y<stop;){
                    const int y=p.y,i=W::index(p);int end=y+1,shape=-1;
                    uint64_t before=0,capacity=125000;
                    if(r->brick_geometry==WaterBrickGeometry::air)end=stop;
                    else{
                        const int column=WaterBrickIntervals::column(i),tier=y&7;
                        const int closed=WaterBrickIntervals::run(r->intervals.closed[column],tier);
                        if(closed){p.y=std::min(stop,y+closed);continue;}
                        const int clear=WaterBrickIntervals::run(r->intervals.air[column],tier);
                        if(clear)end=std::min(stop,y+clear);
                        else{
                            if(r->floor[i]==r->ceiling[i]){++p.y;continue;}
                            auto bed=W::profile(*r,i);
                            if(!bed.is_full_air()){
                                capacity=bed.capacity();
                                if(!capacity||bed.volume((upper-y*.5)*1000.)<=0){++p.y;continue;}
                                if(shapes.size()>=budget*2)return fail("shaped tier budget");
                                shape=int(shapes.size());shapes.push_back(bed);
                            }
                        }
                    }
                    if(!r->water.is_initial_zero())for(int n=y;n<end;++n){
                        const int start=i+8*(n-y);
                        for(int dz=0;dz<side[c];++dz)for(int dx=0;dx<side[c];++dx)before+=r->water[start+64*dz+dx];
                    }
                    capacity*=uint64_t(end-y)*side[c]*side[c];
                    p.y=end;
                    const bool contiguous=int(tiers.size())>col.begin&&tiers.back().end==y;
                    if(contiguous&&shape<0&&tiers.back().shape<0){
                        auto &tier=tiers.back();tier.end=end;tier.capacity+=capacity;
                        auto &room=rooms[tier.room];room.capacity+=capacity;room.before+=before;continue;
                    }
                    bool joins=contiguous&&WaterCellProfile::connected(geometry(tiers.back().shape),500.,geometry(shape),1e-5,5);
                    if(!joins){
                        if(rooms.size()>=budget)return fail("room budget");
                        rooms.push_back({int(tiers.size()),int(tiers.size()),c});
                    }
                    if(tiers.size()>=budget*3)return fail("tier budget");
                    auto &room=rooms.back();
                    tiers.push_back({y,end,shape,int(rooms.size()-1),room.capacity,capacity});
                    ++room.end;room.capacity+=capacity;room.before+=before;
                }
            }
            col.end=int(tiers.size());
        }
    };
    auto task=[](void *data,uint32_t i){(*static_cast<decltype(prepare)*>(data))(i);};
    auto *pool=WorkerThreadPool::get_singleton();
    const auto handle=lanes>1?pool->add_native_group_task(task,&prepare,lanes,lanes,true,"Water column intervals"):-1;
    if(handle>=0)pool->wait_for_group_task_completion(handle);
    else for(int lane=0;lane<lanes;++lane)prepare(lane);
    size_t total_rooms=0,total_tiers=0,total_profiles=0;
    for(const auto &stripe:stripes){
        if(stripe.failure)return defer(stripe.failure);
        total_rooms+=stripe.rooms.size();total_tiers+=stripe.tiers.size();total_profiles+=stripe.shapes.size();
    }
    // Leave space in the graph reservation for contiguous publication while
    // individual stripes retire. All later IDs keep canonical column order.
    const size_t merge_bytes=total_rooms*sizeof(Room)+total_tiers*sizeof(Tier)+total_profiles*sizeof(WaterCellProfile);
    if(lanes>1&&merge_bytes>hierarchy_cell_limit*128)return defer("interval merge budget");
    auto merged=std::move(stripes.front());
    auto &tiers=merged.tiers;auto &rooms=merged.rooms;auto &shapes=merged.shapes;
    tiers.reserve(total_tiers);rooms.reserve(total_rooms);shapes.reserve(total_profiles);
    for(int lane=1;lane<lanes;++lane){
        auto &stripe=stripes[lane];
        const int first_tier=int(tiers.size()),first_room=int(rooms.size()),first_shape=int(shapes.size());
        for(int c=int(area*lane/lanes);c<int(area*(lane+1)/lanes);++c){
            columns[c].begin+=first_tier;columns[c].end+=first_tier;
        }
        for(auto tier:stripe.tiers){
            tier.room+=first_room;if(tier.shape>=0)tier.shape+=first_shape;tiers.push_back(tier);
        }
        for(auto room:stripe.rooms){room.first+=first_tier;room.end+=first_tier;rooms.push_back(room);}
        shapes.insert(shapes.end(),stripe.shapes.begin(),stripe.shapes.end());stripe=Stripe{};
    }
    auto geometry=[&](int shape)->const WaterCellProfile&{return shape<0?air:shapes[shape];};
    for(int c=0;c<int(area);++c)if(representative[c]!=c)columns[c]=columns[representative[c]];
    mark(0);
    if(rooms.empty())return defer("empty footprint");
    auto find_room=[&](Vector3i p){
        int c=p.x-lo.x*8+width*(p.z-lo.z*8);
        for(int j=columns[c].begin;j<columns[c].end;++j)if(p.y>=tiers[j].y&&p.y<tiers[j].end)return tiers[j].room;
        return -1;
    };
    int source_room=find_room(source);
    if(source_room<0)return defer("no source interval");
    std::vector<int> parent(rooms.size());std::iota(parent.begin(),parent.end(),0);
    auto root=[&](int i){while(parent[i]!=i){parent[i]=parent[parent[i]];i=parent[i];}return i;};
    std::vector<WaterSpillEdge> edges;
    auto link=[&](int a,int b,double h){
        if(edges.size()>=hierarchy_cell_limit*6)return false;
        edges.push_back({a,b,std::min(upper,h+2e-9)});parent[root(a)]=root(b);return true;
    };
    auto depth=[&](int y){return std::clamp((upper-y*.5)*1000.,0.,500.);};
    for(int c=0;c<int(area);++c){
        if(cancelled.load())return defer("cancelled");
        auto &column=columns[c];
        for(int i=column.begin+1;representative[c]==c&&i<column.end;++i){
            auto &a=tiers[i-1],&b=tiers[i];
            if(a.room!=b.room&&a.end==b.y&&WaterCellProfile::connected(geometry(a.shape),depth(a.end-1),geometry(b.shape),depth(b.y),5))
                if(!link(a.room,b.room,b.y*.5))return defer("edge budget");
        }
        for(int axis:{0,2}){
            if(axis==0?c%width+1==width:c+width>=int(area))continue;
            const int next=c+(axis==0?1:width);
            if(representative[c]==representative[next])continue;
            if(side[representative[c]]>1&&side[representative[next]]>1&&((axis==0?c/width:c%width)&7))continue;
            const auto &neighbor=columns[next];
            int i=column.begin,j=neighbor.begin,linked_a=-1,linked_b=-1;
            while(i<column.end&&j<neighbor.end){
                const auto &a=tiers[i],&b=tiers[j];const int y=std::max(a.y,b.y);
                if(y<std::min(a.end,b.end)&&(a.room!=linked_a||b.room!=linked_b)){
                    const auto &first=geometry(a.shape),&second=geometry(b.shape);
                    double sill=0;bool connected=true;
                    if(a.shape>=0||b.shape>=0){
                        if(first.solid||second.solid){
                            connected=WaterCellProfile::connected(first,depth(y),second,depth(y),axis==0?1:3);
                            if(connected)sill=WaterCellProfile::clipped_spill_height(first,second,axis,1);
                        }else connected=WaterCellProfile::floor_passage(first,depth(y),second,depth(y),axis,1,sill);
                    }
                    if(connected){
                        if(!link(a.room,b.room,y*.5+sill*.001))return defer("edge budget");
                        linked_a=a.room;linked_b=b.room;
                    }
                }
                if(a.end<=b.end)++i;
                if(b.end<=a.end)++j;
            }
        }
    }
    mark(1);
    const int connected=root(source_room);
    std::vector<int> ids(rooms.size(),-1);
    std::vector<Room> body;
    size_t cells=0;uint64_t quantity=0;
    for(int i=0;i<int(rooms.size());++i){
        if(root(i)!=connected){
            if(rooms[i].before)return defer("separate wet components");
            continue;
        }
        ids[i]=int(body.size());body.push_back(rooms[i]);
        int span=side[rooms[i].column];
        cells+=size_t(tiers[rooms[i].end-1].end-tiers[rooms[i].first].y)*span*span;quantity+=rooms[i].before;
    }
    if(quantity!=store.total)return defer("unaccounted water");
    // Only a portal connected to this body may request an absent region.
    // A cave on the dry side of a wall never expands the edit footprint.
    const Vector3i steps[]={{0,-1,0},{1,0,0},{-1,0,0},{0,0,1},{0,0,-1},{0,1,0}};
    W::WetFrontier exits;
    bool open=false;
    for(const auto &room:body){
        if(cancelled.load())return defer("cancelled");
        for(int j=room.first;j<room.end;++j){
            const auto &tier=tiers[j];
            auto test=[&](Vector3i p,int d){
                auto q=p+steps[d];if(!W::in_domain(q)||depth(q.y)<=0||locate(q))return;
                if(!WaterCellProfile::connected(geometry(tier.shape),depth(p.y),air,depth(q.y),d))return;
                open=true;const auto key=W::region_key(q);const auto b=W::position(key);
                for(const auto &[min,max]:wide_edit_bounds)if(b==b.clamp(min,max)){
                    exits.entries.try_emplace(key,p,d);break;
                }
            };
            auto p=xyz(room.column,tier.y);
            if(!(p.y&7))test(p,0);
            for(;p.y<tier.end;p.y=(p.y|7)+1){
                const int reach=side[room.column]-1;
                if(((p.x+reach)&7)==7)test(p+Vector3i(reach,0,0),1);
                if(!(p.x&7))test(p,2);
                if(((p.z+reach)&7)==7)test(p+Vector3i(0,0,reach),3);
                if(!(p.z&7))test(p,4);
            }
            p.y=tier.end-1;if((p.y&7)==7)test(p,5);
        }
    }
    if(!exits.entries.empty()){
        exits.head=upper;wet_frontier=std::move(exits);
        for(const auto &[k,exit]:wet_frontier.entries)required.push_back(k);
        return SpanResult::dependencies;
    }
    edges.erase(std::remove_if(edges.begin(),edges.end(),[&](auto &e){
        if(ids[e.a]<0)return true;e.a=ids[e.a];e.b=ids[e.b];return false;
    }),edges.end());
    mark(2);
    std::vector<WaterVolumeQuery> queries;queries.reserve(shapes.size());
    for(const auto &shape:shapes)queries.emplace_back(shape);
    auto volume=[&](int id,double h){
        const auto &room=body[id];
        if(h<=tiers[room.first].y*.5)return 0.;
        if(h>=tiers[room.end-1].end*.5)return double(room.capacity);
        auto it=std::upper_bound(tiers.begin()+room.first,tiers.begin()+room.end,h,
            [](double elevation,const Tier &tier){return elevation<tier.y*.5;});
        const auto &tier=*std::prev(it);double mm=(h-tier.y*.5)*1000.;
        int span=side[room.column];
        double part=(tier.shape<0?mm*250.:queries[tier.shape].volume(mm))*span*span;
        return double(tier.below)+std::clamp(part,0.,double(tier.capacity));
    };
    if(!local_belt&&open&&!pinned.empty()){
        const int pin_room=find_room(pin);
        if(pin_room<0||ids[pin_room]<0)return defer("fixed shore outside body");
        double lower=0,ceiling=upper;
        for(int iteration=0;iteration<18;++iteration){
            double trial=(lower+ceiling)*.5,available=0;
            for(int i=0;i<int(body.size());++i)if(columns[body[i].column].weight==1.)available+=volume(i,trial);
            if(available>double(quantity+cells))ceiling=trial;else lower=trial;
        }
        std::vector<double> high(body.size());
        parent.resize(body.size());std::iota(parent.begin(),parent.end(),0);
        for(int i=0;i<int(body.size());++i)
            high[i]=std::ceil((upper+(ceiling-upper)*columns[body[i].column].weight)*2.)*.5+.00001;
        for(const auto &edge:edges)if(edge.level<=std::min(high[edge.a],high[edge.b]))parent[root(edge.a)]=root(edge.b);
        const int shore=root(ids[pin_room]);double reachable=0;
        for(int i=0;i<int(body.size());++i)if(root(i)==shore)reachable+=volume(i,high[i]);
        if(reachable+double(cells)>=double(quantity))return defer("connected pinned transition");
    }
    mark(3);
    int64_t exchange=0;const char *reason=nullptr;
    auto cap=[&](int id){return body[id].capacity;};
    auto integral=[&](int id,double h){
        const unsigned count=side[body[id].column]*side[body[id].column];
        return count*uint64_t(std::floor(volume(id,h)/count));
    };
    bool graded=false;
    if(local_belt){
        // Certify the common wet component before using a local water head.
        // A dry sill or undrained perched source goes to the general solver.
        auto at_level=[&](int i,double head,bool blend){
            if(!blend)return volume(i,head);
            const double weight=columns[body[i].column].weight;
            return weight?volume(i,upper+(head-upper)*weight):double(body[i].before);
        };
        auto fill_level=[&](bool blend,double &level){
            double lo_head=upper,hi_head=upper;
            for(const auto &room:body)lo_head=std::min(lo_head,tiers[room.first].y*.5);
            auto sum=[&](double h){double v=0;for(int i=0;i<int(body.size());++i)v+=at_level(i,h,blend);return v;};
            for(int n=0;n<32&&sum(lo_head)>double(quantity);++n)lo_head=upper-std::max(1.,2*(upper-lo_head));
            if(sum(lo_head)>double(quantity)||sum(hi_head)+1e-6<double(quantity))return false;
            level=water_storage_level(lo_head,hi_head,double(quantity),sum,48);
            if(cancelled.load())return false;
            uint64_t assigned=0;std::vector<int> remainder;
            for(int i=0;i<int(body.size());++i){
                const double value=at_level(i,level,blend);auto &room=body[i];
                room.after=uint64_t(std::floor(value));assigned+=room.after;room.fraction=value-room.after;
                if(room.fraction>0&&room.after<room.capacity)remainder.push_back(i);
            }
            if(assigned>quantity||quantity-assigned>remainder.size())return false;
            std::stable_sort(remainder.begin(),remainder.end(),[&](int a,int b){return body[a].fraction>body[b].fraction;});
            for(size_t n=0;n<quantity-assigned;++n)++body[remainder[n]].after;
            return true;
        };
        double level;
        if(!fill_level(false,level))return defer("local column capacity");
        parent.resize(body.size());std::iota(parent.begin(),parent.end(),0);
        for(const auto &edge:edges)if(edge.level<=level&&body[edge.a].after&&body[edge.b].after)
            parent[root(edge.a)]=root(edge.b);
        int wet=-1;size_t dry_sources=0;
        for(int i=0;i<int(body.size());++i){
            if(!body[i].after){
                if(body[i].before)++dry_sources;
            }else if(wet<0)wet=root(i);
            else if(wet!=root(i))return defer("separate local pools");
        }
        if(dry_sources){
            // A sloping shoreline can drain completely into the lower pool.
            // Work backwards from wet rooms only over outlets at which the
            // upstream room retains at most the ledger's one ml residue.
            std::vector<int> first(body.size(),-1),queue;
            struct Drain {int room,next;};
            std::vector<Drain> drains;
            auto drain=[&](int to,int from,double sill){
                if(body[from].after||volume(from,sill)>1.)return;
                drains.push_back({from,first[to]});first[to]=int(drains.size())-1;
            };
            for(const auto &e:edges){drain(e.a,e.b,e.level);drain(e.b,e.a,e.level);}
            std::vector<bool> reached(body.size());
            for(int i=0;i<int(body.size());++i)if(body[i].after){reached[i]=true;queue.push_back(i);}
            for(size_t n=0;n<queue.size()&&dry_sources;++n){
                for(int j=first[queue[n]];j>=0;j=drains[j].next){
                    int id=drains[j].room;if(reached[id])continue;
                    reached[id]=true;queue.push_back(id);if(body[id].before)--dry_sources;
                }
            }
            if(dry_sources)return defer("perched local source");
        }
        graded=open;
        if(graded&&!fill_level(true,level))return defer("local shore capacity");
    }else{
        auto curve=[&](int id){
            WaterColumnCurve key;
            const auto &room=body[id];const auto &first=tiers[room.first];
            // One flat floor followed by a vertical air interval. Keep the
            // rounded first-tier capacity, absolute ceiling and volume offset
            // in the key; a shelf, sloping bed or intervening roof opts out.
            const auto &bed=geometry(first.shape);
            if(bed.solid||bed.ceiling!=500)return key;
            const double bottom=bed.minimum();
            if(bed.maximum()!=bottom)return key;
            for(int j=room.first+1;j<room.end;++j)if(tiers[j].shape>=0)return key;
            key.bottom=first.y*.5+std::max(0.,bottom)*.001;
            const unsigned n=side[room.column]*side[room.column];
            key.terms={double(first.y),double(first.end),double(tiers[room.end-1].end),
                bottom,bed.mean(),bed.volume(0),double(first.capacity/n),double(room.capacity/n)};
            return key;
        };
        if(tile_count){
            auto width=[&](int id)->unsigned{int n=side[body[id].column];return n*n;};
            if(!settle_storage_groups(body,edges,upper,quantity,curve,volume,cancelled,column_storage_groups,width))
                return defer("tiled storage solve");
        }else if(!settle_storage_groups(body,edges,upper,quantity,curve,volume,cancelled,column_storage_groups)&&
                 !distribute_basin_water(body,edges,-1,upper,quantity,exchange,volume,cap,integral,cancelled,[](int){},reason,56))
            return defer(reason);
    }
    if(cancelled.load())return defer("cancelled");
    mark(4);
    std::unordered_set<uint64_t> dirty;
    for(const auto &room:body){
        if((!room.before&&!room.after)||(graded&&columns[room.column].weight==0))continue;
        const int span=side[room.column],count=span*span;
        for(int dz=0;dz<span;++dz)for(int dx=0;dx<span;++dx){
            uint64_t remaining=room.after/count+uint64_t(dz*span+dx<int(room.after%count));
            for(int j=room.first;j<room.end;++j){
                auto &tier=tiers[j];auto amount=std::min(remaining,tier.capacity/count);remaining-=amount;
                for(auto p=xyz(room.column+dx+dz*width,tier.y);p.y<tier.end;){
                    auto &r=*locate(p);const auto &old=static_cast<const W::Region&>(r).water;
                    const int start=p.y,stop=std::min(tier.end,(p.y|7)+1),i=W::index(p);
                    if(!amount&&old.is_initial_zero()){p.y=stop;continue;}
                    for(;p.y<stop;++p.y){
                        const int at=i+8*(p.y-start);const auto ml=std::min<uint64_t>(125000,amount);amount-=ml;
                        if(ml!=old[at]){r.water[at]=ml;dirty.insert(W::region_key(p));}
                    }
                }
            }
        }
    }
    changed_regions.assign(dirty.begin(),dirty.end());
    for(auto &[k,r]:store.regions)r.settle_pending=false;
    if(!open){closed_basins=1;closed_basin_ml=quantity;}
    visited_cells=wide_cells=cells;wide_basin_leaves=column_rooms=body.size();wide_spans=column_tiers=tiers.size();
    column_portals=edges.size();column_us=Time::get_singleton()->get_ticks_usec()-began;
    column_tiles=tile_count;
    mark(5);column_fallback=nullptr;return SpanResult::settled;
}
}
