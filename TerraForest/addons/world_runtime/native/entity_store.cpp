#include "entity_store.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <cmath>
#include <limits>
#include <new>

using namespace godot;
namespace terraforest {
void NativeEntityStore::_bind_methods() {
    ClassDB::bind_method(D_METHOD("configure", "capacity"), &NativeEntityStore::configure);
    ClassDB::bind_method(D_METHOD("spawn", "position", "velocity"), &NativeEntityStore::spawn);
    ClassDB::bind_method(D_METHOD("spawn_grid", "count", "origin", "spacing", "velocity"), &NativeEntityStore::spawn_grid);
    ClassDB::bind_method(D_METHOD("despawn", "id"), &NativeEntityStore::despawn);
    ClassDB::bind_method(D_METHOD("contains", "id"), &NativeEntityStore::contains);
    ClassDB::bind_method(D_METHOD("persistent_id", "handle"), &NativeEntityStore::persistent_id);
    ClassDB::bind_method(D_METHOD("resolve_identity", "identity"), &NativeEntityStore::resolve_identity);
    ClassDB::bind_method(D_METHOD("get_position", "id"), &NativeEntityStore::get_position);
    ClassDB::bind_method(D_METHOD("set_velocity", "id", "velocity"), &NativeEntityStore::set_velocity);
    ClassDB::bind_method(D_METHOD("step", "seconds"), &NativeEntityStore::step);
    ClassDB::bind_method(D_METHOD("multimesh_transforms"), &NativeEntityStore::multimesh_transforms);
    ClassDB::bind_method(D_METHOD("statistics"), &NativeEntityStore::statistics);
    ClassDB::bind_method(D_METHOD("capture_storage_snapshot"), &NativeEntityStore::capture_storage_snapshot);
    ClassDB::bind_method(D_METHOD("validate_snapshot", "data"), &NativeEntityStore::validate_snapshot);
    ClassDB::bind_method(D_METHOD("restore_storage_snapshot", "data"), &NativeEntityStore::restore_storage_snapshot);
    ClassDB::bind_method(D_METHOD("query_sphere","center","radius","result_limit","candidate_budget"),&NativeEntityStore::query_sphere,DEFVAL(256),DEFVAL(4096));
}

NativeEntityStore::Cell NativeEntityStore::cell_for(const Vector3 &p) {
    // Floating cell coordinates avoid undefined integer conversions for the
    // existing store's unrestricted finite-position contract.
    return {real_t(std::floor(double(p.x)/32.0)),real_t(std::floor(double(p.y)/32.0)),real_t(std::floor(double(p.z)/32.0))};
}
void NativeEntityStore::index_insert(uint32_t index) {
    Slot &slot=slots_[index];const Cell cell=cell_for(slot.position);
    auto entry=cell_heads_.find(cell);slot.previous=UINT32_MAX;
    slot.next=entry==cell_heads_.end()?UINT32_MAX:entry->second;
    if(slot.next!=UINT32_MAX)slots_[slot.next].previous=index;
    cell_heads_[cell]=index;
}
void NativeEntityStore::index_remove(uint32_t index) {
    Slot &slot=slots_[index];
    if(slot.previous!=UINT32_MAX)slots_[slot.previous].next=slot.next;
    else if(slot.next==UINT32_MAX)cell_heads_.erase(cell_for(slot.position));
    else cell_heads_[cell_for(slot.position)]=slot.next;
    if(slot.next!=UINT32_MAX)slots_[slot.next].previous=slot.previous;
    slot.previous=slot.next=UINT32_MAX;
}

void NativeEntityStore::update_moving(uint32_t index) {
    Slot &slot=slots_[index];
    const bool moving=slot.active&&slot.velocity!=Vector3();
    if(moving&&slot.moving_index==UINT32_MAX) {
        slot.moving_index=moving_count_;moving_[moving_count_++]=index;
    } else if(!moving&&slot.moving_index!=UINT32_MAX) {
        uint32_t position=slot.moving_index,last=moving_[--moving_count_];
        moving_[position]=last;slots_[last].moving_index=position;
        slot.moving_index=UINT32_MAX;
    }
}
bool NativeEntityStore::configure(int64_t capacity) {
    if (capacity < 1 || capacity > 262144 || count_ != 0) return false;
    // Commit only after every allocation succeeds; an allocation failure retains the old pool.
    std::unique_ptr<Slot[]> slots(new (std::nothrow) Slot[size_t(capacity)]);
    std::unique_ptr<uint32_t[]> dense(new (std::nothrow) uint32_t[size_t(capacity)]);
    std::unique_ptr<uint32_t[]> free(new (std::nothrow) uint32_t[size_t(capacity)]);
    std::unique_ptr<uint32_t[]> moving(new (std::nothrow) uint32_t[size_t(capacity)]);
    if (!slots || !dense || !free || !moving) return false;
    for (uint32_t i = 0; i < uint32_t(capacity); ++i) free[i] = uint32_t(capacity) - i - 1;
    slots_ = std::move(slots); dense_ = std::move(dense); free_ = std::move(free);
    moving_=std::move(moving);moving_count_=last_step_visited_=0;
    capacity_ = uint32_t(capacity); free_count_ = capacity_; ticks_ = 0;
    cell_heads_.clear();
    identity_slots_.clear();
    return true;
}

NativeEntityStore::Slot *NativeEntityStore::resolve(int64_t id) const {
    if (id <= 0) return nullptr;
    uint32_t index = uint32_t(uint64_t(id)), generation = uint32_t(uint64_t(id) >> 32);
    if (index >= capacity_) return nullptr;
    Slot &slot = slots_[index];
    return slot.active && slot.generation == generation ? &slot : nullptr;
}

int64_t NativeEntityStore::spawn_unchecked(const Vector3 &position, const Vector3 &velocity, uint64_t persistent_id) {
    const uint32_t index = free_[--free_count_];
    Slot &slot = slots_[index];
    slot.position = position; slot.velocity = velocity; slot.generation = next_generation_++;
    slot.dense_index = count_; slot.active = true; dense_[count_++] = index;
    update_moving(index);
    slot.persistent_id = persistent_id ? persistent_id : next_persistent_id_++;
    identity_slots_[slot.persistent_id] = index;
    index_insert(index);
    return int64_t((uint64_t(slot.generation) << 32) | index);
}

int64_t NativeEntityStore::spawn(const Vector3 &position, const Vector3 &velocity) {
    if (next_persistent_id_ > INT64_MAX || !free_count_ || next_generation_ > 0x7fffffffU || !position.is_finite() || !velocity.is_finite()) return 0;
    return spawn_unchecked(position, velocity);
}

PackedInt64Array NativeEntityStore::spawn_grid(int64_t count, const Vector3 &origin, double spacing, const Vector3 &velocity) {
    PackedInt64Array ids;
    if (count < 0 || uint64_t(count) > free_count_ || uint64_t(next_generation_) + uint64_t(count) > 0x80000000ULL || !origin.is_finite() || !velocity.is_finite() || !std::isfinite(spacing) || spacing <= 0.0 || spacing > 10000.0) return ids;
    if (count == 0) return ids;
    if (uint64_t(count) > 0x8000000000000000ULL-next_persistent_id_) return ids;
    const uint32_t width = uint32_t(std::ceil(std::sqrt(double(count))));
    if (!(origin + Vector3(real_t(width * spacing), 0, real_t(width * spacing))).is_finite()) return ids;
    ids.resize(count);
    int64_t *out = ids.ptrw();
    for (uint32_t i = 0; i < uint32_t(count); ++i) {
        Vector3 position = origin + Vector3(real_t((i % width) * spacing), 0, real_t((i / width) * spacing));
        out[i] = spawn_unchecked(position, velocity);
    }
    return ids;
}

bool NativeEntityStore::despawn(int64_t id) {
    Slot *slot = resolve(id);
    if (!slot) return false;
    uint32_t index = uint32_t(uint64_t(id)), dense_index = slot->dense_index;
    index_remove(index);
    identity_slots_.erase(slot->persistent_id);
    uint32_t moved = dense_[--count_];
    dense_[dense_index] = moved; slots_[moved].dense_index = dense_index;
    slot->active = false;update_moving(index);free_[free_count_++] = index;
    return true;
}
bool NativeEntityStore::contains(int64_t id) const { return resolve(id) != nullptr; }
int64_t NativeEntityStore::persistent_id(int64_t handle) const {
    const Slot *slot=resolve(handle); return slot ? int64_t(slot->persistent_id) : 0;
}
int64_t NativeEntityStore::resolve_identity(int64_t identity) const {
    if(identity<=0)return 0;
    auto found=identity_slots_.find(uint64_t(identity));
    if(found==identity_slots_.end())return 0;
    const Slot &slot=slots_[found->second];
    return int64_t((uint64_t(slot.generation)<<32)|found->second);
}
Vector3 NativeEntityStore::get_position(int64_t id) const { auto *slot = resolve(id); return slot ? slot->position : Vector3(); }
bool NativeEntityStore::set_velocity(int64_t id, const Vector3 &velocity) {
    Slot *slot = resolve(id);
    if (!slot || !velocity.is_finite()) return false;
    slot->velocity = velocity;update_moving(uint32_t(uint64_t(id)));return true;
}
bool NativeEntityStore::step(double seconds) {
    last_step_visited_=0;
    if (!std::isfinite(seconds) || seconds <= 0.0 || seconds > 0.1) return false;
    const real_t dt = real_t(seconds);
    // Reject the entire tick before mutation if caller-supplied values would overflow.
    for (uint32_t i = 0; i < moving_count_; ++i) {
        const Slot &slot = slots_[moving_[i]];++last_step_visited_;
        if (!(slot.position + slot.velocity * dt).is_finite()) return false;
    }
    for (uint32_t i = 0; i < moving_count_; ++i) {
        uint32_t index=moving_[i];Slot &slot=slots_[index];Vector3 next=slot.position+slot.velocity*dt;
        if(!(cell_for(slot.position)==cell_for(next))){index_remove(index);slot.position=next;index_insert(index);}
        else slot.position=next;
    }
    ++ticks_; return true;
}
PackedFloat32Array NativeEntityStore::multimesh_transforms() const {
    PackedFloat32Array buffer; buffer.resize(int64_t(count_) * 12);
    float *out = buffer.ptrw();
    for (uint32_t i = 0; i < count_; ++i) {
        const Vector3 &p = slots_[dense_[i]].position;
        float *row = out + i * 12;
        row[0]=1; row[1]=0; row[2]=0; row[3]=p.x;
        row[4]=0; row[5]=1; row[6]=0; row[7]=p.y;
        row[8]=0; row[9]=0; row[10]=1; row[11]=p.z;
    }
    return buffer;
}
Dictionary NativeEntityStore::statistics() const {
    Dictionary result;
    result["capacity"] = capacity_; result["active"] = count_; result["free"] = free_count_;
    result["ticks"] = int64_t(ticks_); result["pool_bytes"] = int64_t(capacity_) * int64_t(sizeof(Slot) + 3 * sizeof(uint32_t));
    result["moving"]=moving_count_;result["last_step_visited"]=last_step_visited_;
    result["native"] = true; result["collision_simulation"] = false;
    result["spatial_cells"]=int64_t(cell_heads_.size());result["spatial_cell_size"]=32;
    return result;
}
Dictionary NativeEntityStore::query_sphere(const Vector3 &center,double radius,int result_limit,int candidate_budget) const {
    Dictionary out;PackedInt64Array ids;out["ok"]=false;out["complete"]=false;out["ids"]=ids;out["visited"]=0;out["cells_visited"]=0;
    if(!center.is_finite()||std::abs(center.x)>10000000||std::abs(center.y)>10000000||std::abs(center.z)>10000000||
       !std::isfinite(radius)||radius<0||radius>1024||result_limit<1||result_limit>4096||candidate_budget<1||candidate_budget>16384){out["reason"]="invalid_query";return out;}
    const Cell low=cell_for(center-Vector3(radius,radius,radius)),high=cell_for(center+Vector3(radius,radius,radius));
    int64_t nx=int64_t(high.x-low.x)+1,ny=int64_t(high.y-low.y)+1,nz=int64_t(high.z-low.z)+1;
    if(nx*ny*nz>4096){out["reason"]="region_too_large";return out;}
    int visited=0,cells=0;bool complete=true;
    for(int64_t z=0;z<nz&&complete;++z)for(int64_t y=0;y<ny&&complete;++y)for(int64_t x=0;x<nx&&complete;++x){
        ++cells;auto entry=cell_heads_.find({real_t(low.x+x),real_t(low.y+y),real_t(low.z+z)});
        if(entry==cell_heads_.end())continue;
        for(uint32_t index=entry->second;index!=UINT32_MAX;index=slots_[index].next){
            if(visited==candidate_budget){complete=false;out["reason"]="candidate_budget";break;}++visited;
            const Slot &slot=slots_[index];const double dx=double(slot.position.x)-center.x,dy=double(slot.position.y)-center.y,dz=double(slot.position.z)-center.z;
            if(dx*dx+dy*dy+dz*dz>radius*radius)continue;
            if(ids.size()==result_limit){complete=false;out["reason"]="result_limit";break;}
            ids.push_back(int64_t((uint64_t(slot.generation)<<32)|index));
        }
    }
    out["ok"]=true;out["complete"]=complete;out["ids"]=ids;out["visited"]=visited;out["cells_visited"]=cells;
    return out;
}
}
