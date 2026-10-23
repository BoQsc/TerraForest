// SPDX-License-Identifier: 0BSD
#pragma once
#include "core.h"
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <map>
#include <mutex>
#include <vector>

namespace terraforest {
// Immutable 64 m region products selected by the compound world's checkpoint.
// This class owns no mutable "latest" pointer and never substitutes base terrain
// for a missing region. Callers retain canonical/backup checkpoint references.
class NativeTerrainRegionStore : public godot::RefCounted {
 GDCLASS(NativeTerrainRegionStore,godot::RefCounted)
 using Buffer=godot::PackedByteArray;
 struct Region {uint32_t pages=0,offset=0,length=0;Buffer digest,pack;};
 struct Index {
  uint32_t seed=0,generator=1,revision=0,edits=0;
  std::vector<uint32_t> order;
  Buffer blocks;
  std::map<uint32_t,Region> regions;
 };
 std::mutex mutex_;
 godot::String directory_;
 void *lease_=nullptr;
 bool writable_=false;
 int worker_limit_=4,last_workers_=1;
 int64_t written_=0,reused_=0,reused_regions_=0,written_bytes_=0,read_regions_=0;
 Buffer cached_id_;
 Index cached_index_;
 static Buffer hash(const Buffer &bytes);
 static bool ordinary(const godot::String &path,bool directory);
 static bool read_file(const godot::String &path,int64_t limit,Buffer &bytes);
 bool read_blob(const Buffer &id,const char *suffix,int64_t limit,Buffer &bytes) const;
 bool publish_blob(const Buffer &bytes,const char *suffix,Buffer &id);
 bool read_packet(const Region &entry,Buffer &bytes) const;
 static uint32_t region_for(uint32_t page);
 static bool valid_page(uint32_t page);
 static bool valid_blocks(const Buffer &blocks);
 static bool parse_index(const Buffer &bytes,Index &out);
 bool load_index(const Buffer &reference,Index &out);
 bool load_region(uint32_t key,const Region &entry,std::map<uint32_t,Buffer> &pages);
 void close_locked();
protected:
 static void _bind_methods();
public:
 ~NativeTerrainRegionStore();
 bool open_store(const godot::String &absolute_directory,bool writable=false);
 bool configure_worker_limit(int64_t workers);
 void close();
 Buffer publish_snapshot(const Buffer &snapshot,const Buffer &inherited=Buffer(),int64_t test_stop_after=-1);
 Buffer expand_snapshot(const Buffer &reference);
 godot::Dictionary describe_snapshot(const Buffer &reference);
 godot::Dictionary read_region(const Buffer &reference,godot::Vector3i coordinate);
 godot::Dictionary stats();
};
}
