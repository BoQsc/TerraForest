// SPDX-License-Identifier: 0BSD
#include "core.h"
#include <cstdlib>
#include <cstdio>
static void packet(const Mesh &mesh,int scenario,int style,int site,int mode,int x,int z){
 Bytes bytes;encode_mesh(mesh,x,z,16,1,bytes);
 unsigned long long hash=1469598103934665603ull;
 for(int i=0;i<bytes.n;i++){hash^=bytes.p[i];hash*=1099511628211ull;}
 std::printf("%d %d %d %d %d %d %016llx\n",scenario,style,site,mode,mesh.v.n,mesh.i.n,hash);
 bytes.release();
}
int main(){
 tr_alloc=std::malloc;tr_realloc=std::realloc;tr_free=std::free;tr_oom=false;
 World world;world.init(1703);
 for(int scenario=0;scenario<4;scenario++){
  if(scenario==1||scenario==2){
   // Dig and place across a reconstruction boundary. Explicit material exercises
   // the edited-cell projection branch in both surface styles.
   V3 p={816.f,world.height(816,1288)-1,1288.f},lo,hi;int changed=0;
   if(scenario==2)p.y+=2;
   if(!world.edit(p,p,3.25f,scenario==1?0:1,scenario==2,2,lo,hi,changed)||!changed)return 2;
  }
  if(scenario==3){Bytes saved;world.serialize(saved);if(!world.deserialize(saved.p,saved.n))return 3;saved.release();}
  for(int style=0;style<2;style++){
   // Surface style is part of reconstruction policy; don't reuse another style's cache.
   release_geometry_cache(world);world.surface_style=style;
   for(int site=0;site<3;site++)for(int mode=0;mode<3;mode++){
    Mesh mesh;int x=800+site*16,z=1280;
    bool ok=mode==2?build_owned_region(world,x,z,16,1,32,64,mesh,terrain_build_epoch(&world)):
     build_patch(world,x,z,16,1,mesh,0xffffffffu,mode==1);
    if(!ok||tr_oom)return 1;
    packet(mesh,scenario,style,site,mode,x,z);mesh.release();
   }
  }
 }
 world.release();
}
