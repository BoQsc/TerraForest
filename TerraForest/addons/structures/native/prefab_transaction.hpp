// SPDX-License-Identifier: 0BSD
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include "block_world.hpp"
#include "static_batch.hpp"
#include <memory>
namespace terraforest {
class NativePrefabPlacement : public RefCounted {
    GDCLASS(NativePrefabPlacement,RefCounted)
    struct Pending;
    std::unique_ptr<Pending> pending;
    bool busy=false;
    bool current() const;
    Dictionary state() const;
protected:
    static void _bind_methods();
public:
    NativePrefabPlacement();
    ~NativePrefabPlacement();
    Dictionary begin(NativeBlockWorld *blocks,const Ref<NativeBlockPrefab> &prefab,Vector3i origin,int turns,const Dictionary &models,const Array &protected_boxes);
    Dictionary advance(int64_t max_cells,int64_t max_models,int64_t max_usec);
    Dictionary commit(const Array &protected_boxes);
    bool cancel();
    Dictionary place(NativeBlockWorld *blocks,const Ref<NativeBlockPrefab> &prefab,Vector3i origin,int turns,const Dictionary &models,const Array &protected_boxes);
    Dictionary model_counts(const Ref<NativeBlockPrefab> &prefab) const;
};
}
