// SPDX-License-Identifier: 0BSD
#pragma once
#include "regional_water.hpp"
#include <godot_cpp/classes/dir_access.hpp>
#include <godot_cpp/classes/hashing_context.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <mutex>
#include <atomic>
#include <cstring>
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
namespace terraforest {
// One serialized I/O owner. Immutable blobs/checkpoints; no mutable current-world
// pointer. The compound world archive must own the selected checkpoint identity.
class NativeWaterRegionStore : public godot::RefCounted {
 GDCLASS(NativeWaterRegionStore,godot::RefCounted)
 using Bytes=godot::PackedByteArray;
 std::mutex mutex;
 godot::String directory;
 HANDLE lease=INVALID_HANDLE_VALUE;
 static constexpr int64_t REGION_LIMIT=8*1024*1024,CATALOG_LIMIT=4*1024*1024;
 static Bytes hash(const Bytes &b){godot::Ref<godot::HashingContext> h;h.instantiate();h->start(godot::HashingContext::HASH_SHA256);h->update(b);return h->finish();}
 static godot::Dictionary result(bool ok){godot::Dictionary d;d["ok"]=ok;return d;}
 static uint64_t key(const godot::Vector3i &p){return (uint64_t(p.x)<<24)|(uint64_t(p.y)<<12)|uint64_t(p.z);}
 static bool valid(const godot::Vector3i &p){return p.x>=0&&p.x<500&&p.y>=0&&p.y<64&&p.z>=0&&p.z<500;}
 static godot::Vector3i coordinate(uint64_t k){return godot::Vector3i((k>>24)&4095,(k>>12)&4095,k&4095);}
 godot::String path(const Bytes &id,const char *suffix) const{return directory.path_join(id.hex_encode()+suffix);}
 static bool read_file(const godot::String &path,int64_t limit,Bytes &data){
  auto name=path.utf16();HANDLE f=CreateFileW((LPCWSTR)name.get_data(),GENERIC_READ,FILE_SHARE_READ,nullptr,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,nullptr);
  if(f==INVALID_HANDLE_VALUE)return false;LARGE_INTEGER size{};bool ok=GetFileSizeEx(f,&size)&&size.QuadPart>0&&size.QuadPart<=limit;
  if(ok)ok=data.resize(size.QuadPart)==godot::OK;
  DWORD got=0;if(ok)ok=ReadFile(f,data.ptrw(),DWORD(size.QuadPart),&got,nullptr)&&got==size.QuadPart;CloseHandle(f);return ok;
 }
 bool read(const Bytes &id,const char *suffix,int64_t limit,Bytes &data) const{return id.size()==32&&read_file(path(id,suffix),limit,data)&&hash(data)==id;}
 bool publish(const Bytes &data,const char *suffix,Bytes &id){
  id=hash(data);auto target=path(id,suffix);auto target_name=target.utf16();
  if(GetFileAttributesW((LPCWSTR)target_name.get_data())!=INVALID_FILE_ATTRIBUTES){Bytes old;return read(id,suffix,data.size(),old)&&old==data;}
  static std::atomic<uint64_t> sequence{0};
  auto temporary=target+".pending."+godot::String::num_uint64(GetCurrentProcessId())+"."+godot::String::num_uint64(++sequence);auto name=temporary.utf16();
  HANDLE f=CreateFileW((LPCWSTR)name.get_data(),GENERIC_WRITE,0,nullptr,CREATE_NEW,FILE_ATTRIBUTE_NORMAL|FILE_FLAG_WRITE_THROUGH,nullptr);
  if(f==INVALID_HANDLE_VALUE)return false;DWORD written=0;
  bool ok=WriteFile(f,data.ptr(),DWORD(data.size()),&written,nullptr)&&written==data.size()&&FlushFileBuffers(f);CloseHandle(f);
  Bytes verified;ok=ok&&read_file(temporary,data.size(),verified)&&verified==data;
  if(ok)ok=MoveFileExW((LPCWSTR)name.get_data(),(LPCWSTR)target_name.get_data(),MOVEFILE_WRITE_THROUGH);
  if(!ok)DeleteFileW((LPCWSTR)name.get_data());return ok;
 }
 static bool packet_valid(const godot::Vector3i &p,const Bytes &packet){
  godot::Ref<NativeRegionalWater> validator;validator.instantiate();return validator->restore_region_snapshot(p,packet,0,true);
 }
 static bool parse(const Bytes &bytes,std::map<uint64_t,Bytes> &entries){
  if(bytes.size()<12||bytes.size()>CATALOG_LIMIT||std::memcmp(bytes.ptr(),"TFWC\1\0\0\0",8))return false;
  uint32_t count=bytes.decode_u32(8);if(count>65536||bytes.size()!=12+int64_t(count)*40)return false;
  uint64_t previous=0;for(uint32_t i=0;i<count;++i){int64_t at=12+int64_t(i)*40;uint64_t k=bytes.decode_u64(at);auto p=coordinate(k);
   if(!valid(p)||key(p)!=k||(i&&k<=previous))return false;previous=k;entries.emplace(k,bytes.slice(at+8,at+40));}
  return true;
 }
 void close_unlocked(){if(lease!=INVALID_HANDLE_VALUE)CloseHandle(lease);lease=INVALID_HANDLE_VALUE;directory=godot::String();}
protected:
 static void _bind_methods(){
  godot::ClassDB::bind_method(godot::D_METHOD("open_store","absolute_directory"),&NativeWaterRegionStore::open_store);
  godot::ClassDB::bind_method(godot::D_METHOD("close"),&NativeWaterRegionStore::close);
  godot::ClassDB::bind_method(godot::D_METHOD("publish_region","coordinate","packet"),&NativeWaterRegionStore::publish_region);
  godot::ClassDB::bind_method(godot::D_METHOD("publish_checkpoint","coordinates","digests"),&NativeWaterRegionStore::publish_checkpoint);
  godot::ClassDB::bind_method(godot::D_METHOD("read_region","checkpoint","coordinate"),&NativeWaterRegionStore::read_region);
 }
public:
 ~NativeWaterRegionStore(){close();}
 bool open_store(const godot::String &absolute_directory){std::lock_guard<std::mutex> lock(mutex);if(lease!=INVALID_HANDLE_VALUE||!absolute_directory.is_absolute_path())return false;
  if(godot::DirAccess::make_dir_recursive_absolute(absolute_directory)!=godot::OK)return false;
  auto name=absolute_directory.path_join("writer.lock").utf16();lease=CreateFileW((LPCWSTR)name.get_data(),GENERIC_READ|GENERIC_WRITE,0,nullptr,OPEN_ALWAYS,FILE_ATTRIBUTE_NORMAL,nullptr);
  if(lease==INVALID_HANDLE_VALUE)return false;directory=absolute_directory;return true;
 }
 void close(){std::lock_guard<std::mutex> lock(mutex);close_unlocked();}
 godot::Dictionary publish_region(const godot::Vector3i &p,const Bytes &packet){std::lock_guard<std::mutex> lock(mutex);
  if(lease==INVALID_HANDLE_VALUE||!valid(p)||packet.size()>REGION_LIMIT||!packet_valid(p,packet))return result(false);
  Bytes id;if(!publish(packet,".water",id))return result(false);auto out=result(true);out["digest"]=id;return out;
 }
 godot::Dictionary publish_checkpoint(const godot::PackedInt32Array &coordinates,const godot::Array &digests){std::lock_guard<std::mutex> lock(mutex);
  if(lease==INVALID_HANDLE_VALUE||coordinates.size()%3||digests.size()!=coordinates.size()/3||digests.size()>65536)return result(false);
  std::map<uint64_t,Bytes> entries;
  for(int64_t i=0;i<digests.size();++i){godot::Vector3i p(coordinates[i*3],coordinates[i*3+1],coordinates[i*3+2]);if(!valid(p)||digests[i].get_type()!=godot::Variant::PACKED_BYTE_ARRAY)return result(false);
   Bytes id=digests[i],packet;if(!entries.emplace(key(p),id).second||!read(id,".water",REGION_LIMIT,packet)||!packet_valid(p,packet))return result(false);
  }
  Bytes bytes;bytes.resize(12+entries.size()*40);std::memcpy(bytes.ptrw(),"TFWC\1\0\0\0",8);bytes.encode_u32(8,entries.size());int64_t at=12;
  for(const auto &[k,id]:entries){bytes.encode_u64(at,k);std::memcpy(bytes.ptrw()+at+8,id.ptr(),32);at+=40;}
  Bytes id;if(!publish(bytes,".checkpoint",id))return result(false);auto out=result(true);out["checkpoint"]=id;out["regions"]=int64_t(entries.size());return out;
 }
 godot::Dictionary read_region(const Bytes &checkpoint,const godot::Vector3i &p){std::lock_guard<std::mutex> lock(mutex);
  if(lease==INVALID_HANDLE_VALUE||!valid(p))return result(false);
  Bytes bytes;std::map<uint64_t,Bytes> entries;if(!read(checkpoint,".checkpoint",CATALOG_LIMIT,bytes)||!parse(bytes,entries))return result(false);
  auto it=entries.find(key(p));if(it==entries.end())return result(false);Bytes packet;
  if(!read(it->second,".water",REGION_LIMIT,packet)||!packet_valid(p,packet))return result(false);
  auto out=result(true);out["packet"]=packet;out["digest"]=it->second;return out;
 }
};
}
