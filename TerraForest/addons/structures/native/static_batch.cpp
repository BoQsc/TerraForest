#include "static_batch.hpp"
#include <godot_cpp/classes/multi_mesh.hpp>
#include <godot_cpp/classes/hashing_context.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <cmath>
#include <cstring>
namespace terraforest {
NativeStaticBatch::NativeStaticBatch() {set_notify_transform(true);}
void NativeStaticBatch::_bind_methods() {
    ClassDB::bind_method(D_METHOD("capture_region","region"),&NativeStaticBatch::capture_region);
    ClassDB::bind_method(D_METHOD("validate_region_snapshot","bytes"),&NativeStaticBatch::validate_region_snapshot);
    ClassDB::bind_method(D_METHOD("unload_region","expected_snapshot"),&NativeStaticBatch::unload_region);
    ClassDB::bind_method(D_METHOD("restore_region","bytes"),&NativeStaticBatch::restore_region);
    ClassDB::bind_method(D_METHOD("is_region_loaded","region"),&NativeStaticBatch::is_region_loaded);
    ClassDB::bind_method(D_METHOD("region_stats"),&NativeStaticBatch::region_stats);
    ClassDB::bind_method(D_METHOD("configure_collision_only"),&NativeStaticBatch::configure_collision_only);
    ClassDB::bind_method(D_METHOD("upsert_transforms","ids","transforms"),&NativeStaticBatch::upsert_transforms);
    ClassDB::bind_method(D_METHOD("overlap_mask","transforms","prototype_bounds"),&NativeStaticBatch::overlap_mask);
    ClassDB::bind_method(D_METHOD("can_insert_instance","transform","protected_bounds"),&NativeStaticBatch::can_insert_instance,DEFVAL(AABB()));
    ClassDB::bind_method(D_METHOD("insert_instance","transform","protected_bounds"),&NativeStaticBatch::insert_instance,DEFVAL(AABB()));
    ClassDB::bind_method(D_METHOD("set_instances","mesh","transforms"),&NativeStaticBatch::set_instances);
    ClassDB::bind_method(D_METHOD("configure_asset","asset_id","mesh"),&NativeStaticBatch::configure_asset);
    ClassDB::bind_method(D_METHOD("lock_asset_identity"),&NativeStaticBatch::lock_asset_identity);
    ClassDB::bind_method(D_METHOD("upsert_instances","ids","transforms"),&NativeStaticBatch::upsert_instances);
    ClassDB::bind_method(D_METHOD("remove_instances","ids"),&NativeStaticBatch::remove_instances);
    ClassDB::bind_method(D_METHOD("get_instance","id"),&NativeStaticBatch::get_instance);
    ClassDB::bind_method(D_METHOD("get_ids"),&NativeStaticBatch::get_ids);
    ClassDB::bind_method(D_METHOD("capture_snapshot"),&NativeStaticBatch::capture_snapshot);
    ClassDB::bind_method(D_METHOD("validate_snapshot","bytes"),&NativeStaticBatch::validate_snapshot);
    ClassDB::bind_method(D_METHOD("restore_snapshot","bytes"),&NativeStaticBatch::restore_snapshot);
    ClassDB::bind_method(D_METHOD("stats"),&NativeStaticBatch::stats);
    ClassDB::bind_method(D_METHOD("configure_render_streaming","enabled","radius","batch_limit","byte_limit","uploads_per_tick","bytes_per_tick"),&NativeStaticBatch::configure_render_streaming);
    ClassDB::bind_method(D_METHOD("set_render_focus","focus"),&NativeStaticBatch::set_render_focus);
    ClassDB::bind_method(D_METHOD("render_stats"),&NativeStaticBatch::render_stats);
    ClassDB::bind_method(D_METHOD("configure_collision","box","radius","instance_limit","builds_per_tick"),&NativeStaticBatch::configure_collision);
    ClassDB::bind_method(D_METHOD("configure_compound_collision","boxes","radius","instance_limit","builds_per_tick","shape_limit","shapes_per_tick"),&NativeStaticBatch::configure_compound_collision);
    ClassDB::bind_method(D_METHOD("set_collision_focus","focus"),&NativeStaticBatch::set_collision_focus);
    ClassDB::bind_method(D_METHOD("collision_stats"),&NativeStaticBatch::collision_stats);
    ClassDB::bind_method(D_METHOD("is_collision_region_ready","world_bounds"),&NativeStaticBatch::is_collision_region_ready);
    ClassDB::bind_method(D_METHOD("placement_for_body","body"),&NativeStaticBatch::placement_for_body);
    ADD_SIGNAL(MethodInfo("changed"));
    ADD_SIGNAL(MethodInfo("exclusion_changed"));
}
bool NativeStaticBatch::valid_transform(const float *t) {
    for(int j=0;j<12;j++)if(!std::isfinite(t[j])||std::abs(t[j])>1048575)return false;
    double determinant=t[0]*(double(t[5])*t[10]-double(t[6])*t[9])-t[1]*(double(t[4])*t[10]-double(t[6])*t[8])+t[2]*(double(t[4])*t[9]-double(t[5])*t[8]);
    return std::abs(determinant)>=1e-9;
}
void NativeStaticBatch::publish_change() {
    ++edit_revision;
    if(!defer_change_signal)emit_signal("changed");
}
bool NativeStaticBatch::placement_clear(const PackedFloat32Array &transform,const AABB &protection) const {
    if(source_mesh.is_null()||transform.size()!=12||!valid_transform(transform.ptr())||!protection.position.is_finite()||!protection.size.is_finite()||
       protection.size.x<0||protection.size.y<0||protection.size.z<0)return false;
    Placement p;std::copy(transform.ptr(),transform.ptr()+12,p.begin());
    if(unloaded_regions.count(group_for(p)))return false;
    if(protection.size.x>0&&protection.size.y>0&&protection.size.z>0) {
        Transform3D frame=is_inside_tree()?get_global_transform():get_transform();
        if(!frame.is_finite()||std::abs(frame.basis.determinant())<1e-12)return false;
        Transform3D world=frame*placement_transform(p);
        if(!world.is_finite())return false;
        if(proxy_parts.empty())return !world.xform(source_mesh->get_aabb()).intersects(protection);
        for(const auto &part:proxy_parts)if(world.xform(part).intersects(protection))return false;
    }
    return true;
}
bool NativeStaticBatch::can_insert_instance(const PackedFloat32Array &transform,const AABB &protection) const {
    if(!placement_clear(transform,protection)||placements.size()+unloaded_ids.size()>=100000||
       (!placements.empty()&&placements.rbegin()->first==INT64_MAX)||
       (!unloaded_ids.empty()&&*unloaded_ids.rbegin()==INT64_MAX))return false;
    Placement p;std::copy(transform.ptr(),transform.ptr()+12,p.begin());
    return groups.count(group_for(p))||groups.size()+unloaded_regions.size()<4096;
}
int64_t NativeStaticBatch::insert_instance(const PackedFloat32Array &transform,const AABB &protection) {
    if(!can_insert_instance(transform,protection))return 0;
    int64_t id=placements.empty()?0:placements.rbegin()->first;
    if(!unloaded_ids.empty())id=std::max(id,*unloaded_ids.rbegin());
    ++id;
    PackedInt64Array ids;ids.push_back(id);
    return upsert_instances(ids,transform)?id:0;
}
BlockKey NativeStaticBatch::group_for(const Placement &p) {return {int(std::floor(p[3]/32)),int(std::floor(p[7]/32)),int(std::floor(p[11]/32))};}
bool NativeStaticBatch::valid_asset(const String &id) {
    if(id.is_empty()||id.length()>128)return false;
    for(int i=0;i<id.length();i++)if(id[i]<33||id[i]>126)return false;
    return true;
}
bool NativeStaticBatch::configure_asset(const String &id,const Ref<Mesh> &mesh) {
    if(!unloaded_regions.empty()&&(id!=asset_id||mesh!=source_mesh))return false;
    if(!valid_asset(id)||mesh.is_null()||((asset_locked||!placements.empty())&&!asset_id.is_empty()&&asset_id!=id))return false;
    bool changed=asset_id!=id||source_mesh!=mesh;
    asset_id=id;source_mesh=mesh;
    std::set<BlockKey> keys;for(auto &e:groups)keys.insert(e.first);refresh_collision_bounds(keys);
    for(auto &e:batches)e.second->get_multimesh()->set_mesh(mesh);
    // Invalidate journals before either notification can call back into editing.
    if(changed)++edit_revision;
    emit_signal("exclusion_changed");
    if(changed&&!defer_change_signal)emit_signal("changed");return true;
}
bool NativeStaticBatch::lock_asset_identity() {if(!valid_asset(asset_id)||source_mesh.is_null())return false;asset_locked=true;return true;}
bool NativeStaticBatch::configure_collision_only(){
    if(!placements.empty()||!unloaded_regions.empty()||!batches.empty())return false;
    collision_only=true;set_process(false);return true;
}
bool NativeStaticBatch::upsert_transforms(const PackedInt64Array &ids,const TypedArray<Transform3D> &transforms){
    if(ids.size()!=transforms.size()||ids.size()>100000)return false;
    PackedFloat32Array packed;packed.resize(ids.size()*12);float *out=packed.ptrw();
    for(int64_t i=0;i<ids.size();++i){
        Transform3D t=transforms[i];
        for(int row=0;row<3;++row){
            for(int column=0;column<3;++column)out[i*12+row*4+column]=t.basis[row][column];
            out[i*12+row*4+3]=t.origin[row];
        }
    }
    return upsert_instances(ids,packed);
}
void NativeStaticBatch::rebuild(const std::set<BlockKey> &keys) {
    // Membership changes invalidate page offsets. Ordinary same-group transform
    // edits bypass this path and retain the ordered index allocation.
    for(auto key:keys)render_ids.erase(key);
    refresh_collision_bounds(keys);
    // Release all old memberships before assigning slots in their new groups.
    for(auto k:keys)release_group(k);
    if(collision_only)return;
    if(render_streaming) {if(!keys.empty())render_dirty=true;return;}
    for(auto k:keys)if(groups.count(k))upload_batch({k,0});
}
bool NativeStaticBatch::upsert_instances(const PackedInt64Array &ids,const PackedFloat32Array &transforms) {
    if(source_mesh.is_null()||ids.size()>100000||transforms.size()!=ids.size()*12)return false;
    std::map<int64_t,Placement> staged;
    std::map<BlockKey,int> counts;
    int added=0;
    auto delta=[&](BlockKey k,int n){auto it=counts.find(k);if(it==counts.end()){auto g=groups.find(k);it=counts.emplace(k,g==groups.end()?0:int(g->second.size())).first;}it->second+=n;};
    for(int64_t i=0;i<ids.size();i++) {
        int64_t id=ids[i];const float *t=transforms.ptr()+i*12;
        if(id<=0||staged.count(id)||unloaded_ids.count(id)||!valid_transform(t))return false;
        Placement p;std::copy(t,t+12,p.begin());staged.emplace(id,p);
        if(unloaded_regions.count(group_for(p)))return false;
        auto old=placements.find(id);
        if(old!=placements.end())delta(group_for(old->second),-1);else added++;
        delta(group_for(p),1);
    }
    if(placements.size()+unloaded_ids.size()+added>100000)return false;
    int group_count=int(groups.size());for(auto &e:counts)group_count+=(e.second>0)-(groups.count(e.first)>0);
    if(group_count+unloaded_regions.size()>4096)return false;
    std::set<BlockKey> touched;
    std::map<BlockKey,std::vector<int64_t>> local_updates;
    for(auto &e:staged) {
        auto old=placements.find(e.first);
        if(old!=placements.end()&&old->second==e.second)continue;
        invalidate_proxy(e.first);
        if(old!=placements.end()) {
            auto a=group_for(old->second),b=group_for(e.second);
            if(!(a<b)&&!(b<a)) {
                old->second=e.second;local_updates[a].push_back(e.first);continue;
            }
        }
        if(old!=placements.end()) {
            auto k=group_for(old->second);auto &g=groups.at(k);g.erase(e.first);if(g.empty())groups.erase(k);touched.insert(k);
        }
        auto k=group_for(e.second);placements[e.first]=e.second;groups[k].insert(e.first);touched.insert(k);
    }
    // A few moves inside an existing group update GPU slots directly. Large
    // edits use one buffer upload instead of thousands of renderer API calls.
    for(auto &e:local_updates)if(!render_streaming&&e.second.size()>64)touched.insert(e.first);
    rebuild(touched);
    std::set<BlockKey> locally_changed;for(auto &e:local_updates)if(!touched.count(e.first))locally_changed.insert(e.first);
    refresh_collision_bounds(locally_changed);
    for(auto &e:local_updates)if(!touched.count(e.first)) {
        if(collision_only)continue;
        if(render_streaming) {
            // Same-group transforms preserve sorted membership. Rebuild only
            // their draw pages; untouched pages retain both nodes and buffers.
            const auto &ordered=render_ids.at(e.first);std::set<uint32_t> pages;
            for(auto id:e.second) {
                auto index=std::lower_bound(ordered.begin(),ordered.end(),id)-ordered.begin();
                pages.insert(uint32_t(index/render_page_capacity()));
            }
            for(auto page:pages)release_batch({e.first,page});
            continue;
        }
        if(!batches.count({e.first,0}))continue;
        auto multi=batches.at({e.first,0})->get_multimesh();
        for(auto id:e.second) {
            auto &p=placements.at(id);Basis basis(p[0],p[1],p[2],p[4],p[5],p[6],p[8],p[9],p[10]);
            multi->set_instance_transform(slots.at(id),Transform3D(basis,Vector3(p[3]-e.first.x*32,p[7]-e.first.y*32,p[11]-e.first.z*32)));instance_updates++;
        }
    }
    if(!touched.empty()||!local_updates.empty())publish_change();return true;
}
bool NativeStaticBatch::remove_instances(const PackedInt64Array &ids) {
    if(ids.size()>100000)return false;std::set<int64_t> unique;
    for(int64_t id:ids)if(id<=0||!placements.count(id)||!unique.insert(id).second)return false;
    std::set<BlockKey> touched;
    for(auto id:unique) {
        invalidate_proxy(id);
        auto old=placements.find(id);auto k=group_for(old->second);auto &g=groups.at(k);g.erase(id);if(g.empty())groups.erase(k);
        placements.erase(old);slots.erase(id);touched.insert(k);
    }
    rebuild(touched);if(!touched.empty())publish_change();return true;
}
bool NativeStaticBatch::set_instances(const Ref<Mesh> &mesh,const PackedFloat32Array &transforms) {
    if(!unloaded_regions.empty())return false;
    if(mesh.is_null()||transforms.size()%12||transforms.size()>1200000)return false;
    std::map<int64_t,Placement> staged;std::map<BlockKey,std::set<int64_t>> staged_groups;
    for(int64_t i=0;i<transforms.size()/12;i++) {
        const float *t=transforms.ptr()+i*12;if(!valid_transform(t))return false;
        Placement p;std::copy(t,t+12,p.begin());auto k=group_for(p);
        if(!staged_groups.count(k)&&staged_groups.size()>=4096)return false;
        staged[i+1]=p;staged_groups[k].insert(i+1);
    }
    std::set<BlockKey> touched;for(auto &e:groups)touched.insert(e.first);for(auto &e:staged_groups)touched.insert(e.first);
    clear_proxies();collision_bounds.clear();collision_dirty=true;
    placements=std::move(staged);groups=std::move(staged_groups);slots.clear();source_mesh=mesh;
    for(auto &e:batches)e.second->get_multimesh()->set_mesh(mesh);
    rebuild(touched);publish_change();return true;
}
PackedFloat32Array NativeStaticBatch::get_instance(int64_t id) const {
    PackedFloat32Array result;auto it=placements.find(id);if(it==placements.end())return result;
    result.resize(12);std::copy(it->second.begin(),it->second.end(),result.ptrw());return result;
}
PackedInt64Array NativeStaticBatch::get_ids() const {PackedInt64Array out;out.resize(placements.size());int i=0;for(auto &e:placements)out.set(i++,e.first);return out;}
static PackedByteArray checksum(const PackedByteArray &bytes) {Ref<HashingContext> h;h.instantiate();h->start(HashingContext::HASH_SHA256);h->update(bytes);return h->finish();}
PackedByteArray NativeStaticBatch::capture_snapshot() const {
    if(!unloaded_regions.empty())return {};
    return encode_placements(asset_id,placements);
}
PackedByteArray NativeStaticBatch::encode_placements(const String &id,const std::map<int64_t,Placement> &values) {
    PackedByteArray result;if(!valid_asset(id))return result;
    std::vector<uint8_t> data={'T','F','S','I',1,0,0,0};
    auto write=[&](uint64_t n,int size){for(int i=0;i<size;i++)data.push_back(uint8_t(n>>(i*8)));};
    auto asset=id.to_utf8_buffer();write(asset.size(),4);write(values.size(),4);
    data.insert(data.end(),asset.ptr(),asset.ptr()+asset.size());
    for(auto &e:values) {write(uint64_t(e.first),8);for(float v:e.second){uint32_t bits;std::memcpy(&bits,&v,4);write(bits,4);}}
    result.resize(data.size());std::memcpy(result.ptrw(),data.data(),data.size());result.append_array(checksum(result));return result;
}
bool NativeStaticBatch::parse(const PackedByteArray &bytes,String &asset,std::map<int64_t,Placement> *out) {
    if(bytes.size()<49||bytes.size()>5600176||std::memcmp(bytes.ptr(),"TFSI\1\0\0\0",8))return false;
    auto payload=bytes.slice(0,bytes.size()-32);if(checksum(payload)!=bytes.slice(bytes.size()-32))return false;
    const uint8_t *data=payload.ptr();size_t p=8;
    auto read=[&](int size){uint64_t v=0;for(int i=0;i<size;i++)v|=uint64_t(data[p++])<<(i*8);return v;};
    uint32_t length=uint32_t(read(4)),count=uint32_t(read(4));
    if(!length||length>128||count>100000||uint64_t(payload.size())!=16+uint64_t(length)+uint64_t(count)*56)return false;
    for(uint32_t i=0;i<length;i++)if(data[p+i]<33||data[p+i]>126)return false;
    asset=String::utf8(reinterpret_cast<const char*>(data+p),length);p+=length;
    std::set<BlockKey> keys;int64_t previous=0;
    for(uint32_t i=0;i<count;i++) {
        uint64_t raw=read(8);if(raw>uint64_t(INT64_MAX)||int64_t(raw)<=previous)return false;previous=int64_t(raw);
        Placement t;for(auto &v:t){uint32_t bits=uint32_t(read(4));std::memcpy(&v,&bits,4);}
        if(!valid_transform(t.data()))return false;
        keys.insert(group_for(t));if(keys.size()>4096)return false;
        if(out)out->emplace(previous,t);
    }
    return true;
}
bool NativeStaticBatch::validate_snapshot(const PackedByteArray &bytes) const {String asset;return parse(bytes,asset,nullptr);}
bool NativeStaticBatch::restore_snapshot(const PackedByteArray &bytes) {
    String asset;std::map<int64_t,Placement> restored;
    if(!parse(bytes,asset,&restored)||asset!=asset_id||source_mesh.is_null())return false;
    unloaded_regions.clear();unloaded_ids.clear();
    std::set<BlockKey> touched;for(auto &e:groups)touched.insert(e.first);
    clear_proxies();collision_bounds.clear();collision_dirty=true;
    placements=std::move(restored);groups.clear();slots.clear();for(auto &e:placements){auto k=group_for(e.second);groups[k].insert(e.first);touched.insert(k);}
    rebuild(touched);publish_change();return true;
}
Dictionary NativeStaticBatch::stats() const {
    Dictionary d;d["instances"]=int(placements.size());d["spatial_batches"]=int(batches.size());d["transform_bytes"]=int(placements.size())*48;
    d["asset_id"]=asset_id;d["batch_uploads"]=int64_t(uploads);d["instance_updates"]=int64_t(instance_updates);d["slot_entries"]=int(slots.size());return d;
}
}
