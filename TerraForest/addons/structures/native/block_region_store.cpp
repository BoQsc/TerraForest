// SPDX-License-Identifier: 0BSD
#include "block_region_store.hpp"
#include <godot_cpp/classes/hashing_context.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <atomic>
#include <cstring>
#include <limits>
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>

namespace terraforest {
static constexpr int64_t CATALOG_LIMIT=4*1024*1024, BLOB_LIMIT=2*1024*1024;
static constexpr size_t REGION_LIMIT=65536;
static Dictionary status(Error error,const String &message=String()) {
    Dictionary out;out["ok"]=error==OK;out["error"]=int(error);out["message"]=message;return out;
}
static PackedByteArray digest(const PackedByteArray &bytes) {
    Ref<HashingContext> h;h.instantiate();h->start(HashingContext::HASH_SHA256);h->update(bytes);return h->finish();
}
static bool read_file(const String &path,int64_t limit,PackedByteArray &bytes,bool &exists) {
    const auto name=path.utf16();
    HANDLE file=CreateFileW(reinterpret_cast<LPCWSTR>(name.get_data()),GENERIC_READ,
        FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_SHARE_DELETE,nullptr,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,nullptr);
    if(file==INVALID_HANDLE_VALUE) {
        DWORD error=GetLastError();exists=error!=ERROR_FILE_NOT_FOUND&&error!=ERROR_PATH_NOT_FOUND;
        bytes=PackedByteArray();return !exists;
    }
    exists=true;LARGE_INTEGER size{};
    bool ok=GetFileSizeEx(file,&size)&&size.QuadPart>=0&&size.QuadPart<=limit;
    if(ok)ok=bytes.resize(size.QuadPart)==OK;
    if(ok&&size.QuadPart) {DWORD got=0;ok=ReadFile(file,bytes.ptrw(),DWORD(size.QuadPart),&got,nullptr)&&got==DWORD(size.QuadPart);}
    CloseHandle(file);return ok;
}
static void delete_exact(const String &path) {
    const auto name=path.utf16();DeleteFileW(reinterpret_cast<LPCWSTR>(name.get_data()));
}
static bool move_file(const String &source,const String &target,bool replace) {
    const auto a=source.utf16(),b=target.utf16();
    return MoveFileExW(reinterpret_cast<LPCWSTR>(a.get_data()),reinterpret_cast<LPCWSTR>(b.get_data()),
        MOVEFILE_WRITE_THROUGH|(replace?MOVEFILE_REPLACE_EXISTING:0));
}
static bool write_pending(const String &target,const PackedByteArray &bytes,String &temporary) {
    static std::atomic<uint64_t> sequence{0};
    temporary=target+String(".pending.")+String::num_uint64(GetCurrentProcessId())+String(".")+String::num_uint64(++sequence);
    const auto name=temporary.utf16();
    HANDLE file=CreateFileW(reinterpret_cast<LPCWSTR>(name.get_data()),GENERIC_WRITE,0,nullptr,CREATE_NEW,
        FILE_ATTRIBUTE_NORMAL|FILE_FLAG_WRITE_THROUGH,nullptr);
    if(file==INVALID_HANDLE_VALUE)return false;
    DWORD wrote=0;
    bool ok=WriteFile(file,bytes.ptr(),DWORD(bytes.size()),&wrote,nullptr)&&wrote==DWORD(bytes.size())&&FlushFileBuffers(file);
    CloseHandle(file);
    PackedByteArray verified;bool exists=false;
    ok=ok&&read_file(temporary,CATALOG_LIMIT,verified,exists)&&exists&&verified==bytes;
    if(!ok)delete_exact(temporary);
    return ok;
}
void NativeBlockRegionStore::_bind_methods() {
    ClassDB::bind_method(D_METHOD("open_store","absolute_directory","recover_backup"),&NativeBlockRegionStore::open_store,DEFVAL(false));
    ClassDB::bind_method(D_METHOD("close"),&NativeBlockRegionStore::close);
    ClassDB::bind_method(D_METHOD("stats"),&NativeBlockRegionStore::stats);
    ClassDB::bind_method(D_METHOD("list_regions"),&NativeBlockRegionStore::list_regions);
    ClassDB::bind_method(D_METHOD("checksum","region"),&NativeBlockRegionStore::checksum);
    ClassDB::bind_method(D_METHOD("read_region","region"),&NativeBlockRegionStore::read_region);
    ClassDB::bind_method(D_METHOD("publish_region","packet","expected_checksum"),&NativeBlockRegionStore::publish_region);
    ClassDB::bind_method(D_METHOD("publish_regions","packets","expected_checksums"),&NativeBlockRegionStore::publish_regions);
    ClassDB::bind_method(D_METHOD("remove_region","region","expected_checksum"),&NativeBlockRegionStore::remove_region);
    ClassDB::bind_method(D_METHOD("collect_garbage","max_inspected"),&NativeBlockRegionStore::collect_garbage);
}
PackedByteArray NativeBlockRegionStore::pack_digest(const Digest &value) {
    PackedByteArray out;out.resize(32);std::memcpy(out.ptrw(),value.data(),32);return out;
}
bool NativeBlockRegionStore::packet_entry(const PackedByteArray &bytes,BlockKey &key,Entry &entry) {
    std::map<BlockKey,BlockChunk> chunks;
    if(!NativeBlockWorld::parse_region(bytes,key,chunks))return false;
    std::memcpy(entry.digest.data(),bytes.ptr()+bytes.size()-32,32);entry.size=uint32_t(bytes.size());return true;
}
bool NativeBlockRegionStore::parse_catalog(const PackedByteArray &bytes,Catalog &entries,uint64_t &generation) {
    if(bytes.size()<52||bytes.size()>CATALOG_LIMIT||std::memcmp(bytes.ptr(),"TFRC\1\0\0\0",8))return false;
    uint64_t gen=bytes.decode_u64(8),count=bytes.decode_u32(16);
    if(!gen||gen>uint64_t(INT64_MAX)||count>REGION_LIMIT||bytes.size()!=int64_t(52+48*count))return false;
    if(digest(bytes.slice(0,bytes.size()-32))!=bytes.slice(bytes.size()-32))return false;
    Catalog parsed;BlockKey previous;
    for(uint64_t i=0;i<count;i++) {
        int64_t at=20+48*i;
        BlockKey key{int(bytes.decode_s32(at)),int(bytes.decode_s32(at+4)),int(bytes.decode_s32(at+8))};
        if(!NativeBlockWorld::valid_region(key)||(i&&!(previous<key)))return false;
        Entry entry;entry.size=uint32_t(bytes.decode_u32(at+44));
        if(entry.size<100||entry.size>BLOB_LIMIT)return false;
        std::memcpy(entry.digest.data(),bytes.ptr()+at+12,32);parsed.emplace(key,entry);previous=key;
    }
    entries=std::move(parsed);generation=gen;return true;
}
PackedByteArray NativeBlockRegionStore::encode_catalog(const Catalog &entries,uint64_t generation) {
    PackedByteArray out;out.resize(20+48*entries.size());std::memcpy(out.ptrw(),"TFRC\1\0\0\0",8);
    out.encode_u64(8,generation);out.encode_u32(16,uint32_t(entries.size()));int64_t at=20;
    for(const auto &entry:entries) {
        out.encode_s32(at,entry.first.x);out.encode_s32(at+4,entry.first.y);out.encode_s32(at+8,entry.first.z);
        std::memcpy(out.ptrw()+at+12,entry.second.digest.data(),32);out.encode_u32(at+44,entry.second.size);at+=48;
    }
    out.append_array(digest(out));return out;
}
void NativeBlockRegionStore::reset_scan() {if(scan_){FindClose(static_cast<HANDLE>(scan_));scan_=nullptr;}}
void NativeBlockRegionStore::close_locked() {
    reset_scan();if(lease_)CloseHandle(static_cast<HANDLE>(lease_));lease_=nullptr;
    directory_=String();entries_.clear();retained_.clear();canonical_bytes_=PackedByteArray();backup_bytes_=PackedByteArray();
    canonical_exists_=backup_exists_=canonical_active_=backup_valid_=recovered_=false;generation_=generation_floor_=deleted_=0;
}
NativeBlockRegionStore::~NativeBlockRegionStore(){close();}
void NativeBlockRegionStore::close(){std::lock_guard<std::mutex> lock(mutex_);close_locked();}
void NativeBlockRegionStore::rebuild_retained() {
    reset_scan();retained_.clear();for(const auto &entry:entries_)retained_.insert(entry.second.digest);
    Catalog backup;uint64_t generation=0;
    if(backup_valid_&&parse_catalog(backup_bytes_,backup,generation))for(const auto &entry:backup)retained_.insert(entry.second.digest);
}
Dictionary NativeBlockRegionStore::open_store(const String &path,bool recover_backup) {
    std::lock_guard<std::mutex> lock(mutex_);
    if(lease_||!path.is_absolute_path()||path.begins_with("res://")||path.begins_with("user://"))return status(ERR_INVALID_PARAMETER,"Use an existing absolute store directory and a closed store instance.");
    const auto root=path.utf16();DWORD attributes=GetFileAttributesW(reinterpret_cast<LPCWSTR>(root.get_data()));
    if(attributes==INVALID_FILE_ATTRIBUTES||!(attributes&FILE_ATTRIBUTE_DIRECTORY)||(attributes&FILE_ATTRIBUTE_REPARSE_POINT))return status(ERR_CANT_OPEN,"Store must be a local ordinary directory.");
    directory_=path.simplify_path();const auto lease_path=directory_.path_join(".region.lock").utf16();
    HANDLE lease=CreateFileW(reinterpret_cast<LPCWSTR>(lease_path.get_data()),GENERIC_READ|GENERIC_WRITE,0,nullptr,OPEN_ALWAYS,FILE_ATTRIBUTE_NORMAL,nullptr);
    if(lease==INVALID_HANDLE_VALUE){directory_=String();return status(ERR_BUSY,"Store directory is locked or inaccessible.");}
    lease_=lease;
    const auto blobs=directory_.path_join("blobs").utf16();const auto b=reinterpret_cast<LPCWSTR>(blobs.get_data());
    CreateDirectoryW(b,nullptr);attributes=GetFileAttributesW(b);
    if(attributes==INVALID_FILE_ATTRIBUTES||!(attributes&FILE_ATTRIBUTE_DIRECTORY)||(attributes&FILE_ATTRIBUTE_REPARSE_POINT)) {close_locked();return status(ERR_CANT_CREATE,"Cannot use blob directory.");}
    if(!read_file(directory_.path_join("catalog.tfrc"),CATALOG_LIMIT,canonical_bytes_,canonical_exists_)||
       !read_file(directory_.path_join("catalog.tfrc.bak"),CATALOG_LIMIT,backup_bytes_,backup_exists_)) {close_locked();return status(ERR_FILE_CANT_READ,"Catalog files exceed limits or cannot be read.");}
    Catalog main,backup;uint64_t main_gen=0,backup_gen=0;
    bool main_valid=canonical_exists_&&parse_catalog(canonical_bytes_,main,main_gen);
    backup_valid_=backup_exists_&&parse_catalog(backup_bytes_,backup,backup_gen);
    if((recover_backup&&!backup_valid_)||(!recover_backup&&!main_valid&&(canonical_exists_||backup_exists_))) {
        Dictionary out=status(ERR_FILE_CORRUPT,"No valid selected catalog. Backup recovery must be explicitly requested.");
        out["backup_available"]=backup_valid_;close_locked();return out;
    }
    if(recover_backup){entries_=std::move(backup);generation_=backup_gen;recovered_=true;}
    else if(main_valid){entries_=std::move(main);generation_=main_gen;canonical_active_=true;}
    else {
        // Establish a committed empty catalog before any region blob can be
        // published. Existing blobs without either catalog are not a new world.
        WIN32_FIND_DATAW data{};const auto pattern=directory_.path_join("blobs").path_join("*.tfrg").utf16();
        HANDLE found=FindFirstFileW(reinterpret_cast<LPCWSTR>(pattern.get_data()),&data);
        if(found!=INVALID_HANDLE_VALUE){FindClose(found);close_locked();return status(ERR_FILE_CORRUPT,"Region blobs exist without a catalog; refusing to infer an empty world.");}
        if(GetLastError()!=ERROR_FILE_NOT_FOUND){close_locked();return status(ERR_FILE_CANT_READ,"Cannot inspect new store directory.");}
        const String path=directory_.path_join("catalog.tfrc");String pending;
        canonical_bytes_=encode_catalog({},1);
        if(!write_pending(path,canonical_bytes_,pending)){close_locked();return status(ERR_FILE_CANT_WRITE,"Cannot initialize empty catalog.");}
        if(!move_file(pending,path,false)){delete_exact(pending);close_locked();return status(ERR_FILE_CANT_WRITE,"Cannot publish initial catalog.");}
        canonical_exists_=canonical_active_=true;generation_=main_gen=1;
    }
    generation_floor_=std::max(main_gen,backup_gen);rebuild_retained();
    Dictionary out=status(OK);out["generation"]=int64_t(generation_);out["regions"]=int(entries_.size());out["recovered_from_backup"]=recovered_;out["backup_valid"]=backup_valid_;return out;
}
bool NativeBlockRegionStore::observed_files_unchanged() const {
    PackedByteArray bytes;bool exists=false;
    if(!read_file(directory_.path_join("catalog.tfrc"),CATALOG_LIMIT,bytes,exists)||exists!=canonical_exists_||bytes!=canonical_bytes_)return false;
    return read_file(directory_.path_join("catalog.tfrc.bak"),CATALOG_LIMIT,bytes,exists)&&exists==backup_exists_&&bytes==backup_bytes_;
}
Dictionary NativeBlockRegionStore::commit_catalog(Catalog &&next) {
    if(generation_floor_>=uint64_t(INT64_MAX))return status(ERR_OUT_OF_MEMORY,"Catalog generation exhausted.");
    if(!observed_files_unchanged())return status(ERR_BUSY,"Catalog files changed outside this owner; reopen the store.");
    const auto bytes=encode_catalog(next,generation_floor_+1);String pending;
    const String canonical=directory_.path_join("catalog.tfrc");
    if(!write_pending(canonical,bytes,pending))return status(ERR_FILE_CANT_WRITE,"Cannot write and verify new catalog.");
    if(canonical_active_) {
        const String backup=directory_.path_join("catalog.tfrc.bak");String backup_pending;
        if(!write_pending(backup,canonical_bytes_,backup_pending)){delete_exact(pending);return status(ERR_FILE_CANT_WRITE,"Cannot flush backup catalog.");}
        if(!move_file(backup_pending,backup,true)){delete_exact(backup_pending);delete_exact(pending);return status(ERR_FILE_CANT_WRITE,"Cannot publish backup catalog.");}
        backup_bytes_=canonical_bytes_;backup_exists_=backup_valid_=true;
        // Even a later failed canonical rename must retain the actual backup state.
        rebuild_retained();
    }
    if(!move_file(pending,canonical,canonical_exists_)){delete_exact(pending);return status(ERR_FILE_CANT_WRITE,"Cannot atomically publish catalog.");}
    canonical_bytes_=bytes;canonical_exists_=canonical_active_=true;recovered_=false;
    entries_=std::move(next);generation_=++generation_floor_;rebuild_retained();
    Dictionary out=status(OK);out["generation"]=int64_t(generation_);out["regions"]=int(entries_.size());return out;
}
Dictionary NativeBlockRegionStore::publish_region(const PackedByteArray &packet,const PackedByteArray &expected_checksum) {
    Array packets,expected;packets.push_back(packet);expected.push_back(expected_checksum);return publish_regions(packets,expected);
}
Dictionary NativeBlockRegionStore::publish_regions(const Array &packets,const Array &expected_checksums) {
    std::lock_guard<std::mutex> lock(mutex_);
    if(!lease_)return status(ERR_UNCONFIGURED,"Store is closed.");
    if(packets.is_empty()||packets.size()>64||packets.size()!=expected_checksums.size())return status(ERR_INVALID_PARAMETER,"Batch must contain 1..64 packet/checksum pairs.");
    struct Pending {PackedByteArray bytes;Entry entry;};std::vector<Pending> pending;Catalog next=entries_;std::set<BlockKey> seen;
    int64_t total=0;bool changed=false;
    for(int64_t i=0;i<packets.size();i++) {
        if(packets[i].get_type()!=Variant::PACKED_BYTE_ARRAY||expected_checksums[i].get_type()!=Variant::PACKED_BYTE_ARRAY)return status(ERR_INVALID_DATA,"Packets and expected checksums must be byte arrays.");
        PackedByteArray packet=packets[i],expected=expected_checksums[i];total+=packet.size();
        if(total>64*1024*1024)return status(ERR_OUT_OF_MEMORY,"Batch exceeds 64 MiB.");
        BlockKey key;Entry entry;
        if(!packet_entry(packet,key,entry)||!seen.insert(key).second)return status(ERR_INVALID_DATA,"Invalid packet or duplicate region in batch.");
        const auto old=entries_.find(key);
        if(old==entries_.end()?!expected.is_empty():expected!=pack_digest(old->second.digest))return status(ERR_BUSY,"Expected region version no longer matches catalog.");
        changed=changed||old==entries_.end()||old->second.digest!=entry.digest||old->second.size!=entry.size;
        next[key]=entry;if(next.size()>REGION_LIMIT)return status(ERR_OUT_OF_MEMORY,"Catalog region capacity exceeded.");
        pending.push_back({packet,entry});
    }
    if(!observed_files_unchanged())return status(ERR_BUSY,"Catalog files changed outside this owner; reopen the store.");
    for(const auto &item:pending) {
        const String target=directory_.path_join("blobs").path_join(pack_digest(item.entry.digest).hex_encode()+String(".tfrg"));
        PackedByteArray existing;bool exists=false;
        if(!read_file(target,BLOB_LIMIT,existing,exists))return status(ERR_FILE_CANT_READ,"Cannot inspect content-addressed blob.");
        if(exists){if(existing!=item.bytes)return status(ERR_FILE_CORRUPT,"Existing immutable blob is corrupt; it was not overwritten.");continue;}
        String temporary;
        if(!write_pending(target,item.bytes,temporary))return status(ERR_FILE_CANT_WRITE,"Cannot flush and verify region blob.");
        if(!move_file(temporary,target,false)){delete_exact(temporary);return status(ERR_FILE_CANT_WRITE,"Cannot publish region blob.");}
    }
    if(!changed&&!recovered_) {Dictionary out=status(OK);out["generation"]=int64_t(generation_);out["unchanged"]=true;return out;}
    return commit_catalog(std::move(next));
}
Dictionary NativeBlockRegionStore::remove_region(Vector3i region,const PackedByteArray &expected_checksum) {
    std::lock_guard<std::mutex> lock(mutex_);if(!lease_)return status(ERR_UNCONFIGURED,"Store is closed.");
    const BlockKey key{region.x,region.y,region.z};auto it=entries_.find(key);
    if(it==entries_.end()||expected_checksum!=pack_digest(it->second.digest))return status(ERR_BUSY,"Expected region version no longer matches catalog.");
    Catalog next=entries_;next.erase(key);return commit_catalog(std::move(next));
}
PackedByteArray NativeBlockRegionStore::checksum(Vector3i region) const {
    std::lock_guard<std::mutex> lock(mutex_);auto it=entries_.find({region.x,region.y,region.z});return it==entries_.end()?PackedByteArray():pack_digest(it->second.digest);
}
PackedInt32Array NativeBlockRegionStore::list_regions() const {
    std::lock_guard<std::mutex> lock(mutex_);PackedInt32Array out;out.resize(entries_.size()*3);int64_t at=0;
    for(const auto &entry:entries_){out.set(at++,entry.first.x);out.set(at++,entry.first.y);out.set(at++,entry.first.z);}return out;
}
Dictionary NativeBlockRegionStore::read_region(Vector3i region) const {
    std::lock_guard<std::mutex> lock(mutex_);if(!lease_)return status(ERR_UNCONFIGURED,"Store is closed.");
    const BlockKey key{region.x,region.y,region.z};auto it=entries_.find(key);
    if(it==entries_.end())return status(ERR_DOES_NOT_EXIST,"Region is not cataloged.");
    const auto expected=pack_digest(it->second.digest);PackedByteArray bytes;bool exists=false;BlockKey parsed;Entry entry;
    if(!read_file(directory_.path_join("blobs").path_join(expected.hex_encode()+String(".tfrg")),BLOB_LIMIT,bytes,exists)||!exists||
       bytes.size()!=it->second.size||!packet_entry(bytes,parsed,entry)||parsed<key||key<parsed||entry.digest!=it->second.digest)return status(ERR_FILE_CORRUPT,"Cataloged blob is missing or corrupt.");
    Dictionary out=status(OK);out["bytes"]=bytes;out["checksum"]=expected;out["generation"]=int64_t(generation_);return out;
}
Dictionary NativeBlockRegionStore::stats() const {
    std::lock_guard<std::mutex> lock(mutex_);Dictionary out;uint64_t bytes=0;for(const auto &entry:entries_)bytes+=entry.second.size;
    out["open"]=lease_!=nullptr;out["regions"]=int(entries_.size());out["generation"]=int64_t(generation_);
    out["recovered_from_backup"]=recovered_;out["catalog_bytes"]=canonical_bytes_.size();out["referenced_blob_bytes"]=int64_t(bytes);
    out["garbage_deleted"]=int64_t(deleted_);out["max_regions"]=int(REGION_LIMIT);return out;
}
Dictionary NativeBlockRegionStore::collect_garbage(int max_inspected) {
    std::lock_guard<std::mutex> lock(mutex_);
    if(!lease_)return status(ERR_UNCONFIGURED,"Store is closed.");
    if(max_inspected<1||max_inspected>256)return status(ERR_INVALID_PARAMETER,"Inspection budget must be 1..256 files.");
    if(recovered_||(backup_exists_&&!backup_valid_)||!observed_files_unchanged())return status(ERR_BUSY,"Publish recovery or repair/reopen catalog state before cleanup.");
    WIN32_FIND_DATAW data{};bool found=false;DWORD enumeration_error=ERROR_SUCCESS;
    if(scan_){found=FindNextFileW(static_cast<HANDLE>(scan_),&data);if(!found)enumeration_error=GetLastError();}
    else {
        const auto pattern=directory_.path_join("blobs").path_join("*.tfrg").utf16();
        HANDLE handle=FindFirstFileW(reinterpret_cast<LPCWSTR>(pattern.get_data()),&data);
        if(handle!=INVALID_HANDLE_VALUE){scan_=handle;found=true;}
        else if(GetLastError()!=ERROR_FILE_NOT_FOUND)return status(ERR_FILE_CANT_READ,"Cannot enumerate blob directory.");
    }
    int inspected=0,removed=0;bool complete=false;
    while(found&&inspected<max_inspected) {
        ++inspected;String name=String::utf16(reinterpret_cast<const char16_t*>(data.cFileName));
        bool eligible=!(data.dwFileAttributes&(FILE_ATTRIBUTE_DIRECTORY|FILE_ATTRIBUTE_REPARSE_POINT))&&name.length()==69&&name.ends_with(".tfrg");
        for(int i=0;eligible&&i<64;i++)eligible=(name[i]>='0'&&name[i]<='9')||(name[i]>='a'&&name[i]<='f');
        if(eligible) {
            Digest id{};auto nibble=[](char32_t c){return c<='9'?int(c-'0'):int(c-'a'+10);};
            for(int i=0;i<32;i++)id[i]=uint8_t((nibble(name[i*2])<<4)|nibble(name[i*2+1]));
            if(!retained_.count(id)) {
                const String path=directory_.path_join("blobs").path_join(name);PackedByteArray bytes;bool exists=false;BlockKey key;Entry entry;
                if(read_file(path,BLOB_LIMIT,bytes,exists)&&exists&&packet_entry(bytes,key,entry)&&entry.digest==id) {
                    const auto file=path.utf16();if(DeleteFileW(reinterpret_cast<LPCWSTR>(file.get_data()))){++removed;++deleted_;}
                }
            }
        }
        if(inspected<max_inspected){found=FindNextFileW(static_cast<HANDLE>(scan_),&data);if(!found)enumeration_error=GetLastError();}
    }
    bool failed=enumeration_error!=ERROR_SUCCESS&&enumeration_error!=ERROR_NO_MORE_FILES;
    if(!found){reset_scan();complete=!failed;}
    Dictionary out=status(failed?ERR_FILE_CANT_READ:OK,failed?String("Blob enumeration failed."):String());out["inspected"]=inspected;out["deleted"]=removed;out["complete"]=complete;return out;
}
}
