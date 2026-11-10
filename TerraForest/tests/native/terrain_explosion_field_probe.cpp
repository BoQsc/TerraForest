// SPDX-License-Identifier: 0BSD
#define main atomicity_main
#include "terrain_edit_atomicity_probe.cpp"
#undef main
#include <chrono>

int main(){
 int failures=atomicity_main();
 for(int generator:{1,31})for(int repeat=0;repeat<5;repeat++){
  World world;world.init(1703,generator);float height=world.height(1296,1296);
  Bytes receipts;bool ok=true;V3 lo,hi;int changes=0;
  auto start=std::chrono::steady_clock::now();
  for(int z=0;z<16;z++)for(int x=0;x<16;x++){
   V3 p{1290+x*.75f,height,1290+z*.75f};u32 removed[16]{};
   bool accepted=world.edit(p,p,3.5f,0,false,0,lo,hi,changes,1,0,0,removed);
   ok&=accepted;receipts.u(accepted);receipts.u(changes);receipts.u(world.revision);receipts.raw(removed,sizeof(removed));
  }
  auto elapsed=std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now()-start).count();
  Bytes encoded;world.serialize(encoded,true);char name[80];
  std::snprintf(name,sizeof(name),"cohort_field_%d.bin",generator);ok&=write_file(name,encoded);
  std::snprintf(name,sizeof(name),"cohort_receipts_%d.bin",generator);ok&=write_file(name,receipts);
  encoded.release();receipts.release();world.release();ok&=live_allocations==0;
  printf("{\"case\":\"ordered_256_field\",\"generator\":%d,\"repeat\":%d,\"elapsed_us\":%lld,\"passed\":%s}\n",generator,repeat,(long long)elapsed,ok?"true":"false");
  failures+=!ok;
 }
 return failures?1:0;
}
