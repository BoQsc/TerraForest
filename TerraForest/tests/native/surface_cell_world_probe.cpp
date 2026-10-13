// SPDX-License-Identifier: 0BSD
#include "core.h"
#include <cstdlib>
#include <cstdio>
int main(){
 tr_alloc=std::malloc;tr_realloc=std::realloc;tr_free=std::free;tr_oom=false;
 World world;world.init(1703);
 for(int style=0;style<2;style++)for(int site=0;site<3;site++){
  world.surface_style=style;Mesh mesh;int x=800+site*16,z=1280;
  if(!build_patch(world,x,z,16,1,mesh)||tr_oom)return 1;
  Bytes packet;encode_mesh(mesh,x,z,16,1,packet);
  unsigned long long hash=1469598103934665603ull;
  for(int i=0;i<packet.n;i++){hash^=packet.p[i];hash*=1099511628211ull;}
  std::printf("%d %d %d %d %016llx\n",style,site,mesh.v.n,mesh.i.n,hash);
  packet.release();mesh.release();
 }
 world.release();
}
