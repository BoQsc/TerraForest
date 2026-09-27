#include "world_archive.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/classes/hashing_context.hpp>
#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/variant/array.hpp>
#include <algorithm>
#include <atomic>
#include <cstring>
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>

using namespace godot;
namespace terraforest {
static constexpr int64_t LIMIT=256ll*1024*1024;
static constexpr uint8_t MAGIC[8]={'T','F','W','O','R','L','D','1'};
static bool valid_name(const String &name) {
    if(name.length()<1 || name.length()>48)return false;
    for(int i=0;i<name.length();++i) {
        const char32_t c=name[i];
        if(!((c>='a'&&c<='z')||(c>='0'&&c<='9')||c=='_'))return false;
    }
    return true;
}
static PackedByteArray archive_hash(const PackedByteArray &data) {
    Ref<HashingContext> context; context.instantiate();
    if(context->start(HashingContext::HASH_SHA256)!=OK || context->update(data.slice(8,16))!=OK)return {};
    for(int64_t offset=48;offset<data.size();offset+=65536)
        if(context->update(data.slice(offset,std::min(offset+65536,data.size())))!=OK)return {};
    return context->finish();
}
void NativeWorldArchive::_bind_methods() {
    ClassDB::bind_method(D_METHOD("acquire","absolute_path"),&NativeWorldArchive::acquire);
    ClassDB::bind_method(D_METHOD("release"),&NativeWorldArchive::release);
    ClassDB::bind_method(D_METHOD("encode","sections"),&NativeWorldArchive::encode);
    ClassDB::bind_method(D_METHOD("decode","bytes"),&NativeWorldArchive::decode);
    ClassDB::bind_method(D_METHOD("read","absolute_path"),&NativeWorldArchive::read);
    ClassDB::bind_method(D_METHOD("publish","absolute_path","bytes"),&NativeWorldArchive::publish);
}
NativeWorldArchive::~NativeWorldArchive(){release();}
bool NativeWorldArchive::acquire(const String &path) {
    if(lease_ || !path.is_absolute_path() || path.begins_with("res://") || path.begins_with("user://"))return false;
    const Char16String lock=(path+String(".lock")).utf16();
    HANDLE handle=CreateFileW(reinterpret_cast<LPCWSTR>(lock.get_data()),GENERIC_READ|GENERIC_WRITE,0,nullptr,OPEN_ALWAYS,FILE_ATTRIBUTE_NORMAL,nullptr);
    if(handle==INVALID_HANDLE_VALUE)return false;
    lease_=handle; leased_path_=path; return true;
}
void NativeWorldArchive::release(){if(lease_){CloseHandle(static_cast<HANDLE>(lease_));lease_=nullptr;leased_path_=String();}}
PackedByteArray NativeWorldArchive::encode(const Dictionary &sections) const {
    if(sections.size()<1 || sections.size()>64 || !sections.has("terrain"))return {};
    Array keys=sections.keys();
    int64_t total=48;
    for(int64_t i=0;i<keys.size();++i) {
        if(keys[i].get_type()!=Variant::STRING)return {};
        const String name=keys[i]; const Variant value=sections[name];
        if(!valid_name(name) || value.get_type()!=Variant::PACKED_BYTE_ARRAY)return {};
        const PackedByteArray part=value;
        if(part.size()>LIMIT || (name!="terrain" && part.size()>16*1024*1024))return {};
        total+=8+name.length()+part.size();
        if(total>LIMIT)return {};
    }
    keys.sort();
    PackedByteArray out; if(out.resize(total)!=OK)return {};
    std::memcpy(out.ptrw(),MAGIC,8); out.encode_u32(8,1);out.encode_u32(12,uint32_t(keys.size()));
    int64_t cursor=48;
    for(int64_t i=0;i<keys.size();++i) {
        const String name=keys[i];const PackedByteArray part=sections[name];
        out.encode_u32(cursor,uint32_t(name.length()));out.encode_u32(cursor+4,uint32_t(part.size()));cursor+=8;
        const CharString utf8=name.utf8();std::memcpy(out.ptrw()+cursor,utf8.get_data(),size_t(name.length()));cursor+=name.length();
        if(part.size())std::memcpy(out.ptrw()+cursor,part.ptr(),size_t(part.size()));cursor+=part.size();
    }
    // Digest includes version and count as well as the complete section table.
    const PackedByteArray digest=archive_hash(out);if(digest.size()!=32)return {};
    std::memcpy(out.ptrw()+16,digest.ptr(),32);return out;
}
static Dictionary decode_archive(const PackedByteArray &bytes, bool materialize) {
    Dictionary result;result["ok"]=false;
    if(bytes.size()<48 || bytes.size()>LIMIT || std::memcmp(bytes.ptr(),MAGIC,8)!=0 || bytes.decode_u32(8)!=1)return result;
    const uint32_t count=bytes.decode_u32(12);if(count<1||count>64)return result;
    if(archive_hash(bytes)!=bytes.slice(16,48))return result;
    // Validate every bound/name before materializing section payloads.
    int64_t offsets[64], lengths[64];String names[64];int64_t cursor=48;
    String previous;
    for(uint32_t i=0;i<count;++i) {
        if(cursor>bytes.size()-8)return result;
        const uint32_t n=bytes.decode_u32(cursor), length=bytes.decode_u32(cursor+4);cursor+=8;
        if(n<1||n>48||cursor+n>bytes.size()||length>bytes.size()-cursor-n)return result;
        names[i]=String::utf8(reinterpret_cast<const char*>(bytes.ptr()+cursor),n);
        if(!valid_name(names[i]) || (i && names[i]<=previous) || (names[i]!="terrain" && length>16*1024*1024))return result;
        previous=names[i];cursor+=n;offsets[i]=cursor;lengths[i]=length;cursor+=length;
    }
    if(cursor!=bytes.size())return result;
    bool terrain_found=false;
    for(uint32_t i=0;i<count;++i)if(names[i]=="terrain")terrain_found=true;
    if(!terrain_found)return result;
    if(!materialize){result["ok"]=true;return result;}
    Dictionary sections;
    for(uint32_t i=0;i<count;++i)sections[names[i]]=bytes.slice(offsets[i],offsets[i]+lengths[i]);
    if(!sections.has("terrain"))return result;
    result["ok"]=true;result["sections"]=sections;return result;
}
Dictionary NativeWorldArchive::decode(const PackedByteArray &bytes) const {return decode_archive(bytes,true);}
PackedByteArray NativeWorldArchive::read(const String &path) const {
    Ref<FileAccess> file=FileAccess::open(path,FileAccess::READ);
    if(file.is_null() || file->get_length()>LIMIT)return {};
    return file->get_buffer(file->get_length());
}
int64_t NativeWorldArchive::publish(const String &path,const PackedByteArray &bytes) const {
    if(!lease_ || path!=leased_path_ || !bool(decode_archive(bytes,false)["ok"]))return ERR_INVALID_DATA;
    static std::atomic<uint64_t> sequence{0};
    const String temporary=path+String(".pending.")+String::num_uint64(GetCurrentProcessId())+String(".")+String::num_uint64(++sequence);
    const Char16String temp=temporary.utf16(), target=path.utf16(), backup=(path+String(".bak")).utf16(), backup_temp=(temporary+String(".bak")).utf16();
    const auto t=reinterpret_cast<LPCWSTR>(temp.get_data()), p=reinterpret_cast<LPCWSTR>(target.get_data());
    HANDLE file=CreateFileW(t,GENERIC_WRITE,0,nullptr,CREATE_NEW,FILE_ATTRIBUTE_NORMAL|FILE_FLAG_WRITE_THROUGH,nullptr);
    if(file==INVALID_HANDLE_VALUE)return ERR_CANT_CREATE;
    DWORD written=0;const BOOL wrote=WriteFile(file,bytes.ptr(),DWORD(bytes.size()),&written,nullptr);
    const BOOL flushed=wrote && written==DWORD(bytes.size()) && FlushFileBuffers(file);
    CloseHandle(file);
    bool verified=flushed;
    {
        Ref<FileAccess> verify=FileAccess::open(temporary,FileAccess::READ);
        verified=verified && verify.is_valid() && verify->get_length()==uint64_t(bytes.size());
        for(int64_t offset=0;verified&&offset<bytes.size();offset+=65536) {
            const int64_t length=std::min(int64_t(65536),bytes.size()-offset);
            verified=verify->get_buffer(length)==bytes.slice(offset,offset+length);
        }
    }
    if(!verified){DeleteFileW(t);return ERR_FILE_CANT_WRITE;}
    // Copy the previous version without moving the canonical file out of place.
    if(GetFileAttributesW(p)!=INVALID_FILE_ATTRIBUTES) {
        const auto bt=reinterpret_cast<LPCWSTR>(backup_temp.get_data());
        if(!CopyFileW(p,bt,TRUE) || !MoveFileExW(bt,reinterpret_cast<LPCWSTR>(backup.get_data()),MOVEFILE_REPLACE_EXISTING|MOVEFILE_WRITE_THROUGH)) {
            DeleteFileW(bt);DeleteFileW(t);return ERR_FILE_CANT_WRITE;
        }
    }
    if(!MoveFileExW(t,p,MOVEFILE_REPLACE_EXISTING|MOVEFILE_WRITE_THROUGH)){DeleteFileW(t);return ERR_FILE_CANT_WRITE;}
    return OK;
}
}
