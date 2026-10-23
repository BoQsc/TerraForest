// SPDX-License-Identifier: 0BSD
#include "world_archive.hpp"
#include <godot_cpp/classes/dir_access.hpp>
#include <godot_cpp/classes/file_access.hpp>
#include <filesystem>
#include <atomic>
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
namespace terraforest {
using namespace godot;
namespace fs=std::filesystem;
static bool slot_name(const String &s){
 if(s.is_empty()||s.length()>48)return false;
 for(int i=0;i<s.length();i++){char32_t c=s[i];bool letter=(c>='a'&&c<='z')||(c>='A'&&c<='Z')||c=='_';if(!letter&&(i==0||c<'0'||c>'9'))return false;}return true;
}
Dictionary NativeWorldArchive::clone_world(const String &root,const String &source,const String &destination) const {
 Dictionary result;result["ok"]=false;result["created"]=false;
 auto fail=[&](const char *reason){result["reason"]=reason;return result;};
 if(!root.is_absolute_path()||root.begins_with("user://")||root.begins_with("res://")||!slot_name(source)||!slot_name(destination)||source.nocasecmp_to(destination)==0)return fail("Invalid publication path or slot");
 String original=root.path_join(source+String(".trw")),target=root.path_join(destination+String(".trw"));
 // Acquire the same OS leases used by ordinary world saves. No live writer can
 // change either canonical root while immutable regional files are copied.
 Ref<NativeWorldArchive> source_lease,target_lease;source_lease.instantiate();target_lease.instantiate();
 if(!source_lease->acquire(original)||!target_lease->acquire(target))return fail("World is in use");
 std::error_code error;auto base=fs::weakly_canonical(fs::u8path(root.utf8().get_data()),error);
 if(error||!fs::is_directory(base,error))return fail("World directory unavailable");
 auto src=base/fs::u8path((source+String(".trw")).utf8().get_data()),dst=base/fs::u8path((destination+String(".trw")).utf8().get_data());
 if(fs::exists(dst,error))return fail("Destination already exists");
 if(error)return fail("Cannot inspect destination");
 for(const char *suffix:{".regions",".models",".water",".bak",".tmp"}){
  if(fs::exists(fs::u8path((target+String(suffix)).utf8().get_data()),error))return fail("Destination contains unpublished data");
  if(error)return fail("Cannot inspect destination stores");
 }
 PackedByteArray canonical=read(original);if(!bool(decode(canonical)["ok"]))return fail("Source archive is invalid");
 static std::atomic<uint64_t> sequence{0};
 String stage_name=".publish_"+destination+"_"+String::num_uint64(GetCurrentProcessId())+"_"+String::num_uint64(++sequence);
 auto stage=base/fs::u8path(stage_name.utf8().get_data());
 if(!fs::create_directory(stage,error)||error)return fail("Cannot create publication staging directory");
 result["staging"]=root.path_join(stage_name);
 uint64_t bytes=0,files=0;
 for(const char *suffix:{".regions",".models",".water"}){
  auto from=fs::u8path((original+suffix).utf8().get_data()),to=stage/fs::path(suffix+1);
  bool present=fs::exists(from,error);if(error)return fail("Cannot inspect source store");if(!present)continue;
  if(fs::is_symlink(from,error)||!fs::is_directory(from,error))return fail("Unsupported source store");
  fs::create_directory(to,error);if(error)return fail("Cannot create staged store");
  fs::recursive_directory_iterator it(from,fs::directory_options::none,error),end;
  while(!error&&it!=end){
   const auto entry=*it;auto status=entry.symlink_status(error);if(error||fs::is_symlink(status))return fail("Store contains unsupported links");
   auto relative=entry.path().lexically_relative(from),output=to/relative;
   if(fs::is_directory(status)){fs::create_directory(output,error);}
   else if(fs::is_regular_file(status)){
    auto size=entry.file_size(error);if(error||size>256ull*1024*1024||++files>1000000||bytes+size>512ull*1024*1024*1024)return fail("Publication storage budget exceeded");
    bytes+=size;fs::copy_file(entry.path(),output,fs::copy_options::none,error);
    if(error)return fail("Store copy failed; staging retained");
    // Root publication must not get ahead of the copied authoritative file data.
    HANDLE copied=CreateFileW(output.c_str(),GENERIC_WRITE,FILE_SHARE_READ,nullptr,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,nullptr);
    if(copied==INVALID_HANDLE_VALUE)return fail("Cannot flush staged file");
    BOOL flushed=FlushFileBuffers(copied);CloseHandle(copied);
    if(!flushed)return fail("Staged file flush failed");
   }else return fail("Store contains unsupported entries");
   if(error)return fail("Store copy failed; staging retained");it.increment(error);
  }
  if(error)return fail("Store enumeration failed; staging retained");
 }
 if(read(original)!=canonical)return fail("Source changed during publication");
 String stage_root=root.path_join(stage_name).path_join("world.trw");
 Ref<NativeWorldArchive> staged;staged.instantiate();
 if(!staged->acquire(stage_root)||staged->publish(stage_root,canonical)!=OK)return fail("Staged root publication failed");
 staged->release();
 for(const char *suffix:{".regions",".models",".water"}){
  auto folder=stage/fs::path(suffix+1);bool present=fs::exists(folder,error);if(error)return fail("Cannot inspect staged store");if(!present)continue;
  fs::rename(folder,fs::u8path((target+suffix).utf8().get_data()),error);if(error)return fail("Store promotion failed; canonical root not published");
 }
 // No replacement flags: existing destinations are never overwritten.
 auto from=fs::u8path(stage_root.utf8().get_data());
 if(!MoveFileExW(from.c_str(),dst.c_str(),MOVEFILE_WRITE_THROUGH))return fail("Canonical promotion failed; staged data retained");
 fs::remove(fs::u8path((stage_root+".lock").utf8().get_data()),error);fs::remove(stage,error);
 result["ok"]=true;result["created"]=true;result["files"]=int64_t(files);result["bytes"]=int64_t(bytes);result["slot"]=destination;return result;
}
}
