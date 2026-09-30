#include "experimental/world_region_sampler.hpp"
#include <cstdio>
#include <cstdlib>
#include <string>
using namespace terraforest::experimental;
int main(int argc,char**argv){
 if(argc!=2)return 2;
 tr_alloc=std::malloc;tr_realloc=std::realloc;tr_free=std::free;
 World w;w.init(1703);MeshLimits limits;limits.exact_zero_vertices=true;
 for(int site=0;site<3;site++){
  int base=site?1280:960;
  if(site==2){V3 p{1296,w.height(1296,1296),1296},lo,hi;int changes;if(!w.edit(p,p,5,0,false,1,lo,hi,changes)||!changes)return 3;}
  for(int part=0;part<5;part++){
   int size=part?16:32,x=base+(part?(part-1)%2*16:0),z=base+(part?(part-1)/2*16:0);
   Result mesh=build_world_region(w,x,z,size,limits);if(mesh.status!=MeshStatus::ok)return 4;
   std::string name=std::to_string(site)+"_"+std::to_string(x)+"_"+std::to_string(z)+"_"+std::to_string(size);
   FILE*f=fopen((std::string(argv[1])+"/"+name+".bin").c_str(),"wb");if(!f)return 5;
   u32 counts[2]={u32(mesh.p.size()),u32(mesh.indices.size())};
   fwrite(counts,4,2,f);fwrite(mesh.p.data(),sizeof(V3),mesh.p.size(),f);fwrite(mesh.indices.data(),4,mesh.indices.size(),f);fclose(f);
   printf("{\"name\":\"%s\",\"collapsed_triangles\":%zu}\n",name.c_str(),mesh.collapsed_triangles);
  }
 }
 w.release();return 0;
}
