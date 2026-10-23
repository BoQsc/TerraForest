// SPDX-License-Identifier: 0BSD
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <atomic>
#include <mutex>

namespace terraforest {
class TerrainCore;
class NativeTerrainRegionStore;
// Scene-independent immutable field capture. Only native publication can certify
// a checkpoint for acknowledgement; scripts cannot edit the captured arrays.
class NativeTerrainCapture : public godot::RefCounted {
 GDCLASS(NativeTerrainCapture,godot::RefCounted)
 friend class TerrainCore;
 friend class NativeTerrainRegionStore;
 inline static std::atomic<uint64_t> pending_bytes_{0};
 uint64_t owner_=0,epoch_=0,reserved_=0;
 uint32_t seed_=0,generator_=1,revision_=0,edits_=0;
 bool sealed_=false;
 godot::PackedInt32Array keys_,changed_;
 godot::PackedInt64Array versions_;
 godot::PackedByteArray samples_,blocks_,source_,expected_;
 std::mutex publication_mutex_;
 godot::PackedByteArray published_;
protected:
 static void _bind_methods(){godot::ClassDB::bind_method(godot::D_METHOD("stats"),&NativeTerrainCapture::stats);}
public:
 ~NativeTerrainCapture(){if(reserved_)pending_bytes_.fetch_sub(reserved_);}
 godot::Dictionary stats() const {
  godot::Dictionary out;out["sealed"]=sealed_;out["pages"]=keys_.size();out["dirty_pages"]=changed_.size();out["sample_bytes"]=samples_.size();out["legacy_block_bytes"]=blocks_.size();out["reserved_bytes"]=int64_t(reserved_);out["revision"]=int64_t(revision_);return out;
 }
};
}
