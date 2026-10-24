// SPDX-License-Identifier: 0BSD
#include "terrain_region_store.hpp"
#include "terrain_capture.hpp"
#include "terrain_checksum.hpp"
#include "generation_parallel.hpp"
#include <godot_cpp/classes/dir_access.hpp>
#include <godot_cpp/classes/hashing_context.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <atomic>
#include <cstring>
#include <set>
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>

namespace terraforest {
using namespace godot;
using Buffer=PackedByteArray;
static constexpr int64_t REGION_LIMIT=16+64*(12+PAGE_SAMPLES*3);
static constexpr int64_t INDEX_LIMIT=20*1024*1024,PACK_LIMIT=16*1024*1024;
static constexpr uint32_t PAGE_COUNT=WORLD_PAGE_COLUMNS*WORLD_PAGE_COLUMNS*17;
static bool magic(const Buffer &b,const char *value){return b.size()>=8&&!std::memcmp(b.ptr(),value,4)&&b.decode_u32(4)==1;}
static uint32_t fnv(const uint8_t *p,int n){uint32_t h=2166136261u;while(n--){h^=*p++;h*=16777619u;}return h;}
Buffer NativeTerrainRegionStore::hash(const Buffer &b){
 Ref<HashingContext> h;h.instantiate();
 if(h->start(HashingContext::HASH_SHA256)!=OK||h->update(b)!=OK)return {};
 return h->finish();
}
bool NativeTerrainRegionStore::ordinary(const String &path,bool directory){
 auto name=path.utf16();DWORD a=GetFileAttributesW((LPCWSTR)name.get_data());
 return a!=INVALID_FILE_ATTRIBUTES&&!(a&FILE_ATTRIBUTE_REPARSE_POINT)&&bool(a&FILE_ATTRIBUTE_DIRECTORY)==directory;
}
bool NativeTerrainRegionStore::read_file(const String &path,int64_t limit,Buffer &b){
 if(!ordinary(path,false))return false;auto name=path.utf16();
 HANDLE f=CreateFileW((LPCWSTR)name.get_data(),GENERIC_READ,FILE_SHARE_READ,nullptr,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL|FILE_FLAG_OPEN_REPARSE_POINT,nullptr);
 if(f==INVALID_HANDLE_VALUE)return false;BY_HANDLE_FILE_INFORMATION info{};LARGE_INTEGER size{};
 bool ok=GetFileInformationByHandle(f,&info)&&!(info.dwFileAttributes&(FILE_ATTRIBUTE_REPARSE_POINT|FILE_ATTRIBUTE_DIRECTORY))&&GetFileSizeEx(f,&size)&&size.QuadPart>0&&size.QuadPart<=limit;
 if(ok)ok=b.resize(size.QuadPart)==OK;DWORD got=0;
 if(ok)ok=ReadFile(f,b.ptrw(),DWORD(size.QuadPart),&got,nullptr)&&got==size.QuadPart;
 CloseHandle(f);return ok;
}
bool NativeTerrainRegionStore::read_blob(const Buffer &id,const char *suffix,int64_t limit,Buffer &b) const {
 return id.size()==32&&read_file(directory_.path_join(id.hex_encode()+suffix),limit,b)&&hash(b)==id;
}
bool NativeTerrainRegionStore::publish_blob(const Buffer &b,const char *suffix,Buffer &id){
 if(!writable_||!ordinary(directory_,true)||b.is_empty())return false;
 id=hash(b);if(id.size()!=32)return false;
 String target=directory_.path_join(id.hex_encode()+suffix);auto to=target.utf16();
 if(GetFileAttributesW((LPCWSTR)to.get_data())!=INVALID_FILE_ATTRIBUTES){
  Buffer old;if(!read_blob(id,suffix,b.size(),old)||old!=b)return false;++reused_;return true;
 }
 static std::atomic<uint64_t> sequence{0};
 String temporary=target+".pending."+String::num_uint64(GetCurrentProcessId())+"."+String::num_uint64(++sequence);auto from=temporary.utf16();
 HANDLE f=CreateFileW((LPCWSTR)from.get_data(),GENERIC_WRITE,0,nullptr,CREATE_NEW,FILE_ATTRIBUTE_NORMAL|FILE_FLAG_WRITE_THROUGH,nullptr);
 if(f==INVALID_HANDLE_VALUE)return false;DWORD count=0;
 bool ok=WriteFile(f,b.ptr(),DWORD(b.size()),&count,nullptr)&&count==b.size()&&FlushFileBuffers(f);CloseHandle(f);
 Buffer verified;ok=ok&&read_file(temporary,b.size(),verified)&&verified==b;
 if(ok)ok=MoveFileExW((LPCWSTR)from.get_data(),(LPCWSTR)to.get_data(),MOVEFILE_WRITE_THROUGH);
 if(!ok)DeleteFileW((LPCWSTR)from.get_data());else{++written_;written_bytes_+=b.size();}
 return ok;
}
bool NativeTerrainRegionStore::read_packet(const Region &entry,Buffer &b) const {
 if(entry.pack.size()!=32||entry.digest.size()!=32||entry.offset<8||entry.length<16||entry.length>REGION_LIMIT)return false;
 String path=directory_.path_join(entry.pack.hex_encode()+".tpack");if(!ordinary(path,false))return false;auto name=path.utf16();
 HANDLE f=CreateFileW((LPCWSTR)name.get_data(),GENERIC_READ,FILE_SHARE_READ,nullptr,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL|FILE_FLAG_OPEN_REPARSE_POINT,nullptr);
 if(f==INVALID_HANDLE_VALUE)return false;BY_HANDLE_FILE_INFORMATION info{};LARGE_INTEGER size{},offset{};uint8_t header[8]{};DWORD got=0;
 bool ok=GetFileInformationByHandle(f,&info)&&!(info.dwFileAttributes&(FILE_ATTRIBUTE_REPARSE_POINT|FILE_ATTRIBUTE_DIRECTORY))&&GetFileSizeEx(f,&size)&&size.QuadPart<=PACK_LIMIT&&int64_t(entry.offset)+entry.length<=size.QuadPart;
 if(ok)ok=ReadFile(f,header,8,&got,nullptr)&&got==8&&!std::memcmp(header,"TFTP\1\0\0\0",8);
 offset.QuadPart=entry.offset;if(ok)ok=SetFilePointerEx(f,offset,nullptr,FILE_BEGIN)&&b.resize(entry.length)==OK;
 if(ok)ok=ReadFile(f,b.ptrw(),entry.length,&got,nullptr)&&got==entry.length;
 CloseHandle(f);return ok&&hash(b)==entry.digest;
}
bool NativeTerrainRegionStore::valid_page(uint32_t p){return p>=1&&p<=PAGE_COUNT;}
uint32_t NativeTerrainRegionStore::region_for(uint32_t page){
 uint32_t v=page-1,x=v%WORLD_PAGE_COLUMNS;v/=WORLD_PAGE_COLUMNS;uint32_t z=v%WORLD_PAGE_COLUMNS,y=v/WORLD_PAGE_COLUMNS;
 return 1+(x/4)+32*((z/4)+32*(y/4));
}
bool NativeTerrainRegionStore::valid_blocks(const Buffer &blocks){
 if(blocks.size()%8||blocks.size()>2000000*8)return false;std::set<uint32_t> seen;
 for(int64_t i=0;i<blocks.size();i+=8){uint32_t k=blocks.decode_u32(i),v=blocks.decode_u32(i+4),raw=k-1;
  if(!k||(raw&2047)>=WORLD||((raw>>11)&2047)>=WORLD||(raw>>22)<1||(raw>>22)>=255||v<1||v>3||!seen.insert(k).second)return false;
 }
 return true;
}
bool NativeTerrainRegionStore::parse_index(const Buffer &b,Index &out){
 if(!magic(b,"TFTC")||b.size()<40||b.size()>INDEX_LIMIT||b.decode_u32(36))return false;
 uint32_t pc=b.decode_u32(24),bc=b.decode_u32(28),rc=b.decode_u32(32);
 if(pc>PAGE_COUNT||bc>2000000||rc>5120||b.size()!=40+int64_t(pc)*4+int64_t(bc)*8+int64_t(rc)*80)return false;
 out=Index{};out.seed=b.decode_u32(8);out.generator=b.decode_u32(12);out.revision=b.decode_u32(16);out.edits=b.decode_u32(20);
 if(out.generator<1||out.generator>MAX_GENERATOR_ID)return false;
 int64_t at=40;std::set<uint32_t> seen;std::map<uint32_t,uint32_t> counts;
 for(uint32_t i=0;i<pc;i++,at+=4){uint32_t k=b.decode_u32(at);if(!valid_page(k)||!seen.insert(k).second)return false;out.order.push_back(k);++counts[region_for(k)];}
 out.blocks=b.slice(at,at+int64_t(bc)*8);at+=int64_t(bc)*8;if(!valid_blocks(out.blocks)||counts.size()!=rc)return false;
 uint32_t previous=0;
 for(uint32_t i=0;i<rc;i++,at+=80){uint32_t k=b.decode_u32(at),count=b.decode_u32(at+4);
  if(k<=previous||!counts.count(k)||counts[k]!=count||count<1||count>64)return false;previous=k;
  Buffer digest=b.slice(at+8,at+40);bool nonzero=false;for(int j=0;j<32;j++)nonzero|=digest[j]!=0;if(!nonzero)return false;
  uint32_t offset=b.decode_u32(at+72),length=b.decode_u32(at+76);
  if(offset<8||length<16||length>REGION_LIMIT||int64_t(offset)+length>PACK_LIMIT)return false;
  out.regions.emplace(k,Region{count,offset,length,digest,b.slice(at+40,at+72)});
 }
 return true;
}
bool NativeTerrainRegionStore::load_index(const Buffer &reference,Index &out){
 if(directory_.is_empty()||!magic(reference,"TFTR")||reference.size()!=40)return false;
 Buffer id=reference.slice(8,40);
 if(id==cached_id_){out=cached_index_;return true;}
 Buffer b;if(!read_blob(id,".tindex",INDEX_LIMIT,b)||!parse_index(b,out))return false;
 cached_id_=id;cached_index_=out;return true;
}
// Runs encode a complete (density, material) sample. Raw fallback prevents
// adversarial/high-entropy pages from growing beyond their original payload.
static Buffer encode_page(const uint8_t *density,const uint8_t *materials,uint32_t key){
 Buffer runs;if(runs.resize(PAGE_SAMPLES*5)!=OK)return {};auto *run_bytes=runs.ptrw();int used=0;
 for(int i=0;i<PAGE_SAMPLES;){int end=i+1;while(end<PAGE_SAMPLES&&density[end*2]==density[i*2]&&density[end*2+1]==density[i*2+1]&&materials[end]==materials[i])++end;
  uint32_t count=end-i;run_bytes[used]=uint8_t(count);run_bytes[used+1]=uint8_t(count>>8);run_bytes[used+2]=density[i*2];run_bytes[used+3]=density[i*2+1];run_bytes[used+4]=materials[i];used+=5;i=end;
 }
 Buffer raw;if(raw.resize(PAGE_SAMPLES*3)!=OK)return {};std::memcpy(raw.ptrw(),density,PAGE_SAMPLES*2);std::memcpy(raw.ptrw()+PAGE_SAMPLES*2,materials,PAGE_SAMPLES);
 Buffer fast=raw.compress(0); // Godot's bounded FastLZ codec, already an engine dependency.
 uint32_t encoding=used<PAGE_SAMPLES*3?1:0;
 Buffer payload=encoding?runs.slice(0,used):raw;
 if(!fast.is_empty()&&fast.size()<payload.size()){encoding=2;payload=fast;}
 Buffer out;if(out.resize(12+payload.size())!=OK)return {};out.encode_u32(0,key);out.encode_u32(4,encoding);out.encode_u32(8,payload.size());
 std::memcpy(out.ptrw()+12,payload.ptr(),payload.size());return out;
}
bool NativeTerrainRegionStore::load_region(uint32_t key,const Region &entry,std::map<uint32_t,Buffer> &pages,bool account){
 Buffer b;if(!read_packet(entry,b)||!magic(b,"TFPG")||b.size()<16||b.decode_u32(8)!=key||b.decode_u32(12)!=entry.pages)return false;
 int64_t at=16;std::map<uint32_t,Buffer> staged;
 for(uint32_t i=0;i<entry.pages;i++){
  if(at+12>b.size())return false;uint32_t k=b.decode_u32(at),encoding=b.decode_u32(at+4),length=b.decode_u32(at+8);at+=12;
  if(!valid_page(k)||region_for(k)!=key||staged.count(k)||length>PAGE_SAMPLES*3||at+length>b.size()||encoding>2)return false;
  Buffer raw;if(raw.resize(PAGE_SAMPLES*3)!=OK)return false;auto *p=raw.ptrw();
  if(!encoding){if(length!=PAGE_SAMPLES*3)return false;std::memcpy(p,b.ptr()+at,length);}
  else if(encoding==2){
   if(!length)return false;Buffer decoded=b.slice(at,at+length).decompress(PAGE_SAMPLES*3,0);
   if(decoded.size()!=PAGE_SAMPLES*3)return false;raw=decoded;
  }else{
   if(!length||length%5)return false;int sample=0;
   for(uint32_t j=0;j<length;j+=5){uint32_t count=b.decode_u16(at+j);if(!count||sample+count>PAGE_SAMPLES)return false;
    for(uint32_t n=0;n<count;n++,sample++){p[sample*2]=b[at+j+2];p[sample*2+1]=b[at+j+3];p[PAGE_SAMPLES*2+sample]=b[at+j+4];}
   }
   if(sample!=PAGE_SAMPLES)return false;
  }
  staged.emplace(k,raw);at+=length;
 }
 if(at!=b.size())return false;if(account)++read_regions_;pages=std::move(staged);return true;
}
void NativeTerrainRegionStore::_bind_methods(){
 ClassDB::bind_method(D_METHOD("configure_worker_limit","workers"),&NativeTerrainRegionStore::configure_worker_limit);
 ClassDB::bind_method(D_METHOD("open_store","absolute_directory","writable"),&NativeTerrainRegionStore::open_store,DEFVAL(false));
 ClassDB::bind_method(D_METHOD("close"),&NativeTerrainRegionStore::close);
 ClassDB::bind_method(D_METHOD("publish_capture","capture","inherited","test_stop_after"),&NativeTerrainRegionStore::publish_capture,DEFVAL(Buffer()),DEFVAL(-1));
 ClassDB::bind_method(D_METHOD("verify_snapshot","reference"),&NativeTerrainRegionStore::verify_snapshot);
 ClassDB::bind_method(D_METHOD("publish_snapshot","snapshot","inherited","test_stop_after"),&NativeTerrainRegionStore::publish_snapshot,DEFVAL(Buffer()),DEFVAL(-1));
 ClassDB::bind_method(D_METHOD("expand_snapshot","reference"),&NativeTerrainRegionStore::expand_snapshot);
 ClassDB::bind_method(D_METHOD("describe_snapshot","reference"),&NativeTerrainRegionStore::describe_snapshot);
 ClassDB::bind_method(D_METHOD("read_region","reference","coordinate"),&NativeTerrainRegionStore::read_region);
 ClassDB::bind_method(D_METHOD("stats"),&NativeTerrainRegionStore::stats);
}
NativeTerrainRegionStore::~NativeTerrainRegionStore(){close();}
void NativeTerrainRegionStore::close_locked(){
 if(lease_)CloseHandle(static_cast<HANDLE>(lease_));lease_=nullptr;directory_=String();writable_=false;cached_id_=Buffer();cached_index_=Index{};page_cache_.clear();page_cache_id_=Buffer();page_cache_region_=0;
}
void NativeTerrainRegionStore::close(){std::lock_guard<std::mutex> lock(mutex_);close_locked();}
bool NativeTerrainRegionStore::configure_worker_limit(int64_t workers){
 std::lock_guard<std::mutex> lock(mutex_);if(!directory_.is_empty()||workers<1||workers>4)return false;worker_limit_=int(workers);return true;
}
bool NativeTerrainRegionStore::open_store(const String &path,bool writable){
 std::lock_guard<std::mutex> lock(mutex_);
 if(!directory_.is_empty()||!path.is_absolute_path()||path.begins_with("res://")||path.begins_with("user://"))return false;
 if(writable&&!DirAccess::dir_exists_absolute(path)&&DirAccess::make_dir_recursive_absolute(path)!=OK)return false;
 if(!ordinary(path,true))return false;
 if(writable){auto name=path.path_join(".lock").utf16();
  HANDLE f=CreateFileW((LPCWSTR)name.get_data(),GENERIC_READ|GENERIC_WRITE,0,nullptr,OPEN_ALWAYS,FILE_ATTRIBUTE_NORMAL|FILE_FLAG_OPEN_REPARSE_POINT,nullptr);
  if(f==INVALID_HANDLE_VALUE)return false;BY_HANDLE_FILE_INFORMATION info{};
  if(!GetFileInformationByHandle(f,&info)||(info.dwFileAttributes&FILE_ATTRIBUTE_REPARSE_POINT)){CloseHandle(f);return false;}lease_=f;
 }
 directory_=path;writable_=writable;written_=reused_=reused_regions_=written_bytes_=read_regions_=0;return true;
}
Buffer NativeTerrainRegionStore::publish_snapshot(const Buffer &b,const Buffer &inherited,int64_t stop){
 std::lock_guard<std::mutex> lock(mutex_);
 Index previous;if(!inherited.is_empty()&&!load_index(inherited,previous))return {};
 if(!writable_||b.size()<32||b.size()>256*1024*1024||b.decode_u32(0)!=SAVE_MAGIC||stop< -1||stop>5120)return {};
 uint32_t format=b.decode_u32(4),pc=b.decode_u32(12),bc=b.decode_u32(16);int header=format==1?28:32;
 if(format<1||format>3||pc>PAGE_COUNT||bc>2000000||b.size()!=header+4+int64_t(pc)*(4+PAGE_SAMPLES*3)+int64_t(bc)*8)return {};
 if(b.decode_u32(b.size()-4)!=(format==3?terrain_checksum::checksum(b.ptr(),int(b.size()-4)):fnv(b.ptr(),int(b.size()-4))))return {};
 uint32_t generator=format==1?1:b.decode_u32(28);if(generator<1||generator>MAX_GENERATOR_ID)return {};
 int64_t at=header;std::vector<uint32_t> order;std::set<uint32_t> seen;
 std::map<uint32_t,std::vector<std::pair<uint32_t,int64_t>>> sources;
 for(uint32_t i=0;i<pc;i++,at+=4+PAGE_SAMPLES*3){uint32_t key=b.decode_u32(at);if(!valid_page(key)||!seen.insert(key).second)return {};order.push_back(key);sources[region_for(key)].emplace_back(key,at+4);}
 Buffer blocks=b.slice(at,b.size()-4);if(!valid_blocks(blocks))return {};
 struct Job{uint32_t key;const std::vector<std::pair<uint32_t,int64_t>> *source;Buffer group;};std::vector<Job> jobs;
 for(const auto &[key,source]:sources)jobs.push_back({key,&source,{}});
 std::atomic<bool> failed{false};const uint8_t *samples=b.ptr();
 last_workers_=generation_parallel_for(int(jobs.size()),[&](int n){
  if(failed.load(std::memory_order_relaxed))return;auto &job=jobs[n];Buffer group;
  if(group.resize(16)!=OK){failed=true;return;}std::memcpy(group.ptrw(),"TFPG",4);group.encode_u32(4,1);group.encode_u32(8,job.key);group.encode_u32(12,job.source->size());
  for(const auto &[key,offset]:*job.source){
   Buffer encoded=encode_page(samples+offset,samples+offset+PAGE_SAMPLES*2,key);if(encoded.is_empty()){failed=true;return;}
   int64_t expected=group.size()+encoded.size();group.append_array(encoded);if(group.size()!=expected){failed=true;return;}
  }
  job.group=group;
 },16,pc>=256?worker_limit_:1);
 if(failed)return {};
 Index metadata;metadata.seed=b.decode_u32(8);metadata.generator=generator;metadata.revision=b.decode_u32(20);metadata.edits=b.decode_u32(24);metadata.order=std::move(order);metadata.blocks=blocks;
 std::vector<Product> products;for(auto &job:jobs)products.push_back({job.key,uint32_t(job.source->size()),job.group});
 return publish_products(std::move(metadata),products,previous,false,stop);
}
Buffer NativeTerrainRegionStore::publish_products(Index metadata,std::vector<Product> &products,const Index &previous,bool preserve,int64_t stop){
 if(stop==0)return {};int promoted=0;Buffer pack;std::map<uint32_t,Region> entries=preserve?previous.regions:std::map<uint32_t,Region>{};std::vector<uint32_t> pending;
 std::set<uint32_t> touched;for(const auto &product:products)touched.insert(product.key);
 // Retained products are still verified. Incremental capture avoids copying and
 // recompressing their density pages; it does not silently skip integrity checks.
 if(preserve)for(const auto &[key,entry]:previous.regions)if(!touched.count(key)){
  Buffer packet;if(!read_packet(entry,packet)||!magic(packet,"TFPG")||packet.decode_u32(8)!=key||packet.decode_u32(12)!=entry.pages)return {};++reused_regions_;
 }
 auto flush=[&](){
  if(pending.empty())return true;Buffer id;if(!publish_blob(pack,".tpack",id))return false;
  for(uint32_t key:pending)entries[key].pack=id;
  pending.clear();pack=Buffer();return true;
 };
 for(auto &product:products){
  uint32_t key=product.key,count=product.pages;Buffer &group=product.packet;Buffer digest=hash(group);if(digest.size()!=32)return {};
  auto old=previous.regions.find(key);
  if(old!=previous.regions.end()&&old->second.pages==count&&old->second.digest==digest){
   Buffer verified;if(!read_packet(old->second,verified)||verified!=group)return {};entries[key]=old->second;++reused_regions_;
  }else{
   if(pack.size()+group.size()>PACK_LIMIT&&!flush())return {};
   if(pack.is_empty()){if(pack.resize(8)!=OK)return {};std::memcpy(pack.ptrw(),"TFTP",4);pack.encode_u32(4,1);}
   Region entry;entry.pages=count;entry.digest=digest;entry.offset=pack.size();entry.length=group.size();
   int64_t expected=pack.size()+group.size();pack.append_array(group);if(pack.size()!=expected)return {};entries[key]=entry;pending.push_back(key);
  }
  if(++promoted==stop){flush();return {};}
 }
 if(!flush())return {};
 Buffer index;if(index.resize(40+int64_t(metadata.order.size())*4+metadata.blocks.size()+int64_t(entries.size())*80)!=OK||index.size()>INDEX_LIMIT)return {};index.fill(0);
 std::memcpy(index.ptrw(),"TFTC",4);index.encode_u32(4,1);index.encode_u32(8,metadata.seed);index.encode_u32(12,metadata.generator);index.encode_u32(16,metadata.revision);index.encode_u32(20,metadata.edits);index.encode_u32(24,metadata.order.size());index.encode_u32(28,metadata.blocks.size()/8);index.encode_u32(32,entries.size());
 int64_t at=40;for(uint32_t key:metadata.order){index.encode_u32(at,key);at+=4;}
 if(metadata.blocks.size())std::memcpy(index.ptrw()+at,metadata.blocks.ptr(),metadata.blocks.size());at+=metadata.blocks.size();
 for(const auto &[key,entry]:entries){
  index.encode_u32(at,key);index.encode_u32(at+4,entry.pages);std::memcpy(index.ptrw()+at+8,entry.digest.ptr(),32);std::memcpy(index.ptrw()+at+40,entry.pack.ptr(),32);index.encode_u32(at+72,entry.offset);index.encode_u32(at+76,entry.length);at+=80;
 }
 Buffer id;if(!publish_blob(index,".tindex",id))return {};
 Buffer reference;if(reference.resize(40)!=OK)return {};std::memcpy(reference.ptrw(),"TFTR",4);reference.encode_u32(4,1);std::memcpy(reference.ptrw()+8,id.ptr(),32);return reference;
}
Buffer NativeTerrainRegionStore::publish_capture(const Ref<NativeTerrainCapture> &capture,const Buffer &inherited,int64_t stop){
 std::lock_guard<std::mutex> lock(mutex_);
 if(!writable_||capture.is_null()||!capture->sealed_||stop< -1||stop>5120)return {};
 const bool incremental=!capture->source_.is_empty();
 if(incremental&&capture->expected_!=inherited)return {};
 Index previous;if(incremental){if(!load_index(capture->source_,previous))return {};}
 else if(!inherited.is_empty()&&!load_index(inherited,previous))return {};
 int64_t count=capture->keys_.size(),dirty=capture->changed_.size();
 if(count>MAX_AUTHORED_PAGES||capture->versions_.size()!=count||capture->samples_.size()!=dirty*PAGE_SAMPLES*3||(!incremental&&dirty!=count)||capture->blocks_.size()%8||capture->blocks_.size()>2000000*8||capture->generator_<1||capture->generator_>MAX_GENERATOR_ID)return {};
 if(incremental&&(previous.seed!=capture->seed_||previous.generator!=capture->generator_||previous.order.size()>size_t(count)))return {};
 Index metadata;metadata.seed=capture->seed_;metadata.generator=capture->generator_;metadata.revision=capture->revision_;metadata.edits=capture->edits_;metadata.blocks=capture->blocks_;
 std::set<uint32_t> seen;std::map<uint32_t,std::vector<uint32_t>> members;
 for(int64_t i=0;i<count;i++){
  uint32_t key=capture->keys_[i];if(!valid_page(key)||!seen.insert(key).second||(incremental&&i<int64_t(previous.order.size())&&previous.order[i]!=key))return {};
  metadata.order.push_back(key);members[region_for(key)].push_back(key);
 }
 std::map<uint32_t,std::vector<std::pair<uint32_t,int64_t>>> changes;int64_t last=-1;
 for(int64_t i=0;i<dirty;i++){
  int64_t index=capture->changed_[i];if(index<=last||index<0||index>=count)return {};last=index;
  uint32_t key=capture->keys_[index];changes[region_for(key)].emplace_back(key,i*PAGE_SAMPLES*3);
 }
 // Every appended page needs captured data; old pages come from the bound source.
 int64_t at=0;for(int64_t i=incremental?previous.order.size():0;i<count;i++){
  while(at<dirty&&capture->changed_[at]<i)++at;if(at==dirty||capture->changed_[at]!=i)return {};
 }
 struct Job{uint32_t key=0;const std::vector<std::pair<uint32_t,int64_t>> *changes=nullptr;Product output;bool read=false;};std::vector<Job> jobs;
 for(const auto &[key,rows]:changes)jobs.push_back({key,&rows,{key,uint32_t(members.at(key).size()),{}},false});
 std::atomic<bool> failed{false};const uint8_t *samples=capture->samples_.ptr();
 last_workers_=generation_parallel_for(int(jobs.size()),[&](int n){
  if(failed.load())return;auto &job=jobs[n];std::map<uint32_t,Buffer> pages;
  auto old=previous.regions.find(job.key);
  if(incremental&&old!=previous.regions.end()){
   if(!load_region(job.key,old->second,pages,false)){failed=true;return;}job.read=true;
  }
  for(const auto &[key,offset]:*job.changes){Buffer raw;if(raw.resize(PAGE_SAMPLES*3)!=OK){failed=true;return;}std::memcpy(raw.ptrw(),samples+offset,PAGE_SAMPLES*3);pages[key]=raw;}
  Buffer group;if(group.resize(16)!=OK){failed=true;return;}std::memcpy(group.ptrw(),"TFPG",4);group.encode_u32(4,1);group.encode_u32(8,job.key);group.encode_u32(12,job.output.pages);
  if(pages.size()!=job.output.pages){failed=true;return;}
  for(uint32_t key:members.at(job.key)){
   auto found=pages.find(key);if(found==pages.end()){failed=true;return;}const uint8_t *raw=found->second.ptr();
   Buffer encoded=encode_page(raw,raw+PAGE_SAMPLES*2,key);if(encoded.is_empty()){failed=true;return;}
   int64_t expected=group.size()+encoded.size();group.append_array(encoded);if(group.size()!=expected){failed=true;return;}
  }
  job.output.packet=group;
 },16,dirty>=256?worker_limit_:1);
 if(failed)return {};
 std::vector<Product> products;for(auto &job:jobs){products.push_back(job.output);read_regions_+=job.read;}
 Buffer reference=publish_products(std::move(metadata),products,previous,incremental,stop);
 if(!reference.is_empty()){std::lock_guard<std::mutex> publication(capture->publication_mutex_);capture->published_=reference;}
 return reference;
}
Buffer NativeTerrainRegionStore::expand_snapshot(const Buffer &reference){
 std::lock_guard<std::mutex> lock(mutex_);Index index;if(!load_index(reference,index)||index.order.size()>MAX_PAGES)return {};
 int64_t size=36+int64_t(index.order.size())*(4+PAGE_SAMPLES*3)+index.blocks.size();if(size>256*1024*1024)return {};
 Buffer b;if(b.resize(size)!=OK)return {};b.encode_u32(0,SAVE_MAGIC);b.encode_u32(4,3);b.encode_u32(8,index.seed);b.encode_u32(12,index.order.size());b.encode_u32(16,index.blocks.size()/8);b.encode_u32(20,index.revision);b.encode_u32(24,index.edits);b.encode_u32(28,index.generator);
 // Decode one region at a time and scatter to the original page order.
 // Scratch memory is bounded by a single region, not a duplicate whole world.
 std::map<uint32_t,int64_t> offsets;int64_t at=32;
 for(uint32_t key:index.order){offsets.emplace(key,at);at+=4+PAGE_SAMPLES*3;}
 for(const auto &[key,entry]:index.regions){std::map<uint32_t,Buffer> pages;if(!load_region(key,entry,pages))return {};
  for(const auto &[page,raw]:pages){auto found=offsets.find(page);if(found==offsets.end())return {};b.encode_u32(found->second,page);std::memcpy(b.ptrw()+found->second+4,raw.ptr(),raw.size());}
 }
 if(index.blocks.size())std::memcpy(b.ptrw()+at,index.blocks.ptr(),index.blocks.size());
 b.encode_u32(size-4,terrain_checksum::checksum(b.ptr(),int(size-4)));return b;
}
Dictionary NativeTerrainRegionStore::describe_snapshot(const Buffer &reference){
 std::lock_guard<std::mutex> lock(mutex_);Dictionary out;out["ok"]=false;Index index;if(!load_index(reference,index))return out;
 PackedInt32Array coordinates;
 for(const auto &[key,entry]:index.regions){uint32_t v=key-1;coordinates.push_back(v%32);coordinates.push_back(v/1024);coordinates.push_back((v/32)%32);}
 out["ok"]=true;out["seed"]=index.seed;out["generator"]=index.generator;out["revision"]=index.revision;out["edits"]=index.edits;out["pages"]=int64_t(index.order.size());out["blocks"]=index.blocks.size()/8;out["coordinates"]=coordinates;return out;
}
Dictionary NativeTerrainRegionStore::verify_snapshot(const Buffer &reference){
 std::lock_guard<std::mutex> lock(mutex_);Dictionary out;out["ok"]=false;Index index;if(!load_index(reference,index))return out;
 std::set<uint32_t> expected(index.order.begin(),index.order.end());
 for(const auto &[key,entry]:index.regions){
  std::map<uint32_t,Buffer> pages;if(!load_region(key,entry,pages))return out;
  for(const auto &[page,raw]:pages)if(!expected.erase(page))return out;
 }
 if(!expected.empty())return out;
 out["ok"]=true;out["seed"]=index.seed;out["generator"]=index.generator;out["revision"]=index.revision;out["pages"]=int64_t(index.order.size());out["regions"]=int64_t(index.regions.size());out["blocks"]=index.blocks.size()/8;return out;
}
Dictionary NativeTerrainRegionStore::read_region(const Buffer &reference,Vector3i p){
 std::lock_guard<std::mutex> lock(mutex_);Dictionary out;out["ok"]=false;
 if(p.x<0||p.x>=32||p.z<0||p.z>=32||p.y<0||p.y>4)return out;
 Index index;if(!load_index(reference,index))return out;uint32_t key=1+p.x+32*(p.z+32*p.y);auto found=index.regions.find(key);
 if(found==index.regions.end()){out["ok"]=true;out["present"]=false;return out;}
 std::map<uint32_t,Buffer> pages;if(!load_region(key,found->second,pages))return out;
 Dictionary result;std::set<uint32_t> expected;for(uint32_t page:index.order)if(region_for(page)==key)expected.insert(page);
 for(const auto &[page,raw]:pages){if(!expected.erase(page))return out;result[int64_t(page)]=raw;}if(!expected.empty())return out;
 out["ok"]=true;out["present"]=true;out["pages"]=result;return out;
}
Dictionary NativeTerrainRegionStore::stats(){
 std::lock_guard<std::mutex> lock(mutex_);Dictionary out;out["written_files"]=written_;out["reused_files"]=reused_;out["reused_regions"]=reused_regions_;out["written_bytes"]=written_bytes_;out["region_reads"]=read_regions_;out["workers"]=last_workers_;return out;
}
}
