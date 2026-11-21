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
// A compact setup for a full unpaged world: every page below 64 m in this
// square has authored, uniform solid density. Pages have normal owned storage.
static bool full_world_edit(){
 World world;world.init(1703,5);
 for(int y=0;y<4;y++)for(int z=0;z<64;z++)for(int x=0;x<64;x++){
  Page page;page.key=1+x+WORLD_PAGE_COLUMNS*(z+WORLD_PAGE_COLUMNS*y);
  page.d=(i16*)tr_alloc(PAGE_SAMPLES*sizeof(i16));page.mat=(u8*)tr_alloc(PAGE_SAMPLES);
  for(int i=0;i<PAGE_SAMPLES;i++){page.d[i]=-4096;page.mat[i]=1;}
  int index=world.pages.push(page);world.pages_by_key.put(page.key,index);
  world.edit_columns[x+WORLD_PAGE_COLUMNS*z]|=1u<<y;
 }
 V3 lo,hi,air{1500,230,1500};int changes=0;
 bool ok=world.pages.n==MAX_PAGES;
 // The brush halo extends across x=1024. Both sides are rock there, so
 // excavation centred one radius farther inside modifies existing pages only.
 ok=ok&&world.edit(air,air,4,0,false,1,lo,hi,changes)&&changes==0;
 V3 inside{1016,30,512};
 ok=ok&&world.edit(inside,inside,4,0,false,1,lo,hi,changes)&&changes>0;
 const auto revision=world.revision;
 ok=ok&&!world.edit(air,air,4,0,true,1,lo,hi,changes)&&changes==0
      &&world.revision==revision&&world.pages.n==MAX_PAGES;
 // This cut stages changes in existing pages before it encounters a new
 // page at x=1024. An over-budget cut must leave those earlier samples intact.
 V3 edge{1023,30,512};
 bool add=world.sample(1024,30,512)>=0;
 if(add){
  Page *existing=world.ensure(1022/16,30/16,512/16);
  existing->d[(1022&15)+16*((512&15)+16*(30&15))]=4096;
 }
 float before=world.sample(1022,30,512);
 ok=ok&&!world.edit(edge,edge,4,0,add,1,lo,hi,changes)&&changes==0
      &&world.sample(1022,30,512)==before&&world.revision==revision;
 world.release();return ok;
}
static int common_edit_checks(){
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

// Diff every authored page against its independent pre-edit image. For a
// newly admitted page the reference is the generator's full page image.
static bool exact_write_footprints(){
 World live;live.init(1703,3);
 const int x=1280,z=1280,y=fl(live.height(x,z));
 const V3 point={float(x),float(y),float(z)};
 const u32 cube=1+u32(x|(z<<11)|(y<<22));
 live.set_block(cube,3);
 bool ok=true;int checked=0;
 for(int step=0;step<5;++step){
  World prior;Bytes save;live.serialize(save,true);
  ok&=prior.deserialize(save.p,save.n);save.release();
  TerrainEditWrites writes;live.edit_writes=&writes;
  V3 lo,hi;int changes=0;
  const bool paint=step==1;
  const bool add=step==0||paint;
  bool accepted=live.edit(point,point,step<2?2.f:16.f,paint?4:1,add,paint?8:1,lo,hi,changes);
  live.edit_writes=nullptr;
  ok&=accepted&&writes.complete;
  List<u8> written,new_pages;
  written.resize(live.pages.n*PAGE_SAMPLES);new_pages.resize(live.pages.n);
  int reported=0,blocks=0;
  for(int i=0;i<writes.records.n;++i){
   auto r=writes.records[i];
   int gx=r.address&2047,gz=(r.address>>11)&2047,gy=int(r.address>>22);
   if(r.detail==TerrainEditWrites::BLOCK){++blocks;ok&=r.address+1==cube;continue;}
   if(r.detail==TerrainEditWrites::PAGE_ADMITTED){
    u32 key=1+(gx/16)+WORLD_PAGE_COLUMNS*((gz/16)+WORLD_PAGE_COLUMNS*(gy/16));
    int id=live.pages_by_key.get(key);
    if(id<0){ok=false;continue;}
    ok&=!new_pages[id]&&prior.pages_by_key.get(key)<0;
    new_pages[id]=1;continue;
   }
   for(int yy=gy;yy<=int(r.detail);++yy){
    u32 key=1+(gx/16)+WORLD_PAGE_COLUMNS*((gz/16)+WORLD_PAGE_COLUMNS*(yy/16));
    int id=live.pages_by_key.get(key);
    if(id<0){ok=false;continue;}
    int at=id*PAGE_SAMPLES+(gx&15)+16*((gz&15)+16*(yy&15));
    ok&=!written[at];written[at]=1;++reported;
   }
  }
  ok&=reported+blocks==changes;
  ok&=blocks==int(prior.blocks.get(cube)>=0&&live.blocks.get(cube)<0);
  for(int i=0;i<live.pages.n;++i){
   auto &after=live.pages[i];int v=int(after.key)-1;
   ok&=(prior.pages_by_key.get(after.key)<0)==bool(new_pages[i]);
   auto *before=prior.ensure(v%WORLD_PAGE_COLUMNS,v/(WORLD_PAGE_COLUMNS*WORLD_PAGE_COLUMNS),(v/WORLD_PAGE_COLUMNS)%WORLD_PAGE_COLUMNS);
   if(!before){ok=false;break;}
   for(int j=0;j<PAGE_SAMPLES;++j){
    bool differs=before->d[j]!=after.d[j]||before->mat[j]!=after.mat[j];
    ok&=differs==bool(written[i*PAGE_SAMPLES+j]);
   }
  }
  checked+=reported;written.release();new_pages.release();prior.release();
 }
 live.release();return ok&&checked>1000;
}

int main(){
 int failures=common_edit_checks();
 bool writes_ok=exact_write_footprints();
 printf("{\"case\":\"exact_native_write_footprints\",\"passed\":%s}\n",writes_ok?"true":"false");
 failures+=!writes_ok;
 bool capacity_ok=full_world_edit()&&live_allocations==0;
 printf("{\"case\":\"full_world_admits_existing_page_edit_and_noop\",\"passed\":%s}\n",capacity_ok?"true":"false");
 return failures||!capacity_ok;
}
