// SPDX-License-Identifier: 0BSD
#include "../native/core.h"
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <chrono>
#include <set>
#include <tuple>
static double now(){return std::chrono::duration<double>(std::chrono::steady_clock::now().time_since_epoch()).count();}
int main(int argc,char**argv){tr_alloc=malloc;tr_realloc=realloc;tr_free=free;World world;world.init();std::filesystem::path path=argc>1?argv[1]:"base_cache";std::filesystem::create_directories(path);
 std::set<std::tuple<int,int,int>> keys;for(int z=0;z<2048;z+=256)for(int x=0;x<2048;x+=256)keys.insert({x,z,256});
 // Cache initial approach plus proof locations. Not all fine world terrain is baked/stored.
 const int spots[][2]={{960,1310},{1050,1218},{985,985},{1484,1433}};
 for(auto&p:spots)for(int size:{16,32,64,128}){int range=size<=32?48:size;int x0=(p[0]-range)/size*size,z0=(p[1]-range)/size*size;for(int z=z0;z<=p[1]+range;z+=size)for(int x=x0;x<=p[0]+range;x+=size)if(x>=0&&z>=0&&x<2000&&z<2000)keys.insert({x,z,size});}
 int n=0;long long bytes=0,tris=0;double begin=now();for(auto k:keys){auto[x,z,size]=k;Mesh mesh;build_patch(world,x,z,size,size<32?1:size/32,mesh);Bytes out;encode_mesh(mesh,x,z,size,size<32?1:size/32,out);char name[80];std::snprintf(name,sizeof(name),"%d_%d_%d.trm",x,z,size);auto file=path/name;FILE*f=std::fopen(file.string().c_str(),"wb");if(!f||std::fwrite(out.p,1,out.n,f)!=size_t(out.n)){std::fprintf(stderr,"write failed\n");return 1;}std::fclose(f);bytes+=out.n;tris+=mesh.i.n/3;mesh.release();out.release();n++;if(n%32==0)printf("baked %d/%zu, %.1f seconds\n",n,keys.size(),now()-begin);}
 printf("BAKE_RESULT %d cache files, %lld bytes, %lld total cache triangles, %.3f seconds\n",n,bytes,tris,now()-begin);world.release();return tr_oom?1:0;}
