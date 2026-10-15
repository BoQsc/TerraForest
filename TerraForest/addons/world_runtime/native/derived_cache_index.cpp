// SPDX-License-Identifier: 0BSD
#include "derived_cache_index.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <algorithm>
#include <cstring>
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
using namespace godot;
namespace terraforest {
static std::string key_for(const String &s){auto u=s.utf8();return {u.get_data(),size_t(u.length())};}
static uint64_t pair64(DWORD low,DWORD high){return uint64_t(low)|(uint64_t(high)<<32);}
static uint32_t word(const unsigned char*p){uint32_t v;std::memcpy(&v,p,4);return v;}
static HANDLE open_cache_file(const String &path,DWORD access,DWORD share,DWORD creation,DWORD flags){
    auto w=path.utf16();return CreateFileW(reinterpret_cast<LPCWSTR>(w.get_data()),access,share,nullptr,creation,flags,nullptr);
}
static bool hex64(const String &s){if(s.length()!=64)return false;for(int i=0;i<64;++i)if(!((s[i]>='0'&&s[i]<='9')||(s[i]>='a'&&s[i]<='f')))return false;return true;}
void NativeDerivedCacheIndex::_bind_methods(){
    ClassDB::bind_method(D_METHOD("acquire","root"),&NativeDerivedCacheIndex::acquire);
    ClassDB::bind_method(D_METHOD("release"),&NativeDerivedCacheIndex::release);
    ClassDB::bind_method(D_METHOD("track","path"),&NativeDerivedCacheIndex::track);
    ClassDB::bind_method(D_METHOD("safe_directory","path"),&NativeDerivedCacheIndex::safe_directory);
    ClassDB::bind_method(D_METHOD("touch","path"),&NativeDerivedCacheIndex::touch);
    ClassDB::bind_method(D_METHOD("forget","path"),&NativeDerivedCacheIndex::forget);
    ClassDB::bind_method(D_METHOD("evict_one"),&NativeDerivedCacheIndex::evict_one);
    ClassDB::bind_method(D_METHOD("count"),&NativeDerivedCacheIndex::count);
    ClassDB::bind_method(D_METHOD("available_bytes"),&NativeDerivedCacheIndex::available_bytes);
}
int64_t NativeDerivedCacheIndex::available_bytes() const{
    if(!lease_||!directory_||root_.is_empty())return -1;
    ULARGE_INTEGER available{};
    auto path=root_.utf16();
    if(!GetDiskFreeSpaceExW(reinterpret_cast<LPCWSTR>(path.get_data()),&available,nullptr,nullptr))return -1;
    return available.QuadPart>uint64_t(INT64_MAX)?INT64_MAX:int64_t(available.QuadPart);
}
NativeDerivedCacheIndex::~NativeDerivedCacheIndex(){release();}
void NativeDerivedCacheIndex::release(){entries_.clear();order_.clear();clock_=0;if(lease_)CloseHandle(HANDLE(lease_));if(directory_)CloseHandle(HANDLE(directory_));lease_=directory_=nullptr;root_=String();}
bool NativeDerivedCacheIndex::ordinary(const String &path) const{
    String current=path;
    for(int depth=0;depth<64;++depth){
        auto w=current.utf16();DWORD attributes=GetFileAttributesW(reinterpret_cast<LPCWSTR>(w.get_data()));
        if(attributes==INVALID_FILE_ATTRIBUTES||(attributes&FILE_ATTRIBUTE_REPARSE_POINT))return false;
        String parent=current.get_base_dir();if(parent==current||parent.is_empty()||current.length()<=3)return true;
        current=parent;
    }return false;
}
bool NativeDerivedCacheIndex::acquire(const String &root){
    if(lease_||!root.is_absolute_path()||root.begins_with("user://")||root.begins_with("res://"))return false;
    root_=root.simplify_path().trim_suffix("/");
    if(!ordinary(root_)){root_=String();return false;}
    HANDLE directory=open_cache_file(root_,FILE_LIST_DIRECTORY,FILE_SHARE_READ|FILE_SHARE_WRITE,OPEN_EXISTING,FILE_FLAG_BACKUP_SEMANTICS|FILE_FLAG_OPEN_REPARSE_POINT);
    if(directory==INVALID_HANDLE_VALUE){root_=String();return false;}
    HANDLE lease=open_cache_file(root_.path_join(".terraforest-derived.lock"),GENERIC_READ|GENERIC_WRITE,0,OPEN_ALWAYS,FILE_FLAG_OPEN_REPARSE_POINT);
    if(lease==INVALID_HANDLE_VALUE){CloseHandle(directory);root_=String();return false;}
    BY_HANDLE_FILE_INFORMATION info{};
    if(!GetFileInformationByHandle(lease,&info)||((info.dwFileAttributes&FILE_ATTRIBUTE_REPARSE_POINT)||info.nFileSizeLow||info.nFileSizeHigh)){CloseHandle(lease);CloseHandle(directory);root_=String();return false;}
    directory_=directory;lease_=lease;return true;
}
bool NativeDerivedCacheIndex::safe_directory(const String &path) const{
    return lease_&&path==path.simplify_path()&&(path==root_||path.begins_with(root_+String("/")))&&ordinary(path);
}
bool NativeDerivedCacheIndex::candidate(const String &path) const{
    if(!lease_||path!=path.simplify_path()||!path.begins_with(root_+String("/")))return false;
    auto parts=path.substr(root_.length()+1).split("/");
    if((parts.size()!=3&&parts.size()!=4)||!hex64(parts[0]))return false;
    if(parts.size()==4)return parts[1]=="geometry_v1"&&hex64(parts[2])&&parts[3].ends_with(".trc")&&ordinary(path);
    if(parts[1]=="lakes_v1")return parts[2].ends_with(".trl")&&hex64(parts[2].trim_suffix(".trl"))&&ordinary(path);
    // Legacy snapshot names are kept, but only exact typed packet headers below authorize deletion.
    const String snapshot=parts[1];
    return (hex64(snapshot)||snapshot.begins_with("new_generator_")||snapshot=="new_seed_1703")&&parts[2].ends_with(".trc")&&ordinary(path);
}
bool NativeDerivedCacheIndex::track(const String &path){
    if(!candidate(path))return false;
    const std::string key=key_for(path);if(entries_.size()>=65536&&!entries_.count(key))return false;
    HANDLE file=open_cache_file(path,GENERIC_READ,FILE_SHARE_READ,OPEN_EXISTING,FILE_FLAG_OPEN_REPARSE_POINT);
    if(file==INVALID_HANDLE_VALUE)return false;
    BY_HANDLE_FILE_INFORMATION info{};unsigned char header[76]{};DWORD read=0;
    bool ok=GetFileInformationByHandle(file,&info)&&!(info.dwFileAttributes&(FILE_ATTRIBUTE_DIRECTORY|FILE_ATTRIBUTE_REPARSE_POINT));
    uint64_t size=pair64(info.nFileSizeLow,info.nFileSizeHigh);
    ok=ok&&size>=76&&size<=64*1024*1024+40&&ReadFile(file,header,76,&read,nullptr)&&read==76&&word(header+4)==size-40;
    if(ok&&path.ends_with(".trc")){
        auto coords=path.get_file().trim_suffix(".trc").split("_");
        ok=coords.size()==3&&word(header)==0x36435254&&word(header+40)==0x324d5254&&word(header+44)==5;
        for(int i=0;ok&&i<3;++i)ok=coords[i].is_valid_int()&&coords[i].to_int()>=INT32_MIN&&coords[i].to_int()<=INT32_MAX&&int32_t(word(header+48+i*4))==coords[i].to_int();
    }else if(ok)ok=path.ends_with(".trl")&&word(header)==0x31434c54&&size>=144&&size<=6*1024*1024+40;
    CloseHandle(file);if(!ok)return false;
    forget(path);uint64_t stamp=pair64(info.ftLastWriteTime.dwLowDateTime,info.ftLastWriteTime.dwHighDateTime);clock_=std::max(clock_,stamp);
    Entry entry{path,size,stamp,pair64(info.nFileIndexLow,info.nFileIndexHigh),info.dwVolumeSerialNumber,stamp};
    entries_.emplace(key,entry);order_.insert({stamp,key});return true;
}
void NativeDerivedCacheIndex::forget(const String &path){auto it=entries_.find(key_for(path));if(it!=entries_.end()){order_.erase({it->second.age,it->first});entries_.erase(it);}}
void NativeDerivedCacheIndex::touch(const String &path){auto it=entries_.find(key_for(path));if(it!=entries_.end()){order_.erase({it->second.age,it->first});FILETIME now;GetSystemTimeAsFileTime(&now);clock_=std::max(clock_,pair64(now.dwLowDateTime,now.dwHighDateTime));it->second.age=++clock_;order_.insert({clock_,it->first});}}
Dictionary NativeDerivedCacheIndex::evict_one(){
    Dictionary out;out["ok"]=false;out["bytes"]=0;out["reason"]="empty";
    if(!lease_||order_.empty())return out;
    auto it=entries_.find(order_.begin()->second);const Entry e=it->second;
    out["reason"]="changed";if(!candidate(e.path)){forget(e.path);return out;}
    HANDLE file=open_cache_file(e.path,GENERIC_READ|DELETE,FILE_SHARE_READ,OPEN_EXISTING,FILE_FLAG_OPEN_REPARSE_POINT);
    if(file==INVALID_HANDLE_VALUE){
        const DWORD error=GetLastError();
        if(error==ERROR_SHARING_VIOLATION||error==ERROR_LOCK_VIOLATION)out["reason"]="busy";
        else forget(e.path);
        return out;
    }
    BY_HANDLE_FILE_INFORMATION info{};
    bool same=GetFileInformationByHandle(file,&info)&&!(info.dwFileAttributes&(FILE_ATTRIBUTE_DIRECTORY|FILE_ATTRIBUTE_REPARSE_POINT))&&
        pair64(info.nFileSizeLow,info.nFileSizeHigh)==e.size&&pair64(info.ftLastWriteTime.dwLowDateTime,info.ftLastWriteTime.dwHighDateTime)==e.stamp&&
        pair64(info.nFileIndexLow,info.nFileIndexHigh)==e.identity&&info.dwVolumeSerialNumber==e.volume;
    FILE_DISPOSITION_INFO disposition{TRUE};bool removed=same&&SetFileInformationByHandle(file,FileDispositionInfo,&disposition,sizeof(disposition));
    CloseHandle(file);forget(e.path);if(removed){out["ok"]=true;out["bytes"]=int64_t(e.size);out["reason"]="evicted";}
    return out;
}
}
