// SPDX-License-Identifier: 0BSD
#include <map>
#include "regional_water.hpp"
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
#include <queue>
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
    if(boundary.is_empty()){
        PackedByteArray query;query.resize(24);query.encode_u32(0,32);query.encode_u32(4,rev);query.encode_u32(8,cancel);
        query.encode_u32(12,coord.x*4);query.encode_u32(16,coord.y*4);query.encode_u32(20,coord.z*4);
        boundary=core->call("execute",query);
        if(boundary.size()<28||boundary.decode_u32(0)!=0x32505254||boundary.decode_u32(8)||boundary.decode_u32(12)!=uint64_t(rev)||boundary.decode_u32(16)!=uint64_t(cancel))return status=-4;
        uint32_t vertices=boundary.decode_u32(20),indices=boundary.decode_u32(24);
        if(vertices>4096||indices>24576||indices%3||boundary.size()!=28+int64_t(vertices)*12+int64_t(indices)*4)return status=-2;
        for(uint32_t i=0;i<indices;++i)if(boundary.decode_u32(28+vertices*12+i*4)>=vertices)return status=-2;
    }
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
    // Explicit one-metre terrain cubes are separate from smooth density.
    // Query cell centres on the same pinned worker revision.
    PackedByteArray blocks;blocks.resize(12+512*12);blocks.encode_u32(0,33);blocks.encode_u32(4,rev);blocks.encode_u32(8,512);
    for(int i=0;i<512;++i){Vector3 p=Vector3(coord)*4.0+Vector3(i%8,(i/8)%8,i/64)*.5+Vector3(.25,.25,.25);
        blocks.encode_float(12+i*12,p.x);blocks.encode_float(16+i*12,p.y);blocks.encode_float(20+i*12,p.z);}
    PackedByteArray occupied=core->call("execute",blocks);
    if(!reply_ok(occupied,20+512*4)||occupied.decode_u32(12)!=uint64_t(rev))return status=-4;
    for(int i=0;i<512;++i)if(occupied.decode_float(20+i*4)>0)floor[i]=ceiling[i]=500;
    // Retain the terrain triangles themselves, clipped only in X/Z. No
    // conversion to another density grid or four-corner floor approximation.
    auto prepared=std::make_shared<TerrainWaterContacts>();
    const uint32_t vertices=boundary.decode_u32(20),indices=boundary.decode_u32(24);
    auto vertex=[&](uint32_t i){int at=28+12*i;return Vector3(boundary.decode_float(at),boundary.decode_float(at+4),boundary.decode_float(at+8));};
    using Point=WaterCellProfile::Point;using Triangle=WaterCellProfile::Triangle;
    for(int z=0;z<8;++z)for(int x=0;x<8;++x){
        std::vector<Triangle> column;double area=0,min_y=1e30,max_y=-1e30;
        for(uint32_t i=0;i<indices;i+=3){
            Point polygon[12],next[12];int count=3;
            for(int j=0;j<3;++j){Vector3 p=vertex(boundary.decode_u32(28+vertices*12+(i+j)*4));polygon[j]={(p.x-coord.x*4)*2-x,(p.z-coord.z*4)*2-z,p.y*1000};}
            double det=(polygon[1].x-polygon[0].x)*(polygon[2].z-polygon[0].z)-(polygon[1].z-polygon[0].z)*(polygon[2].x-polygon[0].x);
            if(det<=1e-10)continue; // Only floor-facing terrain; ceilings remain closed by occupancy.
            for(int plane=0;plane<4&&count;++plane){
                auto distance=[&](Point p){return plane==0?p.x:plane==1?1-p.x:plane==2?p.z:1-p.z;};
                int size=0;for(int j=0;j<count;++j){Point a=polygon[j],b=polygon[(j+1)%count];double av=distance(a),bv=distance(b);
                    if(av>=0)next[size++]=a;
                    if((av>=0)!=(bv>=0)){double t=av/(av-bv);next[size++]={a.x+t*(b.x-a.x),a.z+t*(b.z-a.z),a.y+t*(b.y-a.y)};}}
                count=size;std::copy(next,next+count,polygon);
            }
            for(int j=1;j+1<count;++j){Triangle t{polygon[0],polygon[j],polygon[j+1]};auto a=t[0],b=t[1],c=t[2];double part=std::abs((b.x-a.x)*(c.z-a.z)-(b.z-a.z)*(c.x-a.x))*0.5;
                if(part<1e-12)continue;area+=part;column.push_back(t);for(auto p:t){min_y=std::min(min_y,p.y);max_y=std::max(max_y,p.y);}}
        }
        // Multiple floors in one column and incomplete/vertical boundaries need
        // full solid clipping; never pretend their overlapping projections fit.
        if(std::abs(area-1)>1e-5||column.size()>128)continue;
        for(int y=0;y<8;++y){double bottom=(coord.y*8+y)*500.0;
            if(min_y>=bottom+1500||max_y<=bottom-1000)continue;
            float d[8];for(int c=0;c<8;++c)d[c]=density[x+(c&1)+9*(y+((c>>1)&1))+81*(z+((c>>2)&1))];
            int cell=x+8*y+64*z;if(floor[cell]==ceiling[cell])continue;auto original=WaterCellProfile::make(d,true,floor[cell],ceiling[cell]);if(!original.cut)continue;
            if(max_y<=bottom&&original.maximum()<=0&&original.ceiling==500)continue;
            if(min_y>=bottom+500&&original.capacity()==0)continue;
            auto &out=prepared->floors[cell];out=column;for(auto &t:out)for(auto &p:t)p.y-=bottom;
        }
    }
    prepared->bytes=sizeof(TerrainWaterContacts);for(const auto &cell:prepared->floors)prepared->bytes+=cell.capacity()*sizeof(WaterCellProfile::Triangle);
    if(prepared->bytes>sizeof(TerrainWaterContacts))contacts=prepared;
    boundary=PackedByteArray();
    return status=1;
}
Dictionary NativeWaterTerrainPatch::statistics() const {Dictionary d;d["status"]=status;d["coordinate"]=coord;d["sampled_nodes"]=cursor;return d;}

void NativeRegionalWater::_bind_methods(){
    ClassDB::bind_method(D_METHOD("cell_geometry","point"),&NativeRegionalWater::cell_geometry);
    ClassDB::bind_method(D_METHOD("next_request"),&NativeRegionalWater::next_request);
    ClassDB::bind_method(D_METHOD("accept_patch","patch"),&NativeRegionalWater::accept_patch);
    ClassDB::bind_method(D_METHOD("invalidate","bounds","replace_water"),&NativeRegionalWater::invalidate,DEFVAL(false));
    ClassDB::bind_method(D_METHOD("advance","budget","seconds"),&NativeRegionalWater::advance,DEFVAL(1.0/60.0));
    ClassDB::bind_method(D_METHOD("begin_fill","bounds","level","seed","amount"),&NativeRegionalWater::begin_fill);
    ClassDB::bind_method(D_METHOD("remove_bounds","bounds"),&NativeRegionalWater::remove_bounds);
    ClassDB::bind_method(D_METHOD("brush","point","radius","amount"),&NativeRegionalWater::brush);
    ClassDB::bind_method(D_METHOD("place_water","point","amount_ml"),&NativeRegionalWater::place_water);
    ClassDB::bind_method(D_METHOD("transfer_bucket","from","to","pour","inventory","slot","revision"),&NativeRegionalWater::transfer_water);
    ClassDB::bind_method(D_METHOD("surface_near","point","radius"),&NativeRegionalWater::surface_near);
    ClassDB::bind_method(D_METHOD("depth_at","point"),&NativeRegionalWater::depth_at);
    ClassDB::bind_method(D_METHOD("overlaps_occupied","bounds"),&NativeRegionalWater::overlaps_occupied);
    ClassDB::bind_method(D_METHOD("placement_mask","transforms"),&NativeRegionalWater::placement_mask);
    ClassDB::bind_method(D_METHOD("raycast_surface","from","to"),&NativeRegionalWater::raycast_surface);
    ClassDB::bind_method(D_METHOD("commit_mesh_batch","id"),&NativeRegionalWater::commit_mesh_batch);
    ClassDB::bind_method(D_METHOD("next_mesh_batch"),&NativeRegionalWater::next_mesh_batch);
    ClassDB::bind_method(D_METHOD("next_mesh","include_contacts"),&NativeRegionalWater::next_mesh,DEFVAL(false));
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
WaterCellProfile NativeRegionalWater::surface_profile(const Vector3i &p,bool snapshot) const {
    const Region *r=surface_region(region_key(p),snapshot);
    if(!r||!r->valid)return WaterCellProfile::make(nullptr,false,500,500);
    // Static material has an explicit local fill height. Neighbour edits must
    // not tilt an unchanged cell's surface or silently change its connections.
    return profile(*r,index(p));
}
void NativeRegionalWater::changed(const Vector3i &p){
    ++changes;Key k=region_key(p);if(mesh_set.insert(k).second)meshes.push_back(k);
    // Reconstruction reads adjacent levels as well as the meshing halo. Owners may
    // be empty storage regions; they still own boundary triangles.
    Vector3i lo=position(region_key(Vector3i(std::max(p.x-2,0),std::max(p.y-1,0),std::max(p.z-2,0))));
    Vector3i hi=position(region_key(Vector3i(std::min(p.x+2,3999),std::min(p.y+1,508),std::min(p.z+2,3999))));
    for(int z=lo.z;z<=hi.z;++z)for(int y=lo.y;y<=hi.y;++y)for(int x=lo.x;x<=hi.x;++x){Key other=key(Vector3i(x,y,z));
        if(other!=k&&mesh_set.insert(other).second)meshes.push_back(other);}
    for(const Vector3i &d:directions){Vector3i n=p+d;if(!in_domain(n))continue;Key other=region_key(n);
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
    // Preserve the old water head while terrain occupancy is replaced. New
    // solid removes only water below that head; it must not push water upward.
    std::array<double,512> old_heads{};
    const bool had_shape=it->second.has_density&&it->second.replace_water;
    if(had_shape)for(int i=0;i<512;++i)if(it->second.water[i])old_heads[i]=profile(it->second,i).head(it->second.water[i]);
    it->second.density=patch->density;it->second.has_density=true;it->second.contacts=patch->contacts;
    if(mesh_set.insert(k).second)meshes.push_back(k);
    it->second.floor=patch->floor;it->second.ceiling=patch->ceiling;it->second.valid=true;sampled+=729;
    request_set.erase(k);requests.erase(std::remove(requests.begin(),requests.end(),k),requests.end());
    Vector3i base=patch->coord*8;
    for(int i=0;i<512;++i)if(it->second.water[i]){
        if(had_shape){
            auto shape=profile(it->second,i);
            uint64_t retained=uint64_t(std::max(0.0,std::round(shape.volume(old_heads[i]))));
            retained=std::min(it->second.water[i],retained);
            total-=it->second.water[i]-retained;it->second.water[i]=retained;
        }
        changed(base+Vector3i(i%8,(i/8)%8,i/64));
    }
    it->second.replace_water=false;
    prioritize_mesh(k);
    return true;
}
void NativeRegionalWater::invalidate(const AABB &bounds,bool replace_water){
    if(!bounds.position.is_finite()||!bounds.size.is_finite())return;
    cancel_mesh_batch();
    for(auto &[k,r]:regions)if(AABB(Vector3(position(k))*4.0,Vector3(4,4,4)).intersects(bounds.grow(0.5))){r.valid=false;r.replace_water|=replace_water;request(k);}
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
        // has less capacity. Excess remains owned; static water never auto-drains.
        if(fill.remaining>0){Vector3i p=position(fill.seed);auto it=regions.find(region_key(p));if(it!=regions.end()){preserve_mesh_region(region_key(p));it->second.water[index(p)]+=fill.remaining;total+=fill.remaining;changed(p);fill.remaining=0;}}
        fill.running=false;fill.seen.clear();fill.queue.clear();return;}
    Vector3i p=position(fill.queue.front());Region *r=get(p,true);if(!r)return;
    fill.queue.pop_front();int i=index(p);int head=fill.level-p.y*500;
    auto shape=profile(*r,i);uint64_t target=uint64_t(std::floor(shape.volume(head)));if(!target)return;
    if(target>r->water[i]){uint64_t add=target-r->water[i];if(fill.remaining>=0)add=std::min(add,uint64_t(fill.remaining));add=std::min(add,MAX_TOTAL-total);r->water[i]+=add;total+=add;if(fill.remaining>=0)fill.remaining-=add;changed(p);}
    bool retry=false;
    for(int direction=0;direction<6;++direction){Vector3i q=p+directions[direction];
        if(q.x<fill.low.x||q.x>=fill.high.x||q.y<fill.low.y||q.y>=fill.high.y||q.z<fill.low.z||q.z>=fill.high.z||q.y*500>=fill.level)continue;
        Region *other=get(q,true);if(!other){retry=true;continue;}int j=index(q);
        auto next=profile(*other,j);if(!next.capacity())continue;
        int axis=q.x!=p.x?0:2,side=q[axis]>p[axis];
        double opening=std::max(shape.opening(axis,side),next.opening(axis,1-side));
        bool connected=direction==0?(shape.open_bottom&&next.ceiling==500):direction==5?(shape.ceiling==500&&next.open_bottom):
            (opening<std::min(shape.ceiling,next.ceiling)&&head>opening);
        if(connected&&fill.seen.insert(key(q)).second)fill.queue.push_back(key(q));}
    // Revisit just this frontier after missing terrain arrives. Already assigned
    // amounts are idempotent; a disconnected air interval is never a fill edge.
    if(retry)fill.queue.push_back(key(p));
}
void NativeRegionalWater::advance(int64_t budget,double seconds){
    // Only authored lake preparation advances. Existing water never flows,
    // spills or settles; edits and bucket transfers are explicit operations.
    if(budget<1||budget>8192||!std::isfinite(seconds)||seconds<=0)return;
    last_us=0;if(!fill.running)return;
    uint64_t start=Time::get_singleton()->get_ticks_usec();
    for(int n=0;n<budget&&fill.running;++n){
        size_t before=fill.queue.size();process_fill();
        if(fill.running&&fill.queue.size()==before&&!requests.empty())break;
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
bool NativeRegionalWater::plan_connected_scoop(Placement &cells,uint64_t amount,Dictionary &out) const {
    // The caller supplies at most the existing 9^3 local connected cells, in
    // aim-priority order. Peel this body without stranding disconnected pieces.
    // Only the six edges incident to a trial cell need geometric reevaluation.
    struct Cell {Vector3i p;WaterCellProfile shape;uint64_t water;int neighbour[6];unsigned links=0;bool boundary=false;};
    std::vector<Cell> graph;graph.reserve(cells.size());std::unordered_map<Key,int> ids;
    uint64_t total_here=0;
    for(const auto &[p,water]:cells){ids[key(p)]=int(graph.size());graph.push_back({p,surface_profile(p),water,{-1,-1,-1,-1,-1,-1},0});total_here+=water;}
    if(total_here<amount){out["reason"]="Not enough connected water to fill one voxel unit";return false;}
    static constexpr int opposite[6]={5,2,1,4,3,0};
    auto connected=[&](int a,int b,int d,uint64_t av){
        const auto &x=graph[a];const auto &y=graph[b];if(!av||!y.water)return false;
        return d==0?joined_vertical(y.shape,y.water,x.shape,av):d==5?joined_vertical(x.shape,av,y.shape,y.water):
            joined(x.shape,av,y.shape,y.water,d<=2?0:2,d==1||d==3);
    };
    for(int n=0;n<int(graph.size());n++)for(int d=0;d<6;d++){
        Vector3i q=graph[n].p+directions[d];auto found=ids.find(key(q));
        if(found==ids.end()){
            const Region *outside=get(q);if(!outside||!outside->water[index(q)])continue;
            auto a=graph[n].shape,b=surface_profile(q);uint64_t av=graph[n].water,bv=outside->water[index(q)];
            bool linked=d==0?joined_vertical(b,bv,a,av):d==5?joined_vertical(a,av,b,bv):joined(a,av,b,bv,d<=2?0:2,d==1||d==3);
            graph[n].boundary|=linked;continue;
        }
        graph[n].neighbour[d]=found->second;
        if(connected(n,found->second,d,graph[n].water))graph[n].links|=1u<<d;
    }
    bool touches_outside=false;for(const auto &c:graph)touches_outside|=c.boundary;
    if(total_here==amount&&!touches_outside)return true;
    // Retain all connections leaving the bounded search. Connectivity inside
    // this local graph alone cannot prove that a distant body stays connected.
    std::vector<int> visited(graph.size(),0),queue(graph.size());int generation=0,alive=int(graph.size()),connectivity_visits=0;
    // Match the eight half-step density samples owned by each storage cell.
    // Geometric contact alone can be thinner than the rendered lattice.
    auto sample_mask=[](const WaterCellProfile &shape,uint64_t water){
        unsigned mask=0;if(!water)return mask;double head=shape.head(water);
        for(int i=0;i<8;i++){double x=(i&1)?.75:.25,z=(i&4)?.75:.25,y=(i&2)?375:125;
            if(shape.bottom(x,z)<y&&y<shape.surface(head,x,z))mask|=1u<<i;}
        return mask;
    };
    std::vector<unsigned> masks;for(const auto &c:graph)masks.push_back(sample_mask(c.shape,c.water));
    std::vector<int> sample_seen(graph.size()*8,0),sample_queue(graph.size()*8);int sample_generation=0;
    auto visible_connected=[&](int changed,unsigned replacement){
        ++sample_generation;int expected=0,head=0,count=0;
        for(int n=0;n<int(graph.size());n++){unsigned mask=n==changed?replacement:masks[n];
            for(int bit=0;bit<8;bit++)if(mask&(1u<<bit)){expected++;
                if(!count){sample_queue[count++]=n*8+bit;sample_seen[n*8+bit]=sample_generation;}}}
        while(head<count){
            if(++connectivity_visits>131072)return false;
            int node=sample_queue[head++],n=node/8,bit=node%8;
            for(int axis=0;axis<3;axis++)for(int step:{-1,1}){
                int target=n,next=bit^(1<<axis),side=(bit>>axis)&1;
                if((side==0&&step<0)||(side==1&&step>0)){
                    int d=axis==0?(step>0?1:2):axis==1?(step>0?5:0):(step>0?3:4);
                    target=graph[n].neighbour[d];if(target<0)continue;}
                unsigned mask=target==changed?replacement:masks[target];int id=target*8+next;
                if((mask&(1u<<next))&&sample_seen[id]!=sample_generation){sample_seen[id]=sample_generation;sample_queue[count++]=id;}
            }
        }
        // Legacy refill can leave less than one representable unit. Preserve
        // that saved quantity; normal whole-unit gameplay never takes this path.
        return count==expected&&(expected>0||(amount<1000000&&total_here-amount<1000000));
    };
    Placement selected;uint64_t remaining=amount;
    while(remaining){
        bool progress=false;
        for(int n=0;n<int(graph.size())&&remaining;n++){
            auto &c=graph[n];if(!c.water||c.boundary)continue;
            uint64_t debit=std::min(remaining,c.water),left=c.water-debit;unsigned trial=0;
            for(int d=0;d<6;d++)if(c.neighbour[d]>=0&&connected(n,c.neighbour[d],d,left))trial|=1u<<d;
            int expected=alive-(left==0),count=0,head=0;
            ++generation;
            for(int seed=0;seed<int(graph.size());seed++)if((seed==n?left:graph[seed].water)>0){queue[count++]=seed;visited[seed]=generation;break;}
            while(head<count){
                if(++connectivity_visits>131072){out["reason"]="Scoop connectivity limit reached; aim at an outer surface";return false;}
                int a=queue[head++];unsigned links=a==n?trial:graph[a].links;
                for(int d=0;d<6;d++){int b=graph[a].neighbour[d];if(b<0||visited[b]==generation)continue;
                    bool linked=b==n?(trial&(1u<<opposite[d])):(links&(1u<<d));
                    if(linked){visited[b]=generation;queue[count++]=b;}}
            }
            if(count!=expected)continue;
            unsigned mask=sample_mask(c.shape,left);
            if(expected>0&&!visible_connected(n,mask)){
                if(connectivity_visits>131072){out["reason"]="Scoop connectivity limit reached; aim at an outer surface";return false;}
                continue;
            }
            masks[n]=mask;
            selected.emplace_back(c.p,debit);c.water=left;c.links=trial;remaining-=debit;alive=expected;progress=true;
            for(int d=0;d<6;d++)if(c.neighbour[d]>=0){auto &other=graph[c.neighbour[d]];
                other.links&=~(1u<<opposite[d]);if(trial&(1u<<d))other.links|=1u<<opposite[d];}
        }
        if(!progress){out["reason"]="Aim at an outer surface to scoop without leaving disconnected water";return false;}
    }
    cells=std::move(selected);return true;
}
bool NativeRegionalWater::bucket_footprint(Vector3i target,const Vector3 &aim,uint64_t amount,bool collect,int &x0,int &z0,Dictionary &out){
    x0=target.x-(aim.x-target.x*.5<.25?1:0);z0=target.z-(aim.z-target.z*.5<.25?1:0);
    const int preferred_x=x0,preferred_z=z0;
    // Four one-metre footprints contain the aimed half-metre cell. Prefer the
    // nearest; near a wall choose the first that can hold the complete unit.
    // This is bounded selection, not spreading or a volume-fitting iteration.
    for(int choice=0;choice<4;choice++){
        int x=choice&1?2*target.x-1-preferred_x:preferred_x;
        int z=choice&2?2*target.z-1-preferred_z:preferred_z;
        uint64_t available=0;bool waiting=false;
        for(int dz=0;dz<2;dz++)for(int dx=0;dx<2;dx++)
        for(int y=target.y-(collect?1:2);y<=target.y+(collect?0:4);y++){
            Vector3i p(x+dx,y,z+dz);if(!in_domain(p))continue;
            const Region *r=get(p,!collect);
            if(!r){waiting|=!collect&&!limit;continue;}
            auto cap=profile(*r,index(p)).capacity();auto stored=r->water[index(p)];
            available+=collect?std::min(cap,stored):(cap>stored?cap-stored:0);
        }
        if(waiting){out["pending"]=true;out["reason"]="Preparing water at this location";return false;}
        if(available>=amount){x0=x;z0=z;return true;}
    }
    // Irregular shallow sources still use the bounded connected scoop search;
    // placement performs its existing exact capacity/connectivity validation.
    return true;
}
// An explicit nearby pour restores connected missing volume before stacking.
// Read only prepared local cells: no simulation, global search, or remote loads.
bool NativeRegionalWater::plan_local_refill(Vector3i target,const Vector3 &aim,uint64_t amount,Placement &take) const{
    struct Site{Vector3i p;WaterCellProfile shape;uint64_t stored=0,desired=0,added=0;bool body=false,queued=false;};
    constexpr int R=4,N=9;std::vector<Site> sites;sites.reserve(N*N*N);
    std::array<int,N*N*N> ids;ids.fill(-1);
    auto at=[&](Vector3i p){Vector3i d=p-target+Vector3i(R,R,R);return d.x<0||d.y<0||d.z<0||d.x>=N||d.y>=N||d.z>=N?-1:d.x+N*(d.y+N*d.z);};
    auto find=[&](Vector3i p){int i=at(p);return i<0?-1:ids[i];};
    int seed=-1;double best=1e30;
    for(int z=-R;z<=R;z++)for(int y=-R;y<=R;y++)for(int x=-R;x<=R;x++){
        Vector3i p=target+Vector3i(x,y,z);const Region *r=get(p);if(!r)continue;
        auto shape=profile(*r,index(p));if(!shape.capacity())continue;
        uint64_t stored=r->water[index(p)];int id=int(sites.size());ids[at(p)]=id;sites.push_back({p,shape,stored});
        if(stored){Vector3 center=Vector3(p)*.5+Vector3(.25,.25,.25);double distance=center.distance_squared_to(aim);
            if(distance<best){best=distance;seed=id;}}
    }
    // A separate dry placement must not be redirected to a distant lake.
    if(seed<0||best>1.0)return false;
    auto connects=[&](const Site&a,uint64_t av,const Site&b,uint64_t bv){
        if(!av||!bv)return false;Vector3i d=b.p-a.p;
        return d.y<0?joined_vertical(b.shape,bv,a.shape,av):d.y>0?joined_vertical(a.shape,av,b.shape,bv):
            joined(a.shape,av,b.shape,bv,d.x?0:2,d.x?d.x>0:d.z>0);
    };
    std::vector<int> body;body.push_back(seed);sites[seed].body=true;double level=-1e30;
    for(size_t q=0;q<body.size();q++){
        auto &a=sites[body[q]];level=std::max(level,a.p.y*500.0+a.shape.head(a.stored));
        for(int d=0;d<6;d++){int j=find(a.p+directions[d]);if(j<0||sites[j].body)continue;
            if(connects(a,a.stored,sites[j],sites[j].stored)){sites[j].body=true;body.push_back(j);}}
    }
    for(auto &s:sites){double volume=s.shape.volume(std::clamp(level-s.p.y*500.0,0.0,500.0));
        s.desired=std::min(s.shape.capacity(),uint64_t(std::max(0.0,std::floor(volume+1e-6))));}
    auto rank=[&](int i){return (Vector3(sites[i].p)*.5+Vector3(.25,.25,.25)).distance_squared_to(aim);};
    auto farther=[&](int a,int b){auto ra=rank(a),rb=rank(b);return ra!=rb?ra>rb:key(sites[a].p)>key(sites[b].p);};
    std::priority_queue<int,std::vector<int>,decltype(farther)> queue(farther);
    // Refill a gap inside the body, not unused ground around a separate pool.
    auto bounded_gap=[&](int i){
        if(sites[i].body)return true;
        for(int axis: {0,2}){bool sides[2]={false,false};
            for(int side=0;side<2;side++)for(int step=1;step<=R;step++){
                Vector3i p=sites[i].p;p[axis]+=(side?1:-1)*step;int j=find(p);
                if(j<0){
                    // A solid bank bounds a refill hole just as existing water
                    // does. Missing/unprepared cells do not establish a bank.
                    const Region *r=get(p);
                    if(at(p)>=0&&r&&!profile(*r,index(p)).capacity())sides[side]=true;
                    break;
                }
                if(sites[j].body){sides[side]=true;break;}}
            if(sides[0]&&sides[1])return true;}
        return false;
    };
    auto enqueue=[&](int i){if(i>=0&&!sites[i].queued&&sites[i].desired>sites[i].stored+sites[i].added&&bounded_gap(i)){sites[i].queued=true;queue.push(i);}};
    for(int i:body){enqueue(i);for(int d=0;d<6;d++)enqueue(find(sites[i].p+directions[d]));}
    uint64_t remaining=amount;Placement proposed;
    while(!queue.empty()&&remaining){
        int i=queue.top();queue.pop();auto &a=sites[i];a.queued=false;
        uint64_t give=std::min(remaining,a.desired-a.stored-a.added);if(!give)continue;
        bool connected=a.body;
        for(int d=0;d<6&&!connected;d++){int j=find(a.p+directions[d]);if(j<0)continue;const auto &b=sites[j];
            if((b.body||b.added)&&connects(a,a.stored+a.added+give,b,b.stored+b.added))connected=true;}
        if(!connected)continue;
        a.added+=give;remaining-=give;proposed.emplace_back(a.p,give);
        for(int d=0;d<6;d++)enqueue(find(a.p+directions[d]));
    }
    if(remaining)return false;
    take=std::move(proposed);return true;
}
bool NativeRegionalWater::plan_placement(Vector3i target,const Vector3 &aim,uint64_t amount,Placement &take,Dictionary &out){
    Region *origin=get(target,true);
    if(!origin){out["pending"]=in_domain(target)&&!limit;out["reason"]="Preparing water at this location";return false;}
    if(plan_local_refill(target,aim,amount,take))return true;
    uint64_t held=origin->water[index(target)],capacity=profile(*origin,index(target)).capacity();
    // A top-up that fits its existing cell needs no neighbouring region work.
    if(held>0&&held<=capacity&&amount<=capacity-held){take.emplace_back(target,amount);return true;}
        // A static pour has a compact footprint and one final surface height.
        struct Site{Vector3i p;WaterCellProfile shape;uint64_t stored,room;};
        std::vector<Site> sites;std::deque<Vector3i> pending;std::unordered_set<Key> visited;
        int x0,z0;if(!bucket_footprint(target,aim,amount,false,x0,z0,out))return false;
        pending.push_back(target);visited.insert(key(target));uint64_t space=0;
        while(!pending.empty()){
            Vector3i p=pending.front();pending.pop_front();
            Region *current=get(p,true);if(!current){out["pending"]=!limit;out["reason"]="Preparing water at this location";return false;}
            auto shape=profile(*current,index(p));uint64_t cap=shape.capacity(),stored=current->water[index(p)];
            if(!cap)continue;
            uint64_t room=cap>stored?cap-stored:0;sites.push_back({p,shape,stored,room});space+=room;
            for(int d=0;d<6;d++){
                Vector3i q=p+directions[d];
                if(!in_domain(q)||q.x<x0||q.x>x0+1||q.z<z0||q.z>z0+1||q.y<target.y-2||q.y>target.y+4||visited.count(key(q)))continue;
                Region *other=get(q,true);if(!other){out["pending"]=!limit;out["reason"]="Preparing water at this location";return false;}
                auto next=profile(*other,index(q));if(!next.capacity())continue;
                bool connected=d==0?(shape.open_bottom&&next.ceiling==500):d==5?(shape.ceiling==500&&next.open_bottom):
                    WaterCellProfile::face_overlap(shape,shape.ceiling,next,next.ceiling,q.x!=p.x?0:2,q.x!=p.x?q.x>p.x:q.z>p.z);
                if(connected&&visited.insert(key(q)).second)pending.push_back(q);
            }
        }
        if(space<amount){out["reason"]="Not enough connected space near the pour target";return false;}
        auto allocation=[](const Site&s,double level){
            double volume=s.shape.volume(std::clamp(level-s.p.y*500.0,0.0,500.0));
            uint64_t desired=uint64_t(std::max(0.0,std::floor(volume)));
            return std::min(s.room,desired>s.stored?desired-s.stored:0);
        };
        double low=(target.y-2)*500.0,high=(target.y+5)*500.0;
        for(int iteration=0;iteration<32;iteration++){
            double middle=(low+high)*0.5;uint64_t sum=0;for(const auto&s:sites)sum+=allocation(s,middle);
            if(sum>amount)high=middle;else low=middle;
        }
        uint64_t remaining=amount;
        for(const auto&s:sites){uint64_t give=std::min(remaining,allocation(s,low));take.emplace_back(s.p,give);remaining-=give;}
        // Exact integer quantity; distribute only the final rounding millilitres.
        for(size_t n=0;n<sites.size()&&remaining;n++)if(take[n].second<sites[n].room&&allocation(sites[n],high)>take[n].second){take[n].second++;remaining--;}
        if(remaining){out["reason"]="Water placement could not retain its full quantity";return false;}
        // Reject disconnected pockets instead of creating several small pieces.
        std::unordered_map<Key,size_t> lookup;for(size_t n=0;n<sites.size();n++)lookup[key(sites[n].p)]=n;
        std::vector<size_t> reached;std::unordered_set<size_t> seen;
        for(size_t n=0;n<take.size();n++)if(take[n].second){reached.push_back(n);seen.insert(n);break;}
        for(size_t at=0;at<reached.size();at++){
            size_t n=reached[at];const auto&a=sites[n];uint64_t av=a.stored+take[n].second;
            for(int d=0;d<6;d++){
                auto found=lookup.find(key(a.p+directions[d]));if(found==lookup.end()||seen.count(found->second))continue;
                size_t j=found->second;const auto&b=sites[j];uint64_t bv=b.stored+take[j].second;if(!bv)continue;
                bool connected=d==0?joined_vertical(b.shape,bv,a.shape,av):d==5?joined_vertical(a.shape,av,b.shape,bv):
                    joined(a.shape,av,b.shape,bv,b.p.x!=a.p.x?0:2,b.p.x!=a.p.x?b.p.x>a.p.x:b.p.z>a.p.z);
                if(connected){seen.insert(j);reached.push_back(j);}
            }
        }
        for(size_t n=0;n<take.size();n++)if(take[n].second&&!seen.count(n)){out["reason"]="Aim at one connected open area";return false;}
        // Do not debit a bucket into a completely invisible isolated body.
        // These are the same eight owned lattice points used by build_surface:
        // .125/.375 metres, or 125/375 mm in the cached half-metre profile.
        // Existing bodies may receive small surface-height additions normally.
        bool existing_body=false,represented=false;
        for(size_t n=0;n<sites.size();n++){
            const auto &site=sites[n];existing_body|=site.stored>0;
            uint64_t filled=site.stored+take[n].second;if(!filled)continue;
            double head=site.shape.head(filled);
            for(double z:{.25,.75})for(double x:{.25,.75}){
                double bottom=site.shape.bottom(x,z),top=site.shape.surface(head,x,z);
                represented|=(bottom<125&&125<top)||(bottom<375&&375<top);
            }
        }
        if(!existing_body&&!represented){out["reason"]="Too little water to form a visible volume here; water kept in bucket";return false;}
        take.erase(std::remove_if(take.begin(),take.end(),[](const auto&entry){return entry.second==0;}),take.end());

    return true;
}
void NativeRegionalWater::apply_placement(const Placement &take){
    for(const auto &[p,give]:take){preserve_mesh_region(region_key(p));regions.at(region_key(p)).water[index(p)]+=give;total+=give;changed(p);}
}
Dictionary NativeRegionalWater::place_water(const Vector3 &point,int64_t amount){
    Dictionary out;out["ok"]=false;out["pending"]=false;
    if(fill.running||!point.is_finite()||amount<=0||amount>1000000||uint64_t(amount)>MAX_TOTAL-total){out["reason"]="Water placement is unavailable";return out;}
    Vector3i target=cell(point);
    if(!in_domain(target)){out["reason"]="Water target is outside the world";return out;}
    Placement take;if(!plan_placement(target,point,uint64_t(amount),take,out))return out;
    apply_placement(take);prioritize_mesh(region_key(target));
    out["ok"]=true;out["water_ml"]=amount;out["reason"]="Placed water";return out;
}
int64_t NativeRegionalWater::brush(const Vector3 &point,double radius,int64_t amount){
    if(!point.is_finite()||!std::isfinite(radius)||radius<0||radius>16||fill.running)return 0;
    if(amount>0){Dictionary result=place_water(point,amount);return bool(result["ok"])?amount:0;}
    if(amount==0)return 0;
    uint64_t removed=0,requested=amount==INT64_MIN?MAX_TOTAL:uint64_t(-amount);
    Vector3i lo=cell(point-Vector3(radius,radius,radius)),hi=cell(point+Vector3(radius,radius,radius));
    for(int z=lo.z;z<=hi.z;++z)for(int y=lo.y;y<=hi.y;++y)for(int x=lo.x;x<=hi.x;++x){Vector3i p(x,y,z);if(!in_domain(p)||(Vector3(p)*0.5+Vector3(0.25,0.25,0.25)-point).length()>radius)continue;
        auto it=regions.find(region_key(p));if(it==regions.end())continue;preserve_mesh_region(region_key(p));uint64_t &v=it->second.water[index(p)];uint64_t take=std::min(v,requested-removed);if(take){v-=take;total-=take;removed+=take;changed(p);}if(removed==requested){prioritize_mesh(region_key(cell(point)));return removed;}}
    if(removed)prioritize_mesh(region_key(cell(point)));
    return int64_t(removed);
}
Dictionary NativeRegionalWater::transfer_water(const Vector3 &from,const Vector3 &to,bool pour,Object *inventory,int64_t slot,int64_t revision){
    Dictionary out;out["ok"]=false;out["pending"]=false;
    if(fill.running||!from.is_finite()||!to.is_finite()||from.distance_to(to)>5||!inventory||!inventory->has_method("exchange_water")){out["reason"]="Water is preparing, or target is out of reach";return out;}
    if(!inventory->has_method("snapshot")){out["reason"]="Invalid bucket transfer";return out;}
    Dictionary state=inventory->call("snapshot");Array slots=state.get("slots",Array());
    if(int64_t(state.get("revision",-1))!=revision||slot<0||slot>=slots.size()){out["reason"]="Selected item changed";return out;}
    Dictionary stack=slots[slot];int64_t item=stack.get("item",0);
    if(item<401||item>411||int64_t(stack.get("count",0))!=1){out["reason"]="Select a bucket";return out;}
    int64_t held=stack.get("water_ml",int64_t(-1)),capacity=stack.get("water_capacity_ml",int64_t(0));
    if(held<0||capacity!=1000000||held>capacity){out["reason"]="Invalid water container state";return out;}
    // Gameplay moves one terrain-sized unit, never a fractional new bucket.
    // A legacy partial bucket may finish filling without losing saved contents.
    if(pour&&held>0&&held<capacity){out["reason"]="Refill this older partial bucket before placing one water unit";return out;}
    uint64_t amount=uint64_t(pour?held:capacity-held);
    if(!amount){out["reason"]=pour?"Bucket empty":"Bucket full";return out;}
    Dictionary surface=raycast_surface(from,to);bool hit=bool(surface["hit"]);
    Vector3i target=hit?Vector3i(surface["cell"]):cell(to);
    if(!pour&&!hit){out["reason"]="Aim at nearby water";return out;}
    Region *r=get(target,true);if(!r){out["pending"]=in_domain(target)&&!limit;out["reason"]="Preparing water at this location";return out;}
    // A terrain ray can end inside a conservative shoreline cell. Pour into
    // the first open cell just back along the unobstructed aiming segment,
    // instead of rejecting a valid bucket action against a sloping surface.
    if(pour&&!profile(*r,index(target)).capacity()){
        Vector3 back=(from-to).normalized();
        for(int step=1;step<=10;++step){Vector3i p=cell(to+back*(step*0.1));Region *candidate=get(p,true);
            if(!candidate){out["pending"]=in_domain(p)&&!limit;out["reason"]="Preparing water at this location";return out;}
            if(profile(*candidate,index(p)).capacity()>0){target=p;r=candidate;break;}}
    }
    int i=index(target);
    std::vector<std::pair<Vector3i,uint64_t>> take;
    if(!pour){
        uint64_t remaining=amount;
        // A full cubic metre can spread into a shallow local puddle. Search
        // at most 9^3 cells (2 m radius), following actual wet connections.
        // Prefer a one-metre cube immediately beneath the aimed surface.
        // The bounded connected search can expand for shallow sources, but its
        // traversal order must not dictate cross-shaped excavations.
        Vector3 aim=surface["point"];
        int x0,z0;if(!bucket_footprint(target,aim,amount,true,x0,z0,out))return out;
        Vector3i center2(2*x0+1,2*target.y-1,2*z0+1);
        auto rank=[&](Vector3i p){Vector3i delta=p*2-center2;return delta.length_squared();};
        auto farther=[&](Vector3i a,Vector3i b){auto ra=rank(a),rb=rank(b);return ra!=rb?ra>rb:key(a)>key(b);};
        std::priority_queue<Vector3i,std::vector<Vector3i>,decltype(farther)> candidates(farther);
        std::unordered_set<Key> visited;candidates.push(target);visited.insert(key(target));
        while(!candidates.empty()){Vector3i p=candidates.top();candidates.pop();const Region *other=get(p);if(!other)continue;int j=index(p);
            uint64_t available=other->water[j];if(!available||!profile(*other,j).capacity())continue;
            take.emplace_back(p,available);
            for(int d=0;d<6;++d){Vector3i q=p+directions[d];Vector3i distance=q-target;
                if(std::max({std::abs(distance.x),std::abs(distance.y),std::abs(distance.z)})>4||!in_domain(q))continue;
                const Region *next=get(q);if(!next||!next->water[index(q)])continue;int n=index(q);bool connected=false;
                auto a=surface_profile(p),b=surface_profile(q);
                if(d==0)connected=joined_vertical(b,next->water[n],a,other->water[j]);
                else if(d==5)connected=joined_vertical(a,other->water[j],b,next->water[n]);
                else {int axis=q.x!=p.x?0:2;connected=joined(a,other->water[j],b,next->water[n],axis,q[axis]>p[axis]);}
                if(connected&&visited.insert(key(q)).second)candidates.push(q);
            }
        }
        if(!take.empty()){if(!plan_connected_scoop(take,amount,out))return out;remaining=0;}
        amount-=remaining;
        if(!amount){
            // An explicit edit can empty the owner before its new mesh is published.
            // Retry the same click after publication instead of taking unrelated
            // nearby water or reporting a miss against a still-visible surface.
            if(publication_enabled&&(batch_active||publish_pending||mesh_set.count(region_key(target)))){
                prioritize_mesh(region_key(target));out["pending"]=true;out["reason"]="Updating displayed water";
            }else out["reason"]="No water within bucket reach";
            return out;
        }
    }
    if(pour&&!plan_placement(target,hit?Vector3(surface["point"]):to,amount,take,out))return out;
    if(pour&&(!profile(*r,i).capacity()||total>MAX_TOTAL-amount)){out["reason"]="Aim at open space just above terrain";return out;}
    if(!bool(inventory->call("exchange_water",slot,pour,revision,int64_t(amount)))){out["reason"]="Bucket full / empty, or selected item changed";return out;}
    if(pour){apply_placement(take);}else{
        uint64_t remaining=amount;
        for(const auto &[p,available]:take){uint64_t debit=std::min(remaining,available);if(!debit)break;
            preserve_mesh_region(region_key(p));regions.at(region_key(p)).water[index(p)]-=debit;changed(p);remaining-=debit;}
        total-=amount;
    }
    changed(target);prioritize_mesh(region_key(target));out["ok"]=true;out["water_ml"]=int64_t(amount);out["units"]=1;out["reason"]=pour?"Placed one water unit (1 m3)":"Bucket filled: one water unit (1 m3)";out["point"]=Vector3(target)*0.5;return out;
}
Vector3 NativeRegionalWater::surface_near(const Vector3 &point,double radius) const {
    Vector3 best(INFINITY,INFINITY,INFINITY);if(!point.is_finite()||!std::isfinite(radius)||radius<0||radius>3)return best;
    Vector3 margin(radius+0.5,radius+0.5,radius+0.5);
    Vector3i lo=Vector3i(((point-margin)/4.0).floor()),hi=Vector3i(((point+margin)/4.0).floor());double distance=radius*radius;
    for(int z=std::max(0,lo.z);z<=std::min(499,hi.z);++z)for(int y=std::max(0,lo.y);y<=std::min(63,hi.y);++y)for(int x=std::max(0,lo.x);x<=std::min(499,hi.x);++x){
        Key k=key(Vector3i(x,y,z));if(!publication_enabled&&!surface_ready(k))continue;QuerySurface temporary;const QuerySurface *selected=query_surface(k,temporary);if(!selected)continue;const QuerySurface &mesh=*selected;
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

Dictionary NativeRegionalWater::cell_geometry(const Vector3 &point) const {
    Dictionary out;if(!point.is_finite())return out;Vector3i p=cell(point);const Region *r=get(p);if(!r)return out;
    int i=index(p);auto shape=surface_profile(p);double h=shape.head(r->water[i]);auto footprint=shape.footprint(h);
    out["bottom"]=p.y*0.5+shape.bottom(point.x*2-p.x,point.z*2-p.z)*0.001;
    out["head"]=p.y*0.5+shape.surface(h,point.x*2-p.x,point.z*2-p.z)*0.001;out["slope_x"]=0.0;out["slope_z"]=0.0;out["capacity_ml"]=int64_t(shape.capacity());out["cut"]=shape.cut;
    out["wet_centroid"]=Vector3(p)*0.5+Vector3(footprint.x*0.5,shape.bottom(footprint.x,footprint.z)*0.001,footprint.z*0.5);
    int connections=0;
    for(int d=0;d<6;++d){Vector3i q=p+directions[d];const Region *other=get(q);if(!other||!other->water[index(q)])continue;
        auto next=surface_profile(q);uint64_t amount=other->water[index(q)];bool linked=false;
        if(d==0)linked=joined_vertical(next,amount,shape,r->water[i]);
        else if(d==5)linked=joined_vertical(shape,r->water[i],next,amount);
        else{int axis=q.x!=p.x?0:2;linked=joined(shape,r->water[i],next,amount,axis,q[axis]>p[axis]);}
        if(linked)connections|=1<<d;
    }
    out["connections"]=connections;
    return out;
}
bool NativeRegionalWater::overlaps_occupied(const AABB &bounds) const {
    // Conservative edit admission against authoritative occupancy, including
    // temporarily invalid contacts. No terrain sampling or mesh work is needed.
    if(!bounds.position.is_finite()||!bounds.size.is_finite()||bounds.size.x<0||bounds.size.y<0||bounds.size.z<0)return true;
    if(!total)return false;
    for(const auto &[k,r]:regions){Vector3i base=position(k)*8;
        if(!AABB(Vector3(base)*.5,Vector3(4,4,4)).intersects(bounds))continue;
        for(int i=0;i<512;i++)if(r.water[i]){
            Vector3i p=base+Vector3i(i%8,(i/8)%8,i/64);
            if(AABB(Vector3(p)*.5,Vector3(.5,.5,.5)).intersects(bounds))return true;
        }
    }
    return false;
}
double NativeRegionalWater::depth_at(const Vector3 &point) const {
    if(!point.is_finite())return 0;Vector3i p=cell(point);const Region *r=get(p);if(!r)return 0;int i=index(p);
    auto shape=surface_profile(p);if(!r->water[i]||!shape.capacity())return 0;
    double top=p.y*0.5+shape.surface(shape.head(r->water[i]),point.x*2-p.x,point.z*2-p.z)*0.001;
    double bottom=p.y*0.5+shape.bottom(point.x*2-p.x,point.z*2-p.z)*0.001;
    if(point.y>=top||point.y<bottom)return 0;
    // At most the bounded vertical domain, only for actual wet query points.
    for(int y=p.y+1;y<509;++y){Vector3i q(p.x,y,p.z);const Region *above=get(q);if(!above||!above->water[index(q)]||top<y*0.5-0.00001||!profile(*above,index(q)).open_bottom)break;
        int j=index(q);auto shape_above=surface_profile(q);
        if(shape_above.bottom(point.x*2-p.x,point.z*2-p.z)>0)break;
        top=y*0.5+shape_above.surface(shape_above.head(above->water[j]),point.x*2-p.x,point.z*2-p.z)*0.001;}
    return std::max(0.0,top-point.y);
}
PackedByteArray NativeRegionalWater::placement_mask(const TypedArray<Transform3D> &transforms) const {
    PackedByteArray result;if(transforms.size()>512)return result;result.resize(transforms.size());for(int i=0;i<transforms.size();++i){Transform3D t=transforms[i];result.set(i,depth_at(t.origin)>0?1:0);}return result;
}
void NativeRegionalWater::preserve_mesh_region(Key k){
    if(!batch_active||!mesh_snapshot_dependencies.count(k)||mesh_snapshot.count(k)||mesh_snapshot_absent.count(k))return;
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
void NativeRegionalWater::prioritize_mesh(Key k){
    if(!mesh_set.count(k)||meshes.empty()||meshes.front()==k)return;
    auto found=std::find(meshes.begin(),meshes.end(),k);
    if(found!=meshes.end()){meshes.erase(found);meshes.push_front(k);}
}
void NativeRegionalWater::cancel_mesh_batch(){
    if(!batch_active&&!publish_pending)return;
    for(Key k:batch_owners)if(mesh_set.insert(k).second)meshes.push_back(k);
    batch_active=false;publish_pending=false;staged_surfaces.clear();batch_queue.clear();batch_owners.clear();mesh_snapshot.clear();mesh_snapshot_absent.clear();mesh_snapshot_dependencies.clear();
}
Dictionary NativeRegionalWater::next_mesh_batch(){
    Dictionary result;publication_enabled=true;
    if(publish_pending){result["batch"]=int64_t(batch_id);result["complete"]=true;return result;}
    if(!batch_active){
        if(meshes.empty())return result;
        // Only dirty owners with overlapping reconstruction halos must publish
        // together. Distant pools must not wait for one global mesh batch.
        Key seed=meshes.front();mesh_set.erase(seed);batch_owners.push_back(seed);
        for(size_t i=0;i<batch_owners.size();++i){
            Vector3i p=position(batch_owners[i]);
            for(int z=-1;z<=1;++z)for(int y=-1;y<=1;++y)for(int x=-1;x<=1;++x){
                Vector3i n=p+Vector3i(x,y,z);
                if(n.x<0||n.x>=500||n.y<0||n.y>=64||n.z<0||n.z>=500)continue;
                Key k=key(n);if(mesh_set.erase(k))batch_owners.push_back(k);
            }
        }
        // Reconstruction and readiness read only each owner's one-region halo.
        // Copy-on-write must not retain mutations elsewhere in the world.
        for(Key owner:batch_owners){
            Vector3i p=position(owner);
            for(int z=-1;z<=1;++z)for(int y=-1;y<=1;++y)for(int x=-1;x<=1;++x){
                Vector3i n=p+Vector3i(x,y,z);
                if(n.x>=0&&n.x<500&&n.y>=0&&n.y<64&&n.z>=0&&n.z<500)mesh_snapshot_dependencies.insert(key(n));
            }
        }
        batch_queue.assign(batch_owners.begin(),batch_owners.end());
        meshes.erase(std::remove_if(meshes.begin(),meshes.end(),[&](Key k){return !mesh_set.count(k);}),meshes.end());
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
        result["complete"]=true;batch_active=false;publish_pending=true;mesh_snapshot.clear();mesh_snapshot_absent.clear();mesh_snapshot_dependencies.clear();
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
        Key k=key(Vector3i(x,y,z));if(!publication_enabled&&!surface_ready(k))continue;
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
Dictionary NativeRegionalWater::next_mesh(bool include_contacts){
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
    SurfaceMesh mesh=build_surface(k,false,include_contacts);
    result["coordinate"]=position(k);result["faces"]=mesh.faces;Array arrays;arrays.resize(Mesh::ARRAY_MAX);
    arrays[Mesh::ARRAY_VERTEX]=mesh.vertices;arrays[Mesh::ARRAY_NORMAL]=mesh.normals;arrays[Mesh::ARRAY_TEX_UV]=mesh.uv;result["arrays"]=arrays;result["vertices"]=mesh.vertices.size();
    mesh_us=Time::get_singleton()->get_ticks_usec()-start;max_mesh_us=std::max(max_mesh_us,mesh_us);return result;
}
NativeRegionalWater::SurfaceMesh NativeRegionalWater::build_surface(Key k,bool snapshot,bool include_contacts) const {
    SurfaceMesh output;
    // Uniform, global material-density lattice. Geometry is extracted and
    // connected by exactly the terrain path; there is no per-water vertex fit,
    // coordinate displacement, interval crossing override or triangle clipping.
    constexpr int N=16,S=N+2,V=N+1;
    constexpr float STEP=.25f,BAND=.25f;
    struct Node {float density=BAND;Vector3i owner;bool contact=false;};
    struct Vertex {int cx,cy,cz;unsigned mask;Vector3 position;};
    std::array<Node,S*S*S> field;
    std::array<int,V*V*V> ids;ids.fill(-1);
    std::vector<Vertex> vertices;vertices.reserve(512);
    Vector3i base=position(k)*8;
    auto node_index=[](int x,int y,int z){return x+1+S*(y+1+S*(z+1));};
    auto vertex_index=[](int x,int y,int z){return x+1+V*(y+1+V*(z+1));};
    int unresolved=0,wet_cells=0;
    // Rasterise the union of cached local volumes into one signed field. The
    // half-step lattice avoids coincident internal cell faces. All coordinates
    // are derived from global integer keys, identically in neighbouring halos.
    for(int z=-1;z<=8;++z)for(int y=-1;y<=8;++y)for(int x=-1;x<=8;++x){
        Vector3i cell=base+Vector3i(x,y,z);
        if(!in_domain(cell))continue;
        const Region *region=surface_region(region_key(cell),snapshot);
        if(!region||!region->valid)continue;
        uint64_t amount=region->water[index(cell)];if(!amount)continue;
        auto shape=surface_profile(cell,snapshot);if(!shape.capacity())continue;
        double head=shape.head(amount);bool represented=false;
        for(int nz=std::max(-1,2*z-1);nz<=std::min(N,2*z+2);++nz)
        for(int ny=std::max(-1,2*y-1);ny<=std::min(N,2*y+2);++ny)
        for(int nx=std::max(-1,2*x-1);nx<=std::min(N,2*x+2);++nx){
            double lx=(nx+.5)*STEP-x*.5,ly=(ny+.5)*STEP-y*.5,lz=(nz+.5)*STEP-z*.5;
            double bottom=shape.bottom(lx*2,lz*2)*.001;
            double top=shape.surface(head,lx*2,lz*2)*.001;
            float horizontal=float(std::max(std::abs(lx-.25)-.25,std::abs(lz-.25)-.25));
            float below=float(bottom-ly),above=float(ly-top);
            float d=std::max({horizontal,below,above});
            represented|=d<0;
            Node &sample=field[node_index(nx,ny,nz)];
            if(d<sample.density){sample.density=d;sample.owner=cell;
                sample.contact=below>=std::max(horizontal,above)&&!shape.open_bottom;}
        }
        if(x>=0&&x<8&&y>=0&&y<8&&z>=0&&z<8){++wet_cells;if(!represented)++unresolved;}
    }
    for(int z=-1;z<N;++z)for(int y=-1;y<N;++y)for(int x=-1;x<N;++x){
        float d[8];unsigned signs=0;
        for(int c=0;c<8;++c){d[c]=field[node_index(x+(c&1),y+((c>>1)&1),z+((c>>2)&1))].density;if(d[c]<0)signs|=1u<<c;}
        ids[vertex_index(x,y,z)]=int(vertices.size());
        extract_density_components(d,signs,false,[&](const DensitySurfaceVertex &geometry,unsigned component){
        // Sum in lattice coordinates first, then translate once. Shared halo
        // vertices therefore have the same float bits across region packets.
        Vector3 p((base.x*2+x+.5f+geometry.position.x)*STEP,
                  (base.y*2+y+.5f+geometry.position.y)*STEP,
                  (base.z*2+z+.5f+geometry.position.z)*STEP);
        vertices.push_back({x,y,z,component,p});
        });
    }
    std::map<int,int> face_vertices;
    int triangles=0,tops=0,bottoms=0,sides=0;
    connect_material_surface(int(vertices.size()),{0,N,0,N,0,N},
        [&](int i)->const Vertex&{return vertices[i];},
        [&](int x,int y,int z,int ax,int ay,int az,int axis){
            if(x< -1||x>=N||y< -1||y>=N||z< -1||z>=N)return -1;
            int first=ids[vertex_index(x,y,z)];unsigned edge=1u<<(8+terraforest::density_edge_index((ax-x)+2*(ay-y)+4*(az-z),axis));
            for(int i=first;i>=0&&i<int(vertices.size());i++){const auto &v=vertices[i];
                if(v.cx!=x||v.cy!=y||v.cz!=z)break;if(v.mask&edge)return i;}
            return -1;
        },
        // A contact-labelled lattice endpoint does not prove its entire dual
        // face is buried. Removing it opens visible holes along the shoreline.
        // Keep the closed material boundary; normal terrain depth occludes
        // genuinely buried faces without inventing a second diagnostic mesh.
        [&](int,int,int,int){return true;},
        [&](int x,int y,int z,int axis,int ex,int ey,int ez,int edge_axis,int left,int right){
            unsigned arc=0;V3 local=density_face_arc(x,y,z,axis,ex,ey,ez,edge_axis,
                [&](int xx,int yy,int zz){return field[node_index(xx,yy,zz)].density;},arc);
            int key=(vertex_index(x,y,z)*3+axis)*4+arc;auto found=face_vertices.find(key);if(found!=face_vertices.end())return found->second;
            Vector3 p((base.x*2+.5f+local.x)*STEP,(base.y*2+.5f+local.y)*STEP,(base.z*2+.5f+local.z)*STEP);
            int id=int(vertices.size());vertices.push_back({x,y,z,0,p});face_vertices[key]=id;return id;
        },
        [&](int a,int b,int c,int d,bool reverse,const int *middle){
            const auto v=vertices[c];
            int axis=(vertices[a].cx==v.cx&&vertices[b].cx==v.cx&&vertices[d].cx==v.cx)?0:
                     (vertices[a].cy==v.cy&&vertices[b].cy==v.cy&&vertices[d].cy==v.cy)?1:2;
            Vector3i next(v.cx,v.cy,v.cz);next[axis]++;
            const Node &first=field[node_index(v.cx,v.cy,v.cz)],&second=field[node_index(next.x,next.y,next.z)];
            Vector3i owner=first.density<0?first.owner:second.owner;
            surface_split_quad(a,b,c,d,reverse,middle,[&](int i){return vertices[i].position;},
                [&](int a,int b,int c,int d){Vector3 p=(vertices[a].position+vertices[b].position+vertices[c].position+vertices[d].position)*.25f;
                    int id=int(vertices.size());vertices.push_back({v.cx,v.cy,v.cz,0,p});return id;},[&](int a,int b,int c){
                Vector3 p=vertices[a].position,q=vertices[b].position,r=vertices[c].position;
                Vector3 normal=(r-p).cross(q-p).normalized();if(normal.length_squared()<.5)return;
                for(auto point:{p,q,r}){output.vertices.push_back(point);output.normals.push_back(normal);output.uv.push_back(Vector2(point.x,point.z));}
                output.owners.push_back(owner);++triangles;
                if(normal.y>.001)++tops;else if(normal.y<-.001)++bottoms;else ++sides;
            });
        });
    output.faces["top"]=tops;output.faces["bottom"]=bottoms;output.faces["side"]=sides;output.faces["triangles"]=triangles;
    output.faces["shared_surface_nets"]=true;output.faces["terrain_density_extractor"]=true;
    output.faces["density_step_m"]=STEP;output.faces["wet_cells"]=wet_cells;output.faces["unresolved_wet_cells"]=unresolved;
    return output;
}
Dictionary NativeRegionalWater::statistics() const {
    uint64_t contact_bytes=0;for(const auto &[k,r]:regions)if(r.contacts)contact_bytes+=r.contacts->bytes;
    Dictionary d;d["terrain_contact_bytes"]=int64_t(contact_bytes);d["pending_vertical"]=int64_t(0);d["vertical_steps"]=int64_t(0);d["water_ml"]=int64_t(total);d["active_cells"]=int64_t(0);d["regions"]=int64_t(regions.size());d["pending_regions"]=int64_t(requests.size());d["dirty_meshes"]=int64_t(meshes.size()+batch_queue.size());d["mesh_batch_active"]=batch_active;d["mesh_publish_pending"]=publish_pending;d["published_mesh_batch"]=int64_t(published_batch);d["query_cache_bytes"]=int64_t(query_cache_bytes);d["query_builds"]=int64_t(query_builds);d["query_cache_hits"]=int64_t(query_cache_hits);d["mesh_snapshot_bytes"]=int64_t(mesh_snapshot.size()*sizeof(Region));d["fill_active"]=fill.running;d["fill_remaining_ml"]=fill.remaining;d["sampled_nodes"]=int64_t(sampled);d["cache_hits"]=int64_t(cache_hits);d["cached_region_rebuilds"]=int64_t(cache_rebuilds);d["cell_steps"]=int64_t(0);d["changes"]=int64_t(changes);d["step_us"]=int64_t(last_us);d["max_step_us"]=int64_t(max_us);d["mesh_us"]=int64_t(mesh_us);d["max_mesh_us"]=int64_t(max_mesh_us);d["capacity_reached"]=limit;d["resident_cell_bytes"]=int64_t(regions.size()*sizeof(Region)+contact_bytes);return d;
}
// Self-contained compound snapshot: authoritative amounts + derived occupancy.
// Occupancy is valid only for the terrain captured in the SAME world archive.
// Accepted edits invalidate it before capture. Invalid regions are re-sampled on
// reopen. All data has strict bounds; the outer world archive supplies checksums.
static constexpr uint32_t MAGIC=0x31575256,OLD_REGION_BYTES=16+512*12,REGION_BYTES=OLD_REGION_BYTES+729*4;
PackedByteArray NativeRegionalWater::capture_snapshot(const PackedByteArray &catalog) const {
    PackedByteArray out;Ref<NativeLakeCatalog> validator;validator.instantiate();if(fill.running||!validator->validate_snapshot(catalog))return out;
    uint64_t contact_bytes=regions.size()*4;
    for(const auto &[k,r]:regions)if(r.contacts){contact_bytes+=512*4;for(const auto &cell:r.contacts->floors)contact_bytes+=cell.size()*36;}
    if(contact_bytes>64*1024*1024)return out;
    out.resize(32+catalog.size()+regions.size()*REGION_BYTES+contact_bytes);out.encode_u32(0,MAGIC);out.encode_u32(4,7);out.encode_u32(8,catalog.size());out.encode_u32(12,regions.size());out.encode_u64(16,total);out.encode_u64(24,contact_bytes);
    for(int i=0;i<catalog.size();++i)out.set(32+i,catalog[i]);int64_t offset=32+catalog.size();
    for(const auto &[k,r]:regions){out.encode_u64(offset,k);out.encode_u32(offset+8,r.valid?1:0);out.encode_u32(offset+12,(r.has_density?1:0)|(r.replace_water?2:0));offset+=16;
        for(int i=0;i<512;++i){out.encode_u16(offset,r.floor[i]);out.encode_u16(offset+2,r.ceiling[i]);out.encode_u64(offset+4,r.water[i]);offset+=12;}
        for(float value:r.density){out.encode_float(offset,value);offset+=4;}}
    for(const auto &[k,r]:regions){out.encode_u32(offset,r.contacts?1:0);offset+=4;if(!r.contacts)continue;
        for(const auto &cell:r.contacts->floors){out.encode_u32(offset,cell.size());offset+=4;
            for(const auto &triangle:cell)for(auto p:triangle){out.encode_float(offset,p.x);out.encode_float(offset+4,p.z);out.encode_float(offset+8,p.y);offset+=12;}}}
    return out;
}
bool NativeRegionalWater::decode(const PackedByteArray &data,bool install){
    if(data.size()<32||data.decode_u32(0)!=MAGIC||(data.decode_u32(4)<1||data.decode_u32(4)>7)||(data.decode_u32(4)<6&&data.decode_u64(24)!=0)||data.decode_u64(24)>64*1024*1024)return false;
    const bool shaped=data.decode_u32(4)>=2;
    const uint32_t record_bytes=shaped?REGION_BYTES:OLD_REGION_BYTES;
    uint32_t bytes=data.decode_u32(8),count=data.decode_u32(12);uint64_t expected=data.decode_u64(16);
    if(bytes>1100000||count>MAX_REGIONS||expected>MAX_TOTAL||data.size()!=32+int64_t(bytes)+int64_t(count)*record_bytes+int64_t(data.decode_u64(24)))return false;
    Ref<NativeLakeCatalog> validator;validator.instantiate();if(!validator->validate_snapshot(data.slice(32,32+bytes)))return false;
    std::map<Key,Region> staged;int64_t offset=32+bytes;uint64_t sum=0;Key previous=0;
    for(uint32_t n=0;n<count;++n){Key k=data.decode_u64(offset);uint32_t valid=data.decode_u32(offset+8),shape=data.decode_u32(offset+12);Vector3i p=position(k);
        if(k!=key(p)||(n&&k<=previous)||p.x>=500||p.z>=500||p.y>=64||valid>1||shape>(data.decode_u32(4)>=7?3u:shaped?1u:0u))return false;previous=k;offset+=16;
        Region r;r.valid=valid;r.has_density=shape&1;r.replace_water=shape&2;
        for(int i=0;i<512;++i){r.floor[i]=data.decode_u16(offset);r.ceiling[i]=data.decode_u16(offset+2);r.water[i]=data.decode_u64(offset+4);if(r.water[i]>>63){r.water[i]&=~(uint64_t(1)<<63);if(!r.water[i])return false;}offset+=12;
            if(r.floor[i]>r.ceiling[i]||r.ceiling[i]>500||r.water[i]>MAX_TOTAL-sum)return false;sum+=r.water[i];}
        if(shaped)for(float &value:r.density){value=data.decode_float(offset);offset+=4;if(!std::isfinite(value))return false;}
        // Old saved amounts are authoritative, including over-capacity cells.
        // Restore cached profiles without simulation or quantity changes.
        if(install||data.decode_u32(4)>=6)staged.emplace(k,std::move(r));
    }
    if(data.decode_u32(4)>=6){
        for(auto &[k,r]:staged){if(offset+4>data.size())return false;uint32_t present=data.decode_u32(offset);offset+=4;if(present>1)return false;if(!present)continue;
            auto contacts=std::make_shared<TerrainWaterContacts>();
            for(auto &cell:contacts->floors){if(offset+4>data.size())return false;uint32_t count=data.decode_u32(offset);offset+=4;
                if(count>128||offset+int64_t(count)*36>data.size())return false;double area=0;
                for(uint32_t n=0;n<count;++n){WaterCellProfile::Triangle triangle;
                    for(auto &p:triangle){p={data.decode_float(offset),data.decode_float(offset+4),data.decode_float(offset+8)};offset+=12;
                        if(!std::isfinite(p.x)||!std::isfinite(p.z)||!std::isfinite(p.y)||p.x< -1e-6||p.x>1+1e-6||p.z< -1e-6||p.z>1+1e-6||std::abs(p.y)>10000)return false;}
                    auto a=triangle[0],b=triangle[1],c=triangle[2];area+=std::abs((b.x-a.x)*(c.z-a.z)-(b.z-a.z)*(c.x-a.x))*0.5;cell.push_back(triangle);}
                if(count&&std::abs(area-1)>1e-4)return false;
            }
            contacts->bytes=sizeof(TerrainWaterContacts);for(const auto &cell:contacts->floors)contacts->bytes+=cell.capacity()*sizeof(WaterCellProfile::Triangle);
            r.contacts=contacts;
        }
        if(offset!=data.size())return false;
    }
    if(sum!=expected)return false;if(!install)return true;
    cancel_mesh_batch();published_surfaces.clear();published_batch=0;query_cache_bytes=0;query_builds=0;query_cache_hits=0;regions.swap(staged);restored_cache.clear();cache_rebuilds=0;requests.clear();request_set.clear();meshes.clear();mesh_set.clear();fill=Fill{};total=sum;sampled=0;cache_hits=0;changes=0;last_us=max_us=mesh_us=max_mesh_us=0;limit=false;
    for(auto &[k,r]:regions){if(r.valid){++cache_hits;restored_cache.insert(k);}else request(k);
        // Version 1 remains playable during one-time terrain-shape cache upgrade.
        if(!r.has_density)request(k);
        if(mesh_set.insert(k).second)meshes.push_back(k);
        // A face is owned by the minimum endpoint of a crossing edge. A wet
        // boundary node can therefore add only its negative-axis neighbour,
        // not every region in a 3x3x3 reconstruction halo.
        bool negative[3]={false,false,false};
        for(int i=0;i<512;++i)if(r.water[i]&&profile(r,i).capacity()>0){
            if((i&7)==0)negative[0]=true;
            if(((i>>3)&7)==0)negative[1]=true;
            if((i>>6)==0)negative[2]=true;
        }
        Vector3i p=position(k);
        for(int axis=0;axis<3;++axis)if(negative[axis]&&p[axis]>0){
            Vector3i n=p;--n[axis];Key owner=key(n);if(mesh_set.insert(owner).second)meshes.push_back(owner);
        }
    }
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
