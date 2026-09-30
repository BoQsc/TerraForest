// Isolated position-only LOD test, not a runtime addon.
#include "meshoptimizer.h"
#include "terrain_distance_probe.hpp"
int main(int argc,char**argv){
 if(argc!=3)return 2;
 FILE*f=fopen(argv[1],"rb");if(!f)return 3;U nv,ni;if(fread(&nv,4,1,f)!=1||fread(&ni,4,1,f)!=1||!nv||!ni||ni%3||nv>2000000||ni>12000000)return 4;
 std::vector<float>positions(size_t(nv)*3);std::vector<U>indices(ni);if(fread(positions.data(),12,nv,f)!=nv||fread(indices.data(),4,ni,f)!=ni)return 5;fclose(f);for(U i:indices)if(i>=nv)return 6;
 std::vector<V>p(nv);for(U i=0;i<nv;i++)p[i]={positions[i*3],positions[i*3+1],positions[i*3+2]};
 BVH reference(p,indices);
 // Analytic sanity cases exercise face, edge and vertex distance regions.
 if(std::fabs(distance_triangle({.25f,.25f,2},{0,0,0},{1,0,0},{0,1,0})-4)>1e-6f||std::fabs(distance_triangle({2,0,0},{0,0,0},{1,0,0},{0,1,0})-1)>1e-6f)return 7;
 if(std::fabs(distance_triangle({1,1,0},{0,0,0},{1,0,0},{0,1,0})-.5f)>1e-6f)return 7;
 double self_error=sampled_error(p,indices,reference);if(self_error>.0005f)return 10;
 for(int level=0;level<4;level++){
  float budget=std::array<float,4>{.01f,.05f,.1f,.25f}[level],reported=0;
  std::vector<U>output(ni);double begin=now();
  size_t count=meshopt_simplify(output.data(),indices.data(),ni,positions.data(),nv,12,std::max(size_t(12),size_t(ni/48)*3),budget,meshopt_SimplifyLockBorder|meshopt_SimplifyErrorAbsolute,&reported);
  double elapsed=now()-begin;output.resize(count);if(!count)return 8;
  BVH coarse(p,output);double forward=sampled_error(p,indices,coarse),reverse=sampled_error(p,output,reference);
  double brute_difference=0;
  for(U j=0;j<16;j++){
   size_t t=size_t(j*2654435761u)%(indices.size()/3)*3;
   V point=mul(add(add(p[indices[t]],p[indices[t+1]]),p[indices[t+2]]),1.0/3);
   double brute=1e30f;
   for(size_t k=0;k<output.size();k+=3)brute=std::min(brute,distance_triangle(point,p[output[k]],p[output[k+1]],p[output[k+2]]));
   brute_difference=std::max(brute_difference,std::fabs(std::sqrt(brute)-coarse.distance(point)));
  }
  if(brute_difference>.00001f)return 11;
  std::string name=std::string(argv[2])+"_"+std::to_string(level)+".bin";
  f=fopen(name.c_str(),"wb");if(!f)return 9;U out_count=U(count);fwrite(&nv,4,1,f);fwrite(&out_count,4,1,f);fwrite(positions.data(),12,nv,f);fwrite(output.data(),4,count,f);fclose(f);
  printf("{\"level\":%d,\"requested_error\":%.8f,\"reported_error\":%.8f,\"sampled_forward\":%.8f,\"sampled_reverse\":%.8f,\"self_error\":%.8f,\"bvh_bruteforce_difference\":%.8f,\"simplify_ms\":%.6f,\"triangles\":%zu}\n",level,budget,reported,forward,reverse,self_error,brute_difference,elapsed,count/3);
 }
}
