// SPDX-License-Identifier: 0BSD
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include "block_world.hpp"
#include "static_batch.hpp"
namespace terraforest {
class NativePrefabPlacement : public RefCounted {
    GDCLASS(NativePrefabPlacement,RefCounted)
    bool busy=false;
protected:
    static void _bind_methods();
public:
    Dictionary place(NativeBlockWorld *blocks,const Ref<NativeBlockPrefab> &prefab,Vector3i origin,int turns,const Dictionary &models,const Array &protected_boxes);
    Dictionary model_counts(const Ref<NativeBlockPrefab> &prefab) const;
};
}
