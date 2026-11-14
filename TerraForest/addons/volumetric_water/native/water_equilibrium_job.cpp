// SPDX-License-Identifier: 0BSD
#include "regional_water.hpp"
#include "water_volume_query.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/classes/time.hpp>
#include <algorithm>
#include <cmath>
#include <numeric>
#include <queue>
#include <bitset>
using namespace godot;
namespace terraforest {
std::atomic<uint64_t> NativeWaterEquilibriumJob::pending_bytes{0};
NativeWaterEquilibriumJob::~NativeWaterEquilibriumJob(){if(reserved_bytes)pending_bytes.fetch_sub(reserved_bytes);}
void NativeWaterEquilibriumJob::_bind_methods(){
    ClassDB::bind_method(D_METHOD("prepare"),&NativeWaterEquilibriumJob::prepare);
    ClassDB::bind_method(D_METHOD("cancel"),&NativeWaterEquilibriumJob::cancel);
    ClassDB::bind_method(D_METHOD("is_ready"),&NativeWaterEquilibriumJob::is_ready);
}
// Main-thread selection is resumable as well as the COW copy. No iterators into
// the live store survive a slice; revision changes discard this entire state.
struct EquilibriumCaptureState {
    using Key=uint64_t;
    std::unordered_set<Key> selected,candidate,expanded_pending,expanded,queued;
    std::unordered_map<Key,bool> wet;
    std::unordered_set<const void*> contacts;
    std::vector<Key> seeds,frontier,account_keys;
    size_t seed_at=0,frontier_at=0,account_at=0;
    uint64_t selected_bytes=128*1024*1024,bytes=128*1024*1024;
    bool ocean=false,coastal=false,selected_coastal=false;
    int phase=2; // Account initial dependencies, then expand complete groups.
};
Ref<NativeWaterEquilibriumJob> NativeRegionalWater::continue_equilibrium_capture(uint64_t deadline){
    auto job=equilibrium_capture;
    constexpr uint64_t charge=256*1024*1024;
    auto expired=[&](){return deadline&&Time::get_singleton()->get_ticks_usec()>=deadline;};
    auto fail=[&](const char *reason){job->reason=reason;job->ready.store(true);job->capture_selection.reset();equilibrium_capture.unref();return job;};
    const Vector3i adjacent[6]={{1,0,0},{-1,0,0},{0,1,0},{0,-1,0},{0,0,1},{0,0,-1}};
    while(job->capture_selection){
        auto &s=*job->capture_selection;
        if(s.phase==0){
            while(s.seed_at<s.seeds.size()&&s.expanded_pending.count(s.seeds[s.seed_at]))++s.seed_at;
            if(s.seed_at==s.seeds.size()){
                const uint64_t fixed=s.selected_bytes-128*1024*1024+s.selected.size()*512*sizeof(Vector3i)+16*1024*1024;
                if(fixed>=charge)return fail("Water graph has no reserved capacity");
                job->hierarchy_cell_limit=(charge-fixed)/1024;
                job->cell_limit=(charge-fixed)/(s.selected_coastal?1024:256);
                job->capture_keys.assign(s.selected.begin(),s.selected.end());
                job->frozen.instantiate();job->frozen->surrounding_ocean=surrounding_ocean;
                job->capture_selection.reset();
                if(expired())return {};
                break;
            }
            Key seed=s.seeds[s.seed_at++];s.candidate=s.selected;
            s.frontier={seed};s.frontier_at=0;s.expanded.clear();s.queued.clear();s.queued.insert(seed);
            s.ocean=surrounding_ocean&&regions.at(seed).ocean_state;s.phase=1;
        }else if(s.phase==1){
            if(s.frontier_at==s.frontier.size()){
                s.account_keys.assign(s.candidate.begin(),s.candidate.end());s.account_at=0;
                s.contacts.clear();s.bytes=128*1024*1024;s.coastal=false;s.phase=2;
            }else{
                Key k=s.frontier[s.frontier_at++];s.expanded.insert(k);s.candidate.insert(k);Vector3i p=position(k);
                for(auto offset:adjacent){
                    auto q=p+offset;if(q.x<0||q.y<0||q.z<0||q.x>=500||q.y>=64||q.z>=500)continue;
                    Key neighbor=key(q);auto found=regions.find(neighbor);if(found==regions.end())continue;
                    s.candidate.insert(neighbor);
                    if(!job->local_response&&!s.ocean&&!s.queued.count(neighbor)&&found->second.valid){
                        auto known=s.wet.find(neighbor);
                        bool wet=known!=s.wet.end()?known->second:std::any_of(found->second.water.begin(),found->second.water.end(),[](uint64_t ml){return ml!=0;});
                        if(known==s.wet.end())s.wet.emplace(neighbor,wet);
                        if(wet){s.queued.insert(neighbor);s.frontier.push_back(neighbor);}
                    }
                }
            }
        }else{
            if(s.account_at==s.account_keys.size()){
                if(s.bytes>charge){
                    if(s.selected.empty())return fail("Connected water snapshot exceeds memory budget");
                    s.seed_at=s.seeds.size(); // Defer the next entire group, never a partial body.
                }else{
                    s.selected.swap(s.candidate);s.selected_bytes=s.bytes;s.selected_coastal=s.coastal;
                    s.expanded_pending.insert(s.expanded.begin(),s.expanded.end());
                }
                s.phase=0;
            }else{
                auto account=[&](const Region &r){
                    s.bytes+=sizeof(Region)+Region::payload_bytes+r.vacancies.capacity()*sizeof(uint32_t);
                    if(r.contacts&&s.contacts.insert(r.contacts.get()).second)s.bytes+=r.contacts->bytes;
                    if(r.structures&&s.contacts.insert(r.structures.get()).second)s.bytes+=r.structures->bytes;
                };
                Key k=s.account_keys[s.account_at++];const auto &r=regions.at(k);account(r);s.coastal|=r.ocean_state!=0;
                if(r.settle_pending){auto old=published_occupancy.find(k);if(old!=published_occupancy.end())account(old->second);}
            }
        }
        if(expired())return {};
    }
    while(job->capture_cursor<job->capture_keys.size()){
        Key k=job->capture_keys[job->capture_cursor++];const auto &r=regions.at(k);
        auto inserted=job->frozen->regions.emplace(k,r);
        if(job->local_response&&r.ocean_state!=1)inserted.first->second.settle_pending=true;
        for(auto ml:r.water)job->frozen->total+=ml;
        if(r.settle_pending){auto old=published_occupancy.find(k);if(old!=published_occupancy.end())job->frozen->published_occupancy.emplace(k,old->second);}
        if(expired()&&job->capture_cursor<job->capture_keys.size())return {};
    }
    job->capture_keys.clear();equilibrium_capture.unref();return job;
}
Ref<NativeWaterEquilibriumJob> NativeRegionalWater::begin_equilibrium(int64_t budget_usec,bool local_response){
    const uint64_t deadline=budget_usec>0?Time::get_singleton()->get_ticks_usec()+uint64_t(budget_usec):0;
    if(equilibrium_capture.is_valid()&&(equilibrium_capture->revision!=map_revision||equilibrium_capture->local_response!=local_response||fill.running||settling.empty()))equilibrium_capture.unref();
    if(fill.running||settling.empty())return {};
    if(equilibrium_capture.is_valid())return continue_equilibrium_capture(deadline);
    // Restore sea boundaries for persisted edits outside player residency too.
    if(surrounding_ocean&&!local_response){
        std::vector<Key> pending_ocean;
        for(const auto &[k,r]:regions)if(r.settle_pending&&r.ocean_state&&r.has_density)pending_ocean.push_back(k);
        for(Key k:pending_ocean)if(!prepare_ocean_edit(AABB(Vector3(position(k))*4,Vector3(4,4,4))))return {};
    }
    for(const auto &[k,r]:regions)if(r.settle_pending&&!r.valid&&(!local_response||local_edit_regions.empty()||local_edit_regions.count(k)))return {};
    if(!local_response)for(Key k:equilibrium_dependencies){
        auto found=regions.find(k);
        if(found==regions.end()||!found->second.valid){get(position(k)*8,true);return {};}
    }
    Ref<NativeWaterEquilibriumJob> job;job.instantiate();job->revision=map_revision;job->local_response=local_response;
    // Selection, graph and COW payloads share the unchanged bounded reservation.
    constexpr uint64_t charge=256*1024*1024,limit=2*charge;
    uint64_t prior=NativeWaterEquilibriumJob::pending_bytes.load();
    do{if(prior>limit-charge){job->reason="Water equilibrium memory reservation unavailable";job->ready.store(true);return job;}}
    while(!NativeWaterEquilibriumJob::pending_bytes.compare_exchange_weak(prior,prior+charge));
    job->reserved_bytes=charge;job->capture_selection=std::make_shared<EquilibriumCaptureState>();
    auto &s=*job->capture_selection;
    if(!local_response)s.candidate.insert(equilibrium_dependencies.begin(),equilibrium_dependencies.end());
    s.account_keys.assign(s.candidate.begin(),s.candidate.end());
    for(const auto &[k,r]:regions){
        bool selected=r.settle_pending&&(!local_response||local_edit_regions.empty()||local_edit_regions.count(k));
        if(local_response&&!local_occupancy_regions.empty())selected=local_occupancy_regions.count(k)&&r.valid;
        if(selected)s.seeds.push_back(k);
    }
    if(local_response){
        // One bounded union/accounting pass, rather than recopying and charging
        // the growing local set separately for every edited region.
        const Vector3i adjacent[6]={{1,0,0},{-1,0,0},{0,1,0},{0,-1,0},{0,0,1},{0,0,-1}};
        for(Key k:s.seeds){s.candidate.insert(k);const auto p=position(k);
            for(auto d:adjacent){auto q=p+d;if(q.x<0||q.y<0||q.z<0||q.x>=500||q.y>=64||q.z>=500)continue;
                auto found=regions.find(key(q));if(found!=regions.end()&&found->second.valid)s.candidate.insert(found->first);}
        }
        s.seeds.clear();s.account_keys.assign(s.candidate.begin(),s.candidate.end());
    }
    equilibrium_capture=job;
    if(deadline&&Time::get_singleton()->get_ticks_usec()>=deadline)return {};
    return continue_equilibrium_capture(deadline);
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
    out["local_response"]=job->local_response;
    out["blocked_ml"]=int64_t(job->blocked_ml);out["reserved_bytes"]=int64_t(job->reserved_bytes);
    out["graph_cell_limit"]=int64_t(job->cell_limit);
    out["hierarchy_cell_limit"]=int64_t(job->hierarchy_cell_limit);
    out["snapshot_regions"]=job->frozen.is_valid()?int64_t(job->frozen->regions.size()):0;
    out["ocean_exchange_ml"]=job->ocean_exchange_ml;
    if(job->revision!=map_revision||job->cancelled.load()){out["stale"]=true;return out;}
    if(!job->required.empty()){
        // Dry frontier regions are dependencies too: do not repeatedly solve
        // the same body while their terrain samples are still in flight.
        for(auto k:job->required){
            equilibrium_dependencies.insert(k);
            const auto coordinate=position(k);
            // Missing procedural sea is a streamed reservoir dependency, not
            // an empty finite-water region. Preserve its normal admission kind.
            if(surrounding_ocean&&!regions.count(k)&&!deferred_regions.count(k)&&
               coordinate.y>=7&&coordinate.y<=10&&std::min({coordinate.x,coordinate.z,499-coordinate.x,499-coordinate.z})<35){
                if(!restore_ocean_cache(k)&&regions.size()<MAX_REGIONS){Region r;r.ocean_state=1;regions.emplace(k,std::move(r));request(k);}
            }
            get(coordinate*8,true);auto found=regions.find(k);
            if(found==regions.end()){out["reason"]="Water receiving region capacity exhausted";return out;}
            if(found->second.ocean_state!=1)found->second.settle_pending=true;
        }
        invalidate_snapshot();
        out["detail"]=job->reason;out["pending"]=true;out["required_regions"]=int64_t(job->required.size());return out;
    }
    if(!job->success){out["reason"]=job->reason;return out;}
    // Completed load/background transactions must retire their edit seeds too.
    // Otherwise the next player edit inherits every earlier pending region.
    for(const auto &[k,r]:job->frozen->regions){local_edit_regions.erase(k);local_occupancy_regions.erase(k);}
    equilibrium_dependencies.clear();
    total=uint64_t(int64_t(total)+job->ocean_exchange_ml);
    // All quantities install together. Render/query/immersion remain on their
    // previous publication until the matching complete mesh batch is committed.
    if(!job->local_response&&publication_enabled)relaxation_dirty_before=mesh_set;
    cancel_mesh_batch();background_change=!job->local_response;
    for(auto k:job->changed_regions){
        auto live=regions.find(k),prepared=job->frozen->regions.find(k);
        if(live==regions.end()||prepared==job->frozen->regions.end())continue;
        auto &r=live->second;const auto &source=prepared->second;
        const auto &before=static_cast<const Region &>(r).water;
        Vector3i lo(7,7,7),hi;bool any=false;
        for(int i=0;i<512;++i)if(before[i]!=source.water[i]){auto q=Vector3i(i%8,(i/8)%8,i/64);lo=lo.min(q);hi=hi.max(q);any=true;}
        if(!any)continue;
        if(!job->local_response&&publication_enabled)relaxation_before.emplace(k,RelaxationBefore{r.water,r.vacancies,r.ocean_state});
        r.water=source.water;
        if(job->frozen->surrounding_ocean&&r.ocean_state)r.vacancies=source.vacancies;
        else r.vacancies.clear();
        if(r.ocean_state==1)r.ocean_state=2;
        const auto base=position(k)*8;
        for(int corner=0;corner<8;++corner)changed(base+Vector3i((corner&1)?hi.x:lo.x,(corner&2)?hi.y:lo.y,(corner&4)?hi.z:lo.z));
    }
    background_change=false;
    settling.clear();settling_set.clear();
    for(auto &[k,r]:regions){
        const auto prepared=job->frozen->regions.find(k);
        // A local response is a conservative transient, not a claim that the
        // connected body has reached equilibrium. Persist its pending work.
        if(!job->local_response&&prepared!=job->frozen->regions.end())r.settle_pending=prepared->second.settle_pending;
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
        const size_t MAX_CELLS=cell_limit;
        const Vector3i steps[6]={{0,-1,0},{1,0,0},{-1,0,0},{0,0,1},{0,0,-1},{0,1,0}};
        std::vector<Vector3i> displaced;
        for(const auto &[k,r]:store.regions)if(r.settle_pending&&r.valid){
            const auto base=W::position(k)*8;
            for(int i=0;i<512;++i)if(r.water[i]&&r.water[i]>W::profile(r,i).capacity())displaced.push_back(base+Vector3i(i%8,(i/8)%8,i/64));
        }
        // Replacement of solid geometry can push owned quantity out of a cell.
        // This is one conservative displacement pass, not an iterative flow
        // simulation. The body solve below establishes the resulting levels.
        for(auto p:displaced){
            // An open sea can absorb displaced volume. Do not first stack that
            // overflow above sea level as if the streaming boundary were sealed.
            if(!local_response&&!(store.surrounding_ocean&&store.regions.at(W::region_key(p)).ocean_state))store.settle_cell(p,0);
        }
        if(!local_response&&!store.requests.empty()){required.assign(store.requests.begin(),store.requests.end());return false;}
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
                    if(store.surrounding_ocean&&source.ocean_state&&receiver.ocean_state==1&&receiver.water[i]&&p.y*.5<40){
                        // This receiver was reached through the same clipped
                        // displacement connections as finite recipients. It is
                        // certified pristine sea, so overflow leaves the local
                        // transaction instead of creating an artificial mound.
                        const auto amount=source.water[donor_index]-capacity;
                        source.water[donor_index]-=amount;ocean_exchange_ml-=int64_t(amount);
                        store.changed(donor);break;
                    }
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
            if(!local_response&&source.water[donor_index]>capacity&&!unavailable.empty()){required.assign(unavailable.begin(),unavailable.end());return false;}
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
        struct RegionMarks {
            std::unordered_map<uint64_t,std::bitset<512>> blocks;
            bool count(uint64_t key)const{auto p=W::position(key);auto found=blocks.find(W::region_key(p));return found!=blocks.end()&&found->second[W::index(p)];}
            void insert(uint64_t key){auto p=W::position(key);blocks[W::region_key(p)].set(W::index(p));}
        } done;
        std::unordered_set<uint64_t> missing,dirty;
        for(auto k:store.meshes)if(store.regions.count(k))dirty.insert(k);
        struct Cell {Vector3i p;WaterCellProfile shape;uint64_t before=0,after=0;std::array<int,6> adjacent{{-1,-1,-1,-1,-1,-1}};double fraction=0;};
        static_assert(sizeof(Cell)<=128,"Update the graph memory charge when cell layout grows");
        const size_t resident_cells=std::min(MAX_CELLS,store.regions.size()*512);
        std::vector<Cell> cells;cells.reserve(resident_cells);
        // One lookup block per region instead of an allocated hash node per
        // visited cell. The immutable snapshot already bounds these blocks.
        struct CellIndex {const W::Region *region=nullptr;std::array<int,512> values;};
        std::unordered_map<uint64_t,CellIndex> ids;
        for(const auto &[key,r]:store.regions){auto &block=ids[key];block.region=&r;block.values.fill(-1);}
        auto full_air=[](const WaterCellProfile &p){return !p.solid&&!p.contact&&p.ceiling==500&&p.open_bottom&&*std::max_element(p.floor.begin(),p.floor.end())<=0;};
        auto volume_at=[&](const Cell &c,double level){return full_air(c.shape)?std::clamp((level-c.p.y*.5)*250000.,0.,125000.):c.shape.volume((level-c.p.y*.5)*1000.);};
        auto connected=[&](const Cell &a,const Cell &b,int direction,double level){
            double ah=std::clamp((level-a.p.y*.5)*1000.,0.,500.),bh=std::clamp((level-b.p.y*.5)*1000.,0.,500.);
            if(ah<=0||bh<=0)return false;
            // Interior air cells have a fully open common face.
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
            // Pristine sea is a boundary condition, not part of the solved
            // cell graph. Seed only its open interfaces into edited regions.
            // Flooding every unchanged sea cell made a local edit scale with
            // the whole streaming footprint and exhausted MAX_CELLS on load.
            for(const auto &[k,r]:store.regions)if(r.ocean_state==1&&r.valid&&!r.settle_pending){
                const auto base=W::position(k)*8;
                for(int direction=0;direction<6;++direction){
                    auto neighbor=store.regions.find(W::key(W::position(k)+steps[direction]));
                    if(neighbor==store.regions.end()||!neighbor->second.valid||neighbor->second.ocean_state!=2)continue;
                    const int axis=direction==0||direction==5?1:(direction<=2?0:2);
                    const int face=direction==1||direction==3||direction==5?7:0;
                    for(int u=0;u<8;++u)for(int v=0;v<8;++v){
                        auto p=base;p[axis]+=face;p[(axis+1)%3]+=u;p[(axis+2)%3]+=v;
                        const int i=W::index(p);if(!r.water[i])continue;
                        auto q=p+steps[direction];if(done.count(W::key(q)))continue;
                        const auto &receiver=neighbor->second;
                        Cell a{p,W::profile(r,i),r.water[i]},b{q,W::profile(receiver,W::index(q)),receiver.water[W::index(q)]};
                        if(b.shape.volume((40-q.y*.5)*1000.)<=0||!connected(a,b,direction,40))continue;
                        done.insert(W::key(q));frontier.push_back(q);
                    }
                }
            }
            for(size_t at=0;at<frontier.size();++at){
                if(frontier.size()>131072||cancelled.load()){reason="Ocean boundary work budget exceeded";return false;}
                const auto p=frontier[at];const auto &r=store.regions.at(W::region_key(p));
                Cell a{p,W::profile(r,W::index(p)),r.water[W::index(p)]};
                for(int direction=0;direction<6;++direction){
                    auto q=p+steps[direction];if(!W::in_domain(q)||done.count(W::key(q)))continue;
                    auto found=store.regions.find(W::region_key(q));
                    if(found==store.regions.end()||!found->second.valid||found->second.ocean_state!=2)continue;
                    const auto &bregion=found->second;
                    Cell b{q,W::profile(bregion,W::index(q)),bregion.water[W::index(q)]};
                    if(!b.shape.capacity()||b.shape.volume((40-q.y*.5)*1000.)<=0||!connected(a,b,direction,40))continue;
                    done.insert(W::key(q));frontier.push_back(q);
                }
            }
            for(auto p:frontier){
                // Dry edited regions have no donors and therefore no settling
                // flag. They still receive sea water through a proven open
                // connection; limiting installation to wet donors leaves a
                // vertical water wall at the old shoreline's region boundary.
                auto k=W::region_key(p);auto &r=store.regions.at(k);
                int i=W::index(p);auto shape=W::profile(r,i);
                uint64_t amount=std::min(shape.capacity(),uint64_t(std::max(0.0,std::floor(shape.volume((40-p.y*.5)*1000.)))));
                if(!r.vacancies.empty())amount-=std::min<uint64_t>(amount,r.vacancies[i]);
                if(amount!=r.water[i]){ocean_exchange_ml+=int64_t(amount)-int64_t(r.water[i]);r.water[i]=amount;dirty.insert(k);}
            }
            store.total=uint64_t(int64_t(store.total)+ocean_exchange_ml);
            // The reservoir traversal has its own MAX_CELLS guard above and
            // releases its frontier before finite-body discovery. Unchanged
            // boundary cells must not consume the finite-body allowance on
            // every retry, otherwise one deferred body can starve forever.
            visited_cells=0;
        }
        mark(0);
        const bool reservoir_graph=store.surrounding_ocean&&std::any_of(store.regions.begin(),store.regions.end(),[](const auto &entry){return entry.second.ocean_state!=0;});
        for(auto seed:seeds){
            if(done.count(W::key(seed)))continue;
            cells.clear();for(auto &[key,block]:ids)block.values.fill(-1);
            struct Outlet {int cell;double level;};
            std::vector<Outlet> outlets;
            auto add=[&](Vector3i p,const W::Region &r){
                const int i=W::index(p),id=int(cells.size());
                if(cells.size()==cells.capacity())cells.reserve(std::min(MAX_CELLS,std::max(size_t(1),cells.capacity()+cells.capacity()/2)));
                cells.push_back({p,W::profile(r,i),r.water[i]});ids.at(W::region_key(p)).values[i]=id;return id;
            };
            add(seed,store.regions.at(W::region_key(seed)));
            // Gather the existing wet component before looking for dry space.
            // Its quantity then bounds how high receiving-space discovery can
            // climb; a lake edit must not enumerate its entire maximum-head
            // watershed before finding the much lower equilibrium level.
            uint64_t source_quantity=0;
            if(!reservoir_graph)for(size_t cursor=0;cursor<cells.size();++cursor){
                source_quantity+=cells[cursor].before;
                const auto current_key=W::region_key(cells[cursor].p);const auto &current_block=ids.at(current_key);
                for(int direction=0;direction<6;++direction){
                    auto q=cells[cursor].p+steps[direction];if(!W::in_domain(q)||done.count(W::key(q)))continue;
                    const auto neighbor_key=W::region_key(q);const CellIndex *block=&current_block;
                    if(neighbor_key!=current_key){auto found=ids.find(neighbor_key);if(found==ids.end())continue;block=&found->second;}
                    const auto &r=*block->region;if(!r.valid)continue;
                    const int index=W::index(q);if(!r.water[index])continue;
                    int id=block->values[index];
                    if(id>=0){cells[cursor].adjacent[direction]=id;continue;}
                    const auto a=cells[cursor].shape,b=W::profile(r,index);
                    const double ah=full_air(a)?cells[cursor].before/250.:a.head(cells[cursor].before),bh=full_air(b)?r.water[index]/250.:b.head(r.water[index]);
                    const bool open=full_air(a)&&full_air(b)?(direction==0?bh>=500:direction==5?ah>=500:true):direction==0?b.ceiling==500&&a.open_bottom&&WaterCellProfile::vertical_overlap(b,bh,a,ah):
                        direction==5?a.ceiling==500&&b.open_bottom&&WaterCellProfile::vertical_overlap(a,ah,b,bh):
                        WaterCellProfile::face_overlap(a,ah,b,bh,direction<=2?0:2,direction==1||direction==3?1:0);
                    if(!open)continue;
                    if(id<0){if(cells.size()>=MAX_CELLS){reason="Wet component exceeds reserved graph storage";return false;}id=add(q,r);}
                    cells[cursor].adjacent[direction]=id;
                }
            }
            const size_t source_count=cells.size();
            // Disconnected bodies have independent heads. A high inland lake
            // must not flood the coastal discovery frontier up to its elevation.
            double upper=seed.y*.5+cells.front().shape.head(cells.front().before)*.001;
            for(const auto &c:cells)upper=std::max(upper,c.p.y*.5+(full_air(c.shape)?c.before/250.:c.shape.head(c.before))*.001);
            double scanned_head=upper;uint64_t scans=0;bool deferred_body=false;
            using Reach=std::pair<double,int>;
            std::priority_queue<Reach,std::vector<Reach>,std::greater<Reach>> reach;
            std::vector<double> cost(cells.size(),reservoir_graph?seed.y*.5:-1e30);
            // Existing wet cells all have the same minimal reach cost. Visit this
            // prefix directly instead of sorting a whole lake through a heap.
            size_t wet_cursor=0;
            double next_capacity_level=-1e20;
            std::unordered_set<int> head_frontier;
            std::unordered_map<uint64_t,double> unknown_cost;
            double outlet_limit=upper;
            auto connection_height=[&](const Cell &a,const Cell &b,int direction){
                if(full_air(a.shape)&&full_air(b.shape))return std::min(upper,std::max(a.p.y,b.p.y)*.5+2e-9);
                if(!a.shape.solid&&!b.shape.solid){
                    double height=direction==0||direction==5?std::max(a.p.y,b.p.y)*.5:
                        a.p.y*.5+WaterCellProfile::floor_spill_height(a.shape,b.shape,direction<=2?0:2,direction==1||direction==3?1:0)*.001;
                    return std::min(upper,height+2e-9);
                }
                double height=direction==0||direction==5?std::max(a.p.y,b.p.y)*.5:
                    a.p.y*.5+WaterCellProfile::clipped_spill_height(a.shape,b.shape,direction<=2?0:2,direction==1||direction==3?1:0)*.001;
                return std::min(upper,height+2e-9);
            };
            while(wet_cursor<source_count||!reach.empty()){
                Reach entry;
                if(wet_cursor<source_count){entry={cost[wet_cursor],int(wet_cursor)};++wet_cursor;}
                else{entry=reach.top();reach.pop();}
                const size_t cursor=entry.second;
                if(entry.first>cost[cursor]||entry.first>outlet_limit+1e-6)continue;
                // The transient retains higher heads near its fixed boundary.
                // Its bounded snapshot must include receiving space up to that
                // head, not stop at the lower uniform equilibrium estimate.
                if(!local_response&&!reservoir_graph&&entry.first>=next_capacity_level){
                    next_capacity_level=entry.first+.05;
                    double capacity=0;
                    for(size_t i=0;i<cells.size();++i)if(cost[i]<=entry.first)
                        capacity+=volume_at(cells[i],entry.first);
                    // The entire snapshot quantity is a conservative bound,
                    // including other pools that may later join this body.
                    if(capacity>double(store.total)+1){
                        // Certify that all donors can communicate at this head,
                        // including vertically draining cells above it. A
                        // perched pocket invalidates this early-stop proof.
                        std::vector<uint8_t> seen(cells.size());std::vector<int> queue;
                        for(size_t i=0;i<cells.size();++i)if(cost[i]<=entry.first&&volume_at(cells[i],entry.first)>0){seen[i]=1;queue.push_back(int(i));break;}
                        for(size_t at=0;at<queue.size();++at){const int i=queue[at];
                            for(int d=0;d<6;++d){auto q=cells[i].p+steps[d];auto block=ids.find(W::region_key(q));if(block==ids.end())continue;
                                int j=block->second.values[W::index(q)];if(j<0||seen[j]||cost[j]>entry.first)continue;
                                if(connected(cells[i],cells[j],d,entry.first)){seen[j]=1;queue.push_back(j);}
                            }
                        }
                        for(size_t at=0;at<queue.size();++at){const int i=queue[at];
                            for(int d=0;d<6;++d){auto q=cells[i].p+steps[d];auto block=ids.find(W::region_key(q));if(block==ids.end())continue;
                                int j=block->second.values[W::index(q)];if(j<0||seen[j]||cost[j]>entry.first||!connected(cells[i],cells[j],d,upper))continue;
                                double spill=connection_height(cells[i],cells[j],d);
                                if(volume_at(cells[j],spill)<=1){seen[j]=1;queue.push_back(j);}
                            }
                        }
                        bool certified=true;for(size_t i=0;i<source_count;++i)certified&=bool(seen[i]);
                        // Keep the original connection head for the merge
                        // hierarchy: upper donor cells may drain down through
                        // edges above the final receiving level.
                        if(certified){outlet_limit=entry.first;break;}
                    }
                }
                if(cancelled.load()){reason="Cancelled";return false;}
                if(++scans>4000000){reason="Connected head discovery work budget exceeded";return false;}
                if(cells.size()+visited_cells>=MAX_CELLS){
                    if(visited_cells){deferred_body=true;break;}
                    reason="Connected water body exceeds bounded transaction: seed="+String(seed)+" ocean="+String::num_int64(store.regions.at(W::region_key(seed)).ocean_state)+" regions="+String::num_int64(store.regions.size())+" head="+String::num_real(upper);return false;
                }
                const auto p=cells[cursor].p;
                for(int direction=0;direction<6;++direction){
                    // Wet-component discovery already proved these links. Both
                    // ends have the same minimal reach cost; revisiting them
                    // cannot add receiving space or improve a frontier cost.
                    if(!reservoir_graph&&cursor<source_count&&cells[cursor].adjacent[direction]>=0)continue;

                    auto q=p+steps[direction];if(!W::in_domain(q))continue;
                    auto r=store.regions.find(W::region_key(q));
                    // Certify a local vertical path to fixed-head sea. Air
                    // above an open reservoir is an outlet too; expanding that
                    // air as finite receiving capacity walks the entire coast.
                    if(store.surrounding_ocean&&r!=store.regions.end()&&r->second.valid&&r->second.ocean_state){
                        std::vector<Cell> path;
                        auto down=q;bool reservoir=false;
                        for(int depth=0;depth<16;++depth,down+=Vector3i(0,-1,0)){
                            auto region=store.regions.find(W::region_key(down));
                            if(region==store.regions.end()||!region->second.valid)break;
                            const auto &value=region->second;
                            Cell cell{down,W::profile(value,W::index(down)),value.water[W::index(down)]};
                            if(!cell.shape.capacity())break;
                            if(!path.empty()&&!connected(path.back(),cell,0,upper))break;
                            path.push_back(cell);
                            if(down.y*.5<40&&value.water[W::index(down)]&&
                               (done.count(W::key(down))||value.ocean_state==1)){reservoir=true;break;}
                        }
                        if(reservoir&&connected(cells[cursor],path.front(),direction,upper)){
                            auto opens=[&](double level){
                                if(!connected(cells[cursor],path.front(),direction,level))return false;
                                for(size_t at=1;at<path.size();++at)if(!connected(path[at-1],path[at],0,level))return false;
                                return true;
                            };
                            double lo=40,hi=upper;
                            for(int iteration=0;iteration<32;++iteration){double mid=(lo+hi)*.5;if(opens(mid))hi=mid;else lo=mid;}
                            outlets.push_back({int(cursor),hi});outlet_limit=std::min(outlet_limit,std::max(cost[cursor],hi));continue;
                        }
                    }
                    if(done.count(W::key(q)))continue;
                    if(q.y*.5>=upper){
                        if(r==store.regions.end()||!r->second.valid||!r->second.water[W::index(q)]){head_frontier.insert(int(cursor));continue;}
                        Cell above{q,W::profile(r->second,W::index(q)),r->second.water[W::index(q)]};
                        double head=q.y*.5+above.shape.head(above.before)*.001;
                        if(!connected(cells[cursor],above,direction,head))continue;
                        upper=std::max(upper,head);
                        if(outlets.empty())outlet_limit=upper;
                    }
                    if(r==store.regions.end()||!r->second.valid){
                        // Local response has a closed transaction boundary.
                        // It cannot borrow from unknown/distant water. Wider
                        // relaxation follows after this volume is published.
                        if(local_response)continue;
                        Cell air;air.p=q;
                        if(connected(cells[cursor],air,direction,upper)){
                            double value=std::max(cost[cursor],connection_height(cells[cursor],air,direction));auto key=W::region_key(q);
                            auto old=unknown_cost.find(key);if(old==unknown_cost.end()||value<old->second)unknown_cost[key]=value;
                        }
                        continue;
                    }
                    const int known=ids.at(W::region_key(q)).values[W::index(q)];
                    if(known>=0){
                        int id=known;cells[cursor].adjacent[direction]=id;
                        if(connected(cells[cursor],cells[id],direction,upper)){
                            double value=std::max(cost[cursor],connection_height(cells[cursor],cells[id],direction));
                            if(value<cost[id]){cost[id]=value;reach.push({value,id});}
                        }
                        continue;
                    }
                    Cell candidate{q,W::profile(r->second,W::index(q)),r->second.water[W::index(q)]};
                    if(candidate.shape.capacity()==0)continue;
                    if(candidate.shape.volume((upper-q.y*.5)*1000.)<=0||!connected(cells[cursor],candidate,direction,upper)){head_frontier.insert(int(cursor));continue;}
                    if(candidate.before>candidate.shape.capacity()){reason="Displaced quantity needs expanded receiving capacity";return false;}
                    const double existing=q.y*.5+candidate.shape.head(candidate.before)*.001;
                    if(candidate.before)upper=std::max(upper,existing);
                    if(outlets.empty())outlet_limit=upper;
                    double value=std::max(cost[cursor],connection_height(cells[cursor],candidate,direction));
                    if(value>outlet_limit+1e-6)continue;
                    int id=add(q,r->second);cells[cursor].adjacent[direction]=id;cost.push_back(value);reach.push({value,id});
                }
                if(reach.empty()&&upper>scanned_head){scanned_head=upper;if(outlets.empty())outlet_limit=upper;for(int i:head_frontier)reach.push({cost[i],i});}
            }
            // Commit completed, disconnected bodies and resume the untouched
            // body in a later bounded job. Never partially level one body.
            if(deferred_body)break;
            // Discovery may stop before every queued cell is popped. Populate
            // all existing graph links before the connectivity/hierarchy solve.
            for(auto &c:cells)for(int d=0;d<6;++d){if(c.adjacent[d]>=0)continue;auto q=c.p+steps[d];auto block=ids.find(W::region_key(q));if(block!=ids.end())c.adjacent[d]=block->second.values[W::index(q)];}
            for(const auto &[key,value]:unknown_cost)if(outlets.empty()?value<=outlet_limit+1e-6:value<outlet_limit-1e-6)missing.insert(key);
            if(!missing.empty()){reason="seed="+String(seed)+" outlets="+String::num_int64(outlets.size())+" head="+String::num_real(upper)+" spill="+String::num_real(outlet_limit)+" cells="+String::num_int64(cells.size())+" donor_cells="+String::num_int64(source_count)+" donor_ml="+String::num_int64(source_quantity)+" snapshot_ml="+String::num_int64(store.total);required.assign(missing.begin(),missing.end());return false;}
            visited_cells+=cells.size();if(visited_cells>MAX_CELLS){reason="Water transaction work budget exceeded";return false;}
            mark(1);
            uint64_t quantity=0;double low=upper;
            std::vector<WaterVolumeQuery> queries;queries.reserve(cells.size());
            std::array<uint32_t,512> air_layers{};std::vector<int> boundary_cells;
            for(size_t i=0;i<cells.size();++i){const auto &c=cells[i];quantity+=c.before;low=std::min(low,c.p.y*.5);queries.emplace_back(c.shape);
                if(full_air(c.shape))++air_layers[c.p.y];else boundary_cells.push_back(int(i));}
            if(!quantity)continue;
            double high=upper;
            // Resolve less than one ml over the entire connected surface, not
            // only a fixed head precision. Large full lakes can differ by 1 ml.
            for(int iteration=0;iteration<48;++iteration){
                const double middle=(low+high)*.5;double volume=0;
                // Interior volumes share one linear curve per elevation. Only
                // cut cells need their individual terrain/solid evaluator.
                for(size_t y=0;y<air_layers.size();++y)if(air_layers[y])volume+=air_layers[y]*std::clamp((middle-y*.5)*250000.,0.,125000.);
                for(int i:boundary_cells)volume+=std::min(double(queries[i].capacity()),queries[i].volume((middle-cells[i].p.y*.5)*1000.));
                if(volume<double(quantity))low=middle;else high=middle;
                if((high-low)*double(cells.size())*250000.<.25)break;
            }
            uint64_t assigned=0;
            for(size_t i=0;i<cells.size();++i){auto &c=cells[i];double volume=std::min(double(queries[i].capacity()),queries[i].volume((high-c.p.y*.5)*1000.));
                c.after=std::min(queries[i].capacity(),uint64_t(std::max(0.,std::floor(volume))));c.fraction=volume-c.after;assigned+=c.after;}
            if(assigned>quantity||quantity-assigned>cells.size()){reason="Equilibrium quantity cannot be represented";return false;}
            std::vector<int> remainder;for(size_t i=0;i<cells.size();++i)if(cells[i].fraction>0&&cells[i].after<queries[i].capacity())remainder.push_back(int(i));
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
                if(full_air(a.shape)&&full_air(b.shape))return std::min(upper,std::max(a.p.y,b.p.y)*.5+2e-9);
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
            bool needs_hierarchy=!outlets.empty()||queue.size()!=wet;
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
                if(cells.size()>hierarchy_cell_limit){reason="Water basin hierarchy exceeds reserved memory";return false;}
                // The uniform result crosses a dry sill. Build a bounded merge
                // hierarchy of communicating basins, retaining each child's
                // water below its spill elevation before passing excess up.
                struct Edge {int a,b;double level;};
                struct Basin {int left=-1,right=-1,parent=-1,begin=0,end=0;double level=0;uint64_t capacity=0,quantity=0,excess=0,extra=0;bool outlet=false;};
                static_assert(sizeof(Basin)<=80,"Update the hierarchy memory charge when basin layout grows");
                std::vector<Edge> edges;edges.reserve(cells.size()*3);
                for(size_t i=0;i<cells.size();++i)for(int d=0;d<6;++d){
                    int j=cells[i].adjacent[d];if(j<=int(i)||!connected(cells[i],cells[j],d,upper))continue;
                    edges.push_back({int(i),j,spill(int(i),j,d)});
                }
                const int sink=outlets.empty()?-1:int(cells.size());
                for(const auto &outlet:outlets)edges.push_back({outlet.cell,sink,outlet.level});
                mark(5);
                std::stable_sort(edges.begin(),edges.end(),[](const Edge &a,const Edge &b){return a.level<b.level;});
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
                    if(node.left<0)incoming=int(id)==sink?0:cells[id].before;
                    else{node.quantity=tree[node.left].quantity+tree[node.right].quantity;incoming=tree[node.left].excess+tree[node.right].excess;}
                    if(node.quantity>node.capacity){reason="Inconsistent basin capacity";return false;}
                    uint64_t retained=node.outlet?0:std::min(incoming,node.capacity-node.quantity);node.excess=incoming-retained;
                    node.quantity+=retained;if(node.left>=0)node.extra=retained;
                    if(node.outlet&&node.excess){ocean_exchange_ml-=int64_t(node.excess);store.total-=node.excess;quantity-=node.excess;node.excess=0;}
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
            if(local_response&&!needs_hierarchy&&!reservoir_graph){
                // A local response is a transient, not a smaller sealed lake.
                // Keep the outer cell ring unchanged and taper redistribution
                // into it. A uniform local head creates an artificial rectangular
                // waterfall where this transaction meets untouched water.
                std::unordered_set<uint64_t> columns;
                const int surface_layer=int(std::floor((upper-1e-5)/4.));
                for(const auto &[k,r]:store.regions){auto p=W::position(k);if(p.y==surface_layer)columns.insert((uint64_t(p.x)<<32)|uint32_t(p.z));}
                std::vector<double> weights(cells.size());
                double lower=upper;
                for(size_t i=0;i<cells.size();++i){const auto p=cells[i].p;double distance=3.5;
                    auto owner=W::position(W::region_key(p));
                    for(int dz=-1;dz<=1;++dz)for(int dx=-1;dx<=1;++dx){
                        auto x=owner.x+dx,z=owner.z+dz;
                        if(columns.count((uint64_t(uint32_t(x))<<32)|uint32_t(z)))continue;
                        double px=(p.x+.5)*.5,pz=(p.z+.5)*.5;
                        double ex=std::max({x*4.-px,0.,px-(x+1)*4.}),ez=std::max({z*4.-pz,0.,pz-(z+1)*4.});
                        distance=std::min(distance,std::sqrt(ex*ex+ez*ez));
                    }
                    double t=std::clamp((distance-.5)/3.,0.,1.);weights[i]=t*t*(3-2*t);
                    lower=std::min(lower,p.y*.5);
                }
                double upper_head=upper;
                auto blended=[&](size_t i,double head){
                    if(weights[i]==0)return double(cells[i].before);
                    // Taper column head, never per-cell fill fraction: mixing
                    // fractions leaves alternating air gaps in deep new cuts.
                    double level=upper+(head-upper)*weights[i];
                    return std::min(double(queries[i].capacity()),queries[i].volume((level-cells[i].p.y*.5)*1000.));
                };
                for(int bracket=0;bracket<32;++bracket){double volume=0;
                    for(size_t i=0;i<cells.size();++i)volume+=blended(i,lower);
                    if(volume<=double(quantity))break;
                    lower=upper-std::max(1.,2*(upper-lower));
                }
                for(int iteration=0;iteration<48;++iteration){double middle=(lower+upper_head)*.5,volume=0;
                    for(size_t i=0;i<cells.size();++i)volume+=blended(i,middle);
                    if(volume<double(quantity))lower=middle;else upper_head=middle;
                    if((upper_head-lower)*double(cells.size())*250000.<.25)break;
                }
                uint64_t filled=0;std::vector<int> fractions;
                for(size_t i=0;i<cells.size();++i){double volume=std::max(0.,blended(i,upper_head));auto &c=cells[i];
                    c.after=uint64_t(std::floor(volume));c.fraction=volume-c.after;filled+=c.after;
                    if(c.fraction>0&&c.after<queries[i].capacity())fractions.push_back(int(i));
                }
                std::stable_sort(fractions.begin(),fractions.end(),[&](int a,int b){return cells[a].fraction>cells[b].fraction;});
                for(int i:fractions)if(filled<quantity){++cells[i].after;++filled;}
                if(filled!=quantity){reason="Local response integer remainder is unresolved";return false;}
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
