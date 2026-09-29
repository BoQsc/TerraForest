#include "block_world.hpp"
#include <algorithm>
#include <cmath>

namespace terraforest {
bool NativeBlockWorld::configure_history(int64_t byte_limit,int step_limit) {
    if(byte_limit<0||byte_limit>64*1024*1024||step_limit<0||step_limit>1024)return false;
    ++history_revision;history_budget=uint64_t(byte_limit);history_steps=step_limit;
    if(!history_budget||!history_steps)clear_history();else trim_history();
    return true;
}
void NativeBlockWorld::clear_history() {
    ++history_revision;
    decltype(undo_edits)().swap(undo_edits);decltype(redo_edits)().swap(redo_edits);history_bytes=0;
}
void NativeBlockWorld::trim_history() {
    while(history_bytes>history_budget||undo_edits.size()+redo_edits.size()>size_t(history_steps)) {
        // Keep the nearest undo/redo chain. If no past remains, discard far future.
        auto &queue=undo_edits.empty()?redo_edits:undo_edits;
        if(queue.empty())break;
        history_bytes-=queue.front().capacity()*sizeof(BlockChange);queue.pop_front();
    }
}
void NativeBlockWorld::remember_edit(std::vector<BlockChange> &&changes) {
    if(!history_budget||!history_steps)return;
    ++history_revision;
    for(const auto &edit:redo_edits)history_bytes-=edit.capacity()*sizeof(BlockChange);
    decltype(redo_edits)().swap(redo_edits);
    // Duplicate input coordinates have last-write-wins semantics. Retain the
    // first previous value and final new value, without a per-cell map allocation.
    auto less=[](const BlockChange &a,const BlockChange &b){return std::tie(a.x,a.y,a.z)<std::tie(b.x,b.y,b.z);};
    std::stable_sort(changes.begin(),changes.end(),less);
    size_t count=0;
    for(size_t i=0;i<changes.size();) {
        BlockChange value=changes[i++];
        while(i<changes.size()&&!less(value,changes[i]))value.after=changes[i++].after;
        if(value.before!=value.after)changes[count++]=value;
    }
    if(count*sizeof(BlockChange)>history_budget) {
        // An accepted non-undoable edit is a history barrier: old undo commands
        // must never cross it and overwrite newer authored data.
        clear_history();unrecorded_edits++;return;
    }
    std::vector<BlockChange> compact(changes.begin(),changes.begin()+count);
    if(compact.capacity()*sizeof(BlockChange)>history_budget) {clear_history();unrecorded_edits++;return;}
    if(compact.empty())return;
    history_bytes+=compact.capacity()*sizeof(BlockChange);
    undo_edits.push_back(std::move(compact));trim_history();
}
bool NativeBlockWorld::replay_edit(bool backwards,const AABB &protected_bounds) {
    auto &source=backwards?undo_edits:redo_edits;
    auto &destination=backwards?redo_edits:undo_edits;
    if(source.empty())return false;
    if(!protected_bounds.position.is_finite()||!protected_bounds.size.is_finite())return false;
    const bool protect=protected_bounds.size!=Vector3();
    AABB local;
    if(protect) {
        if(protected_bounds.size.x<=0||protected_bounds.size.y<=0||protected_bounds.size.z<=0)return false;
        Transform3D frame=is_inside_tree()?get_global_transform():get_transform();
        if(!frame.is_finite()||std::abs(frame.basis.determinant())<1e-12)return false;
        local=frame.affine_inverse().xform(protected_bounds);
        if(!local.position.is_finite()||!local.get_end().is_finite())return false;
    }
    const auto &edit=source.back();
    PackedInt32Array records;records.resize(edit.size()*4);int i=0;
    for(const auto &c:edit) {
        int expected=backwards?c.after:c.before,w=backwards?c.before:c.after;
        if(cell(c.x,c.y,c.z)!=expected)return false;
        if(protect&&w&&AABB(Vector3(c.x,c.y,c.z),Vector3(1,1,1)).intersects(local))return false;
        records.set(i++,c.x);records.set(i++,c.y);records.set(i++,c.z);records.set(i++,w);
    }
    bool changed=false;
    if(!apply_cells(records,false,changed))return false;
    destination.push_back(std::move(source.back()));source.pop_back();
    // Publish after updating the history cursor. Signal listeners may query or
    // mutate the world; no references to a command are used after this signal.
    if(changed)emit_signal("changed");
    return true;
}
bool NativeBlockWorld::region_has_history(BlockKey region) const {
    const int x=region.x*64,y=region.y*64,z=region.z*64;
    // History records are already sorted by xyz. Skip unrelated x ranges without
    // allocating a second per-cell/region index outside the history budget.
    for(const auto *queue:{&undo_edits,&redo_edits})for(const auto &edit:*queue) {
        auto begin=std::lower_bound(edit.begin(),edit.end(),x,[](const BlockChange &cell,int low){return cell.x<low;});
        for(auto it=begin;it!=edit.end()&&it->x<x+64;++it)
            if(it->y>=y&&it->y<y+64&&it->z>=z&&it->z<z+64)return true;
    }
    return false;
}
Dictionary NativeBlockWorld::history_stats() const {
    Dictionary out;
    out["undo_steps"]=int(undo_edits.size());out["redo_steps"]=int(redo_edits.size());
    out["cell_capacity_bytes"]=int64_t(history_bytes);out["byte_limit"]=int64_t(history_budget);
    out["step_limit"]=history_steps;out["unrecorded_edits"]=int64_t(unrecorded_edits);
    return out;
}
}
