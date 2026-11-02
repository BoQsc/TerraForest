// SPDX-License-Identifier: 0BSD
#include "world_archive.hpp"
#include <godot_cpp/classes/dir_access.hpp>
#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/classes/hashing_context.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <algorithm>
#include <climits>
#include <map>
#include <mutex>

namespace terraforest {
using namespace godot;
namespace {
constexpr int location_limit=128,manifest_header=48,manifest_record=80,digest_size=32;
constexpr int64_t baseline_limit=16*1024*1024,total_limit=256*1024*1024;
constexpr uint32_t manifest_magic=0x49424654,identity_magic=0x42514654;
const char *required_sections[]={"terrain","blocks","cubes","models","doors","damage","containers","residents","corpses","trees","ground","water"};
PackedByteArray hash_bytes(const PackedByteArray &bytes){
    Ref<HashingContext> context;context.instantiate();
    if(context->start(HashingContext::HASH_SHA256)!=OK||context->update(bytes)!=OK)return {};
    return context->finish();
}
bool valid_digest(const PackedByteArray &bytes){
    return bytes.size()==digest_size&&std::any_of(bytes.ptr(),bytes.ptr()+bytes.size(),[](uint8_t value){return value!=0;});
}
bool valid_sections(const Dictionary &sections){
    if(sections.size()<12||sections.size()>64||sections.has("baseline_identity"))return false;
    for(const char *name:required_sections)if(!sections.has(name))return false;
    int64_t total=48+8+17+80;
    const auto names=sections.keys();
    for(int index=0;index<names.size();++index){
        if((names[index].get_type()!=Variant::STRING&&names[index].get_type()!=Variant::STRING_NAME)||sections[names[index]].get_type()!=Variant::PACKED_BYTE_ARRAY)return false;
        const String name=names[index];const PackedByteArray bytes=sections[names[index]];
        if(name.is_empty()||name.length()>48||bytes.size()>baseline_limit)return false;
        for(int letter=0;letter<name.length();++letter){
            const char32_t value=name[letter];
            if(!((value>='a'&&value<='z')||(value>='0'&&value<='9')||value=='_'))return false;
        }
        total+=8+name.length()+bytes.size();if(total>baseline_limit)return false;
    }
    return true;
}
}
class NativeLocationBaselineStore : public RefCounted {
    GDCLASS(NativeLocationBaselineStore,RefCounted)
    struct Entry {PackedByteArray definition,digest;int64_t bytes=0;};
    mutable std::mutex mutex;
    String directory;
    PackedByteArray world;
    Ref<NativeWorldArchive> lease;
    std::map<int64_t,Entry> entries;
    int64_t revision=0;
    mutable bool io_active=false;
    int64_t total_bytes() const {int64_t total=0;for(const auto &[key,entry]:entries)total+=entry.bytes;return total;}
    Dictionary result(bool ok,const char *reason) const {
        Dictionary output;output["ok"]=ok;output["reason"]=reason;output["revision"]=revision;return output;
    }
    static bool parse(const PackedByteArray &data,std::map<int64_t,Entry> &parsed,PackedByteArray &identity){
        if(data.is_empty())return true;
        if(data.size()<manifest_header+digest_size||data.size()>manifest_header+location_limit*manifest_record+digest_size||
            data.decode_u32(0)!=manifest_magic||data.decode_u32(4)!=1||data.decode_u32(12)!=0)return false;
        const uint32_t count=data.decode_u32(8);
        if(count>location_limit||data.size()!=manifest_header+int64_t(count)*manifest_record+digest_size)return false;
        identity=data.slice(16,48);if(!valid_digest(identity)||hash_bytes(data.slice(0,data.size()-digest_size))!=data.slice(data.size()-digest_size))return false;
        int64_t previous=0,total=0;
        for(uint32_t index=0;index<count;++index){
            const int offset=manifest_header+index*manifest_record;const uint64_t key=data.decode_u64(offset),size=data.decode_u64(offset+72);
            if(key<=uint64_t(previous)||key>INT64_MAX||size==0||size>baseline_limit||size>uint64_t(total_limit-total))return false;
            Entry entry{data.slice(offset+8,offset+40),data.slice(offset+40,offset+72),int64_t(size)};
            if(!valid_digest(entry.definition)||!valid_digest(entry.digest))return false;
            parsed.emplace(int64_t(key),entry);previous=int64_t(key);total+=int64_t(size);
        }
        return true;
    }
    PackedByteArray read_blob(const PackedByteArray &digest,int64_t expected_size) const {
        const auto path=directory.path_join(digest.hex_encode()+".baseline");
        const Ref<FileAccess> file=FileAccess::open(path,FileAccess::READ);
        if(file.is_null()||file->get_length()!=uint64_t(expected_size)||expected_size<=0||expected_size>baseline_limit)return {};
        const auto data=file->get_buffer(expected_size);
        return data.size()==expected_size&&hash_bytes(data)==digest?data:PackedByteArray();
    }
    PackedByteArray metadata(int64_t key,const PackedByteArray &definition) const {
        PackedByteArray identity;identity.resize(16);identity.encode_u32(0,identity_magic);identity.encode_u32(4,1);identity.encode_u64(8,key);
        identity.append_array(world);identity.append_array(definition);return identity;
    }
protected:
    static void _bind_methods(){
        ClassDB::bind_method(D_METHOD("open_store","absolute_directory","world_identity"),&NativeLocationBaselineStore::open_store);
        ClassDB::bind_method(D_METHOD("state"),&NativeLocationBaselineStore::state);
        ClassDB::bind_method(D_METHOD("publish_baseline","key","definition","sections","revision","owner"),&NativeLocationBaselineStore::publish_baseline);
        ClassDB::bind_method(D_METHOD("load_baseline","key","definition"),&NativeLocationBaselineStore::load_baseline);
        ClassDB::bind_method(D_METHOD("capture_storage_snapshot"),&NativeLocationBaselineStore::capture_storage_snapshot);
        ClassDB::bind_method(D_METHOD("validate_snapshot","data"),&NativeLocationBaselineStore::validate_snapshot);
        ClassDB::bind_method(D_METHOD("restore_storage_snapshot","data"),&NativeLocationBaselineStore::restore_storage_snapshot);
    }
public:
    bool open_store(const String &absolute_directory,const PackedByteArray &world_identity){
        std::lock_guard<std::mutex> lock(mutex);
        if(lease.is_valid()||!absolute_directory.is_absolute_path()||absolute_directory.begins_with("res://")||absolute_directory.begins_with("user://")||!valid_digest(world_identity))return false;
        const String path=absolute_directory.replace("\\","/").simplify_path();
        if(DirAccess::make_dir_recursive_absolute(path)!=OK)return false;
        Ref<NativeWorldArchive> writer;writer.instantiate();if(!writer->acquire(path.path_join("baselines")))return false;
        directory=path;world=world_identity;lease=writer;++revision;return true;
    }
    Dictionary state() const {
        std::lock_guard<std::mutex> lock(mutex);
        auto output=result(lease.is_valid(),lease.is_valid()?"":"not_open");
        output["owner"]=int64_t(get_instance_id());output["locations"]=int64_t(entries.size());output["bytes"]=total_bytes();output["io_active"]=io_active;return output;
    }
    Dictionary publish_baseline(int64_t key,const PackedByteArray &definition,const Dictionary &sections,int64_t expected_revision,int64_t expected_owner){
        std::unique_lock<std::mutex> lock(mutex);
        if(lease.is_null()||expected_revision!=revision||expected_owner!=int64_t(get_instance_id())||revision==INT64_MAX)return result(false,"invalid_or_stale");
        if(io_active)return result(false,"busy");
        if(key<=0||!valid_digest(definition)||!valid_sections(sections))return result(false,"invalid_baseline");
        const auto found=entries.find(key);
        if(found!=entries.end()&&found->second.definition!=definition)return result(false,"immutable_conflict");
        if(found==entries.end()&&entries.size()>=location_limit)return result(false,"location_capacity");
        Dictionary combined;const auto names=sections.keys();
        for(int index=0;index<names.size();++index){const String name=names[index];if(combined.has(name))return result(false,"invalid_baseline");combined[name]=sections[names[index]];}
        combined["baseline_identity"]=metadata(key,definition);
        const bool added=found==entries.end();
        const Entry previous=added?Entry{}:found->second;
        const int64_t available=total_limit-total_bytes();
        PackedByteArray digest;int64_t size=0;io_active=true;lock.unlock();
        const char *failure=[&]()->const char *{
            const auto packet=lease->encode(combined);if(packet.is_empty()||packet.size()>baseline_limit)return "invalid_baseline";
            size=packet.size();digest=hash_bytes(packet);if(!valid_digest(digest))return "hash_failed";
            if(!added&&(previous.digest!=digest||previous.bytes!=size))return "immutable_conflict";
            if(added&&size>available)return "byte_capacity";
            const String path=directory.path_join(digest.hex_encode()+".baseline");
            Ref<NativeWorldArchive> publisher;publisher.instantiate();
            if(!publisher->acquire(path))return "writer_busy";
            if(FileAccess::file_exists(path)){
                if(read_blob(digest,size)!=packet)return "corrupt_baseline";
            }else if(!added||DirAccess::dir_exists_absolute(path))return "missing_baseline";
            else if(publisher->publish(path,packet)!=OK)return "publish_failed";
            return "";
        }();
        lock.lock();io_active=false;if(*failure)return result(false,failure);
        if(added){entries.emplace(key,Entry{definition,digest,size});++revision;}
        auto output=result(true,"");output["digest"]=digest;output["bytes"]=size;output["added"]=added;return output;
    }
    Dictionary load_baseline(int64_t key,const PackedByteArray &definition) const {
        std::unique_lock<std::mutex> lock(mutex);
        const auto found=entries.find(key);
        if(lease.is_null()||found==entries.end()||definition!=found->second.definition)return result(false,"unknown_or_changed_location");
        if(io_active)return result(false,"busy");
        const Entry entry=found->second;Dictionary sections;const auto identity=metadata(key,definition);
        io_active=true;lock.unlock();
        const char *failure=[&]()->const char *{
            const auto packet=read_blob(entry.digest,entry.bytes);if(packet.is_empty())return "missing_or_corrupt_baseline";
            const auto decoded=lease->decode(packet);if(!bool(decoded["ok"]))return "invalid_baseline";
            sections=decoded["sections"];
            if(!sections.has("baseline_identity")||sections["baseline_identity"].get_type()!=Variant::PACKED_BYTE_ARRAY||PackedByteArray(sections["baseline_identity"])!=identity)return "identity_mismatch";
            sections.erase("baseline_identity");return valid_sections(sections)?"":"invalid_baseline";
        }();
        lock.lock();io_active=false;if(*failure)return result(false,failure);
        auto output=result(true,"");output["sections"]=sections;output["digest"]=found->second.digest;return output;
    }
    PackedByteArray capture_storage_snapshot() const {
        std::lock_guard<std::mutex> lock(mutex);if(lease.is_null())return {};
        PackedByteArray data;if(data.resize(manifest_header+entries.size()*manifest_record)!=OK)return {};data.fill(0);
        data.encode_u32(0,manifest_magic);data.encode_u32(4,1);data.encode_u32(8,entries.size());
        for(int index=0;index<digest_size;++index)data.set(16+index,world[index]);
        int offset=manifest_header;
        for(const auto &[key,entry]:entries){
            data.encode_u64(offset,key);data.encode_u64(offset+72,entry.bytes);
            for(int index=0;index<digest_size;++index){data.set(offset+8+index,entry.definition[index]);data.set(offset+40+index,entry.digest[index]);}
            offset+=manifest_record;
        }
        const auto digest=hash_bytes(data);if(digest.size()!=digest_size)return {};data.append_array(digest);return data;
    }
    bool validate_snapshot(const PackedByteArray &data) const {
        std::lock_guard<std::mutex> lock(mutex);std::map<int64_t,Entry> parsed;PackedByteArray identity;
        return parse(data,parsed,identity)&&(world.is_empty()||identity.is_empty()||identity==world);
    }
    bool restore_storage_snapshot(const PackedByteArray &data){
        std::lock_guard<std::mutex> lock(mutex);if(lease.is_null()||io_active||revision==INT64_MAX)return false;
        std::map<int64_t,Entry> parsed;PackedByteArray identity;
        if(!parse(data,parsed,identity)||(!identity.is_empty()&&identity!=world))return false;
        entries=std::move(parsed);++revision;return true;
    }
};
void register_location_baseline(){ClassDB::register_class<NativeLocationBaselineStore>();}
}
