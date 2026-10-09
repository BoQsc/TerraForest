// SPDX-License-Identifier: 0BSD
#include "prefab_transaction.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/object.hpp>
#include <godot_cpp/classes/time.hpp>
#include <algorithm>
#include <cmath>
namespace terraforest {
namespace {
Dictionary failure(const char *reason){Dictionary d;d["ok"]=false;d["status"]="failed";d["reason"]=reason;return d;}
bool protection_valid(const Array &boxes,const AABB &envelope) {
    if(boxes.size()>16)return false;
    for(int i=0;i<boxes.size();++i) {
        if(boxes[i].get_type()!=Variant::AABB)return false;
        const AABB b=boxes[i];
        if(!b.position.is_finite()||!b.size.is_finite()||b.size.x<0||b.size.y<0||b.size.z<0)return false;
        if(b.size.x>0&&b.size.y>0&&b.size.z>0&&b.intersects(envelope))return false;
    }
    return true;
}
}
struct NativePrefabPlacement::Pending {
    Ref<NativeBlockPrefab> prefab;
    uint64_t source_revision=0,block_id=0,block_revision=0;
    Vector3i origin;int turns=0;
    AABB envelope,changed_bounds;
    Transform3D placement;
    struct Collection {uint64_t id,revision;Ref<Mesh> mesh;AABB mesh_box;std::vector<AABB> parts;};
    std::map<String,Collection> models;
    struct Stage {uint64_t id=0;std::map<int64_t,NativeStaticBatch::Placement> values;std::set<BlockKey> touched;int64_t next=0;};
    std::map<String,Stage> staged;
    std::map<BlockKey,BlockChunk> chunks;
    std::set<BlockKey> invalidations;
    std::map<BlockKey,std::vector<AABB>> inserted_parts;
    size_t cell_at=0,model_at=0,new_chunks=0;
    uint64_t probes=0,comparisons=0,block_us=0,model_us=0;
    bool ready=false;
};
NativePrefabPlacement::NativePrefabPlacement()=default;
NativePrefabPlacement::~NativePrefabPlacement()=default;
void NativePrefabPlacement::_bind_methods() {
    ClassDB::bind_method(D_METHOD("place","blocks","prefab","origin","quarter_turns","models","protected_boxes"),&NativePrefabPlacement::place);
    ClassDB::bind_method(D_METHOD("begin","blocks","prefab","origin","quarter_turns","models","protected_boxes"),&NativePrefabPlacement::begin);
    ClassDB::bind_method(D_METHOD("advance","max_cells","max_models","max_usec"),&NativePrefabPlacement::advance);
    ClassDB::bind_method(D_METHOD("commit","protected_boxes"),&NativePrefabPlacement::commit);
    ClassDB::bind_method(D_METHOD("cancel"),&NativePrefabPlacement::cancel);
    ClassDB::bind_method(D_METHOD("model_counts","prefab"),&NativePrefabPlacement::model_counts);
}
Dictionary NativePrefabPlacement::model_counts(const Ref<NativeBlockPrefab> &prefab) const {
    Dictionary counts;if(prefab.is_null())return counts;
    for(int i=0;i<prefab->model_attachments.size();++i) {
        const Dictionary item=prefab->model_attachments[i];const String key=item["model"];
        counts[key]=int64_t(counts.get(key,0))+1;
    }
    return counts;
}
bool NativePrefabPlacement::cancel(){if(busy)return false;pending.reset();return true;}
bool NativePrefabPlacement::current() const {
    if(!pending)return false;
    const auto &p=*pending;
    auto *blocks=Object::cast_to<NativeBlockWorld>(ObjectDB::get_instance(p.block_id));
    if(!blocks||blocks->mutation_revision!=p.block_revision||p.prefab->definition_revision!=p.source_revision||
       (blocks->is_inside_tree()?blocks->get_global_transform():blocks->get_transform())!=Transform3D())return false;
    for(const auto &entry:p.models) {
        const auto &m=entry.second;
        auto *batch=Object::cast_to<NativeStaticBatch>(ObjectDB::get_instance(m.id));
        if(!batch||batch->edit_revision!=m.revision||batch->admission||batch->defer_change_signal||batch->asset_id!=entry.first||batch->source_mesh!=m.mesh||batch->proxy_parts!=m.parts||
           (batch->is_inside_tree()?batch->get_global_transform():batch->get_transform())!=Transform3D())return false;
        if(m.mesh.is_valid()&&m.mesh->get_aabb()!=m.mesh_box)return false;
        if(p.staged.count(entry.first)&&!batch->render_streaming)return false;
    }
    return true;
}
Dictionary NativePrefabPlacement::state() const {
    Dictionary d;d["ok"]=bool(pending);d["status"]=pending?(pending->ready?"ready":"preparing"):"idle";
    if(pending){d["prepared_cells"]=int64_t(pending->cell_at);d["prepared_models"]=int64_t(pending->model_at);d["staged_chunks"]=int64_t(pending->chunks.size());}
    return d;
}
Dictionary NativePrefabPlacement::begin(NativeBlockWorld *blocks,const Ref<NativeBlockPrefab> &prefab,Vector3i origin,int turns,const Dictionary &models,const Array &protected_boxes) {
    if(busy||pending||!blocks||prefab.is_null()||prefab->cells.empty()||turns<0||turns>3||models.size()>256)return failure("Invalid or busy placement");
    for(int a=0;a<3;++a)if(origin[a]<-1048575||origin[a]>1048575)return failure("Invalid placement origin");
    if((blocks->is_inside_tree()?blocks->get_global_transform():blocks->get_transform())!=Transform3D())return failure("Unsupported block frame");
    auto next=std::make_unique<Pending>();auto &p=*next;
    p.prefab=prefab;p.source_revision=prefab->definition_revision;p.block_id=blocks->get_instance_id();p.block_revision=blocks->mutation_revision;p.origin=origin;p.turns=turns;
    p.envelope=prefab->placement_bounds(origin,turns);
    if(!protection_valid(protected_boxes,p.envelope))return failure("Invalid protection or protected actor overlaps building");
    Vector3 x_axis(1,0,0),z_axis(0,0,1);
    for(int r=0;r<turns;++r){x_axis=Vector3(-x_axis.z,0,x_axis.x);z_axis=Vector3(-z_axis.z,0,z_axis.x);}
    const Basis rotation(x_axis,Vector3(0,1,0),z_axis);const Vector3 half(0.5,0,0.5);
    p.placement=Transform3D(rotation,Vector3(origin)+half-rotation.xform(half));
    const Array keys=models.keys();
    for(int i=0;i<keys.size();++i) {
        if(keys[i].get_type()!=Variant::STRING||models[keys[i]].get_type()!=Variant::OBJECT)return failure("Invalid model registry");
        auto *batch=Object::cast_to<NativeStaticBatch>(models[keys[i]]);
        if(!batch||batch->asset_id!=String(keys[i])||batch->admission||batch->defer_change_signal)return failure("Model collection unavailable");
        if((batch->is_inside_tree()?batch->get_global_transform():batch->get_transform())!=Transform3D())return failure("Unsupported model frame");
        p.models.emplace(String(keys[i]),Pending::Collection{batch->get_instance_id(),batch->edit_revision,batch->source_mesh,batch->source_mesh.is_valid()?batch->source_mesh->get_aabb():AABB(),batch->proxy_parts});
    }
    pending=std::move(next);return state();
}
Dictionary NativePrefabPlacement::advance(int64_t max_cells,int64_t max_models,int64_t max_usec) {
    if(busy||!pending||max_cells<1||max_cells>8192||max_models<1||max_models>64||max_usec<100||max_usec>4000)return failure("Invalid preparation budget or no pending placement");
    auto fail=[&](const char *why){pending.reset();return failure(why);};
    if(!current())return fail("World, model or source changed during preparation");
    auto &p=*pending;const auto started=Time::get_singleton()->get_ticks_usec();
    auto *blocks=Object::cast_to<NativeBlockWorld>(ObjectDB::get_instance(p.block_id));
    const auto &prefab=p.prefab;const auto origin=p.origin;const int turns=p.turns;
    if(p.cell_at<prefab->cells.size()) {
        int64_t count=0;
        while(p.cell_at<prefab->cells.size()&&count<max_cells) {
            if(count&&count%32==0&&Time::get_singleton()->get_ticks_usec()-started>=uint64_t(max_usec))break;
            const auto &c=prefab->cells[p.cell_at];int64_t x=c.x,y=int64_t(c.y)+origin.y,z=c.z;
            for(int r=0;r<turns;++r){int64_t old=x;x=-z;z=old;}x+=origin.x;z+=origin.z;
            for(auto v:{x,y,z})if(v<-1048575||v>1048575)return fail("Block coordinate limit exceeded");
            const auto key=NativeBlockWorld::key_for(int(x),int(y),int(z));
            if(blocks->unloaded_regions.count(NativeBlockWorld::region_for(key)))return fail("Block region unavailable");
            auto staged=p.chunks.find(key);
            if(staged==p.chunks.end()) {
                auto existing=blocks->chunks.find(key);
                if(existing==blocks->chunks.end())++p.new_chunks;
                if(blocks->chunks.size()+p.new_chunks>2048||p.chunks.size()>=2048)return fail("Block chunk capacity exceeded");
                staged=p.chunks.emplace(key,existing==blocks->chunks.end()?BlockChunk():existing->second).first;
                const AABB box(Vector3(key.x*16,key.y*16,key.z*16),Vector3(16,16,16));
                p.changed_bounds=p.chunks.size()==1?box:p.changed_bounds.merge(box);
                for(const auto &neighbor:std::initializer_list<BlockKey>{key,{key.x-1,key.y,key.z},{key.x+1,key.y,key.z},{key.x,key.y-1,key.z},{key.x,key.y+1,key.z},{key.x,key.y,key.z-1},{key.x,key.y,key.z+1}})p.invalidations.insert(neighbor);
            }
            auto &chunk=staged->second;auto &word=chunk.cells[NativeBlockWorld::index(int(x),int(y),int(z))];
            if(word)return fail("Prefab block occupied");
            word=uint16_t((c.word&~24)|((((c.word>>3)+turns)&3)<<3));++chunk.count;
            chunk.columns[(x&15)+16*(z&15)]|=uint16_t(1u<<(y&15));
            ++p.cell_at;++count;
        }
        p.block_us+=Time::get_singleton()->get_ticks_usec()-started;
        return state();
    }
    auto proposed_cell=[&](int x,int y,int z) {
        x-=origin.x;y-=origin.y;z-=origin.z;
        for(int r=0;r<turns;++r){int old=x;x=z;z=-old;}
        const PrefabCell key{x,y,z,0};const auto &cells=prefab->cells;
        auto it=std::lower_bound(cells.begin(),cells.end(),key,[](const PrefabCell &a,const PrefabCell &b){return std::tie(a.x,a.y,a.z)<std::tie(b.x,b.y,b.z);});
        return it!=cells.end()&&it->x==x&&it->y==y&&it->z==z;
    };
    auto &staged=p.staged;auto &inserted_parts=p.inserted_parts;auto &probes=p.probes;auto &comparisons=p.comparisons;
    const auto &envelope=p.envelope;const auto &placement=p.placement;
    std::vector<NativeStaticBatch*> collections;
    for(const auto &entry:p.models)collections.push_back(Object::cast_to<NativeStaticBatch>(ObjectDB::get_instance(entry.second.id)));
    int64_t count=0;
    while(p.model_at<size_t(prefab->model_attachments.size())&&count<max_models) {
        if(count&&Time::get_singleton()->get_ticks_usec()-started>=uint64_t(max_usec))break;
        const int i=int(p.model_at);
        const Dictionary item=prefab->model_attachments[i];const String key=item["model"];
        if(!p.models.count(key))return fail("Missing model asset");
        auto *batch=Object::cast_to<NativeStaticBatch>(ObjectDB::get_instance(p.models.at(key).id));
        if(batch->source_mesh.is_null()||!batch->render_streaming)return fail("Model requires bounded streaming");
        auto &stage=staged[key];
        if(!stage.id) {
            stage.id=batch->get_instance_id();stage.next=batch->placements.empty()?0:batch->placements.rbegin()->first;
            if(!batch->unloaded_ids.empty())stage.next=std::max(stage.next,*batch->unloaded_ids.rbegin());
        }
        if(stage.next==INT64_MAX||batch->placements.size()+batch->unloaded_ids.size()+stage.values.size()>=100000)return fail("Model identity or capacity exhausted");
        const Transform3D pose=placement*Transform3D(item["transform"]);
        NativeStaticBatch::Placement packed;
        for(int row=0;row<3;++row){for(int col=0;col<3;++col)packed[row*4+col]=pose.basis[row][col];packed[row*4+3]=pose.origin[row];}
        if(!NativeStaticBatch::valid_transform(packed.data()))return fail("Invalid placed model transform");
        const auto group=NativeStaticBatch::group_for(packed);
        if(batch->unloaded_regions.count(group)||batch->retirement_locks(group))return fail("Model destination unavailable");
        stage.touched.insert(group);
        size_t new_groups=0;for(auto g:stage.touched)if(!batch->groups.count(g))++new_groups;
        if(batch->groups.size()+batch->unloaded_regions.size()+new_groups>4096)return fail("Model group capacity exceeded");
        const int parts=batch->proxy_parts.empty()?1:int(batch->proxy_parts.size());
        uint64_t model_probes=0;
        for(int part=0;part<parts;++part) {
            AABB box=pose.xform(batch->proxy_parts.empty()?batch->source_mesh->get_aabb():batch->proxy_parts[part]);
            if(!envelope.encloses(box))return fail("Model extends outside surveyed building envelope");
            // Remove numerical contact at floors/walls; retain genuine overlap.
            box=box.grow(-0.0001);
            if(box.size.x<=0||box.size.y<=0||box.size.z<=0)return fail("Degenerate model bounds");
            if(blocks->occupied(box))return fail("Model overlaps existing blocks");
            Vector3i lo=box.position.floor(),hi=box.get_end().floor();
            uint64_t volume=uint64_t(hi.x-lo.x+1)*(hi.y-lo.y+1)*(hi.z-lo.z+1);
            model_probes+=volume;if(model_probes>4096)return fail("Single-model validation budget exceeded");
            probes+=volume;if(probes>262144)return fail("Model block-validation budget exceeded");
            for(int z=lo.z;z<=hi.z;++z)for(int y=lo.y;y<=hi.y;++y)for(int x=lo.x;x<=hi.x;++x)if(proposed_cell(x,y,z))return fail("Model overlaps prefab blocks");
            const Vector3i grid_lo=(box.position/4).floor(),grid_hi=(box.get_end()/4).floor();
            for(int z=grid_lo.z;z<=grid_hi.z;++z)for(int y=grid_lo.y;y<=grid_hi.y;++y)for(int x=grid_lo.x;x<=grid_hi.x;++x) {
                auto found=inserted_parts.find({x,y,z});if(found==inserted_parts.end())continue;
                for(const auto &b:found->second){if(++comparisons>262144)return fail("Model overlap-validation budget exceeded");if(box.intersects(b))return fail("Prefab models overlap");}
            }
            // Avoid comparing touching/overlapping compound parts of one model.
            TypedArray<Transform3D> query;query.push_back(Transform3D());
            for(auto *other:collections){auto mask=other->overlap_mask(query,box);if(mask.size()!=1||mask[0])return fail("Model overlaps existing or unavailable objects");}
        }
        for(int part=0;part<parts;++part) {
            const AABB box=pose.xform(batch->proxy_parts.empty()?batch->source_mesh->get_aabb():batch->proxy_parts[part]).grow(-0.0001);
            const Vector3i lo=(box.position/4).floor(),hi=(box.get_end()/4).floor();
            for(int z=lo.z;z<=hi.z;++z)for(int y=lo.y;y<=hi.y;++y)for(int x=lo.x;x<=hi.x;++x)inserted_parts[{x,y,z}].push_back(box);
        }
        stage.values.emplace(++stage.next,packed);

        ++p.model_at;++count;
    }
    p.model_us+=Time::get_singleton()->get_ticks_usec()-started;
    p.ready=p.model_at==size_t(prefab->model_attachments.size());return state();
}
Dictionary NativePrefabPlacement::commit(const Array &protected_boxes) {
    if(busy||!pending||!pending->ready)return failure("Placement is not ready");
    if(!current()||!protection_valid(protected_boxes,pending->envelope)){pending.reset();return failure("World, source or protection changed before commit");}
    const auto started=Time::get_singleton()->get_ticks_usec();
    auto work=std::move(pending);auto &p=*work;busy=true;
    auto *blocks=Object::cast_to<NativeBlockWorld>(ObjectDB::get_instance(p.block_id));
    // No validation, per-cell traversal or scripts in this publication section.
    // Transfer prepared nodes for new chunks; existing chunks receive one copy.
    for(auto it=p.chunks.begin();it!=p.chunks.end();) {
        auto existing=blocks->chunks.find(it->first);
        if(existing!=blocks->chunks.end()){existing->second=std::move(it->second);it=p.chunks.erase(it);}
        else {auto next=it++;blocks->chunks.insert(p.chunks.extract(next));}
    }
    ++blocks->mutation_revision;
    for(auto key:p.invalidations)blocks->invalidate(key);
    blocks->clear_history();blocks->set_process(true);
    const auto blocks_committed=Time::get_singleton()->get_ticks_usec();
    for(auto &entry:p.staged) {
        auto &s=entry.second;auto *batch=Object::cast_to<NativeStaticBatch>(ObjectDB::get_instance(s.id));
        for(const auto &v:s.values)batch->groups[NativeStaticBatch::group_for(v.second)].insert(v.first);
        batch->placements.merge(s.values);++batch->edit_revision;
    }
    const auto models_committed=Time::get_singleton()->get_ticks_usec();
    for(auto &entry:p.staged) {
        auto &s=entry.second;auto *batch=Object::cast_to<NativeStaticBatch>(ObjectDB::get_instance(s.id));
        for(auto key:s.touched)batch->render_ids.erase(key);
        batch->refresh_collision_bounds(s.touched);
    }
    // All authoring records and query bounds agree before renderer nodes or
    // public notifications can invoke scene callbacks.
    for(auto &entry:p.staged)if(auto *batch=Object::cast_to<NativeStaticBatch>(ObjectDB::get_instance(entry.second.id)))batch->rebuild(entry.second.touched);
    if(auto *live=ObjectDB::get_instance(p.block_id))live->emit_signal("cells_changed",p.changed_bounds);
    if(auto *live=ObjectDB::get_instance(p.block_id))live->emit_signal("changed");
    for(const auto &entry:p.staged)if(auto *live=ObjectDB::get_instance(entry.second.id))live->emit_signal("changed");
    busy=false;
    Dictionary result;result["ok"]=true;result["status"]="committed";result["models"]=int64_t(p.model_at);result["block_probes"]=p.probes;result["model_comparisons"]=p.comparisons;
    Dictionary timing;timing["block_validation_us"]=p.block_us;timing["model_validation_us"]=p.model_us;timing["block_commit_us"]=blocks_committed-started;timing["model_commit_us"]=models_committed-blocks_committed;timing["publication_us"]=Time::get_singleton()->get_ticks_usec()-models_committed;result["timing"]=timing;return result;
}
Dictionary NativePrefabPlacement::place(NativeBlockWorld *blocks,const Ref<NativeBlockPrefab> &prefab,Vector3i origin,int turns,const Dictionary &models,const Array &protected_boxes) {
    Dictionary result=begin(blocks,prefab,origin,turns,models,protected_boxes);
    if(!bool(result["ok"]))return result;
    do {result=advance(8192,64,4000);}while(bool(result["ok"])&&String(result["status"])=="preparing");
    return bool(result["ok"])?commit(protected_boxes):result;
}
}
