// SPDX-License-Identifier: 0BSD
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <atomic>

namespace terraforest {
// One-shot offline job. It owns a detached water store and runs on the terrain
// owner's worker; only immutable bytes are handed back to the scene. cancel()
// and progress() are the only methods callable concurrently with run().
class NativeGeneratedLakeBake : public godot::RefCounted {
    GDCLASS(NativeGeneratedLakeBake,godot::RefCounted)
    std::atomic<bool> cancelled{false},started{false};
    std::atomic<int64_t> state{0},completed{0},regions{0};
protected:
    static void _bind_methods();
public:
    void cancel(){cancelled.store(true,std::memory_order_relaxed);}
    godot::Dictionary progress() const;
    godot::Dictionary run(godot::Object *core,const godot::PackedByteArray &catalog,int64_t revision,int64_t epoch,int64_t timeout_ms=30000);
};
}
