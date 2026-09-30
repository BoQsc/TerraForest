#include "meshoptimizer.h"
#include "terrain_distance_probe.hpp"

struct Coverage{
 size_t used=0,limit=200000;
 double upper=0;
 bool exhausted=false;
};
static bool cover(V a,V b,V c,const BVH&target,double budget,Coverage&work,int depth=0){
 if(work.used>=work.limit){work.exhausted=true;return false;}work.used++;
 V center=mul(add(add(a,b),c),1.0/3);double nearest_distance=1e30;U t=0;
 target.query(0,center,nearest_distance,&t);
 if(std::sqrt(nearest_distance)>budget)return false;
 V u=target.p[target.idx[t]],v=target.p[target.idx[t+1]],w=target.p[target.idx[t+2]];
 double upper=std::sqrt(std::max({distance_triangle(a,u,v,w),distance_triangle(b,u,v,w),distance_triangle(c,u,v,w)}))+1e-7;
 // Distance to one closed convex triangle is convex. Bounding all three
 // vertices against that SAME triangle covers every point in this subtriangle.
 if(upper<=budget){work.upper=std::max(work.upper,upper);return true;}
 if(depth>=20)return false;
 double ab=dot(sub(a,b),sub(a,b)),bc=dot(sub(b,c),sub(b,c)),ca=dot(sub(c,a),sub(c,a));
 if(ab>=bc&&ab>=ca){V m=mul(add(a,b),.5);return cover(a,m,c,target,budget,work,depth+1)&&cover(m,b,c,target,budget,work,depth+1);}
 if(bc>=ca){V m=mul(add(b,c),.5);return cover(a,b,m,target,budget,work,depth+1)&&cover(a,m,c,target,budget,work,depth+1);}
 V m=mul(add(c,a),.5);return cover(a,b,m,target,budget,work,depth+1)&&cover(m,b,c,target,budget,work,depth+1);
}
static bool covers(const std::vector<V>&p,const std::vector<U>&indices,const BVH&target,double budget,Coverage&work){
 for(size_t i=0;i<indices.size();i+=3)if(!cover(p[indices[i]],p[indices[i+1]],p[indices[i+2]],target,budget,work))return false;
 return true;
}
int main(int argc,char**argv){
 if(argc!=3)return 2;
 FILE*f=fopen(argv[1],"rb");if(!f)return 3;U nv,ni;if(fread(&nv,4,1,f)!=1||fread(&ni,4,1,f)!=1||!nv||!ni||ni%3||nv>2000000||ni>12000000)return 4;
 std::vector<float>positions(size_t(nv)*3);std::vector<U>indices(ni);if(fread(positions.data(),12,nv,f)!=nv||fread(indices.data(),4,ni,f)!=ni)return 5;fclose(f);for(U i:indices)if(i>=nv)return 6;
 std::vector<V>p(nv);for(U i=0;i<nv;i++)p[i]={positions[i*3],positions[i*3+1],positions[i*3+2]};
 double reference_begin=now();BVH reference(p,indices);double reference_ms=now()-reference_begin;
 // Controls: identical triangle is covered; displaced surface is rejected;
 // a zero work allowance cannot certify a candidate.
 std::vector<V>testp={{0,0,0},{1,0,0},{0,1,0}};std::vector<U>testi={0,1,2};BVH test(testp,testi);
 Coverage control;if(!covers(testp,testi,test,.01,control))return 7;
 control=Coverage{};if(cover({0,0,1},{1,0,1},{0,1,1},test,.01,control))return 8;
 control=Coverage{};control.limit=0;if(covers(testp,testi,test,.01,control)||!control.exhausted)return 9;
 for(int level=0;level<2;level++){
  double budget=level==0?.05:.25,begin=now();float requested=float(budget),reported=0;
  std::vector<U>output=indices;Coverage work;bool accepted=false;int attempts=0;double simplify_ms=0,coverage_ms=0;
  for(int attempt=0;attempt<3&&!work.exhausted;attempt++){
   attempts++;std::vector<U>candidate(ni);double tick=now();
   size_t count=meshopt_simplify(candidate.data(),indices.data(),ni,positions.data(),nv,12,std::max(size_t(12),size_t(ni/48)*3),requested,meshopt_SimplifyLockBorder|meshopt_SimplifyErrorAbsolute,&reported);
   simplify_ms+=now()-tick;candidate.resize(count);
   if(!count||count>=ni)break;
   tick=now();BVH coarse(p,candidate);work.upper=0;
   bool valid=covers(p,indices,coarse,budget,work)&&covers(p,candidate,reference,budget,work);
   coverage_ms+=now()-tick;
   if(valid){output=std::move(candidate);accepted=true;break;}
   requested*=.25f;
  }
  double total_ms=now()-begin,upper=accepted?work.upper:0;
  BVH final_mesh(p,output);double forward=sampled_error(p,indices,final_mesh),reverse=sampled_error(p,output,reference);
  if(std::max(forward,reverse)>upper+1e-6)return 10;
  std::string name=std::string(argv[2])+"_"+std::to_string(level)+".bin";f=fopen(name.c_str(),"wb");if(!f)return 11;U count=U(output.size());
  fwrite(&nv,4,1,f);fwrite(&count,4,1,f);fwrite(positions.data(),12,nv,f);fwrite(output.data(),4,count,f);fclose(f);
  printf("{\"level\":%d,\"requested_error\":%.8f,\"reported_error\":%.8f,\"sampled_forward\":%.8f,\"sampled_reverse\":%.8f,\"coverage_upper\":%.8f,\"fallback\":%s,\"attempts\":%d,\"coverage_queries\":%zu,\"coverage_exhausted\":%s,\"simplify_ms\":%.6f,\"coverage_ms\":%.6f,\"reference_bvh_ms\":%.6f,\"admission_ms\":%.6f,\"triangles\":%zu}\n",level,budget,reported,forward,reverse,upper,accepted?"false":"true",attempts,work.used,work.exhausted?"true":"false",simplify_ms,coverage_ms,reference_ms,total_ms,output.size()/3);
 }
}
