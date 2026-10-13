// SPDX-License-Identifier: 0BSD
#include "regional_water.hpp"
#include "water_surface_interval.hpp"
#include "../../volumetric_terrain/native/density_surface.hpp"
#include "lake_catalog.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <algorithm>
#include <cmath>
#include <vector>
using namespace godot;
namespace terraforest {
static const Vector3i directions[6]={{0,-1,0},{1,0,0},{-1,0,0},{0,0,1},{0,0,-1},{0,1,0}};
static bool reply_ok(const PackedByteArray &p,int size){return p.size()==size&&p.decode_u32(0)==0x32505254&&p.decode_u32(8)==0;}
void NativeWaterTerrainPatch::_bind_methods(){
    ClassDB::bind_method(D_METHOD("configure","coordinate"),&NativeWaterTerrainPatch::configure);
    ClassDB::bind_method(D_METHOD("sample_terrain","core","budget","revision","epoch"),&NativeWaterTerrainPatch::sample_terrain);
    ClassDB::bind_method(D_METHOD("statistics"),&NativeWaterTerrainPatch::statistics);
}
bool NativeWaterTerrainPatch::configure(const Vector3i &p){
    if(status!=-1||p.x<0||p.x>=500||p.z<0||p.z>=500||p.y<0||p.y>=64)return false;
    coord=p;status=0;return true;
}
int64_t NativeWaterTerrainPatch::sample_terrain(Object *core,int64_t budget,int64_t rev,int64_t cancel){
    if(status!=0||!core||budget<1||budget>2048)return status;
    if(revision<0){revision=rev;epoch=cancel;}
    if(revision!=rev||epoch!=cancel)return status=-4;
    // The backend pins the terrain revision and cancel epoch around every call.
    // One native interpolated batch (<=256 points), rather than a script call per sample.
    const uint64_t started=Time::get_singleton()->get_ticks_usec();
    const int count=std::min({int(budget),512,729-cursor});
    PackedByteArray command;command.resize(12+count*12);command.encode_u32(0,31);command.encode_u32(4,rev);command.encode_u32(8,count);
    for(int j=0;j<count;++j){int i=cursor+j;Vector3 p=Vector3(coord)*4.0+Vector3(i%9,(i/9)%9,i/81)*0.5;
        p.y=std::clamp(double(p.y),1.0,255.0);
        command.encode_float(12+j*12,p.x);command.encode_float(16+j*12,p.y);command.encode_float(20+j*12,p.z);}
    const PackedByteArray reply=core->call("execute",command);
    if(!reply_ok(reply,20+count*4)||reply.decode_u32(12)!=uint64_t(rev)||reply.decode_u32(16)!=uint64_t(count))return status=-4;
    for(int j=0;j<count;++j){float d=reply.decode_float(20+j*4);if(!std::isfinite(d))return status=-2;density[cursor++]=d;}
    if(cursor<729){if(budget>count&&Time::get_singleton()->get_ticks_usec()-started<1500)return sample_terrain(core,budget-count,rev,cancel);return 0;}
    for(int z=0;z<8;++z)for(int y=0;y<8;++y)for(int x=0;x<8;++x){
        // Intersection of the four vertical air intervals. This deliberately
        // errs toward solid support: no leakage through a thin diagonal wall.
        // A 0.5 m grid cannot resolve sub-cell tunnels or overhangs.
        double lo=0,hi=500;
        for(int dz=0;dz<2;++dz)for(int dx=0;dx<2;++dx){
            double a=density[x+dx+9*y+81*(z+dz)],b=density[x+dx+9*(y+1)+81*(z+dz)];
            if(a<=0&&b<=0){lo=500;hi=0;}
            else if(a<=0)lo=std::max(lo,500*(-a)/(b-a));
            else if(b<=0)hi=std::min(hi,500*a/(a-b));
        }
        int i=x+8*y+64*z;
        floor[i]=uint16_t(std::clamp(int(std::ceil(lo)),0,500));
        ceiling[i]=uint16_t(std::clamp(int(std::floor(hi)),int(floor[i]),500));
        if(coord.y*8+y<2||coord.y*8+y>=509)floor[i]=ceiling[i]=500;
    }
    return status=1;
}
Dictionary NativeWaterTerrainPatch::statistics() const {Dictionary d;d["status"]=status;d["coordinate"]=coord;d["sampled_nodes"]=cursor;return d;}

void NativeRegionalWater::_bind_methods(){
    ClassDB::bind_method(D_METHOD("next_request"),&NativeRegionalWater::next_request);
    ClassDB::bind_method(D_METHOD("accept_patch","patch"),&NativeRegionalWater::accept_patch);
    ClassDB::bind_method(D_METHOD("invalidate","bounds"),&NativeRegionalWater::invalidate);
    ClassDB::bind_method(D_METHOD("advance","budget"),&NativeRegionalWater::advance);
    ClassDB::bind_method(D_METHOD("begin_fill","bounds","level","seed","amount"),&NativeRegionalWater::begin_fill);
    ClassDB::bind_method(D_METHOD("remove_bounds","bounds"),&NativeRegionalWater::remove_bounds);
    ClassDB::bind_method(D_METHOD("brush","point","radius","amount"),&NativeRegionalWater::brush);
    ClassDB::bind_method(D_METHOD("transfer_litre","from","to","pour","inventory","slot","revision"),&NativeRegionalWater::transfer_litre);
    ClassDB::bind_method(D_METHOD("surface_near","point","radius"),&NativeRegionalWater::surface_near);
    ClassDB::bind_method(D_METHOD("depth_at","point"),&NativeRegionalWater::depth_at);
    ClassDB::bind_method(D_METHOD("placement_mask","transforms"),&NativeRegionalWater::placement_mask);
    ClassDB::bind_method(D_METHOD("raycast_surface","from","to"),&NativeRegionalWater::raycast_surface);
    ClassDB::bind_method(D_METHOD("commit_mesh_batch","id"),&NativeRegionalWater::commit_mesh_batch);
    ClassDB::bind_method(D_METHOD("next_mesh_batch"),&NativeRegionalWater::next_mesh_batch);
    ClassDB::bind_method(D_METHOD("next_mesh"),&NativeRegionalWater::next_mesh);
    ClassDB::bind_method(D_METHOD("statistics"),&NativeRegionalWater::statistics);
    ClassDB::bind_method(D_METHOD("capture_snapshot","catalog"),&NativeRegionalWater::capture_snapshot);
    ClassDB::bind_method(D_METHOD("restore_snapshot","bytes"),&NativeRegionalWater::restore_snapshot);
    ClassDB::bind_method(D_METHOD("validate_snapshot","bytes"),&NativeRegionalWater::validate_snapshot);
    ClassDB::bind_method(D_METHOD("snapshot_catalog","bytes"),&NativeRegionalWater::snapshot_catalog);
}
NativeRegionalWater::Key NativeRegionalWater::key(const Vector3i &p){return (uint64_t(p.x)<<24)|(uint64_t(p.y)<<12)|uint64_t(p.z);}
Vector3i NativeRegionalWater::position(Key k){return Vector3i((k>>24)&4095,(k>>12)&4095,k&4095);}
Vector3i NativeRegionalWater::cell(const Vector3 &p){return Vector3i((p*2.0).floor());}
NativeRegionalWater::Key NativeRegionalWater::region_key(const Vector3i &p){return key(Vector3i(p.x/8,p.y/8,p.z/8));}
int NativeRegionalWater::index(const Vector3i &p){return (p.x&7)+8*(p.y&7)+64*(p.z&7);}
bool NativeRegionalWater::in_domain(const Vector3i &p){return p.x>=0&&p.x<4000&&p.z>=0&&p.z<4000&&p.y>=2&&p.y<509;}
void NativeRegionalWater::request(Key k){if(request_set.insert(k).second)requests.push_back(k);}
NativeRegionalWater::Region *NativeRegionalWater::get(const Vector3i &p,bool ask){
    if(!in_domain(p))return nullptr;
    Key k=region_key(p);auto it=regions.find(k);
    if(it==regions.end()){
        if(!ask)return nullptr;
        if(regions.size()>=MAX_REGIONS){limit=true;return nullptr;}
        preserve_mesh_region(k);it=regions.emplace(k,Region{}).first;
    }
    if(!it->second.valid){if(ask)request(k);return nullptr;}
    preserve_mesh_region(k);return &it->second;
}
const NativeRegionalWater::Region *NativeRegionalWater::get(const Vector3i &p) const {
    if(!in_domain(p))return nullptr;auto it=regions.find(region_key(p));return it!=regions.end()&&it->second.valid?&it->second:nullptr;
}
void NativeRegionalWater::wake(const Vector3i &p){
    if(!in_domain(p))return;auto it=regions.find(region_key(p));
    if(it!=regions.end()&&it->second.water[index(p)]&&active_set.insert(key(p)).second)active.push_back(key(p));
}
void NativeRegionalWater::changed(const Vector3i &p){
    queue_vertical(p);queue_vertical(p+Vector3i(0,-1,0));
    ++changes;wake(p);Key k=region_key(p);if(mesh_set.insert(k).second)meshes.push_back(k);
    // Surface-nets representatives read a one-cell halo. Render owners may
    // be empty storage regions; they still own boundary triangles.
    Vector3i lo=position(region_key(Vector3i(std::max(p.x-1,0),std::max(p.y-1,0),std::max(p.z-1,0))));
    Vector3i hi=position(region_key(Vector3i(std::min(p.x+1,3999),std::min(p.y+1,508),std::min(p.z+1,3999))));
    for(int z=lo.z;z<=hi.z;++z)for(int y=lo.y;y<=hi.y;++y)for(int x=lo.x;x<=hi.x;++x){Key other=key(Vector3i(x,y,z));
        if(other!=k&&mesh_set.insert(other).second)meshes.push_back(other);}
    for(const Vector3i &d:directions){Vector3i n=p+d;if(!in_domain(n))continue;wake(n);Key other=region_key(n);
        if(other!=k&&mesh_set.insert(other).second)meshes.push_back(other);}
}
Dictionary NativeRegionalWater::next_request(){
    Dictionary d;if(requests.empty())return d;Key k=requests.front();
    // Keep reservation until accepted. A stale worker can simply retry it.
    d["coordinate"]=position(k);return d;
}
bool NativeRegionalWater::accept_patch(const Ref<NativeWaterTerrainPatch> &patch){
    if(patch.is_null()||patch->status!=1)return false;Key k=key(patch->coord);auto it=regions.find(k);if(it==regions.end())return false;
    preserve_mesh_region(k);if(restored_cache.count(k))++cache_rebuilds;
    it->second.density=patch->density;it->second.has_density=true;
    if(mesh_set.insert(k).second)meshes.push_back(k);
    it->second.floor=patch->floor;it->second.ceiling=patch->ceiling;it->second.valid=true;sampled+=729;
    request_set.erase(k);requests.erase(std::remove(requests.begin(),requests.end(),k),requests.end());
    Vector3i base=patch->coord*8;
    for(int i=0;i<512;++i){Vector3i p=base+Vector3i(i%8,(i/8)%8,i/64);wake(p);
        if(it->second.water[i])changed(p);
        // Wake wet neighbours held at a previously unknown/invalid boundary.
        if((i%8)==0)wake(p+Vector3i(-1,0,0));if((i%8)==7)wake(p+Vector3i(1,0,0));
        if(((i/8)%8)==0)wake(p+Vector3i(0,-1,0));if(((i/8)%8)==7)wake(p+Vector3i(0,1,0));
        if((i/64)==0)wake(p+Vector3i(0,0,-1));if((i/64)==7)wake(p+Vector3i(0,0,1));}
    return true;
}
void NativeRegionalWater::invalidate(const AABB &bounds){
    if(!bounds.position.is_finite()||!bounds.size.is_finite())return;
    cancel_mesh_batch();
    for(auto &[k,r]:regions)if(AABB(Vector3(position(k))*4.0,Vector3(4,4,4)).intersects(bounds.grow(0.5))){r.valid=false;request(k);}
}
// Prioritised conservative gravity repair. Each job handles exactly one face;
// chains resume through the same bounded queue rather than scanning a column.
void NativeRegionalWater::queue_vertical(const Vector3i &lower){
    const Region *a=get(lower);Vector3i upper=lower+Vector3i(0,1,0);const Region *b=get(upper);
    if(!a||!b)return;int i=index(lower),j=index(upper);
    uint64_t capacity=uint64_t(a->ceiling[i]-a->floor[i])*250;
    if(a->ceiling[i]!=500||b->floor[j]!=0||a->water[i]>=capacity||!b->water[j])return;
    Key k=key(lower);if(vertical_set.insert(k).second){vertical.push_back(k);++vertical_regions[region_key(lower)];}
    // The existing saved awake bit records work even if the lower cell is dry.
    wake(upper);
}
void NativeRegionalWater::settle_vertical(){
    Key k=vertical.front();vertical.pop_front();vertical_set.erase(k);Vector3i lower=position(k);
    auto pending=vertical_regions.find(region_key(lower));if(pending!=vertical_regions.end()&&!--pending->second)vertical_regions.erase(pending);
    Vector3i upper=lower+Vector3i(0,1,0);Region *a=get(lower,false),*b=get(upper,false);++vertical_steps;
    if(!a||!b)return;int i=index(lower),j=index(upper);
    uint64_t capacity=uint64_t(a->ceiling[i]-a->floor[i])*250;
    if(a->ceiling[i]==500&&b->floor[j]==0&&capacity>a->water[i]&&b->water[j])
        move(upper,lower,std::min(capacity-a->water[i],b->water[j]));
}
void NativeRegionalWater::move(const Vector3i &a,const Vector3i &b,uint64_t amount){
    if(!amount)return;preserve_mesh_region(region_key(a));preserve_mesh_region(region_key(b));regions.at(region_key(a)).water[index(a)]-=amount;regions.at(region_key(b)).water[index(b)]+=amount;changed(a);changed(b);
}
void NativeRegionalWater::process_cell(const Vector3i &p){
    Region *a=get(p,true);if(!a)return;int i=index(p);if(!a->water[i])return;
    const uint64_t capacity=uint64_t(a->ceiling[i]-a->floor[i])*250;
    // Newly placed solid terrain never deletes water. Try adjacent free cells;
    // any trapped displacement stays owned here until terrain opens again.
    if(capacity==0){
        for(const Vector3i &d:directions){Vector3i q=p+d;Region *b=get(q,true);if(!b)continue;int j=index(q);uint64_t cap=uint64_t(b->ceiling[j]-b->floor[j])*250;
            if(cap>b->water[j])move(p,q,std::min(a->water[i],cap-b->water[j]));if(!a->water[i])break;}
        return;
    }
    Vector3i below=p+directions[0];Region *down=nullptr;
    if(a->floor[i]==0){down=get(below,true);if(down){int j=index(below);uint64_t cap=uint64_t(down->ceiling[j]-down->floor[j])*250;
        if(down->ceiling[j]==500&&cap>down->water[j])move(p,below,std::min(a->water[i],cap-down->water[j]));}}
    if(!a->water[i])return;
    // Equalise only across a shared air interval, with exact integer transfers.
    // Rotating the deterministic order avoids a permanent cardinal-direction bias.
    const int rotation=int(key(p)&3);
    for(int t=0;t<4&&a->water[i];++t){Vector3i q=p+directions[1+(t+rotation)%4];Region *b=get(q,true);if(!b)continue;int j=index(q);
        int opening=std::max(a->floor[i],b->floor[j]);if(opening>=std::min(a->ceiling[i],b->ceiling[j]))continue;
        uint64_t cap=uint64_t(b->ceiling[j]-b->floor[j])*250;if(b->water[j]>=cap)continue;
        int64_t head_a=int64_t(a->floor[i])*250+int64_t(a->water[i]);
        int64_t head_b=int64_t(b->floor[j])*250+int64_t(b->water[j]);
        int64_t available=head_a-int64_t(opening)*250;
        int64_t difference=head_a-head_b;
        if(available>0&&difference>250)move(p,q,std::min({uint64_t(available),uint64_t(difference/2),cap-b->water[j],a->water[i]}));
    }
    if(a->water[i]>capacity&&a->ceiling[i]==500){Vector3i q=p+directions[5];Region *b=get(q,true);if(b&&b->floor[index(q)]==0){
        uint64_t cap=uint64_t(b->ceiling[index(q)])*250;if(cap>b->water[index(q)])move(p,q,std::min(a->water[i]-capacity,cap-b->water[index(q)]));}}
}
bool NativeRegionalWater::begin_fill(const AABB &bounds,double level,const Vector3 &seed,int64_t amount){
    if(fill.running||!bounds.position.is_finite()||!bounds.size.is_finite()||!seed.is_finite()||!std::isfinite(level)||amount<-1||amount>int64_t(MAX_TOTAL-total))return false;
    Vector3i lo=cell(bounds.position),hi=cell(bounds.position+bounds.size);Vector3i start=cell(seed);
    if(!in_domain(lo)||!in_domain(hi)||hi.x<=lo.x||hi.y<=lo.y||hi.z<=lo.z||int64_t(hi.x-lo.x)*(hi.y-lo.y)*(hi.z-lo.z)>2097152||!bounds.has_point(seed)||seed.y>=level)return false;
    fill=Fill{};fill.running=true;fill.low=lo;fill.high=hi;fill.level=int(std::round(level*1000));fill.remaining=amount;fill.seed=key(start);fill.queue.push_back(key(start));fill.seen.insert(key(start));return true;
}
void NativeRegionalWater::process_fill(){
    if(fill.queue.empty()||fill.remaining==0){
        // Legacy finite saves retain every millilitre even when a coarser grid
        // has less capacity. Excess remains owned and drains through local flow.
        if(fill.remaining>0){Vector3i p=position(fill.seed);auto it=regions.find(region_key(p));if(it!=regions.end()){preserve_mesh_region(region_key(p));it->second.water[index(p)]+=fill.remaining;total+=fill.remaining;changed(p);fill.remaining=0;}}
        fill.running=false;fill.seen.clear();fill.queue.clear();return;}
    Vector3i p=position(fill.queue.front());Region *r=get(p,true);if(!r)return;
    fill.queue.pop_front();int i=index(p);int head=fill.level-p.y*500;
    int height=std::clamp(head-int(r->floor[i]),0,int(r->ceiling[i]-r->floor[i]));if(!height)return;
    uint64_t target=uint64_t(height)*250;
    if(target>r->water[i]){uint64_t add=target-r->water[i];if(fill.remaining>=0)add=std::min(add,uint64_t(fill.remaining));add=std::min(add,MAX_TOTAL-total);r->water[i]+=add;total+=add;if(fill.remaining>=0)fill.remaining-=add;changed(p);}
    bool retry=false;
    for(int direction=0;direction<6;++direction){Vector3i q=p+directions[direction];
        if(q.x<fill.low.x||q.x>=fill.high.x||q.y<fill.low.y||q.y>=fill.high.y||q.z<fill.low.z||q.z>=fill.high.z||q.y*500>=fill.level)continue;
        Region *other=get(q,true);if(!other){retry=true;continue;}int j=index(q);
        if(other->floor[j]==other->ceiling[j])continue;
        bool connected=direction==0?(r->floor[i]==0&&other->ceiling[j]==500):direction==5?(r->ceiling[i]==500&&other->floor[j]==0):
            (std::max(r->floor[i],other->floor[j])<std::min(r->ceiling[i],other->ceiling[j])&&head>std::max(r->floor[i],other->floor[j]));
        if(connected&&fill.seen.insert(key(q)).second)fill.queue.push_back(key(q));}
    // Revisit just this frontier after missing terrain arrives. Already assigned
    // amounts are idempotent; a disconnected air interval is never a fill edge.
    if(retry)fill.queue.push_back(key(p));
}
void NativeRegionalWater::advance(int64_t budget){
    if(budget<1||budget>8192)return;uint64_t start=Time::get_singleton()->get_ticks_usec();
    for(int n=0;n<budget;++n){
        if(fill.running){size_t before=fill.queue.size();process_fill();if(fill.running&&fill.queue.size()==before&&!requests.empty())break;}
        else if(!vertical.empty())settle_vertical();
        else{if(active.empty())break;Key k=active.front();active.pop_front();active_set.erase(k);process_cell(position(k));++steps;}
        if((n&7)==7&&Time::get_singleton()->get_ticks_usec()-start>=1000)break;
    }
    last_us=Time::get_singleton()->get_ticks_usec()-start;max_us=std::max(max_us,last_us);
}
int64_t NativeRegionalWater::remove_bounds(const AABB &bounds){
    if(fill.running||!bounds.position.is_finite()||!bounds.size.is_finite())return 0;
    uint64_t removed=0;
    for(auto &[k,r]:regions){Vector3i base=position(k)*8;if(!AABB(Vector3(base)*0.5,Vector3(4,4,4)).intersects(bounds))continue;preserve_mesh_region(k);
        for(int i=0;i<512;++i)if(r.water[i]){Vector3i p=base+Vector3i(i%8,(i/8)%8,i/64);if(bounds.has_point(Vector3(p)*0.5+Vector3(0.25,0.25,0.25))){removed+=r.water[i];r.water[i]=0;changed(p);}}}
    total-=removed;return removed;
}
int64_t NativeRegionalWater::brush(const Vector3 &point,double radius,int64_t amount){
    if(!point.is_finite()||!std::isfinite(radius)||radius<0||radius>16||fill.running)return 0;
    if(amount>0){if(uint64_t(amount)>MAX_TOTAL-total)return 0;Vector3i p=cell(point);Region *r=get(p,true);if(!r||r->floor[index(p)]==r->ceiling[index(p)])return 0;
        r->water[index(p)]+=amount;total+=amount;changed(p);return amount;}
    if(amount==0)return 0;
    uint64_t removed=0,requested=amount==INT64_MIN?MAX_TOTAL:uint64_t(-amount);
    Vector3i lo=cell(point-Vector3(radius,radius,radius)),hi=cell(point+Vector3(radius,radius,radius));
    for(int z=lo.z;z<=hi.z;++z)for(int y=lo.y;y<=hi.y;++y)for(int x=lo.x;x<=hi.x;++x){Vector3i p(x,y,z);if(!in_domain(p)||(Vector3(p)*0.5+Vector3(0.25,0.25,0.25)-point).length()>radius)continue;
        auto it=regions.find(region_key(p));if(it==regions.end())continue;preserve_mesh_region(region_key(p));uint64_t &v=it->second.water[index(p)];uint64_t take=std::min(v,requested-removed);if(take){v-=take;total-=take;removed+=take;changed(p);}if(removed==requested)return removed;}
    return int64_t(removed);
}
Dictionary NativeRegionalWater::transfer_litre(const Vector3 &from,const Vector3 &to,bool pour,Object *inventory,int64_t slot,int64_t revision){
    Dictionary out;out["ok"]=false;out["pending"]=false;
    if(fill.running||!from.is_finite()||!to.is_finite()||from.distance_to(to)>5||!inventory||!inventory->has_method("exchange_bucket")){out["reason"]="Water is preparing, or target is out of reach";return out;}
    Dictionary surface=raycast_surface(from,to);bool hit=bool(surface["hit"]);
    Vector3i target=hit?Vector3i(surface["cell"]):cell(to);
    if(!pour&&!hit){out["reason"]="Aim at nearby water containing at least one litre";return out;}
    Region *r=get(target,true);if(!r){out["pending"]=in_domain(target)&&!limit;out["reason"]="Preparing water at this location";return out;}
    // A terrain ray can end inside a conservative shoreline cell. Pour into
    // the first open cell just back along the unobstructed aiming segment,
    // instead of rejecting a valid bucket action against a sloping surface.
    if(pour&&r->ceiling[index(target)]==r->floor[index(target)]){
        Vector3 back=(from-to).normalized();
        for(int step=1;step<=10;++step){Vector3i p=cell(to+back*(step*0.1));Region *candidate=get(p,true);
            if(!candidate){out["pending"]=in_domain(p)&&!limit;out["reason"]="Preparing water at this location";return out;}
            if(candidate->ceiling[index(p)]>candidate->floor[index(p)]){target=p;r=candidate;break;}}
    }
    int i=index(target);
    std::vector<std::pair<Vector3i,uint64_t>> take;
    if(!pour){
        uint64_t remaining=1000;
        // A litre may occupy several shallow cells. Collect locally, never
        // require one cell to contain the whole bucket transfer.
        std::deque<Vector3i> candidates;std::unordered_set<Key> visited;candidates.push_back(target);visited.insert(key(target));
        while(!candidates.empty()&&remaining){Vector3i p=candidates.front();candidates.pop_front();const Region *other=get(p);if(!other)continue;int j=index(p);
            uint64_t amount=std::min(remaining,other->water[j]);if(!amount||other->floor[j]==other->ceiling[j])continue;
            take.emplace_back(p,amount);remaining-=amount;
            for(int d=0;d<6;++d){Vector3i q=p+directions[d];Vector3i distance=q-target;
                if(std::max({std::abs(distance.x),std::abs(distance.y),std::abs(distance.z)})>2||!in_domain(q))continue;
                const Region *next=get(q);if(!next||!next->water[index(q)])continue;int n=index(q);bool connected=false;
                if(d==0)connected=other->floor[j]==0&&next->ceiling[n]==500&&next->water[n]>=uint64_t(500-next->floor[n])*250;
                else if(d==5)connected=other->ceiling[j]==500&&next->floor[n]==0&&other->water[j]>=uint64_t(500-other->floor[j])*250;
                else connected=water_intervals_joined(other->floor[j],other->ceiling[j],other->water[j],next->floor[n],next->ceiling[n],next->water[n]);
                if(connected&&visited.insert(key(q)).second)candidates.push_back(q);
            }
        }
        if(remaining){out["reason"]="Less than one litre within bucket reach";return out;}
    }
    if(pour&&(r->ceiling[i]==r->floor[i]||total>MAX_TOTAL-1000)){out["reason"]="Aim at open space just above terrain";return out;}
    if(!bool(inventory->call("exchange_bucket",slot,pour,revision))){out["reason"]="Bucket full / empty, or selected item changed";return out;}
    if(pour){r->water[i]+=1000;total+=1000;}else{for(const auto &[p,amount]:take){preserve_mesh_region(region_key(p));regions.at(region_key(p)).water[index(p)]-=amount;changed(p);}total-=1000;}
    changed(target);out["ok"]=true;out["reason"]=pour?"Poured 1 L":"Scooped 1 L";out["point"]=Vector3(target)*0.5;return out;
}
Vector3 NativeRegionalWater::surface_near(const Vector3 &point,double radius) const {
    Vector3 best(INFINITY,INFINITY,INFINITY);if(!point.is_finite()||!std::isfinite(radius)||radius<0||radius>3)return best;
    Vector3 margin(radius+0.5,radius+0.5,radius+0.5);
    Vector3i lo=Vector3i(((point-margin)/4.0).floor()),hi=Vector3i(((point+margin)/4.0).floor());double distance=radius*radius;
    for(int z=std::max(0,lo.z);z<=std::min(499,hi.z);++z)for(int y=std::max(0,lo.y);y<=std::min(63,hi.y);++y)for(int x=std::max(0,lo.x);x<=std::min(499,hi.x);++x){
        Key k=key(Vector3i(x,y,z));if(!surface_ready(k))continue;QuerySurface temporary;const QuerySurface *selected=query_surface(k,temporary);if(!selected)continue;const QuerySurface &mesh=*selected;
        auto consider=[&](Vector3 q){double d=point.distance_squared_to(q);if(d<distance){distance=d;best=q;}};
        for(int i=0;i<mesh.vertices.size();i+=3){
            if((mesh.vertices[i+2]-mesh.vertices[i]).cross(mesh.vertices[i+1]-mesh.vertices[i]).y<=0)continue;
            Vector3 a=mesh.vertices[i],b=mesh.vertices[i+1],c=mesh.vertices[i+2];
            Vector3 u=b-a,v=c-a,n=u.cross(v);double n2=n.length_squared();if(n2<1e-16)continue;
            Vector3 q=point-n*(n.dot(point-a)/n2),w=q-a;
            double uu=u.dot(u),uv=u.dot(v),vv=v.dot(v),wu=w.dot(u),wv=w.dot(v),denom=uu*vv-uv*uv;
            if(denom>1e-16){double bu=(vv*wu-uv*wv)/denom,bv=(uu*wv-uv*wu)/denom;if(bu>=0&&bv>=0&&bu+bv<=1)consider(q);}
            for(int edge=0;edge<3;++edge){Vector3 start=mesh.vertices[i+edge],delta=mesh.vertices[i+(edge+1)%3]-start;
                double length=delta.length_squared();if(length>1e-16)consider(start+delta*std::clamp(double((point-start).dot(delta))/length,0.0,1.0));}
        }
    }
    return best;
}

double NativeRegionalWater::depth_at(const Vector3 &point) const {
    if(!point.is_finite())return 0;Vector3i p=cell(point);const Region *r=get(p);if(!r)return 0;int i=index(p);
    if(!r->water[i]||r->floor[i]==r->ceiling[i])return 0;
    double top=p.y*0.5+r->floor[i]*0.001+std::min(r->water[i],uint64_t(r->ceiling[i]-r->floor[i])*250)/250000.0;
    if(point.y>=top||point.y<p.y*0.5+r->floor[i]*0.001)return 0;
    // At most the bounded vertical domain, only for actual wet query points.
    for(int y=p.y+1;y<509;++y){Vector3i q(p.x,y,p.z);const Region *above=get(q);if(!above||!above->water[index(q)]||top<y*0.5-0.00001||above->floor[index(q)]!=0)break;
        int j=index(q);top=y*0.5+std::min(above->water[j],uint64_t(above->ceiling[j])*250)/250000.0;}
    return std::max(0.0,top-point.y);
}
PackedByteArray NativeRegionalWater::placement_mask(const TypedArray<Transform3D> &transforms) const {
    PackedByteArray result;if(transforms.size()>512)return result;result.resize(transforms.size());for(int i=0;i<transforms.size();++i){Transform3D t=transforms[i];result.set(i,depth_at(t.origin)>0?1:0);}return result;
}
void NativeRegionalWater::preserve_mesh_region(Key k){
    if(!batch_active||mesh_snapshot.count(k)||mesh_snapshot_absent.count(k))return;
    auto found=regions.find(k);
    if(found==regions.end())mesh_snapshot_absent.insert(k);else mesh_snapshot.emplace(k,found->second);
}
const NativeRegionalWater::Region *NativeRegionalWater::surface_region(Key k,bool snapshot) const {
    if(snapshot){
        if(mesh_snapshot_absent.count(k))return nullptr;
        auto saved=mesh_snapshot.find(k);if(saved!=mesh_snapshot.end())return &saved->second;
    }
    auto live=regions.find(k);return live==regions.end()?nullptr:&live->second;
}
void NativeRegionalWater::cancel_mesh_batch(){
    if(!batch_active&&!publish_pending)return;
    for(Key k:batch_owners)if(mesh_set.insert(k).second)meshes.push_back(k);
    batch_active=false;publish_pending=false;staged_surfaces.clear();batch_queue.clear();batch_owners.clear();mesh_snapshot.clear();mesh_snapshot_absent.clear();
}
Dictionary NativeRegionalWater::next_mesh_batch(){
    Dictionary result;publication_enabled=true;
    if(publish_pending){result["batch"]=int64_t(batch_id);result["complete"]=true;return result;}
    if(!batch_active){
        if(meshes.empty())return result;
        batch_queue.swap(meshes);mesh_set.clear();batch_owners.assign(batch_queue.begin(),batch_queue.end());
        batch_active=true;++batch_id;
    }
    result["batch"]=int64_t(batch_id);result["complete"]=false;
    uint64_t start=Time::get_singleton()->get_ticks_usec();
    for(int attempt=0;attempt<8&&!batch_queue.empty();++attempt){
        Key k=batch_queue.front();batch_queue.pop_front();
        if(!surface_ready(k,true)){if(mesh_set.insert(k).second)meshes.push_back(k);continue;}
        SurfaceMesh mesh=build_surface(k,true);
        // Empty geometry only needs publication when retiring an existing mesh.
        if(mesh.vertices.is_empty()&&!published_surfaces.count(k))continue;
        Array arrays;arrays.resize(Mesh::ARRAY_MAX);
        arrays[Mesh::ARRAY_VERTEX]=mesh.vertices;arrays[Mesh::ARRAY_NORMAL]=mesh.normals;arrays[Mesh::ARRAY_TEX_UV]=mesh.uv;
        staged_surfaces[k]={mesh.vertices,std::move(mesh.owners)};
        result["coordinate"]=position(k);result["faces"]=mesh.faces;result["arrays"]=arrays;result["vertices"]=mesh.vertices.size();break;
    }
    if(batch_queue.empty()){
        result["complete"]=true;batch_active=false;publish_pending=true;mesh_snapshot.clear();mesh_snapshot_absent.clear();
    }
    mesh_us=Time::get_singleton()->get_ticks_usec()-start;max_mesh_us=std::max(max_mesh_us,mesh_us);return result;
}
bool NativeRegionalWater::commit_mesh_batch(int64_t id){
    if(!publish_pending||id<0||uint64_t(id)!=batch_id)return false;
    for(auto &[k,surface]:staged_surfaces){
        auto old=published_surfaces.find(k);
        if(old!=published_surfaces.end())query_cache_bytes-=uint64_t(old->second.vertices.size())*sizeof(Vector3)+old->second.owners.size()*sizeof(Vector3i);
        if(surface.vertices.is_empty())published_surfaces.erase(k);
        else{
            query_cache_bytes+=uint64_t(surface.vertices.size())*sizeof(Vector3)+surface.owners.size()*sizeof(Vector3i);
            published_surfaces[k]=std::move(surface);
        }
    }
    staged_surfaces.clear();batch_owners.clear();publish_pending=false;published_batch=batch_id;return true;
}
const NativeRegionalWater::QuerySurface *NativeRegionalWater::query_surface(Key k,QuerySurface &temporary) const {
    if(publication_enabled){
        auto found=published_surfaces.find(k);if(found==published_surfaces.end())return nullptr;
        ++query_cache_hits;return &found->second;
    }
    // Immediate native diagnostics have no renderer. The game enables published
    // queries with its first batch and never rebuilds geometry to target water.
    SurfaceMesh mesh=build_surface(k);++query_builds;
    temporary={mesh.vertices,std::move(mesh.owners)};return &temporary;
}
bool NativeRegionalWater::surface_ready(Key k,bool snapshot) const {
    Vector3i c=position(k);
    for(int z=-1;z<=1;++z)for(int y=-1;y<=1;++y)for(int x=-1;x<=1;++x){
        Vector3i n=c+Vector3i(x,y,z);if(n.x<0||n.y<0||n.z<0)continue;
        const Region *neighbour=surface_region(key(n),snapshot);if(neighbour&&!neighbour->valid)return false;
    }
    return true;
}
Dictionary NativeRegionalWater::raycast_surface(const Vector3 &from,const Vector3 &to) const {
    Dictionary result;result["hit"]=false;
    if(!from.is_finite()||!to.is_finite()||from.distance_to(to)>5.0)return result;
    Vector3 direction=to-from;if(direction.length_squared()<1e-12)return result;
    Vector3 low=from.min(to)-Vector3(0.5,0.5,0.5),high=from.max(to)+Vector3(0.5,0.5,0.5);
    Vector3i lo=Vector3i((low/4.0).floor()),hi=Vector3i((high/4.0).floor());
    double nearest=2.0;Vector3 point,normal;Vector3i owner;
    // The five-metre reach bounds the candidate owner box. Build from precisely
    // the rendering source; never use an independent shoreline polygon or level.
    for(int z=std::max(0,lo.z);z<=std::min(499,hi.z);++z)for(int y=std::max(0,lo.y);y<=std::min(63,hi.y);++y)for(int x=std::max(0,lo.x);x<=std::min(499,hi.x);++x){
        Key k=key(Vector3i(x,y,z));if(!surface_ready(k))continue;
        QuerySurface temporary;const QuerySurface *selected=query_surface(k,temporary);if(!selected)continue;const QuerySurface &mesh=*selected;
        for(int i=0;i<mesh.vertices.size();i+=3){
            Vector3 a=mesh.vertices[i],e1=mesh.vertices[i+1]-a,e2=mesh.vertices[i+2]-a;
            Vector3 h=direction.cross(e2);double determinant=e1.dot(h);if(std::abs(determinant)<1e-12)continue;
            double inverse=1.0/determinant;Vector3 offset=from-a;double u=offset.dot(h)*inverse;if(u< -1e-6||u>1.000001)continue;
            Vector3 q=offset.cross(e1);double v=direction.dot(q)*inverse;if(v< -1e-6||u+v>1.000001)continue;
            double t=e2.dot(q)*inverse;if(t<0||t>1||t>=nearest)continue;
            nearest=t;point=from+direction*t;normal=e2.cross(e1).normalized();owner=mesh.owners[i/3];
        }
    }
    if(nearest<=1){result["hit"]=true;result["point"]=point;result["normal"]=normal;result["cell"]=owner;}
    return result;
}
Dictionary NativeRegionalWater::next_mesh(){
    Dictionary result;if(meshes.empty())return result;uint64_t start=Time::get_singleton()->get_ticks_usec();
    // Invalid occupancy is unknown, not empty space. Retain the last published
    // surface until its bounded reconstruction neighbourhood is sampled again.
    // Rotate only a bounded number of entries so blocked shores do not starve
    // independent water or turn a frame into an unbounded queue scan.
    Key k=0;bool ready=false;const size_t attempts=std::min<size_t>(meshes.size(),8);
    for(size_t attempt=0;attempt<attempts;++attempt){
        k=meshes.front();meshes.pop_front();
        if(surface_ready(k)){ready=true;mesh_set.erase(k);break;}
        meshes.push_back(k);
    }
    if(!ready)return result;
    SurfaceMesh mesh=build_surface(k);
    result["coordinate"]=position(k);result["faces"]=mesh.faces;Array arrays;arrays.resize(Mesh::ARRAY_MAX);
    arrays[Mesh::ARRAY_VERTEX]=mesh.vertices;arrays[Mesh::ARRAY_NORMAL]=mesh.normals;arrays[Mesh::ARRAY_TEX_UV]=mesh.uv;result["arrays"]=arrays;result["vertices"]=mesh.vertices.size();
    mesh_us=Time::get_singleton()->get_ticks_usec()-start;max_mesh_us=std::max(max_mesh_us,mesh_us);return result;
}
NativeRegionalWater::SurfaceMesh NativeRegionalWater::build_surface(Key k,bool snapshot) const {
    SurfaceMesh output;auto &vertices=output.vertices;auto &normals=output.normals;auto &uv=output.uv;
    // The sole runtime mesher is the terrain surface-nets reconstruction. Water
    // supplies exact material crossings instead of losing thin volumes to a
    // fixed lattice's point samples. Quantities and simulation are not modified.
    struct Sample { Vector3 position; double bottom=0,top=0;uint16_t floor=0,ceiling=0;uint64_t amount=0; bool wet=false; };
    struct Representative { int cx,cy,cz;unsigned mask;Vector3 position;int next; };
    const Vector3i base=position(k)*8;
    std::array<Sample,10*10*10> samples;
    std::array<int,9*9*9> ids;ids.fill(-1);
    std::vector<Representative> representatives;representatives.reserve(256);
    auto sample_index=[](int x,int y,int z){return x+1+10*(y+1+10*(z+1));};
    auto vertex_index=[](int x,int y,int z){return x+1+9*(y+1+9*(z+1));};
    for(int z=-1;z<=8;++z)for(int y=-1;y<=8;++y)for(int x=-1;x<=8;++x){
        Vector3i p=base+Vector3i(x,y,z);Sample &sample=samples[sample_index(x,y,z)];
        sample.position=Vector3(p)*0.5+Vector3(0.25,0.25,0.25);
        if(!in_domain(p))continue;const Region *region=surface_region(region_key(p),snapshot);if(!region||!region->valid)continue;int i=index(p);
        auto interval=WaterSurfaceInterval::from_cell(p.y,region->floor[i],region->ceiling[i],region->water[i]);
        if(!interval.wet)continue;
        sample.wet=true;sample.bottom=interval.bottom;sample.top=interval.top;sample.floor=region->floor[i];sample.ceiling=region->ceiling[i];sample.amount=region->water[i];
        sample.position.y=(interval.bottom+interval.top)*0.5;
    }
    for(int z=-1;z<8;++z)for(int y=-1;y<8;++y)for(int x=-1;x<8;++x){
        const Sample *corners[8];unsigned signs=0;
        for(int c=0;c<8;++c){corners[c]=&samples[sample_index(x+(c&1),y+((c>>1)&1),z+((c>>2)&1))];if(corners[c]->wet)signs|=1u<<c;}
        if(!signs)continue;
        unsigned components[8];int count=surface_components(signs,components,[&](int a,int b){
            const Sample &first=*corners[a],&second=*corners[b];
            if((a^b)==2){const Sample &lower=(a&2)?second:first,&upper=(a&2)?first:second;
                return lower.ceiling==500&&upper.floor==0&&lower.amount>=uint64_t(lower.ceiling-lower.floor)*250;}
            return water_intervals_joined(first.floor,first.ceiling,first.amount,second.floor,second.ceiling,second.amount);
        });
        for(int component=0;component<count;++component){
            unsigned mask=components[component];if(mask==255)continue;
            Vector3 point=surface_crossing_vertex<Vector3>(mask,[&](Vector3 sum,int a,int b){
                const Sample &wet=*corners[(mask&(1u<<a))?a:b];
                const Sample &dry=*corners[(mask&(1u<<a))?b:a];
                Vector3 crossing=wet.position;
                if((a^b)==2)crossing.y=dry.position.y>wet.position.y?wet.top:wet.bottom;
                else if((a^b)==1)crossing.x=(wet.position.x+dry.position.x)*0.5;
                else crossing.z=(wet.position.z+dry.position.z)*0.5;
                return sum+crossing;
            });
            int &head=ids[vertex_index(x,y,z)];
            representatives.push_back({x,y,z,mask,point,head});head=int(representatives.size())-1;
        }
    }
    int triangles=0,tops=0,bottoms=0,sides=0,tiny=0,small=0,medium=0,large=0;double max_side=0;
    connect_material_surface(int(representatives.size()),{0,8,0,8,0,8},
        [&](int i)->const Representative&{return representatives[i];},
        [&](int x,int y,int z,int ax,int ay,int az){
            if(x< -1||x>=8||y< -1||y>=8||z< -1||z>=8)return -1;
            int dx=ax-x,dy=ay-y,dz=az-z;if(dx<0||dx>1||dy<0||dy>1||dz<0||dz>1)return -1;
            unsigned bit=1u<<(dx+2*dy+4*dz);
            for(int id=ids[vertex_index(x,y,z)];id>=0;id=representatives[id].next)if(representatives[id].mask&bit)return id;
            return -1;
        },
        [&](int a,int b,int c,int d,bool reverse){
            const auto &origin=representatives[c];Vector3i owner=base+Vector3i(origin.cx,origin.cy,origin.cz);
            if(!(origin.mask&1)){
                const auto &first=representatives[a];const auto &second=representatives[b];const auto &last=representatives[d];
                if(first.cx==origin.cx&&second.cx==origin.cx&&last.cx==origin.cx)++owner.x;
                else if(first.cy==origin.cy&&second.cy==origin.cy&&last.cy==origin.cy)++owner.y;
                else ++owner.z;
            }
            surface_quad(a,b,c,d,reverse,[&](int i){return representatives[i].position;},
                [&](int i,int j,int l){
                    Vector3 a=representatives[i].position,b=representatives[j].position,c=representatives[l].position;
                    Vector3 n=(c-a).cross(b-a).normalized();if(n.length_squared()<0.5)return;
                    for(Vector3 p:{a,b,c}){vertices.push_back(p);normals.push_back(n);uv.push_back(Vector2(p.x,p.z));}
                    output.owners.push_back(owner);++triangles;
                    if(std::abs(n.y)<0.001){
                        ++sides;double height=std::max({a.y,b.y,c.y})-std::min({a.y,b.y,c.y});max_side=std::max(max_side,height);
                        if(height<0.0011)++tiny;else if(height<0.01)++small;else if(height<0.1)++medium;else ++large;
                    }else if(n.y>0)++tops;else ++bottoms;
                });
        });
    Dictionary faces;faces["top"]=tops;faces["bottom"]=bottoms;faces["shore_triangles"]=0;faces["side"]=sides;faces["side_under_1mm"]=tiny;
    faces["side_under_1cm"]=small;faces["side_under_10cm"]=medium;faces["side_larger"]=large;faces["max_side_height"]=max_side;
    faces["shared_surface_nets"]=true;faces["triangles"]=triangles;output.faces=faces;
    return output;
}
Dictionary NativeRegionalWater::statistics() const {
    Dictionary d;d["pending_vertical"]=int64_t(vertical.size());d["vertical_steps"]=int64_t(vertical_steps);d["water_ml"]=int64_t(total);d["active_cells"]=int64_t(active.size());d["regions"]=int64_t(regions.size());d["pending_regions"]=int64_t(requests.size());d["dirty_meshes"]=int64_t(meshes.size()+batch_queue.size());d["mesh_batch_active"]=batch_active;d["mesh_publish_pending"]=publish_pending;d["published_mesh_batch"]=int64_t(published_batch);d["query_cache_bytes"]=int64_t(query_cache_bytes);d["query_builds"]=int64_t(query_builds);d["query_cache_hits"]=int64_t(query_cache_hits);d["mesh_snapshot_bytes"]=int64_t(mesh_snapshot.size()*sizeof(Region));d["fill_active"]=fill.running;d["fill_remaining_ml"]=fill.remaining;d["sampled_nodes"]=int64_t(sampled);d["cache_hits"]=int64_t(cache_hits);d["cached_region_rebuilds"]=int64_t(cache_rebuilds);d["cell_steps"]=int64_t(steps);d["changes"]=int64_t(changes);d["step_us"]=int64_t(last_us);d["max_step_us"]=int64_t(max_us);d["mesh_us"]=int64_t(mesh_us);d["max_mesh_us"]=int64_t(max_mesh_us);d["capacity_reached"]=limit;d["resident_cell_bytes"]=int64_t(regions.size()*sizeof(Region));return d;
}
// Self-contained compound snapshot: authoritative amounts + derived occupancy.
// Occupancy is valid only for the terrain captured in the SAME world archive.
// Accepted edits invalidate it before capture. Invalid regions are re-sampled on
// reopen. All data has strict bounds; the outer world archive supplies checksums.
static constexpr uint32_t MAGIC=0x31575256,OLD_REGION_BYTES=16+512*12,REGION_BYTES=OLD_REGION_BYTES+729*4;
PackedByteArray NativeRegionalWater::capture_snapshot(const PackedByteArray &catalog) const {
    PackedByteArray out;Ref<NativeLakeCatalog> validator;validator.instantiate();if(fill.running||!validator->validate_snapshot(catalog))return out;
    out.resize(32+catalog.size()+regions.size()*REGION_BYTES);out.encode_u32(0,MAGIC);out.encode_u32(4,2);out.encode_u32(8,catalog.size());out.encode_u32(12,regions.size());out.encode_u64(16,total);out.encode_u64(24,0);
    for(int i=0;i<catalog.size();++i)out.set(32+i,catalog[i]);int64_t offset=32+catalog.size();
    for(const auto &[k,r]:regions){out.encode_u64(offset,k);out.encode_u32(offset+8,r.valid?1:0);out.encode_u32(offset+12,r.has_density?1:0);offset+=16;
        for(int i=0;i<512;++i){out.encode_u16(offset,r.floor[i]);out.encode_u16(offset+2,r.ceiling[i]);out.encode_u64(offset+4,r.water[i]|(r.water[i]&&active_set.count(key(position(k)*8+Vector3i(i%8,(i/8)%8,i/64)))?(uint64_t(1)<<63):0));offset+=12;}
        for(float value:r.density){out.encode_float(offset,value);offset+=4;}}
    return out;
}
bool NativeRegionalWater::decode(const PackedByteArray &data,bool install){
    if(data.size()<32||data.decode_u32(0)!=MAGIC||(data.decode_u32(4)!=1&&data.decode_u32(4)!=2)||data.decode_u64(24)!=0)return false;
    const bool shaped=data.decode_u32(4)==2;
    const uint32_t record_bytes=shaped?REGION_BYTES:OLD_REGION_BYTES;
    uint32_t bytes=data.decode_u32(8),count=data.decode_u32(12);uint64_t expected=data.decode_u64(16);
    if(bytes>1100000||count>MAX_REGIONS||expected>MAX_TOTAL||data.size()!=32+int64_t(bytes)+int64_t(count)*record_bytes)return false;
    Ref<NativeLakeCatalog> validator;validator.instantiate();if(!validator->validate_snapshot(data.slice(32,32+bytes)))return false;
    std::map<Key,Region> staged;std::vector<Key> awake;int64_t offset=32+bytes;uint64_t sum=0;Key previous=0;
    for(uint32_t n=0;n<count;++n){Key k=data.decode_u64(offset);uint32_t valid=data.decode_u32(offset+8),shape=data.decode_u32(offset+12);Vector3i p=position(k);
        if(k!=key(p)||(n&&k<=previous)||p.x>=500||p.z>=500||p.y>=64||valid>1||shape>(shaped?1u:0u))return false;previous=k;offset+=16;
        Region r;r.valid=valid;r.has_density=shape;
        for(int i=0;i<512;++i){r.floor[i]=data.decode_u16(offset);r.ceiling[i]=data.decode_u16(offset+2);r.water[i]=data.decode_u64(offset+4);if(r.water[i]>>63){if(install)awake.push_back(key(p*8+Vector3i(i%8,(i/8)%8,i/64)));r.water[i]&=~(uint64_t(1)<<63);if(!r.water[i])return false;}offset+=12;
            if(r.floor[i]>r.ceiling[i]||r.ceiling[i]>500||r.water[i]>MAX_TOTAL-sum)return false;sum+=r.water[i];}
        if(shaped)for(float &value:r.density){value=data.decode_float(offset);offset+=4;if(!std::isfinite(value))return false;}
        if(install)staged.emplace(k,std::move(r));
    }
    if(sum!=expected)return false;if(!install)return true;
    cancel_mesh_batch();published_surfaces.clear();published_batch=0;query_cache_bytes=0;query_builds=0;query_cache_hits=0;regions.swap(staged);vertical.clear();vertical_set.clear();vertical_regions.clear();vertical_steps=0;restored_cache.clear();cache_rebuilds=0;active.clear();active_set.clear();requests.clear();request_set.clear();meshes.clear();mesh_set.clear();fill=Fill{};total=sum;sampled=0;cache_hits=0;steps=0;changes=0;last_us=max_us=mesh_us=max_mesh_us=0;limit=false;
    for(auto &[k,r]:regions){if(r.valid){++cache_hits;restored_cache.insert(k);}else request(k);
        // Version 1 remains playable during one-time terrain-shape cache upgrade.
        if(!r.has_density)request(k);
        if(mesh_set.insert(k).second)meshes.push_back(k);
        // A face is owned by the minimum endpoint of a crossing edge. A wet
        // boundary node can therefore add only its negative-axis neighbour,
        // not every region in a 3x3x3 reconstruction halo.
        bool negative[3]={false,false,false};
        for(int i=0;i<512;++i)if(r.water[i]&&r.floor[i]<r.ceiling[i]){
            if((i&7)==0)negative[0]=true;
            if(((i>>3)&7)==0)negative[1]=true;
            if((i>>6)==0)negative[2]=true;
        }
        Vector3i p=position(k);
        for(int axis=0;axis<3;++axis)if(negative[axis]&&p[axis]>0){
            Vector3i n=p;--n[axis];Key owner=key(n);if(mesh_set.insert(owner).second)meshes.push_back(owner);
        }
    }
    for(Key k:awake){Vector3i p=position(k);wake(p);queue_vertical(p);queue_vertical(p+Vector3i(0,-1,0));}
    return true;
}
bool NativeRegionalWater::restore_snapshot(const PackedByteArray &data){return decode(data,true);}
bool NativeRegionalWater::validate_snapshot(const PackedByteArray &data) const {
    if(data.size()>=4&&data.decode_u32(0)==MAGIC){return const_cast<NativeRegionalWater*>(this)->decode(data,false);}Ref<NativeLakeCatalog> legacy;legacy.instantiate();return legacy->validate_snapshot(data);
}
PackedByteArray NativeRegionalWater::snapshot_catalog(const PackedByteArray &data) const {
    if(!validate_snapshot(data))return PackedByteArray();return data.decode_u32(0)==MAGIC?data.slice(32,32+data.decode_u32(8)):data;
}
}
