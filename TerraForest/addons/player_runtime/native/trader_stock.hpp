#pragma once
#include "inventory.hpp"
#include <array>

namespace terraforest {
class NativeTraderStock : public godot::RefCounted {
    GDCLASS(NativeTraderStock,godot::RefCounted)
    godot::Ref<NativePlayerInventory> inventory;
    std::array<int64_t,32> identities{},amounts{},pending{};
    int64_t count=0;
    int64_t index_of(int64_t identity) const;
protected:
    static void _bind_methods();
public:
    bool configure(const godot::Ref<NativePlayerInventory> &stock,const godot::PackedInt64Array &legacy_additions);
    bool flush_pending();
    godot::PackedByteArray capture_storage_snapshot() const;
    bool validate_snapshot(const godot::PackedByteArray &data) const;
    bool restore_storage_snapshot(const godot::PackedByteArray &data);
};
}
