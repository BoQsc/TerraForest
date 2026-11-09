// SPDX-License-Identifier: 0BSD
#pragma once
#include "structures_snapshot.hpp"
#include "static_batch.hpp"
#include <atomic>
#include <mutex>

namespace terraforest {
// Main-thread copies of canonical values only. No scene owner survives capture.
// The existing ordered save worker performs encoding, hashing and validation.
class NativeStructuresCapture : public godot::RefCounted {
    GDCLASS(NativeStructuresCapture,godot::RefCounted)
    friend class NativeStructuresSnapshot;
    struct Chunk {BlockKey key;std::array<uint16_t,4096> cells;};
    struct Region {BlockKey key;std::array<uint8_t,32> checksum;};
    struct Model {
        godot::String asset;
        std::vector<ModelPlacementRecord> records;
        std::vector<Region> missing;
    };
    godot::Ref<NativeStructuresSnapshot> codec;
    godot::PackedByteArray checkpoint;
    std::vector<Chunk> chunks;
    std::vector<Region> missing;
    std::vector<Model> models;
    uint64_t capture_bytes=0,captured_chunks=0,captured_models=0,model_records=0,missing_regions=0,capture_us=0;
    std::atomic<uint64_t> reserved_bytes{0},serialized_bytes_count{0};
    std::atomic<bool> serialized_ready{false};
    godot::PackedByteArray serialized_bytes;
    std::mutex serialization_mutex;
    bool complete=false;
    static std::atomic<uint64_t> pending_bytes;
    static constexpr uint64_t LIMIT=128ull*1024*1024;
    static void region_arrays(const std::vector<Region> &,godot::PackedInt32Array &,godot::PackedByteArray &);
    godot::PackedByteArray encode_frozen() const;
    void release_frozen();
protected:
    static void _bind_methods();
public:
    ~NativeStructuresCapture();
    godot::PackedByteArray serialize_snapshot();
    godot::Dictionary stats() const;
};
}
