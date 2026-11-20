// SPDX-License-Identifier: 0BSD
#define main atomicity_main
#include "terrain_edit_atomicity_probe.cpp"
#undef main
#include <chrono>

// Reject the second new page after an existing page was staged as well.
static bool rejected_cut_preserves_world(){
 struct Admission:PageAccess{
  int attempts=0,slots=0;
  bool admit(World&)override{return ++attempts<2;}
  bool load(World&,int)override{return false;}
  void touch(World&,int)override{}
  void inserted(World&,int)override{++slots;}
  void removed(World&,int)override{--slots;}
 } access;
 World w;w.init(1703,31);V3 p{1010,28,995},lo,hi;
 w.ensure(63,1,62);Bytes before,after;w.serialize(before,true);
 const u64 serial=w.storage_serial;
 w.page_access=&access;int changes=0;u32 removed[16]{};
 bool accepted=w.edit(p,p,32,1,false,0,lo,hi,changes,1,0,0,removed);
 w.page_access=nullptr;w.serialize(after,true);
 bool ok=!accepted&&changes==0&&access.attempts==2&&access.slots==0&&w.storage_serial==serial&&equal(before,after);
 for(auto amount:removed)ok&=amount==0;
 before.release();after.release();w.release();return ok&&live_allocations==0;
}

static bool rejected_cut_allocation_is_atomic(){
 for(bool grow:{false,true})for(int fault:{1,2,3,5,8,16}){
  World w;w.init(1703,31);V3 center{1010,28,995},lo,hi;
  w.ensure(63,1,62);Bytes before,after;w.serialize(before,true);
  int changes=0;u32 removed[16]{};
  allocation=0;deny=fault;deny_reallocation=grow;tr_oom=false;
  bool accepted=w.edit(center,center,32,1,false,0,lo,hi,changes,1,0,0,removed);
  bool hit=allocation>=fault;deny=0;tr_oom=false;w.serialize(after,true);
  bool ok=hit?(!accepted&&changes==0&&equal(before,after)):accepted;
  if(hit)for(auto amount:removed)ok&=amount==0;
  before.release();after.release();w.release();if(!ok||live_allocations)return false;
 }
 return true;
}

// Compare every value and triangle with the independent general probe
// protocol, including the clamped last half-cell and exact construction grid.
static bool contact_packet_matches_probes(){
 World w;w.init(1703,31);V3 lo,hi;int changes;V3 p{1010,28,995};
 w.edit(p,p,32,1,false,0,lo,hi,changes);
 w.set_block(1+u32(1010|(994<<11)|(28<<22)),3);
 bool ok=true;
 for(V3 origin:{V3{1008,28,992},V3{976,4,992},V3{0,0,0},V3{1996,252,1996}}){
  Bytes query,legacy,patch;query.u(32);query.u(w.revision);query.u(terrain_build_epoch(&w));
  query.u(int(origin.x));query.u(int(origin.y));query.u(int(origin.z));
  process_request(w,query.p,query.n,legacy);query.p[0]=43;
  process_request(w,query.p,query.n,patch);
  ok&=legacy.n>=28&&patch.n==legacy.n+729*4+64&&patch.p[8]==0;
  if(ok)ok&=!std::memcmp(legacy.p+8,patch.p+8,legacy.n-8);
  for(int first=0;ok&&first<729;first+=512){
   int n=imn(512,729-first);Bytes points,result;points.u(31);points.u(w.revision);points.u(n);
   for(int i=first;i<first+n;i++)points.vec({mn(origin.x+i%9*.5f,__builtin_nextafterf(float(WORLD),0.f)),
    clampf(origin.y+(i/9)%9*.5f,1.f,255.f),mn(origin.z+i/81*.5f,__builtin_nextafterf(float(WORLD),0.f))});
   process_request(w,points.p,points.n,result);
   ok&=result.n==20+4*n&&!std::memcmp(result.p+20,patch.p+legacy.n+first*4,n*4);
   points.release();result.release();
  }
  if(ok){
   Bytes points,result;points.u(33);points.u(w.revision);points.u(512);
   for(int i=0;i<512;++i)points.vec(origin+V3{.25f+(i%8)*.5f,.25f+((i/8)%8)*.5f,.25f+(i/64)*.5f});
   process_request(w,points.p,points.n,result);Reader values{result.p,result.n,20};ok&=result.n==20+512*4;
   for(int i=0;ok&&i<512;++i)
    ok&=(values.f()!=0)==bool(patch.p[patch.n-64+(i%8)/2+4*((i/8)%8/2)+16*(i/64/2)]);
   points.release();result.release();
  }
  query.release();legacy.release();patch.release();
 }
 w.release();return ok&&live_allocations==0;
}

int main(int argc,char **argv){
 int failures=common_edit_checks();
 failures+=!rejected_cut_preserves_world();
 bool capacity_ok=full_world_edit()&&live_allocations==0;
 printf("{\"case\":\"full_world_edit\",\"passed\":%s}\n",capacity_ok?"true":"false");
 if(argc>1 && !std::strcmp(argv[1],"--require-full-world-edit")){failures+=!capacity_ok;failures+=!rejected_cut_allocation_is_atomic();bool contact=contact_packet_matches_probes();printf("{\"case\":\"contact_packet_parity\",\"passed\":%s}\n",contact?"true":"false");failures+=!contact;}
 {
  World world;world.init(1703,31);Bytes receipts;V3 lo,hi;int changes;
  EditHeightCache cache;world.edit_height_cache=&cache;
  V3 center{1010,28,995};
  for(int pass=0;pass<3;pass++){
   V3 p=pass==2?center+V3{29,0,4}:center;
   u32 removed[16]{};auto start=std::chrono::steady_clock::now();
   bool accepted=world.edit(p,p,pass==2?14:32,pass==2?0:1,false,0,lo,hi,changes,1,0,0,removed);
   auto us=std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now()-start).count();
   printf("{\"case\":\"full_cut\",\"pass\":%d,\"elapsed_us\":%lld,\"changes\":%d}\n",pass,(long long)us,changes);
   receipts.u(accepted);receipts.u(changes);receipts.u(world.revision);receipts.raw(removed,sizeof(removed));
   if(pass!=1&&(!accepted||changes==0))++failures;
  }
  Bytes field;world.serialize(field,true);
  failures+=!write_file("large_cut_field.bin",field)||!write_file("large_cut_receipts.bin",receipts);
  field.release();receipts.release();world.release();failures+=live_allocations!=0;
 }
 for(int generator:{1,31})for(int repeat=0;repeat<5;repeat++){
  World world;world.init(1703,generator);float height=world.height(1296,1296);
  EditHeightCache cache;world.edit_height_cache=&cache;
  Bytes receipts;bool ok=true;V3 lo,hi;int changes=0;
  auto start=std::chrono::steady_clock::now();
  for(int z=0;z<16;z++)for(int x=0;x<16;x++){
   V3 p{1290+x*.75f,height,1290+z*.75f};u32 removed[16]{};
   bool accepted=world.edit(p,p,3.5f,0,false,0,lo,hi,changes,1,0,0,removed);
   ok&=accepted;receipts.u(accepted);receipts.u(changes);receipts.u(world.revision);receipts.raw(removed,sizeof(removed));
  }
  auto elapsed=std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now()-start).count();
  world.edit_height_cache=nullptr;world.cache_mesh_heights=true;
  Bytes meshes;auto mesh_start=std::chrono::steady_clock::now();
  for(int z:{1280,1296})for(int x:{1280,1296}){
   Mesh mesh;ok&=build_patch(world,x,z,16,1,mesh);Bytes packet;
   encode_mesh(mesh,x,z,16,1,packet);meshes.u(packet.n);meshes.raw(packet.p,packet.n);packet.release();mesh.release();
  }
  auto mesh_us=std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now()-mesh_start).count();
  Bytes encoded;world.serialize(encoded,true);char name[80];
  std::snprintf(name,sizeof(name),"cohort_field_%d.bin",generator);ok&=write_file(name,encoded);
  std::snprintf(name,sizeof(name),"cohort_receipts_%d.bin",generator);ok&=write_file(name,receipts);
  std::snprintf(name,sizeof(name),"cohort_meshes_%d.bin",generator);ok&=write_file(name,meshes);meshes.release();
  world.edit_height_cache=nullptr;
  encoded.release();receipts.release();world.release();ok&=live_allocations==0;
  printf("{\"case\":\"ordered_256_field\",\"generator\":%d,\"repeat\":%d,\"elapsed_us\":%lld,\"mesh_us\":%lld,\"passed\":%s}\n",generator,repeat,(long long)elapsed,(long long)mesh_us,ok?"true":"false");
  failures+=!ok;
 }
 return failures?1:0;
}
