// SPDX-License-Identifier: 0BSD
#include "regional_water.hpp"
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
        it=regions.emplace(k,Region{}).first;
    }
    if(!it->second.valid){if(ask)request(k);return nullptr;}
    return &it->second;
}
const NativeRegionalWater::Region *NativeRegionalWater::get(const Vector3i &p) const {
    if(!in_domain(p))return nullptr;auto it=regions.find(region_key(p));return it!=regions.end()&&it->second.valid?&it->second:nullptr;
}
void NativeRegionalWater::wake(const Vector3i &p){
    if(!in_domain(p))return;auto it=regions.find(region_key(p));
    if(it!=regions.end()&&it->second.water[index(p)]&&active_set.insert(key(p)).second)active.push_back(key(p));
}
void NativeRegionalWater::changed(const Vector3i &p){
    ++changes;wake(p);Key k=region_key(p);if(mesh_set.insert(k).second)meshes.push_back(k);
    // Surface components span three layer changes plus the full cell below.
    // Dirty that bounded halo, including diagonal and vertical region corners.
    Vector3i lo=position(region_key(Vector3i(std::max(p.x-1,0),std::max(p.y-4,0),std::max(p.z-1,0))));
    Vector3i hi=position(region_key(Vector3i(std::min(p.x+1,3999),std::min(p.y+4,508),std::min(p.z+1,3999))));
    for(int z=lo.z;z<=hi.z;++z)for(int y=lo.y;y<=hi.y;++y)for(int x=lo.x;x<=hi.x;++x){Key other=key(Vector3i(x,y,z));
        if(other!=k&&regions.count(other)&&mesh_set.insert(other).second)meshes.push_back(other);}
    for(const Vector3i &d:directions){Vector3i n=p+d;if(!in_domain(n))continue;wake(n);Key other=region_key(n);
        if(other!=k&&regions.count(other)&&mesh_set.insert(other).second)meshes.push_back(other);}
}
Dictionary NativeRegionalWater::next_request(){
    Dictionary d;if(requests.empty())return d;Key k=requests.front();
    // Keep reservation until accepted. A stale worker can simply retry it.
    d["coordinate"]=position(k);return d;
}
bool NativeRegionalWater::accept_patch(const Ref<NativeWaterTerrainPatch> &patch){
    if(patch.is_null()||patch->status!=1)return false;Key k=key(patch->coord);auto it=regions.find(k);if(it==regions.end())return false;
    if(restored_cache.count(k))++cache_rebuilds;
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
    for(auto &[k,r]:regions)if(AABB(Vector3(position(k))*4.0,Vector3(4,4,4)).intersects(bounds.grow(0.5))){r.valid=false;request(k);}
}
void NativeRegionalWater::move(const Vector3i &a,const Vector3i &b,uint64_t amount){
    if(!amount)return;regions.at(region_key(a)).water[index(a)]-=amount;regions.at(region_key(b)).water[index(b)]+=amount;changed(a);changed(b);
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
        if(fill.remaining>0){Vector3i p=position(fill.seed);auto it=regions.find(region_key(p));if(it!=regions.end()){it->second.water[index(p)]+=fill.remaining;total+=fill.remaining;changed(p);fill.remaining=0;}}
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
        else{if(active.empty())break;Key k=active.front();active.pop_front();active_set.erase(k);process_cell(position(k));++steps;}
        if((n&31)==31&&Time::get_singleton()->get_ticks_usec()-start>=1000)break;
    }
    last_us=Time::get_singleton()->get_ticks_usec()-start;max_us=std::max(max_us,last_us);
}
int64_t NativeRegionalWater::remove_bounds(const AABB &bounds){
    if(fill.running||!bounds.position.is_finite()||!bounds.size.is_finite())return 0;
    uint64_t removed=0;
    for(auto &[k,r]:regions){Vector3i base=position(k)*8;if(!AABB(Vector3(base)*0.5,Vector3(4,4,4)).intersects(bounds))continue;
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
        auto it=regions.find(region_key(p));if(it==regions.end())continue;uint64_t &v=it->second.water[index(p)];uint64_t take=std::min(v,requested-removed);if(take){v-=take;total-=take;removed+=take;changed(p);}if(removed==requested)return removed;}
    return int64_t(removed);
}
Dictionary NativeRegionalWater::transfer_litre(const Vector3 &from,const Vector3 &to,bool pour,Object *inventory,int64_t slot,int64_t revision){
    Dictionary out;out["ok"]=false;out["pending"]=false;
    if(fill.running||!from.is_finite()||!to.is_finite()||from.distance_to(to)>5||!inventory||!inventory->has_method("exchange_bucket")){out["reason"]="Water is preparing, or target is out of reach";return out;}
    Vector3i target=cell(to);bool hit=false;
    for(int i=0;i<=100;++i){Vector3 p=from.lerp(to,i/100.0);Vector3i c=cell(p);const Region *r=get(c);
        if(!r||!r->water[index(c)]||r->floor[index(c)]==r->ceiling[index(c)])continue;
        int j=index(c);double top=c.y*0.5+r->floor[j]*0.001+std::min(r->water[j],uint64_t(r->ceiling[j]-r->floor[j])*250)/250000.0;
        bool intersects=depth_at(p)>0;
        // Analytic surface crossing catches a thin one-litre puddle between
        // ray-march samples without picking dry air above it or buried water.
        if(std::abs(to.y-from.y)>0.000001){double t=(top-from.y)/(to.y-from.y);Vector3 q=from.lerp(to,t);
            intersects|=t>=0&&t<=1&&q.x>=c.x*0.5&&q.x<(c.x+1)*0.5&&q.z>=c.z*0.5&&q.z<(c.z+1)*0.5;}
        if(intersects){target=c;hit=true;break;}}
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
                else{int opening=std::max(other->floor[j],next->floor[n]);connected=opening<std::min(other->ceiling[j],next->ceiling[n])&&int64_t(other->floor[j])*250+other->water[j]>uint64_t(opening)*250&&int64_t(next->floor[n])*250+next->water[n]>uint64_t(opening)*250;}
                if(connected&&visited.insert(key(q)).second)candidates.push_back(q);
            }
        }
        if(remaining){out["reason"]="Less than one litre within bucket reach";return out;}
    }
    if(pour&&(r->ceiling[i]==r->floor[i]||total>MAX_TOTAL-1000)){out["reason"]="Aim at open space just above terrain";return out;}
    if(!bool(inventory->call("exchange_bucket",slot,pour,revision))){out["reason"]="Bucket full / empty, or selected item changed";return out;}
    if(pour){r->water[i]+=1000;total+=1000;}else{for(const auto &[p,amount]:take){regions.at(region_key(p)).water[index(p)]-=amount;changed(p);}total-=1000;}
    changed(target);out["ok"]=true;out["reason"]=pour?"Poured 1 L":"Scooped 1 L";out["point"]=Vector3(target)*0.5;return out;
}
Vector3 NativeRegionalWater::surface_near(const Vector3 &point,double radius) const {
    Vector3 best(INFINITY,INFINITY,INFINITY);if(!point.is_finite()||!std::isfinite(radius)||radius<0||radius>3)return best;
    Vector3i lo=cell(point-Vector3(radius,radius,radius)),hi=cell(point+Vector3(radius,radius,radius));double distance=radius*radius;
    for(int z=lo.z;z<=hi.z;++z)for(int y=lo.y;y<=hi.y;++y)for(int x=lo.x;x<=hi.x;++x){Vector3i p(x,y,z);const Region *r=get(p);if(!r)continue;int i=index(p);if(!r->water[i]||r->ceiling[i]==r->floor[i])continue;
        double top=y*0.5+r->floor[i]*0.001+std::min(r->water[i],uint64_t(r->ceiling[i]-r->floor[i])*250)/250000.0;
        Vector3 q((x+0.5)*0.5,top,(z+0.5)*0.5);if(depth_at(q+Vector3(0,0.0001,0))>0)continue;
        double d=point.distance_squared_to(q);if(d<distance){distance=d;best=q;}}
    return best;
}

double NativeRegionalWater::depth_at(const Vector3 &point) const {
    if(!point.is_finite())return 0;Vector3i p=cell(point);const Region *r=get(p);if(!r)return 0;int i=index(p);if(!r->water[i])return 0;
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
Dictionary NativeRegionalWater::next_mesh(){
    Dictionary result;if(meshes.empty())return result;uint64_t start=Time::get_singleton()->get_ticks_usec();Key k=meshes.front();meshes.pop_front();mesh_set.erase(k);
    result["coordinate"]=position(k);Array arrays;arrays.resize(Mesh::ARRAY_MAX);
    PackedVector3Array vertices,normals;PackedVector2Array uv;
    int top_count=0,side_count=0,tiny_count=0,small_count=0,medium_count=0,large_count=0;double max_side=0;
    auto face=[&](Vector3 a,Vector3 b,Vector3 c,Vector3 d,Vector3 n){
        ++side_count;double height=std::max({a.y,b.y,c.y,d.y})-std::min({a.y,b.y,c.y,d.y});max_side=std::max(max_side,height);
        if(height<0.0011)++tiny_count;else if(height<0.01)++small_count;else if(height<0.1)++medium_count;else ++large_count;
        for(Vector3 p:{a,b,c,a,c,d}){vertices.push_back(p);normals.push_back(n);uv.push_back(Vector2(p.x,p.z));}};
    // Reconstruct one shared corner from face-connected surface cells. The
    // component is selected through wet openings, never merely diagonal contact.
    // No state mutation or terrain sampling: this is the regional volume's mesh.
    auto surface=[&](const Vector3i &p,double &height)->bool {
        const Region *r=get(p);if(!r)return false;int i=index(p);
        if(!r->water[i]||r->floor[i]==r->ceiling[i])return false;
        height=p.y*0.5+r->floor[i]*0.001+std::min(r->water[i],uint64_t(r->ceiling[i]-r->floor[i])*250)/250000.0;
        Vector3i q=p+Vector3i(0,1,0);const Region *above=get(q);
        return !(height>=(p.y+1)*0.5-0.00001&&above&&above->floor[index(q)]==0&&above->water[index(q)]);
    };
    auto joined=[&](const Vector3i &a,const Vector3i &b)->bool {
        const Region *ra=get(a),*rb=get(b);if(!ra||!rb)return false;
        int ia=index(a),ib=index(b);int opening=std::max(ra->floor[ia],rb->floor[ib]);
        if(opening>=std::min(ra->ceiling[ia],rb->ceiling[ib]))return false;
        return int64_t(ra->floor[ia])*250+int64_t(ra->water[ia])>opening*250 &&
               int64_t(rb->floor[ib])*250+int64_t(rb->water[ib])>opening*250;
    };
    auto surface_joined=[&](const Vector3i &a,const Vector3i &b)->bool {
        if(a.y==b.y)return joined(a,b);
        if(std::abs(a.y-b.y)!=1)return false;
        Vector3i high=a.y>b.y?a:b,low=a.y>b.y?b:a,under=high+Vector3i(0,-1,0);
        const Region *h=get(high),*u=get(under);if(!h||!u||h->floor[index(high)]!=0)return false;
        int i=index(under);uint64_t cap=uint64_t(u->ceiling[i]-u->floor[i])*250;
        return cap>0&&u->ceiling[i]==500&&u->water[i]>=cap&&joined(under,low);
    };
    // Cache each owner/corner result on this mesh's bounded halo. No per-corner
    // heap allocation, global surface search, or dependency on iteration order.
    Vector3i mesh_base=position(k)*8;
    std::array<double,9*9*14*4> corner_cache;corner_cache.fill(NAN);
    auto cache_index=[&](const Vector3i &owner,int cx,int cz)->int {
        int x=cx-mesh_base.x,z=cz-mesh_base.z,y=owner.y-mesh_base.y+3;
        int quadrant=(owner.x==cx?1:0)+(owner.z==cz?2:0);
        return x>=0&&x<9&&z>=0&&z<9&&y>=0&&y<14?x+9*z+81*y+81*14*quadrant:-1;
    };
    auto corner=[&](const Vector3i &owner,int cx,int cz,double fallback)->double {
        int cached=cache_index(owner,cx,cz);if(cached>=0&&std::isfinite(corner_cache[cached]))return corner_cache[cached];
        Vector3i cells[4];double heights[4];bool columns[4]{};int head=0,tail=1;bool ambiguous=false;
        cells[0]=owner;heights[0]=fallback;columns[(owner.x==cx?1:0)+(owner.z==cz?2:0)]=true;
        while(head<tail&&!ambiguous){Vector3i current=cells[head++];
            Vector3i neighbours[2]={Vector3i(current.x==cx?cx-1:cx,current.y,current.z),Vector3i(current.x,current.y,current.z==cz?cz-1:cz)};
            for(Vector3i q:neighbours)for(int dy=-1;dy<=1;++dy){Vector3i candidate=q+Vector3i(0,dy,0);double height=0;
                bool seen=false;for(int i=0;i<tail;++i)if(cells[i]==candidate){seen=true;break;}
                if(seen||!surface(candidate,height)||!surface_joined(current,candidate))continue;
                int column=(candidate.x==cx?1:0)+(candidate.z==cz?2:0);
                // Multiple surfaces in one column indicate an overhang/stacked
                // body: retain distinct interfaces rather than collapsing them.
                if(columns[column]||tail==4){ambiguous=true;break;}
                columns[column]=true;cells[tail]=candidate;heights[tail++]=height;
            }
        }
        double value=fallback;if(!ambiguous){value=0;for(int i=0;i<tail;++i)value+=heights[i];value/=tail;}
        if(!ambiguous)for(int i=0;i<tail;++i){int index=cache_index(cells[i],cx,cz);if(index>=0)corner_cache[index]=value;}
        else if(cached>=0)corner_cache[cached]=fallback;
        return value;
    };
    auto triangle=[&](Vector3 a,Vector3 b,Vector3 c){Vector3 n=(c-a).cross(b-a).normalized();
        for(Vector3 p:{a,b,c}){vertices.push_back(p);normals.push_back(n);uv.push_back(Vector2(p.x,p.z));}};
    auto it=regions.find(k);Vector3i base=position(k)*8;
    if(it!=regions.end()&&it->second.valid)for(int i=0;i<512;++i){const Region &r=it->second;if(!r.water[i]||r.floor[i]==r.ceiling[i])continue;
        Vector3i p=base+Vector3i(i%8,(i/8)%8,i/64);double x=p.x*0.5,z=p.z*0.5,bottom=p.y*0.5+r.floor[i]*0.001;
        double top=bottom+std::min(r.water[i],uint64_t(r.ceiling[i]-r.floor[i])*250)/250000.0;
        const Region *above=get(p+Vector3i(0,1,0));bool covered=top>=(p.y+1)*0.5-0.00001&&above&&above->floor[index(p+Vector3i(0,1,0))]==0&&above->water[index(p+Vector3i(0,1,0))];
        double h00=top,h10=top,h11=top,h01=top;
        if(!covered){
            ++top_count;h00=corner(p,p.x,p.z,top);h10=corner(p,p.x+1,p.z,top);
            h11=corner(p,p.x+1,p.z+1,top);h01=corner(p,p.x,p.z+1,top);
            triangle(Vector3(x,h00,z),Vector3(x+0.5,h10,z),Vector3(x+0.5,h11,z+0.5));
            triangle(Vector3(x,h00,z),Vector3(x+0.5,h11,z+0.5),Vector3(x,h01,z+0.5));
        }
        for(int d=1;d<=4;++d){Vector3i q=p+directions[d];const Region *neighbour=get(q);double low=bottom;
            if(neighbour){int j=index(q);if(neighbour->floor[j]==neighbour->ceiling[j])continue;low=std::max(low,q.y*0.5+neighbour->floor[j]*0.001+std::min(neighbour->water[j],uint64_t(neighbour->ceiling[j]-neighbour->floor[j])*250)/250000.0);}
            if(top-low<0.00001)continue;
            // An upper surface can close a side belonging to its full cell
            // below. Resolve both ends of that edge before dropping the wall.
            Vector3i owner=p;double owner_height=top;bool has_surface=!covered;
            if(covered){owner=p+Vector3i(0,1,0);has_surface=surface(owner,owner_height);}
            bool shared=false;
            if(has_surface){
                int cx0=p.x+(d==1?1:0),cz0=p.z+(d==3?1:0);
                int cx1=cx0+(d>=3?1:0),cz1=cz0+(d<=2?1:0);
                for(int dy=-1;dy<=1&&!shared;++dy){Vector3i other(q.x,owner.y+dy,q.z);double height=0;
                    if(!surface(other,height)||!surface_joined(owner,other))continue;
                    shared=std::abs(corner(owner,cx0,cz0,owner_height)-corner(other,cx0,cz0,height))<0.000001&&
                           std::abs(corner(owner,cx1,cz1,owner_height)-corner(other,cx1,cz1,height))<0.000001;
                }
            }
            if(shared)continue;
            if(d==1)face(Vector3(x+0.5,low,z),Vector3(x+0.5,h10,z),Vector3(x+0.5,h11,z+0.5),Vector3(x+0.5,low,z+0.5),Vector3(1,0,0));
            if(d==2)face(Vector3(x,low,z+0.5),Vector3(x,h01,z+0.5),Vector3(x,h00,z),Vector3(x,low,z),Vector3(-1,0,0));
            if(d==3)face(Vector3(x+0.5,low,z+0.5),Vector3(x+0.5,h11,z+0.5),Vector3(x,h01,z+0.5),Vector3(x,low,z+0.5),Vector3(0,0,1));
            if(d==4)face(Vector3(x,low,z),Vector3(x,h00,z),Vector3(x+0.5,h10,z),Vector3(x+0.5,low,z),Vector3(0,0,-1));
        }
    }
    // Reconstruct the sub-cell shoreline omitted by conservative capacity.
    // Only a dry cell directly adjacent to a wet surface contributes; triangle
    // connectivity clips against the cached terrain field, never across solids.
    int shore_triangles=0;
    if(it!=regions.end()&&it->second.valid&&it->second.has_density){const Region &r=it->second;
        for(int z=0;z<8;++z)for(int y=0;y<8;++y)for(int x=0;x<8;++x){
            int i=x+8*y+64*z;if(r.water[i])continue;Vector3i p=base+Vector3i(x,y,z);
            bool wet[4]{};double levels[4]{};double level=0;int count=0;bool consistent=true;
            // Perimeter order matches the four center-fan triangles below.
            Vector3i offsets[4]={{0,0,-1},{1,0,0},{0,0,1},{-1,0,0}};
            for(int d=0;d<4;++d){wet[d]=surface(p+offsets[d],levels[d]);
                if(wet[d]){if(count&&std::abs(level/count-levels[d])>0.002)consistent=false;level+=levels[d];++count;}}
            if(!count||!consistent)continue;level/=count;
            double t=(level-p.y*0.5)*2.0;if(t<=0||t>1)continue;
            Vector3 points[5]={Vector3(p.x*0.5,level,p.z*0.5),Vector3((p.x+1)*0.5,level,p.z*0.5),
                Vector3((p.x+1)*0.5,level,(p.z+1)*0.5),Vector3(p.x*0.5,level,(p.z+1)*0.5),Vector3((p.x+0.5)*0.5,level,(p.z+0.5)*0.5)};
            double density[5]{};int dx[4]={0,1,1,0},dz[4]={0,0,1,1};
            for(int n=0;n<4;++n){int node=x+dx[n]+9*y+81*(z+dz[n]);density[n]=r.density[node]*(1-t)+r.density[node+9]*t;density[4]+=density[n]*0.25;}
            // This reconstructs a terrain-cut cell, not a free-air dry cell.
            // Never visually advance a flowing front ahead of its stored water.
            if(*std::min_element(density,density+4)>0||*std::max_element(density,density+4)<=0)continue;
            bool connected[4]{};int queue[4],head=0,tail=0;
            for(int d=0;d<4;++d)if(wet[d]&&(density[d]>0||density[(d+1)%4]>0)){connected[d]=true;queue[tail++]=d;}
            while(head<tail){int d=queue[head++];int neighbours[2]={(d+3)%4,(d+1)%4};int shared[2]={d,(d+1)%4};
                for(int n=0;n<2;++n)if(!connected[neighbours[n]]&&(density[4]>0||density[shared[n]]>0)){
                    connected[neighbours[n]]=true;queue[tail++]=neighbours[n];}}
            for(int d=0;d<4;++d)if(connected[d]){
                int ids[3]={d,(d+1)%4,4};Vector3 clipped[4];int size=0;
                for(int n=0;n<3;++n){int a=ids[n],b=ids[(n+1)%3];bool inside_a=density[a]>0,inside_b=density[b]>0;
                    if(inside_a)clipped[size++]=points[a];
                    if(inside_a!=inside_b)clipped[size++]=points[a].lerp(points[b],density[a]/(density[a]-density[b]));}
                for(int n=1;n+1<size;++n)if((clipped[n]-clipped[0]).cross(clipped[n+1]-clipped[0]).length_squared()>1e-16){
                    triangle(clipped[0],clipped[n],clipped[n+1]);++shore_triangles;}
            }
        }
    }
    Dictionary faces;faces["top"]=top_count;faces["shore_triangles"]=shore_triangles;faces["side"]=side_count;faces["side_under_1mm"]=tiny_count;
    faces["side_under_1cm"]=small_count;faces["side_under_10cm"]=medium_count;faces["side_larger"]=large_count;faces["max_side_height"]=max_side;result["faces"]=faces;
    arrays[Mesh::ARRAY_VERTEX]=vertices;arrays[Mesh::ARRAY_NORMAL]=normals;arrays[Mesh::ARRAY_TEX_UV]=uv;result["arrays"]=arrays;result["vertices"]=vertices.size();
    mesh_us=Time::get_singleton()->get_ticks_usec()-start;max_mesh_us=std::max(max_mesh_us,mesh_us);return result;
}
Dictionary NativeRegionalWater::statistics() const {
    Dictionary d;d["water_ml"]=int64_t(total);d["active_cells"]=int64_t(active.size());d["regions"]=int64_t(regions.size());d["pending_regions"]=int64_t(requests.size());d["dirty_meshes"]=int64_t(meshes.size());d["fill_active"]=fill.running;d["fill_remaining_ml"]=fill.remaining;d["sampled_nodes"]=int64_t(sampled);d["cache_hits"]=int64_t(cache_hits);d["cached_region_rebuilds"]=int64_t(cache_rebuilds);d["cell_steps"]=int64_t(steps);d["changes"]=int64_t(changes);d["step_us"]=int64_t(last_us);d["max_step_us"]=int64_t(max_us);d["mesh_us"]=int64_t(mesh_us);d["max_mesh_us"]=int64_t(max_mesh_us);d["capacity_reached"]=limit;d["resident_cell_bytes"]=int64_t(regions.size()*sizeof(Region));return d;
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
    regions.swap(staged);restored_cache.clear();cache_rebuilds=0;active.clear();active_set.clear();requests.clear();request_set.clear();meshes.clear();mesh_set.clear();fill=Fill{};total=sum;sampled=0;cache_hits=0;steps=0;changes=0;last_us=max_us=mesh_us=max_mesh_us=0;limit=false;
    for(auto &[k,r]:regions){if(r.valid){++cache_hits;restored_cache.insert(k);}else request(k);
        // Version 1 remains playable during one-time terrain-shape cache upgrade.
        if(!r.has_density)request(k);
        if(mesh_set.insert(k).second)meshes.push_back(k);}
    for(Key k:awake)wake(position(k));
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
