// Isolated position-only LOD test, not a runtime addon.
#include "meshoptimizer.h"
#include <array>
#include <vector>
#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cmath>
#include <string>
using U=unsigned int;
struct V{double x,y,z;};
static V sub(V a,V b){return {a.x-b.x,a.y-b.y,a.z-b.z};}
static V add(V a,V b){return {a.x+b.x,a.y+b.y,a.z+b.z};}
static V mul(V a,double t){return {a.x*t,a.y*t,a.z*t};}
static double dot(V a,V b){return a.x*b.x+a.y*b.y+a.z*b.z;}
static double now(){return std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now().time_since_epoch()).count();}
static double distance_triangle(V p,V a,V b,V c){
 V ab=sub(b,a),ac=sub(c,a),ap=sub(p,a);double d1=dot(ab,ap),d2=dot(ac,ap);
 if(d1<=0&&d2<=0)return dot(ap,ap);
 V bp=sub(p,b);double d3=dot(ab,bp),d4=dot(ac,bp);if(d3>=0&&d4<=d3)return dot(bp,bp);
 double vc=d1*d4-d3*d2;
 if(vc<=0&&d1>=0&&d3<=0){V v=sub(ap,mul(ab,d1/(d1-d3)));return dot(v,v);}
 V cp=sub(p,c);double d5=dot(ab,cp),d6=dot(ac,cp);if(d6>=0&&d5<=d6)return dot(cp,cp);
 double vb=d5*d2-d1*d6;
 if(vb<=0&&d2>=0&&d6<=0){V v=sub(ap,mul(ac,d2/(d2-d6)));return dot(v,v);}
 double va=d3*d6-d5*d4;
 if(va<=0&&(d4-d3)>=0&&(d5-d6)>=0){V v=sub(bp,mul(sub(c,b),(d4-d3)/((d4-d3)+(d5-d6))));return dot(v,v);}
 double denom=va+vb+vc;
 if(denom==0)return std::min({dot(ap,ap),dot(bp,bp),dot(cp,cp)});
 V v=sub(ap,add(mul(ab,vb/denom),mul(ac,vc/denom)));return dot(v,v);
}
struct BVH{
 struct Node{V lo,hi;int begin,end,left=-1,right=-1;};
 const std::vector<V>&p;const std::vector<U>&idx;std::vector<U>order;std::vector<Node>nodes;
 BVH(const std::vector<V>&v,const std::vector<U>&i):p(v),idx(i){for(U t=0;t<i.size()/3;t++)order.push_back(t);build(0,int(order.size()));}
 double axis(V v,int a)const{return a==0?v.x:a==1?v.y:v.z;}
 V center(U t)const{return mul(add(add(p[idx[t*3]],p[idx[t*3+1]]),p[idx[t*3+2]]),1.0/3);}
 int build(int begin,int end){
  Node n{{1e30f,1e30f,1e30f},{-1e30f,-1e30f,-1e30f},begin,end};
  for(int j=begin;j<end;j++)for(int k=0;k<3;k++){V v=p[idx[order[j]*3+k]];n.lo={std::min(n.lo.x,v.x),std::min(n.lo.y,v.y),std::min(n.lo.z,v.z)};n.hi={std::max(n.hi.x,v.x),std::max(n.hi.y,v.y),std::max(n.hi.z,v.z)};}
  int at=int(nodes.size());nodes.push_back(n);
  if(end-begin>8){V extent=sub(n.hi,n.lo);int a=extent.x>extent.y?0:1;if(extent.z>axis(extent,a))a=2;int mid=(begin+end)/2;
   std::nth_element(order.begin()+begin,order.begin()+mid,order.begin()+end,[&](U l,U r){return axis(center(l),a)<axis(center(r),a);});
   int left=build(begin,mid),right=build(mid,end);nodes[at].left=left;nodes[at].right=right;
  }return at;
 }
 double box(V p,const Node&n)const{double sum=0;for(int a=0;a<3;a++){double v=axis(p,a),d=std::max({axis(n.lo,a)-v,0.0,v-axis(n.hi,a)});sum+=d*d;}return sum;}
 void query(int at,V point,double&best)const{
  const Node&n=nodes[at];if(box(point,n)>best)return;
  if(n.left<0){for(int i=n.begin;i<n.end;i++){U t=order[i]*3;best=std::min(best,distance_triangle(point,p[idx[t]],p[idx[t+1]],p[idx[t+2]]));}return;}
  int a=n.left,b=n.right;if(box(point,nodes[a])>box(point,nodes[b]))std::swap(a,b);query(a,point,best);query(b,point,best);
 }
 double distance(V point)const{double result=1e30f;query(0,point,result);return std::sqrt(result);}
};
static double sampled_error(const std::vector<V>&p,const std::vector<U>&indices,const BVH&target){
 std::vector<bool>seen(p.size());double result=0;
 for(size_t t=0;t<indices.size();t+=3){V center{};for(int k=0;k<3;k++){U i=indices[t+k];center=add(center,p[i]);if(!seen[i]){seen[i]=true;result=std::max(result,target.distance(p[i]));}}result=std::max(result,target.distance(mul(center,1.0/3)));}return result;
}
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
