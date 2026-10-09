// SPDX-License-Identifier: 0BSD
#include "prefab_transaction.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/object.hpp>
#include <algorithm>
#include <cmath>
namespace terraforest {
void NativePrefabPlacement::_bind_methods() {
    ClassDB::bind_method(D_METHOD("place","blocks","prefab","origin","quarter_turns","models","protected_boxes"),&NativePrefabPlacement::place);
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
Dictionary NativePrefabPlacement::place(NativeBlockWorld *blocks,const Ref<NativeBlockPrefab> &prefab,Vector3i origin,int turns,const Dictionary &models,const Array &protected_boxes) {
    auto fail=[](const char *why){Dictionary d;d["ok"]=false;d["reason"]=why;return d;};
    if(busy||!blocks||prefab.is_null()||models.size()>256||protected_boxes.size()>16)return fail("Invalid or busy placement");
    // Main-world collections share world coordinates. Reject other frames until
    // their block/model conversion and world-space protection are supported.
    if((blocks->is_inside_tree()?blocks->get_global_transform():blocks->get_transform())!=Transform3D())return fail("Unsupported block frame");
    PackedInt32Array records;
    if(!blocks->prefab_records(prefab,origin,turns,false,&records))return fail("Blocks occupied, unavailable or over capacity");
    std::vector<AABB> protected_regions;
    for(int i=0;i<protected_boxes.size();++i) {
        if(protected_boxes[i].get_type()!=Variant::AABB)return fail("Invalid protection");
        AABB b=protected_boxes[i];if(!b.position.is_finite()||!b.size.is_finite()||b.size.x<0||b.size.y<0||b.size.z<0)return fail("Invalid protection");
        if(b.size.x>0&&b.size.y>0&&b.size.z>0)protected_regions.push_back(b);
    }
    const AABB envelope=prefab->placement_bounds(origin,turns);
    for(const auto &b:protected_regions)if(b.intersects(envelope))return fail("Protected actor overlaps building");
    // Coordinate index of this insertion only, never a full-world snapshot.
    std::set<std::tuple<int,int,int>> occupied;
    for(int i=0;i<records.size();i+=4)occupied.emplace(records[i],records[i+1],records[i+2]);
    struct Stage {NativeStaticBatch *batch=nullptr;std::map<int64_t,NativeStaticBatch::Placement> values;std::set<BlockKey> touched;int64_t next=0;};
    std::map<String,Stage> staged;
    Vector3 x_axis(1,0,0),z_axis(0,0,1);
    for(int r=0;r<turns;++r){x_axis=Vector3(-x_axis.z,0,x_axis.x);z_axis=Vector3(-z_axis.z,0,z_axis.x);}
    const Basis rotation(x_axis,Vector3(0,1,0),z_axis);const Vector3 half(0.5,0,0.5);
    const Transform3D placement(rotation,Vector3(origin)+half-rotation.xform(half));
    std::vector<NativeStaticBatch*> collections;
    const Array keys=models.keys();
    for(int i=0;i<keys.size();++i) {
        if(keys[i].get_type()!=Variant::STRING||models[keys[i]].get_type()!=Variant::OBJECT)return fail("Invalid model registry");
        auto *batch=Object::cast_to<NativeStaticBatch>(models[keys[i]]);
        if(!batch||batch->asset_id!=String(keys[i])||batch->admission||batch->defer_change_signal)return fail("Model collection unavailable");
        if((batch->is_inside_tree()?batch->get_global_transform():batch->get_transform())!=Transform3D())return fail("Unsupported model frame");
        collections.push_back(batch);
    }
    // Interior objects must fit inside the already surveyed block envelope.
    // Total query work is capped; large or pathological props reject, not stall.
    uint64_t probes=0,comparisons=0;std::map<BlockKey,std::vector<AABB>> inserted_parts;
    for(int i=0;i<prefab->model_attachments.size();++i) {
        const Dictionary item=prefab->model_attachments[i];const String key=item["model"];
        if(!models.has(key))return fail("Missing model asset");
        auto *batch=Object::cast_to<NativeStaticBatch>(models[key]);
        if(batch->source_mesh.is_null()||!batch->render_streaming)return fail("Model requires bounded streaming");
        auto &stage=staged[key];
        if(!stage.batch) {
            stage.batch=batch;stage.next=batch->placements.empty()?0:batch->placements.rbegin()->first;
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
        for(int part=0;part<parts;++part) {
            AABB box=pose.xform(batch->proxy_parts.empty()?batch->source_mesh->get_aabb():batch->proxy_parts[part]);
            if(!envelope.encloses(box))return fail("Model extends outside surveyed building envelope");
            // Remove numerical contact at floors/walls; retain genuine overlap.
            box=box.grow(-0.0001);
            if(box.size.x<=0||box.size.y<=0||box.size.z<=0)return fail("Degenerate model bounds");
            for(const auto &b:protected_regions)if(box.intersects(b))return fail("Protected actor overlaps model");
            if(blocks->occupied(box))return fail("Model overlaps existing blocks");
            Vector3i lo=box.position.floor(),hi=box.get_end().floor();
            uint64_t volume=uint64_t(hi.x-lo.x+1)*(hi.y-lo.y+1)*(hi.z-lo.z+1);
            probes+=volume;if(probes>262144)return fail("Model block-validation budget exceeded");
            for(int z=lo.z;z<=hi.z;++z)for(int y=lo.y;y<=hi.y;++y)for(int x=lo.x;x<=hi.x;++x)if(occupied.count({x,y,z}))return fail("Model overlaps prefab blocks");
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
    }
    const int committed_models=prefab->model_attachments.size();
    busy=true;bool changed=false;AABB changed_bounds;
    // All rejection paths end above. No signals or script calls occur between
    // the block mutation and authoritative model insertion.
    if(!blocks->apply_cells(records,false,changed,&changed_bounds)){busy=false;return fail("Block admission changed");}
    for(auto &entry:staged) {
        auto &s=entry.second;
        for(const auto &v:s.values){s.batch->placements.emplace(v);s.batch->groups[NativeStaticBatch::group_for(v.second)].insert(v.first);}
        ++s.batch->edit_revision;
    }
    // Until there is a shared journal, never allow block-only undo to erase half
    // of a furnished placement. Model history notices the new edit revisions.
    blocks->clear_history();
    std::vector<uint64_t> ids;const uint64_t block_id=blocks->get_instance_id();
    for(auto &entry:staged) {
        auto &s=entry.second;ids.push_back(s.batch->get_instance_id());
        for(auto key:s.touched)s.batch->render_ids.erase(key);
        s.batch->refresh_collision_bounds(s.touched);
    }
    size_t notification_index=0;
    for(auto &entry:staged)if(auto *live=Object::cast_to<NativeStaticBatch>(ObjectDB::get_instance(ids[notification_index++])))live->rebuild(entry.second.touched);
    if(changed)if(auto *live=ObjectDB::get_instance(block_id))live->emit_signal("cells_changed",changed_bounds);
    if(auto *live=ObjectDB::get_instance(block_id))live->emit_signal("changed");
    for(auto id:ids)if(auto *live=ObjectDB::get_instance(id))live->emit_signal("changed");
    busy=false;Dictionary result;result["ok"]=true;result["models"]=committed_models;result["block_probes"]=probes;result["model_comparisons"]=comparisons;return result;
}
}
