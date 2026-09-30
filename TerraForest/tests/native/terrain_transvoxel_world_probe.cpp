// SPDX-License-Identifier: 0BSD
// Isolated feasibility probe. Third-party tables retain their MIT license.
#include "core.h"
#include "transvoxel_probe_cells.hpp"
#include <chrono>
static double now_ms(){return std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now().time_since_epoch()).count();}
struct Audit{int internal_open=0,overused=0,winding=0,degenerate=0;};
static Audit audit(const std::vector<T>&mesh,int origin){
 struct Use{int count=0,balance=0;};std::map<E,Use> edges;Audit a;
 for(const auto&t:mesh){
  double u[3],v[3],area=0;for(int k=0;k<3;k++){u[k]=double(t[1][k])-t[0][k];v[k]=double(t[2][k])-t[0][k];}
  for(int k=0;k<3;k++){double c=u[(k+1)%3]*v[(k+2)%3]-u[(k+2)%3]*v[(k+1)%3];area+=c*c;}a.degenerate+=area==0;
  for(int k=0;k<3;k++){P p=t[k],q=t[(k+1)%3];bool reverse=q<p;if(reverse)std::swap(p,q);auto&use=edges[{p,q}];use.count++;use.balance+=reverse?-1:1;}
 }
 for(const auto&item:edges){const auto&e=item.first;const auto&u=item.second;
  a.overused+=u.count>2;a.winding+=u.count==2&&u.balance!=0;
  if(u.count==1){bool outside=false;for(int k=0;k<3;k++){float lo=k==1?0.f:float(origin),hi=k==1?256.f:float(origin+256);outside|=e[0][k]==e[1][k]&&(e[0][k]==lo||e[0][k]==hi);}a.internal_open+=!outside;}
 }return a;
}
int main(){
 tr_alloc=std::malloc;tr_realloc=std::realloc;tr_free=std::free;int failures=0;
 for(int origin:{896,1280}){
  World w;w.init();
  for(int edited=0;edited<2;edited++){
   if(edited){V3 p={float(origin+128),w.height(float(origin+128),float(origin+128))-1,float(origin+128)},lo,hi;int changes=0;if(!w.edit(p,p,2.5f,0,false,1,lo,hi,changes))return 2;}
   for(int step:{4,8}){
    int n=256/step+1;size_t count=size_t(n)*n*n;std::vector<float>d(count);std::vector<T> mesh;
    double begin=now_ms();size_t zeros=0;
    for(int z=0;z<n;z++)for(int y=0;y<n;y++)for(int x=0;x<n;x++){
     float value=w.sample(origin+x*step,y*step,origin+z*step);zeros+=value==0;d[x+n*(y+n*z)]=value;
    }
    double sample_ms=now_ms()-begin;begin=now_ms();
    for(int z=0;z<n-1;z++)for(int y=0;y<n-1;y++)for(int x=0;x<n-1;x++){
     std::array<Sample,8>s;for(int k=0;k<8;k++){int dx=x+(k&1),dy=y+((k>>1)&1),dz=z+((k>>2)&1);s[k]={{float(origin+dx*step),float(dy*step),float(origin+dz*step)},d[dx+n*(dy+n*dz)]};}regular(s,mesh);
    }
    double mesh_ms=now_ms()-begin;auto a=audit(mesh,origin);bool passed=!(a.internal_open||a.overused||a.winding||a.degenerate);failures+=!passed;
    printf("{\"origin\":%d,\"edited\":%d,\"step\":%d,\"samples\":%zu,\"zero_samples\":%zu,\"sample_ms\":%.6f,\"mesh_ms\":%.6f,\"triangles\":%zu,\"sample_bytes\":%zu,\"triangle_soup_bytes\":%zu,\"internal_open_edges\":%d,\"overused_edges\":%d,\"winding_errors\":%d,\"degenerate_triangles\":%d,\"passed\":%s}\n",origin,edited,step,count,zeros,sample_ms,mesh_ms,mesh.size(),d.size()*sizeof(float),mesh.size()*sizeof(T),a.internal_open,a.overused,a.winding,a.degenerate,passed?"true":"false");fflush(stdout);
   }
  }w.release();
 }return failures?1:0;
}
