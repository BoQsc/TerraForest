// SPDX-License-Identifier: 0BSD
#include "world_archive.hpp"
#include <godot_cpp/classes/dir_access.hpp>
#include <godot_cpp/classes/file_access.hpp>
#include <filesystem>
#include <atomic>
#include <fstream>
#include <array>
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
Dictionary NativeWorldArchive::clone_world(const String &root,const String &source,const String &destination,int64_t test_stop_after) const {
 Dictionary result;result["ok"]=false;result["created"]=false;
 auto fail=[&](const char *reason){result["reason"]=reason;return result;};
 if(test_stop_after < -1 || test_stop_after > 4)return fail("Invalid publication stop phase");
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
 for(const char *suffix:{".regions",".models",".water",".terrain",".bak",".tmp"}){
  if(fs::exists(fs::u8path((target+String(suffix)).utf8().get_data()),error))return fail("Destination contains unpublished data");
  if(error)return fail("Cannot inspect destination stores");
 }
 PackedByteArray canonical=read(original);if(!bool(decode(canonical)["ok"]))return fail("Source archive is invalid");
 static std::atomic<uint64_t> sequence{0};
 String stage_name=".publish_"+destination+"_"+String::num_uint64(GetCurrentProcessId())+"_"+String::num_uint64(++sequence);
 auto stage=base/fs::u8path(stage_name.utf8().get_data());
 if(!fs::create_directory(stage,error)||error)return fail("Cannot create publication staging directory");
 result["staging"]=root.path_join(stage_name);
 String journal=String("TFPUB1\n")+source+"\n"+destination+"\n";
 auto encoded=journal.utf8();auto journal_path=stage/"publication.txt";
 HANDLE handle=CreateFileW(journal_path.c_str(),GENERIC_WRITE,0,nullptr,CREATE_NEW,FILE_ATTRIBUTE_NORMAL,nullptr);
 if(handle==INVALID_HANDLE_VALUE)return fail("Cannot create publication journal");
 DWORD written=0;BOOL journal_ok=WriteFile(handle,encoded.get_data(),encoded.length(),&written,nullptr)&&written==encoded.length()&&FlushFileBuffers(handle);CloseHandle(handle);
 if(!journal_ok)return fail("Cannot flush publication journal");
 uint64_t bytes=0,files=0;
 for(const char *suffix:{".regions",".models",".water",".terrain"}){
  auto from=fs::u8path((original+suffix).utf8().get_data()),to=stage/fs::path(suffix+1);
  bool present=fs::exists(from,error);if(error)return fail("Cannot inspect source store");if(!present)continue;
  if((GetFileAttributesW(from.c_str())&FILE_ATTRIBUTE_REPARSE_POINT)||fs::is_symlink(from,error)||!fs::is_directory(from,error))return fail("Unsupported source store");
  fs::create_directory(to,error);if(error)return fail("Cannot create staged store");
  fs::recursive_directory_iterator it(from,fs::directory_options::none,error),end;
  while(!error&&it!=end){
   const auto entry=*it;auto status=entry.symlink_status(error);if(error||(GetFileAttributesW(entry.path().c_str())&FILE_ATTRIBUTE_REPARSE_POINT)||fs::is_symlink(status))return fail("Store contains unsupported links");
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
 if(test_stop_after==0)return fail("Injected stop before store promotion");
 int promoted=0;
 for(const char *suffix:{".regions",".models",".water",".terrain"}){
  auto folder=stage/fs::path(suffix+1);bool present=fs::exists(folder,error);if(error)return fail("Cannot inspect staged store");if(!present)continue;
  fs::rename(folder,fs::u8path((target+suffix).utf8().get_data()),error);if(error)return fail("Store promotion failed; canonical root not published");
  if(++promoted==test_stop_after)return fail("Injected stop after store promotion");
 }
 // No replacement flags: existing destinations are never overwritten.
 auto from=fs::u8path(stage_root.utf8().get_data());
 if(!MoveFileExW(from.c_str(),dst.c_str(),MOVEFILE_WRITE_THROUGH))return fail("Canonical promotion failed; staged data retained");
 fs::remove(fs::u8path((stage_root+".lock").utf8().get_data()),error);fs::remove(stage/"publication.txt",error);fs::remove(stage,error);
 result["ok"]=true;result["created"]=true;result["files"]=int64_t(files);result["bytes"]=int64_t(bytes);result["slot"]=destination;return result;
}

static bool ordinary_path(const fs::path &path){
 DWORD attributes=GetFileAttributesW(path.c_str());return attributes!=INVALID_FILE_ATTRIBUTES&&!(attributes&FILE_ATTRIBUTE_REPARSE_POINT);
}
static bool same_file(const fs::path &a,const fs::path &b,std::error_code &error){
 if(!ordinary_path(a)||!ordinary_path(b))return false;
 auto left_size=fs::file_size(a,error);if(error)return false;
 auto right_size=fs::file_size(b,error);if(error||left_size!=right_size)return false;
 std::ifstream left(a,std::ios::binary),right(b,std::ios::binary);if(!left||!right)return false;
 std::array<char,65536> x,y;
 do{
  left.read(x.data(),x.size());right.read(y.data(),y.size());
  if(left.gcount()!=right.gcount()||!std::equal(x.begin(),x.begin()+left.gcount(),y.begin()))return false;
 }while(left.gcount()>0);
 return left.eof()&&right.eof();
}
static bool same_store(const fs::path &source,const fs::path &copy,std::error_code &error){
 if(!ordinary_path(source)||!ordinary_path(copy)||!fs::is_directory(copy,error)||error)return false;
 uint64_t entries=0,bytes=0,copied_entries=0;
 fs::recursive_directory_iterator it(source,fs::directory_options::none,error),end;
 while(!error&&it!=end){
  auto from=it->path(),to=copy/from.lexically_relative(source);
  if(++entries>1000000||!ordinary_path(from)||!ordinary_path(to))return false;
  if(it->is_directory(error)){if(!fs::is_directory(to,error))return false;}
  else if(it->is_regular_file(error)){
   auto size=it->file_size(error);if(error||size>256ull*1024*1024||(bytes+=size)>512ull*1024*1024*1024||!same_file(from,to,error))return false;
  }else return false;
  if(error)return false;it.increment(error);
 }
 if(error)return false;
 for(fs::recursive_directory_iterator c(copy,fs::directory_options::none,error);!error&&c!=end;c.increment(error)){
  if(!ordinary_path(c->path())||++copied_entries>entries)return false;
 }
 return !error&&copied_entries==entries;
}
Dictionary NativeWorldArchive::recover_world(const String &root,const String &destination)const{
 Dictionary result;result["ok"]=false;result["found"]=false;
 auto fail=[&](const char *reason){result["reason"]=reason;return result;};
 if(!root.is_absolute_path()||root.begins_with("user://")||root.begins_with("res://")||!slot_name(destination))return fail("Invalid recovery path");
 std::error_code error;auto base=fs::weakly_canonical(fs::u8path(root.utf8().get_data()),error);
 if(error||!fs::is_directory(base,error))return fail("World directory unavailable");
 fs::path stage;String source;int count=0;
 const String prefix=".publish_"+destination+"_";
 for(fs::directory_iterator it(base,error),end;!error&&it!=end;it.increment(error)){
  if(++count>10000)return fail("Recovery directory budget exceeded");
  String name=String::utf8(it->path().filename().u8string().c_str());
  if(!name.begins_with(prefix))continue;
  auto journal=it->path()/"publication.txt",canonical=it->path()/"world.trw";
  if(!ordinary_path(it->path())||!ordinary_path(journal)||!fs::is_regular_file(journal,error))return fail("Unsupported publication journal");
  // No staged root means copying never completed. It cannot be promoted.
  if(!fs::exists(canonical,error)){if(error)return fail("Cannot inspect staged root");continue;}
  result["found"]=true;
  if(!stage.empty())return fail("Multiple recoverable publications require inspection");
  if(fs::file_size(journal,error)>256||error)return fail("Invalid publication journal size");
  String journal_name=root.path_join(name).path_join("publication.txt");
  auto fields=FileAccess::get_file_as_string(journal_name).split("\n");
  if(fields.size()!=4||fields[0]!="TFPUB1"||fields[2]!=destination||fields[3]!=""||!slot_name(fields[1])||fields[1].nocasecmp_to(destination)==0)return fail("Invalid publication journal");
  stage=it->path();source=fields[1];
 }
 if(error)return fail("Cannot enumerate publication journals");
 if(stage.empty()){result["ok"]=true;return result;}
 String original=root.path_join(source+String(".trw")),target=root.path_join(destination+String(".trw"));
 auto dst=fs::u8path(target.utf8().get_data());
 Ref<NativeWorldArchive> source_lease,target_lease;source_lease.instantiate();target_lease.instantiate();
 if(!source_lease->acquire(original)||!target_lease->acquire(target))return fail("World is in use");
 if(fs::exists(dst,error)||error)return fail("Recovery never replaces an existing world");
 String staged_root=String::utf8((stage/"world.trw").u8string().c_str());
 if(fs::file_size(stage/"world.trw",error)>256ull*1024*1024||error)return fail("Staged root exceeds recovery budget");
 if(!ordinary_path(stage/"world.trw"))return fail("Unsupported staged root");
 auto canonical=FileAccess::get_file_as_bytes(staged_root);
 if(!bool(decode(canonical)["ok"])||canonical!=read(original))return fail("Source or staged world changed after interruption");
 // Validate every authoritative file, including already-promoted stores, before
 // performing any more renames. Source leases prevent cooperating writers.
 for(const char *suffix:{".regions",".models",".water",".terrain"}){
  auto source_store=fs::u8path((original+suffix).utf8().get_data()),pending=stage/fs::path(suffix+1),published=fs::u8path((target+suffix).utf8().get_data());
  bool a=fs::exists(source_store,error);if(error)return fail("Cannot inspect source store");
  bool b=fs::exists(pending,error);if(error)return fail("Cannot inspect staged store");
  bool c=fs::exists(published,error);if(error)return fail("Cannot inspect published store");
  if(error||b&&c||!a&&(b||c)||a&&!b&&!c)return fail("Recovery store ownership mismatch");
  if(a&&!same_store(source_store,b?pending:published,error))return fail("Recovery store verification failed; no changes made");
 }
 for(const char *suffix:{".regions",".models",".water",".terrain"}){
  auto pending=stage/fs::path(suffix+1);bool exists=fs::exists(pending,error);if(error)return fail("Cannot inspect recovery store");
  if(exists){fs::rename(pending,fs::u8path((target+suffix).utf8().get_data()),error);if(error)return fail("Recovery promotion failed; journal retained");}
 }
 if(!MoveFileExW((stage/"world.trw").c_str(),dst.c_str(),MOVEFILE_WRITE_THROUGH))return fail("Recovery root promotion failed; journal retained");
 fs::remove(stage/"world.trw.lock",error);fs::remove(stage/"publication.txt",error);fs::remove(stage,error);
 result["ok"]=true;result["recovered"]=true;result["source"]=source;result["slot"]=destination;return result;
}
}
