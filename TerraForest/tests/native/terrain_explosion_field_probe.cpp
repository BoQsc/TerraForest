// SPDX-License-Identifier: 0BSD
#define main atomicity_main
#include "terrain_edit_atomicity_probe.cpp"
#undef main
#include <chrono>

int main(){
 int failures=atomicity_main();
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
