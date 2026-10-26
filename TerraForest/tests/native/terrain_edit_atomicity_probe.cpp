// SPDX-License-Identifier: 0BSD
#include "core.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <initializer_list>
static int allocation=0,deny=0,live_allocations=0;
static bool deny_reallocation=false;
static void *allocate(size_t n){if(deny&&!deny_reallocation&&++allocation==deny)return nullptr;void *p=std::malloc(n);if(p)live_allocations++;return p;}
static void *reallocate(void *p,size_t n){if(deny&&deny_reallocation&&++allocation==deny)return nullptr;void *next=std::realloc(p,n);if(next&&!p)live_allocations++;return next;}
static void release(void *p){if(p)live_allocations--;std::free(p);}
static bool equal(const Bytes &a,const Bytes &b){return a.n==b.n&&!std::memcmp(a.p,b.p,a.n);}
static bool write_file(const char *name,const Bytes &bytes){
 FILE *file=std::fopen(name,"wb");if(!file)return false;
 bool ok=std::fwrite(bytes.p,1,bytes.n,file)==size_t(bytes.n);return std::fclose(file)==0&&ok;
}
static bool parity_fields(){
 bool ok=true;
 for(int generator:{1,3,5,19}){
  World w;w.init(1703,generator);V3 lo,hi;int changes;u32 removed[16]{};Bytes receipts;
  w.set_block(1+u32(1200|(1000<<11)|(61<<22)),3);w.revision++;w.edits++;
  auto edit=[&](V3 a,V3 b,float radius,int shape,bool add,u8 material,float depth=1,float clearance=0,float shoulder=0,const float *curve=nullptr){
   bool accepted=w.edit(a,b,radius,shape,add,material,lo,hi,changes,depth,clearance,shoulder,removed,curve,curve?1:0,0);
   ok&=accepted;receipts.u(accepted);receipts.u(changes);receipts.u(w.revision);receipts.u(w.edits);receipts.vec(lo);receipts.vec(hi);receipts.raw(removed,sizeof(removed));
  };
  V3 ground{1200,w.height(1200,1000)-.6f,1000};
  edit(ground,ground,3,0,false,1);edit(ground,ground,2,1,true,2);
  edit(ground+V3{4,0,0},ground+V3{15,-3,4},2,0,false,1);
  edit({1190,61,1000},{1210,62,1000},4,2,true,4,3,5,3);
  float curve[4]={.1f,-.1f,1,61};edit({1190,61,1000},{1210,62,1000},3,2,true,3,2,4,2,curve);
  edit({1000,2,1000},{1000,2,1000},5,0,false,1);
  edit({0,60,1000},{0,60,1000},3,1,true,1);
  edit({2000,254,1000},{2000,254,1000},3,0,true,2);
  edit({1000,120,1000},{1000,120,1000},2,0,false,1);
  Bytes encoded;w.serialize(encoded,true);char name[64];
  std::snprintf(name,sizeof(name),"field_%d.bin",generator);ok&=write_file(name,encoded);
  std::snprintf(name,sizeof(name),"receipts_%d.bin",generator);ok&=write_file(name,receipts);
  encoded.release();receipts.release();w.release();
 }
 return ok;
}
static bool allocation_sweep(){
 bool passed=true;int attempts=0,forced=0;
 auto setup=[](World &w,int profile,int existing){
  w.init(1703,profile?19:5);V3 p{1280,64,1280};if(profile)p.y=w.height(p.x,p.z)-.6f;
  if(existing)w.ensure(79,fl(p.y-8)>>4,79);
  if(profile){w.set_block(1+u32(1280|(1280<<11)|(fl(p.y)<<22)),3);w.revision++;w.edits++;}
  return p;
 };
 for(int profile=0;profile<2;profile++)for(int existing=0;existing<2;existing++){
  World control;V3 p=setup(control,profile,existing),lo,hi;int changes;u32 removed[16]{};
  bool accepted=control.edit(p,p,3,profile?0:1,!profile,1,lo,hi,changes,1,0,0,removed);
  Bytes expected;control.serialize(expected,true);control.release();if(!accepted)passed=false;
  for(int endpoint=0;endpoint<2;endpoint++)for(int kind=0;kind<2;kind++)for(int fail=1;fail<=32;fail++){
   int retained=live_allocations;World w;p=setup(w,profile,existing);Bytes before;w.serialize(before,true);u64 original_samples=w.changed_samples;
   Bytes request,response;if(endpoint){request.u(2);request.vec(p);request.vec(p);request.f(3);request.u(profile?0:1);request.u(!profile);request.u(1);}
   allocation=0;deny=fail;deny_reallocation=kind;tr_oom=false;changes=0;
   if(endpoint){process_request(w,request.p,request.n,response);accepted=response.n>=12&&response.p[8]==0;if(response.n>=20){Reader result{response.p,response.n,16};changes=int(result.u());}}
   else accepted=w.edit(p,p,3,profile?0:1,!profile,1,lo,hi,changes,1,0,0,removed);
   bool hit=allocation>=fail;forced+=hit;deny=0;tr_oom=false;Bytes after;w.serialize(after,true);
   bool exact=hit?(!accepted&&equal(before,after)&&changes==0&&w.changed_samples==original_samples):(accepted&&equal(expected,after));
   before.release();after.release();request.release();response.release();w.release();exact&=live_allocations==retained;
   if(!exact)printf("{\"case\":\"sweep_failure\",\"passed\":false,\"profile\":%d,\"existing\":%d,\"endpoint\":%d,\"allocator\":%d,\"fault\":%d,\"hit\":%s}\n",profile,existing,endpoint,kind,fail,hit?"true":"false");
   passed&=exact;attempts++;
  }
  expected.release();
 }
 printf("{\"case\":\"allocation_and_reallocation_sweep\",\"passed\":%s,\"attempts\":%d,\"forced_failures\":%d}\n",passed?"true":"false",attempts,forced);
 return passed;
}
static bool small_edit_sweep(){
 bool passed=true;int attempts=0,forced=0;
 auto setup=[](World &world){world.init(1703,5);for(int index=0;index<44;index++)world.set_block(1+u32((100+index)|(100<<11)|(64<<22)),1);};
 for(int command:{3,38})for(int allocator=0;allocator<2;allocator++)for(int fault=1;fault<=48;fault++){
  int retained=live_allocations;World world;setup(world);Bytes before;world.serialize(before,true);
  int column_count=0;for(int index=0;index<world.block_columns.n;index++)column_count+=world.block_columns[index].n;
  Bytes request,response;request.u(command);request.u(command==3?144:128);request.u(64);request.u(command==3?100:128);request.u(command==3?2:10);
  allocation=0;deny=fault;deny_reallocation=allocator;tr_oom=false;
  process_request(world,request.p,request.n,response);
  bool hit=allocation>=fault,accepted=response.n>=12&&response.p[8]==0;forced+=hit;
  deny=0;tr_oom=false;Bytes after;world.serialize(after,true);
  int after_columns=0;for(int index=0;index<world.block_columns.n;index++)after_columns+=world.block_columns[index].n;
  bool exact=hit?(!accepted&&equal(before,after)&&after_columns==column_count):accepted;
  before.release();after.release();request.release();response.release();world.release();exact&=live_allocations==retained;
  if(!exact)printf("{\"case\":\"small_edit_rollback_failure\",\"passed\":false,\"command\":%d,\"allocator\":%d,\"fault\":%d}\n",command,allocator,fault);
  passed&=exact;attempts++;
 }
 printf("{\"case\":\"voxel_and_paid_stamp_allocation_sweep\",\"passed\":%s,\"attempts\":%d,\"forced_failures\":%d}\n",passed?"true":"false",attempts,forced);
 return passed;
}
int main(){
 tr_alloc=allocate;tr_realloc=reallocate;tr_free=release;int failures=0;
 bool fixtures=parity_fields();printf("{\"case\":\"successful_edit_fields\",\"passed\":%s}\n",fixtures?"true":"false");failures+=!fixtures;
 for(int existing=0;existing<2;existing++){
  World w;w.init(42,5);w.pages.reserve(128);w.pages_by_key.rehash(256);
  if(existing)w.ensure(79,3,79);
  Bytes before;w.serialize(before,true);int original_revision=w.revision;
  allocation=0;deny=existing?1:3;tr_oom=false;
  V3 p{1280,64,1280},lo,hi;int changes=0;u32 removed[16]{};
  bool accepted=w.edit(p,p,3,1,true,1,lo,hi,changes,1,0,0,removed);
  deny=0;tr_oom=false;Bytes after;w.serialize(after,true);
  bool passed=!accepted&&equal(before,after)&&w.revision==original_revision&&changes==0;
  printf("{\"case\":\"%s\",\"passed\":%s,\"accepted\":%s,\"before_bytes\":%d,\"after_bytes\":%d,\"reported_changes\":%d}\n",existing?"existing_page_allocation_failure":"new_page_allocation_failure",passed?"true":"false",accepted?"true":"false",before.n,after.n,changes);
  failures+=!passed;before.release();after.release();w.release();
 }
 failures+=!allocation_sweep();
 failures+=!small_edit_sweep();
 printf("{\"case\":\"allocation_balance\",\"passed\":%s,\"live\":%d}\n",live_allocations==0?"true":"false",live_allocations);
 failures+=live_allocations!=0;
 return failures?1:0;
}
