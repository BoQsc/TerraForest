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
    ClassDB::bind_method(D_METHOD("get_position", "id"), &NativeEntityStore::get_position);
    ClassDB::bind_method(D_METHOD("set_velocity", "id", "velocity"), &NativeEntityStore::set_velocity);
    ClassDB::bind_method(D_METHOD("step", "seconds"), &NativeEntityStore::step);
    ClassDB::bind_method(D_METHOD("multimesh_transforms"), &NativeEntityStore::multimesh_transforms);
    ClassDB::bind_method(D_METHOD("statistics"), &NativeEntityStore::statistics);
}

bool NativeEntityStore::configure(int64_t capacity) {
    if (capacity < 1 || capacity > 262144 || count_ != 0) return false;
    // Commit only after every allocation succeeds; an allocation failure retains the old pool.
    std::unique_ptr<Slot[]> slots(new (std::nothrow) Slot[size_t(capacity)]);
    std::unique_ptr<uint32_t[]> dense(new (std::nothrow) uint32_t[size_t(capacity)]);
    std::unique_ptr<uint32_t[]> free(new (std::nothrow) uint32_t[size_t(capacity)]);
    if (!slots || !dense || !free) return false;
    for (uint32_t i = 0; i < uint32_t(capacity); ++i) free[i] = uint32_t(capacity) - i - 1;
    slots_ = std::move(slots); dense_ = std::move(dense); free_ = std::move(free);
    capacity_ = uint32_t(capacity); free_count_ = capacity_; ticks_ = 0;
    return true;
}

NativeEntityStore::Slot *NativeEntityStore::resolve(int64_t id) const {
    if (id <= 0) return nullptr;
    uint32_t index = uint32_t(uint64_t(id)), generation = uint32_t(uint64_t(id) >> 32);
    if (index >= capacity_) return nullptr;
    Slot &slot = slots_[index];
    return slot.active && slot.generation == generation ? &slot : nullptr;
}

int64_t NativeEntityStore::spawn_unchecked(const Vector3 &position, const Vector3 &velocity) {
    const uint32_t index = free_[--free_count_];
    Slot &slot = slots_[index];
    slot.position = position; slot.velocity = velocity; slot.generation = next_generation_++;
    slot.dense_index = count_; slot.active = true; dense_[count_++] = index;
    return int64_t((uint64_t(slot.generation) << 32) | index);
}

int64_t NativeEntityStore::spawn(const Vector3 &position, const Vector3 &velocity) {
    if (!free_count_ || next_generation_ > 0x7fffffffU || !position.is_finite() || !velocity.is_finite()) return 0;
    return spawn_unchecked(position, velocity);
}

PackedInt64Array NativeEntityStore::spawn_grid(int64_t count, const Vector3 &origin, double spacing, const Vector3 &velocity) {
    PackedInt64Array ids;
    if (count < 0 || uint64_t(count) > free_count_ || uint64_t(next_generation_) + uint64_t(count) > 0x80000000ULL || !origin.is_finite() || !velocity.is_finite() || !std::isfinite(spacing) || spacing <= 0.0 || spacing > 10000.0) return ids;
    if (count == 0) return ids;
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
    uint32_t moved = dense_[--count_];
    dense_[dense_index] = moved; slots_[moved].dense_index = dense_index;
    slot->active = false; free_[free_count_++] = index;
    return true;
}
bool NativeEntityStore::contains(int64_t id) const { return resolve(id) != nullptr; }
Vector3 NativeEntityStore::get_position(int64_t id) const { auto *slot = resolve(id); return slot ? slot->position : Vector3(); }
bool NativeEntityStore::set_velocity(int64_t id, const Vector3 &velocity) {
    Slot *slot = resolve(id);
    if (!slot || !velocity.is_finite()) return false;
    slot->velocity = velocity; return true;
}
bool NativeEntityStore::step(double seconds) {
    if (!std::isfinite(seconds) || seconds <= 0.0 || seconds > 0.1) return false;
    const real_t dt = real_t(seconds);
    // Reject the entire tick before mutation if caller-supplied values would overflow.
    for (uint32_t i = 0; i < count_; ++i) {
        const Slot &slot = slots_[dense_[i]];
        if (!(slot.position + slot.velocity * dt).is_finite()) return false;
    }
    for (uint32_t i = 0; i < count_; ++i) { Slot &slot = slots_[dense_[i]]; slot.position += slot.velocity * dt; }
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
    result["ticks"] = int64_t(ticks_); result["pool_bytes"] = int64_t(capacity_) * int64_t(sizeof(Slot) + 2 * sizeof(uint32_t));
    result["native"] = true; result["collision_simulation"] = false;
    return result;
}
}
