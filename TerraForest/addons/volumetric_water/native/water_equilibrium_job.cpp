// SPDX-License-Identifier: 0BSD
#include "regional_water.hpp"
#include "water_volume_query.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/classes/time.hpp>
#include <algorithm>
#include <cmath>
#include <numeric>
#include <queue>
using namespace godot;
namespace terraforest {
std::atomic<uint64_t> NativeWaterEquilibriumJob::pending_bytes{0};
NativeWaterEquilibriumJob::~NativeWaterEquilibriumJob(){if(reserved_bytes)pending_bytes.fetch_sub(reserved_bytes);}
void NativeWaterEquilibriumJob::_bind_methods(){
    ClassDB::bind_method(D_METHOD("prepare"),&NativeWaterEquilibriumJob::prepare);
    ClassDB::bind_method(D_METHOD("cancel"),&NativeWaterEquilibriumJob::cancel);
    ClassDB::bind_method(D_METHOD("is_ready"),&NativeWaterEquilibriumJob::is_ready);
}
Ref<NativeWaterEquilibriumJob> NativeRegionalWater::begin_equilibrium(){
    if(fill.running||settling.empty())return {};
    for(const auto &[k,r]:regions)if(r.settle_pending&&!r.valid)return {};
    Ref<NativeWaterEquilibriumJob> job;job.instantiate();job->revision=map_revision;
    // Reserve a conservative envelope for the bounded cell graph, merge tree,
    // cached contacts and COW region payloads, including a cancelled predecessor.
    constexpr uint64_t charge=256*1024*1024,limit=2*charge;
    // Freeze pending connected region groups, not unrelated resident lakes.
    // Wet regions propagate the selection; one dry halo admits spill frontiers.
    // Further dry dependencies are requested by the existing transactional solver.
    std::unordered_set<Key> selected;
    const Vector3i adjacent[6]={{1,0,0},{-1,0,0},{0,1,0},{0,-1,0},{0,0,1},{0,0,-1}};
    auto wet=[](const Region &r){for(auto ml:r.water)if(ml)return true;return false;};
    auto retained_bytes=[&](const std::unordered_set<Key> &keys){
        uint64_t bytes=128*1024*1024;
        std::unordered_set<const void*> contacts;
        auto account=[&](const Region &r){
            bytes+=sizeof(Region)+Region::payload_bytes+r.vacancies.capacity()*sizeof(uint32_t);
            if(r.contacts&&contacts.insert(r.contacts.get()).second)bytes+=r.contacts->bytes;
            if(r.structures&&contacts.insert(r.structures.get()).second)bytes+=r.structures->bytes;
        };
        for(Key k:keys){
            const auto &r=regions.at(k);account(r);
            // Prior occupancy is used only for displacement through replaced solids.
            if(r.settle_pending){auto old=published_occupancy.find(k);if(old!=published_occupancy.end())account(old->second);}
        }
        return bytes;
    };
    for(const auto &[seed,region]:regions){
        if(!region.settle_pending||selected.count(seed))continue;
        auto candidate=selected;
        std::vector<Key> frontier{seed};std::unordered_set<Key> expanded;
        for(size_t at=0;at<frontier.size();++at){
            Key k=frontier[at];if(!expanded.insert(k).second)continue;
            candidate.insert(k);Vector3i p=position(k);
            for(auto offset:adjacent){
                auto q=p+offset;if(q.x<0||q.y<0||q.z<0||q.x>=500||q.y>=64||q.z>=500)continue;
                Key neighbor=key(q);auto found=regions.find(neighbor);if(found==regions.end())continue;
                candidate.insert(neighbor);
                if(!(surrounding_ocean&&region.ocean_state)&&found->second.valid&&wet(found->second)&&!expanded.count(neighbor))frontier.push_back(neighbor);
            }
        }
        if(retained_bytes(candidate)>charge){
            if(!selected.empty())break;
            job->reason="Connected water snapshot exceeds memory budget";job->ready.store(true);return job;
        }
        selected.swap(candidate);
    }
    uint64_t prior=NativeWaterEquilibriumJob::pending_bytes.load();
    do{if(prior>limit-charge){job->reason="Water equilibrium memory reservation unavailable";job->ready.store(true);return job;}}
    while(!NativeWaterEquilibriumJob::pending_bytes.compare_exchange_weak(prior,prior+charge));
    job->reserved_bytes=charge;
    job->frozen.instantiate();
    job->frozen->surrounding_ocean=surrounding_ocean;
    for(Key k:selected){
        const auto &r=regions.at(k);job->frozen->regions.emplace(k,r);
        for(auto ml:r.water)job->frozen->total+=ml;
        if(r.settle_pending){auto old=published_occupancy.find(k);if(old!=published_occupancy.end())job->frozen->published_occupancy.emplace(k,old->second);}
    }
    return job;
}
Dictionary NativeRegionalWater::finish_equilibrium(const Ref<NativeWaterEquilibriumJob> &job){
    Dictionary out;out["ok"]=false;
    if(job.is_null()||!job->is_ready()){out["reason"]="Equilibrium is not ready";return out;}
    if(job->consumed){out["reason"]="Equilibrium was already consumed";return out;}
    job->consumed=true;
    auto release=[](NativeWaterEquilibriumJob *p){
        p->frozen.unref();
        if(p->reserved_bytes){NativeWaterEquilibriumJob::pending_bytes.fetch_sub(p->reserved_bytes);p->reserved_bytes=0;}
    };
    std::unique_ptr<NativeWaterEquilibriumJob,decltype(release)> lifetime(job.ptr(),release);
    PackedInt64Array phases;for(auto t:job->phase_us)phases.push_back(t);out["phase_us"]=phases;
    out["worker_us"]=int64_t(job->elapsed_us);out["cells"]=int64_t(job->visited_cells);
    out["blocked_ml"]=int64_t(job->blocked_ml);out["reserved_bytes"]=int64_t(job->reserved_bytes);
    out["snapshot_regions"]=job->frozen.is_valid()?int64_t(job->frozen->regions.size()):0;
    out["ocean_exchange_ml"]=job->ocean_exchange_ml;
    if(job->revision!=map_revision||job->cancelled.load()){out["stale"]=true;return out;}
    if(!job->required.empty()){
        // Dry frontier regions are dependencies too: do not repeatedly solve
        // the same body while their terrain samples are still in flight.
        for(auto k:job->required){
            get(position(k)*8,true);auto found=regions.find(k);
            if(found==regions.end()){out["reason"]="Water receiving region capacity exhausted";return out;}
            found->second.settle_pending=true;
        }
        invalidate_snapshot();
        out["pending"]=true;out["required_regions"]=int64_t(job->required.size());return out;
    }
    if(!job->success){out["reason"]=job->reason;return out;}
    total=uint64_t(int64_t(total)+job->ocean_exchange_ml);
    // All quantities install together. Render/query/immersion remain on their
    // previous publication until the matching complete mesh batch is committed.
    cancel_mesh_batch();
    for(auto k:job->changed_regions){
        auto live=regions.find(k),prepared=job->frozen->regions.find(k);
        if(live==regions.end()||prepared==job->frozen->regions.end())continue;
        auto &r=live->second;const auto &source=prepared->second;
        const auto &before=static_cast<const Region &>(r).water;
        if(std::equal(before.begin(),before.end(),source.water.begin()))continue;
        r.water=source.water;
        if(job->frozen->surrounding_ocean&&r.ocean_state)r.vacancies=source.vacancies;
        else r.vacancies.clear();
        if(r.ocean_state==1)r.ocean_state=2;
        const auto base=position(k)*8;
        for(int corner=0;corner<8;++corner)changed(base+Vector3i((corner&1)*7,((corner>>1)&1)*7,((corner>>2)&1)*7));
    }
    settling.clear();settling_set.clear();
    for(auto &[k,r]:regions){
        const auto prepared=job->frozen->regions.find(k);
        if(prepared!=job->frozen->regions.end())r.settle_pending=prepared->second.settle_pending;
        r.settle_mask.fill(0);
        if(r.settle_pending)wake_settling(k);
    }
    invalidate_snapshot();
    out["ok"]=true;out["changed_regions"]=int64_t(job->changed_regions.size());return out;
}
void NativeWaterEquilibriumJob::prepare(){
    bool expected=false;if(!started.compare_exchange_strong(expected,true))return;
    const uint64_t started_us=Time::get_singleton()->get_ticks_usec();
    uint64_t phase_start=started_us;auto mark=[&](int i){auto now=Time::get_singleton()->get_ticks_usec();phase_us[i]+=now-phase_start;phase_start=now;};
    auto solve=[&]()->bool{
        using W=NativeRegionalWater;
        if(frozen.is_null())return false;
        auto &store=*frozen.ptr();
        constexpr size_t MAX_CELLS=131072;
        const Vector3i steps[6]={{0,-1,0},{1,0,0},{-1,0,0},{0,0,1},{0,0,-1},{0,1,0}};
        std::vector<Vector3i> displaced;
        for(const auto &[k,r]:store.regions)if(r.settle_pending&&r.valid){
            const auto base=W::position(k)*8;
            for(int i=0;i<512;++i)if(r.water[i]&&r.water[i]>W::profile(r,i).capacity())displaced.push_back(base+Vector3i(i%8,(i/8)%8,i/64));
        }
        // Replacement of solid geometry can push owned quantity out of a cell.
        // This is one conservative displacement pass, not an iterative flow
        // simulation. The body solve below establishes the resulting levels.
        for(auto p:displaced)store.settle_cell(p,0);
        if(!store.requests.empty()){required.assign(store.requests.begin(),store.requests.end());return false;}
        std::unordered_set<uint64_t> replaced;
        for(auto p:displaced)replaced.insert(W::key(p));
        uint64_t displacement_visits=0;
        auto displacement_shape=[&](Vector3i p){
            if(replaced.count(W::key(p))){
                auto old=store.published_occupancy.find(W::region_key(p));
                if(old!=store.published_occupancy.end()){auto shape=W::profile(old->second,W::index(p));if(shape.capacity())return shape;}
                return WaterCellProfile{};
            }
            return W::profile(store.regions.at(W::region_key(p)),W::index(p));
        };
        for(auto donor:displaced){
            auto &source=store.regions.at(W::region_key(donor));const int donor_index=W::index(donor);
            const uint64_t capacity=W::profile(source,donor_index).capacity();
            if(source.water[donor_index]<=capacity)continue;
            // Cross the replaced, previously wet volume to reach its boundary;
            // then search communicating air/water for receiving space. This
            // handles the interior of a deposited solid, not just its skin.
            using Entry=std::pair<int,uint64_t>;
            std::priority_queue<Entry,std::vector<Entry>,std::greater<Entry>> frontier;
            std::unordered_set<uint64_t> visited,unavailable;
            frontier.push({donor.y,W::key(donor)});visited.insert(W::key(donor));
            while(!frontier.empty()&&source.water[donor_index]>capacity){
                auto p=W::position(frontier.top().second);frontier.pop();
                if(++displacement_visits>4000000||cancelled.load()){reason="Displacement work budget exceeded";return false;}
                auto &receiver=store.regions.at(W::region_key(p));const int i=W::index(p);
                if(p!=donor){
                    uint64_t room=W::profile(receiver,i).capacity();room=room>receiver.water[i]?room-receiver.water[i]:0;
                    uint64_t amount=std::min(room,source.water[donor_index]-capacity);
                    if(amount){source.water[donor_index]-=amount;receiver.water[i]+=amount;store.changed(donor);store.changed(p);store.wake_settling(W::region_key(p),i);}
                }
                auto a=displacement_shape(p);
                for(int direction=0;direction<6;++direction){
                    auto q=p+steps[direction];if(!W::in_domain(q)||visited.count(W::key(q)))continue;
                    auto r=store.regions.find(W::region_key(q));const bool known=r!=store.regions.end()&&r->second.valid;
                    auto b=known?displacement_shape(q):WaterCellProfile{};
                    bool open=direction==0?b.ceiling==500&&a.open_bottom&&WaterCellProfile::vertical_overlap(b,500,a,500):
                        direction==5?a.ceiling==500&&b.open_bottom&&WaterCellProfile::vertical_overlap(a,500,b,500):
                        WaterCellProfile::face_overlap(a,500,b,500,direction<=2?0:2,direction==1||direction==3?1:0);
                    if(!open)continue;
                    if(!known){unavailable.insert(W::region_key(q));continue;}
                    if(!b.capacity())continue;
                    visited.insert(W::key(q));frontier.push({q.y,W::key(q)});
                }
            }
            if(source.water[donor_index]>capacity&&!unavailable.empty()){required.assign(unavailable.begin(),unavailable.end());return false;}
        }
        std::unordered_map<uint64_t,uint64_t> held;
        for(const auto &[k,r]:store.regions)if(r.settle_pending&&r.valid){
            const auto base=W::position(k)*8;
            for(int i=0;i<512;++i)if(r.water[i]){
                uint64_t capacity=W::profile(r,i).capacity();
                if(r.water[i]>capacity){auto p=base+Vector3i(i%8,(i/8)%8,i/64);held[W::key(p)]=r.water[i]-capacity;blocked_ml+=r.water[i]-capacity;}
            }
        }
        for(const auto &[k,amount]:held){auto p=W::position(k);store.regions.at(W::region_key(p)).water[W::index(p)]-=amount;}
        std::vector<Vector3i> seeds;

        for(const auto &[k,r]:store.regions)if(r.settle_pending){
            const auto base=W::position(k)*8;
            for(int i=0;i<512;++i)if(r.water[i]){
                auto p=base+Vector3i(i%8,(i/8)%8,i/64);const auto shape=W::profile(r,i);
                seeds.push_back(p);
            }
        }
        std::unordered_set<uint64_t> done,missing,dirty;
        for(auto k:store.meshes)if(store.regions.count(k))dirty.insert(k);
        struct Cell {Vector3i p;WaterCellProfile shape;uint64_t before=0,after=0;std::array<int,6> adjacent{{-1,-1,-1,-1,-1,-1}};double fraction=0;};
        std::vector<Cell> cells;cells.reserve(MAX_CELLS);
        std::unordered_map<uint64_t,int> ids;ids.reserve(MAX_CELLS);
        auto connected=[&](const Cell &a,const Cell &b,int direction,double level){
            double ah=std::clamp((level-a.p.y*.5)*1000.,0.,500.),bh=std::clamp((level-b.p.y*.5)*1000.,0.,500.);
            if(ah<=0||bh<=0)return false;
            // Interior air cells have a fully open common face.
            auto full_air=[](const WaterCellProfile &p){return !p.solid&&!p.contact&&p.ceiling==500&&p.open_bottom&&*std::max_element(p.floor.begin(),p.floor.end())<=0;};
            if(full_air(a.shape)&&full_air(b.shape))return true;
            if(direction==0)return b.shape.ceiling==500&&a.shape.open_bottom&&WaterCellProfile::vertical_overlap(b.shape,bh,a.shape,ah);
            if(direction==5)return a.shape.ceiling==500&&b.shape.open_bottom&&WaterCellProfile::vertical_overlap(a.shape,ah,b.shape,bh);
            return WaterCellProfile::face_overlap(a.shape,ah,b.shape,bh,direction<=2?0:2,direction==1||direction==3?1:0);
        };
        // The surrounding procedural sea has an open level-40 boundary, unlike
        // finite authored lakes. Freeze a local halo and flood only connected
        // 3D air. Pristine halo water supplies the boundary; sealed cavities have
        // no source. Record every ml crossing it, never call that finite conservation.
        if(store.surrounding_ocean){
            std::vector<Vector3i> frontier;
            for(const auto &[k,r]:store.regions)if(r.ocean_state==1&&r.valid&&!r.settle_pending){
                auto base=W::position(k)*8;
                for(int i=0;i<512;++i)if(r.water[i]){
                    auto p=base+Vector3i(i%8,(i/8)%8,i/64);
                    if(done.insert(W::key(p)).second)frontier.push_back(p);
                }
            }
            for(size_t at=0;at<frontier.size();++at){
                if(frontier.size()>MAX_CELLS||cancelled.load()){reason="Ocean boundary work budget exceeded";return false;}
                const auto p=frontier[at];const auto &r=store.regions.at(W::region_key(p));
                Cell a{p,W::profile(r,W::index(p)),r.water[W::index(p)]};
                for(int direction=0;direction<6;++direction){
                    auto q=p+steps[direction];if(!W::in_domain(q)||done.count(W::key(q)))continue;
                    auto found=store.regions.find(W::region_key(q));
                    if(found==store.regions.end()||!found->second.valid||!found->second.ocean_state)continue;
                    const auto &bregion=found->second;
                    Cell b{q,W::profile(bregion,W::index(q)),bregion.water[W::index(q)]};
                    if(!b.shape.capacity()||b.shape.volume((40-q.y*.5)*1000.)<=0||!connected(a,b,direction,40))continue;
                    done.insert(W::key(q));frontier.push_back(q);
                }
            }
            for(auto p:frontier){
                auto k=W::region_key(p);auto &r=store.regions.at(k);if(!r.settle_pending)continue;
                int i=W::index(p);auto shape=W::profile(r,i);
                uint64_t amount=std::min(shape.capacity(),uint64_t(std::max(0.0,std::floor(shape.volume((40-p.y*.5)*1000.)))));
                if(!r.vacancies.empty())amount-=std::min<uint64_t>(amount,r.vacancies[i]);
                if(amount!=r.water[i]){ocean_exchange_ml+=int64_t(amount)-int64_t(r.water[i]);r.water[i]=amount;dirty.insert(k);}
            }
            store.total=uint64_t(int64_t(store.total)+ocean_exchange_ml);
            visited_cells=frontier.size();
        }
        mark(0);
        for(auto seed:seeds){
            if(done.count(W::key(seed)))continue;
            cells.clear();ids.clear();
            auto add=[&](Vector3i p,const W::Region &r){
                const int i=W::index(p),id=int(cells.size());
                cells.push_back({p,W::profile(r,i),r.water[i]});ids.emplace(W::key(p),id);return id;
            };
            add(seed,store.regions.at(W::region_key(seed)));
            // Disconnected bodies have independent heads. A high inland lake
            // must not flood the coastal discovery frontier up to its elevation.
            double upper=seed.y*.5+cells.front().shape.head(cells.front().before)*.001;
            double scanned_head=upper;uint64_t scans=0;bool deferred_body=false;
            for(size_t cursor=0;cursor<cells.size();++cursor){
                if(cancelled.load()){reason="Cancelled";return false;}
                if(++scans>4000000){reason="Connected head discovery work budget exceeded";return false;}
                if(cells.size()+visited_cells>=MAX_CELLS){
                    if(visited_cells){deferred_body=true;break;}
                    reason="Connected water body exceeds bounded transaction";return false;
                }
                const auto p=cells[cursor].p;
                for(int direction=0;direction<6;++direction){
                    auto q=p+steps[direction];if(!W::in_domain(q))continue;
                    if(done.count(W::key(q)))continue;
                    auto r=store.regions.find(W::region_key(q));
                    if(q.y*.5>=upper){
                        if(r==store.regions.end()||!r->second.valid||!r->second.water[W::index(q)])continue;
                        Cell above{q,W::profile(r->second,W::index(q)),r->second.water[W::index(q)]};
                        double head=q.y*.5+above.shape.head(above.before)*.001;
                        if(!connected(cells[cursor],above,direction,head))continue;
                        upper=std::max(upper,head);
                    }
                    if(r==store.regions.end()||!r->second.valid){
                        Cell air;air.p=q;
                        if(connected(cells[cursor],air,direction,upper))missing.insert(W::region_key(q));
                        continue;
                    }
                    auto known=ids.find(W::key(q));
                    if(known!=ids.end()){cells[cursor].adjacent[direction]=known->second;continue;}
                    Cell candidate{q,W::profile(r->second,W::index(q)),r->second.water[W::index(q)]};
                    if(candidate.shape.capacity()==0||candidate.shape.volume((upper-q.y*.5)*1000.)<=0||!connected(cells[cursor],candidate,direction,upper))continue;
                    if(candidate.before>candidate.shape.capacity()){reason="Displaced quantity needs expanded receiving capacity";return false;}
                    const double existing=q.y*.5+candidate.shape.head(candidate.before)*.001;
                    if(candidate.before)upper=std::max(upper,existing);
                    cells[cursor].adjacent[direction]=add(q,r->second);
                }
                if(cursor+1==cells.size()&&upper>scanned_head){scanned_head=upper;cursor=size_t(-1);}
            }
            // Commit completed, disconnected bodies and resume the untouched
            // body in a later bounded job. Never partially level one body.
            if(deferred_body)break;
            if(!missing.empty()){required.assign(missing.begin(),missing.end());return false;}
            visited_cells+=cells.size();if(visited_cells>MAX_CELLS){reason="Water transaction work budget exceeded";return false;}
            mark(1);
            uint64_t quantity=0;double low=upper;
            std::vector<WaterVolumeQuery> queries;queries.reserve(cells.size());
            for(const auto &c:cells){quantity+=c.before;low=std::min(low,c.p.y*.5);queries.emplace_back(c.shape);}
            if(!quantity)continue;
            double high=upper;
            for(int iteration=0;iteration<32;++iteration){
                const double middle=(low+high)*.5;double volume=0;
                for(size_t i=0;i<cells.size();++i)volume+=std::min(double(queries[i].capacity()),queries[i].volume((middle-cells[i].p.y*.5)*1000.));
                if(volume<double(quantity))low=middle;else high=middle;
            }
            uint64_t assigned=0;
            for(size_t i=0;i<cells.size();++i){auto &c=cells[i];double volume=std::min(double(queries[i].capacity()),queries[i].volume((high-c.p.y*.5)*1000.));
                c.after=std::min(queries[i].capacity(),uint64_t(std::max(0.,std::floor(volume))));c.fraction=volume-c.after;assigned+=c.after;}
            if(assigned>quantity||quantity-assigned>cells.size()){reason="Equilibrium quantity cannot be represented";return false;}
            std::vector<int> remainder(cells.size());std::iota(remainder.begin(),remainder.end(),0);
            std::stable_sort(remainder.begin(),remainder.end(),[&](int a,int b){return cells[a].fraction>cells[b].fraction;});
            for(int i:remainder)if(assigned<quantity&&cells[i].after<queries[i].capacity()&&cells[i].fraction>0){++cells[i].after;++assigned;}
            if(assigned!=quantity){reason="Equilibrium integer remainder is unresolved";return false;}
            mark(2);
            // A uniform head is valid only while the occupied result remains
            // connected. A dry sill must not teleport retained water between pools.
            std::vector<uint8_t> seen(cells.size());std::vector<int> queue;size_t wet=0;
            for(size_t i=0;i<cells.size();++i)if(cells[i].after){++wet;if(queue.empty()){queue.push_back(i);seen[i]=1;}}
            for(size_t cursor=0;cursor<queue.size();++cursor){int i=queue[cursor];
                for(int d=0;d<6;++d){int j=cells[i].adjacent[d];if(j>=0&&!seen[j]&&cells[j].after&&connected(cells[i],cells[j],d,high)){seen[j]=1;queue.push_back(j);}}
            }
            std::unordered_map<uint64_t,double> spill_cache;
            auto spill=[&](int i,int j,int direction){
                uint64_t key=(uint64_t(std::min(i,j))<<32)|uint32_t(std::max(i,j));
                auto cached=spill_cache.find(key);if(cached!=spill_cache.end())return cached->second;
                const auto &a=cells[i],&b=cells[j];double height;
                if(!a.shape.solid&&!b.shape.solid){
                    height=direction==0||direction==5?std::max(a.p.y,b.p.y)*.5:
                        a.p.y*.5+WaterCellProfile::floor_spill_height(a.shape,b.shape,direction<=2?0:2,direction==1||direction==3?1:0)*.001;
                    height=std::min(upper,height+2e-9);
                }else{
                    height=direction==0||direction==5?std::max(a.p.y,b.p.y)*.5:
                        a.p.y*.5+WaterCellProfile::clipped_spill_height(a.shape,b.shape,direction<=2?0:2,direction==1||direction==3?1:0)*.001;
                    height=std::min(upper,height+2e-9);
                }
                spill_cache.emplace(key,height);return height;
            };
            bool needs_hierarchy=queue.size()!=wet;
            if(!needs_hierarchy){
                // A uniform result can erase an entire perched pocket and still
                // look connected. Dry source cells are safe only if they have
                // a drainage path with zero retained capacity below each sill.
                size_t dry_sources=0;
                for(size_t i=0;i<cells.size();++i)if(cells[i].before&&!seen[i])++dry_sources;
                for(size_t cursor=0;dry_sources&&cursor<queue.size();++cursor){
                    if(cancelled.load()){reason="Cancelled";return false;}
                    int i=queue[cursor];
                    for(int d=0;d<6;++d){
                        int j=cells[i].adjacent[d];if(j<0||seen[j]||!connected(cells[i],cells[j],d,upper))continue;
                        double b=spill(i,j,d);
                        if(queries[j].volume((b-cells[j].p.y*.5)*1000.)>1.0)continue;
                        seen[j]=1;queue.push_back(j);if(cells[j].before)--dry_sources;
                    }
                }
                for(size_t i=0;i<cells.size();++i)if(cells[i].before&&!seen[i]){needs_hierarchy=true;break;}
            }
            mark(3);
            if(needs_hierarchy){
                // The uniform result crosses a dry sill. Build a bounded merge
                // hierarchy of communicating basins, retaining each child's
                // water below its spill elevation before passing excess up.
                struct Edge {int a,b;double level;};
                struct Basin {int left=-1,right=-1,parent=-1,begin=0,end=0;double level=0;uint64_t capacity=0,quantity=0,excess=0,extra=0;};
                std::vector<Edge> edges;edges.reserve(cells.size()*3);
                for(size_t i=0;i<cells.size();++i)for(int d=0;d<6;++d){
                    int j=cells[i].adjacent[d];if(j<=int(i)||!connected(cells[i],cells[j],d,upper))continue;
                    edges.push_back({int(i),j,spill(int(i),j,d)});
                }
                mark(5);
                std::stable_sort(edges.begin(),edges.end(),[](const Edge &a,const Edge &b){return a.level<b.level;});
                std::vector<Basin> tree(cells.size());tree.reserve(cells.size()*2);
                std::vector<int> roots(cells.size());std::iota(roots.begin(),roots.end(),0);
                auto root=[&](int i){int r=i;while(roots[r]!=r)r=roots[r];while(roots[i]!=i){int next=roots[i];roots[i]=r;i=next;}return r;};
                for(const auto &edge:edges){
                    int a=root(edge.a),b=root(edge.b);if(a==b)continue;
                    int id=int(tree.size());tree.push_back({a,b,-1,0,0,edge.level});
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
                    if(tree[id].left<0){order.push_back(id);tree[id].end=int(order.size());}
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
                    if(node.left<0)active[id].push_back(int(id));
                    else{
                        saturated[id]=saturated[node.left]+saturated[node.right];
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
                        uint64_t volume=std::min(queries[i].capacity(),uint64_t(std::max(0.,std::floor(queries[i].volume((top-cells[i].p.y*.5)*1000.)))));
                        if(volume==queries[i].capacity())saturated[id]+=volume;
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
                    if(node.left<0)incoming=cells[id].before;
                    else{node.quantity=tree[node.left].quantity+tree[node.right].quantity;incoming=tree[node.left].excess+tree[node.right].excess;}
                    if(node.quantity>node.capacity){reason="Inconsistent basin capacity";return false;}
                    uint64_t retained=std::min(incoming,node.capacity-node.quantity);node.excess=incoming-retained;
                    node.quantity+=retained;if(node.left>=0)node.extra=retained;
                }
                if(tree[trunk].excess||tree[trunk].quantity!=quantity){reason="Basin exceeds available receiving space";return false;}
                mark(7);
                stack={trunk};
                while(!stack.empty()){
                    int id=stack.back();stack.pop_back();auto &node=tree[id];
                    if(node.left<0){cells[id].after=node.quantity;continue;}
                    auto &left=tree[node.left];auto &right=tree[node.right];
                    if(node.quantity<left.capacity+right.capacity){
                        uint64_t a=std::min(node.extra,left.capacity-left.quantity);
                        uint64_t b=node.extra-a;
                        if(b>right.capacity-right.quantity){reason="Basin overflow routing exceeds capacity";return false;}
                        left.quantity+=a;left.extra+=a;right.quantity+=b;right.extra+=b;
                        stack.push_back(node.right);stack.push_back(node.left);continue;
                    }
                    double a=node.level,b=node.parent<0?upper:tree[node.parent].level;
                    for(int iteration=0;iteration<32;++iteration){double m=(a+b)*.5,volume=0;
                        for(int at=node.begin;at<node.end;++at){int i=order[at];volume+=std::min(double(queries[i].capacity()),queries[i].volume((m-cells[i].p.y*.5)*1000.));}
                        if(volume<double(node.quantity))a=m;else b=m;
                    }
                    uint64_t filled=0;std::vector<int> fractions;
                    for(int at=node.begin;at<node.end;++at){int i=order[at];auto &c=cells[i];double v=std::min(double(queries[i].capacity()),queries[i].volume((b-c.p.y*.5)*1000.));
                        c.after=uint64_t(std::max(0.,std::floor(v)));c.fraction=v-c.after;filled+=c.after;fractions.push_back(i);}
                    // Node capacity is the sum of integer leaf capacities. At a
                    // sill, remove rounding surplus without changing the total.
                    std::stable_sort(fractions.begin(),fractions.end(),[&](int a,int b){return cells[a].fraction>cells[b].fraction;});
                    if(filled>node.quantity){for(auto at=fractions.rbegin();at!=fractions.rend()&&filled>node.quantity;++at)if(cells[*at].after){--cells[*at].after;--filled;}}
                    else for(int i:fractions)if(filled<node.quantity&&cells[i].after<queries[i].capacity()){++cells[i].after;++filled;}
                    if(filled!=node.quantity){reason="Basin remainder exceeds bounded rounding";return false;}
                }
            }
            mark(4);
            for(const auto &c:cells){
                done.insert(W::key(c.p));if(c.before==c.after)continue;
                auto k=W::region_key(c.p);store.regions.at(k).water[W::index(c.p)]=c.after;dirty.insert(k);
            }
        }
        for(auto &[k,r]:store.regions)if(r.settle_pending){
            r.settle_pending=false;const auto base=W::position(k)*8;
            for(int i=0;i<512;++i)if(r.water[i]&&!done.count(W::key(base+Vector3i(i%8,(i/8)%8,i/64)))){r.settle_pending=true;break;}
        }
        for(const auto &[k,amount]:held){auto p=W::position(k);store.regions.at(W::region_key(p)).water[W::index(p)]+=amount;}
        uint64_t conserved=0;for(const auto &[k,r]:store.regions)for(auto amount:r.water)conserved+=amount;
        if(conserved!=store.total){reason="Water transaction conservation check failed";return false;}
        changed_regions.assign(dirty.begin(),dirty.end());return true;
    };
    success=solve();elapsed_us=Time::get_singleton()->get_ticks_usec()-started_us;
    ready.store(true,std::memory_order_release);
}
}
