// SPDX-License-Identifier: 0BSD
// Single planar 2:1 interfaces in real fields. Not runtime transition placement.
#include "core.h"
#include "transvoxel_probe_cells.hpp"
struct Audit{int open=0,overused=0,winding=0,degenerate=0;};
static Audit audit(const std::vector<T>&mesh,P low,P high){
 struct Use{int count=0,balance=0;};std::map<E,Use> edges;Audit out;
 for(const auto&t:mesh){
  double a[3],b[3],area=0;for(int k=0;k<3;k++){a[k]=double(t[1][k])-t[0][k];b[k]=double(t[2][k])-t[0][k];}
  for(int k=0;k<3;k++){double v=a[(k+1)%3]*b[(k+2)%3]-a[(k+2)%3]*b[(k+1)%3];area+=v*v;}out.degenerate+=area==0;
  for(int k=0;k<3;k++){P a=t[k],b=t[(k+1)%3];bool reverse=b<a;if(reverse)std::swap(a,b);auto&u=edges[{a,b}];u.count++;u.balance+=reverse?-1:1;}
 }
 for(const auto&item:edges){const auto&e=item.first;const auto&u=item.second;
  out.overused+=u.count>2;out.winding+=u.count==2&&u.balance!=0;
  if(u.count==1){bool exterior=false;for(int k=0;k<3;k++)exterior|=e[0][k]==e[1][k]&&(e[0][k]==low[k]||e[0][k]==high[k]);out.open+=!exterior;}
 }return out;
}
static double field(const World&w,P p){
 int x=int(std::floor(p[0])),y=int(std::floor(p[1])),z=int(std::floor(p[2]));double result=0;
 for(int k=0;k<8;k++){int dx=k&1,dy=(k>>1)&1,dz=(k>>2)&1;
  double wx=dx?p[0]-x:1-(p[0]-x),wy=dy?p[1]-y:1-(p[1]-y),wz=dz?p[2]-z:1-(p[2]-z);
  result+=wx*wy*wz*w.sample(x+dx,y+dy,z+dz);
 }return result;
}
int main(){
 tr_alloc=std::malloc;tr_realloc=std::realloc;tr_free=std::free;int failures=0;
 for(int site:{1024,1408}){
  World w;w.init();P center={float(site),float(int(w.height(float(site),float(site)))-1),float(site)};
  std::vector<T> previous[24];
  for(int edited=0;edited<2;edited++){
   if(edited){V3 p={center[0],center[1],center[2]},lo,hi;int changes=0;if(!w.edit(p,p,2.5f,0,false,1,lo,hi,changes))return 2;}
   for(int face=0;face<6;face++)for(int si=0;si<4;si++){
    int step=1<<si,queries=0,zeros=0;std::vector<T> mesh;
    auto point=[&](float u,float v,float t){P p=transform({u,v,t},face,0);for(int k=0;k<3;k++)p[k]+=center[k];return p;};
    auto sample=[&](int u,int v,int t,float geometry_t){P p=point(float(u),float(v),float(t));float d=w.sample(int(p[0]),int(p[1]),int(p[2]));queries++;zeros+=d==0;return Sample{point(float(u),float(v),geometry_t),d};};
    // The fine boundary moves inward by step/4. The coarse boundary remains
    // at the shared world plane. Both use densities at that original plane.
    for(int v=-16;v<16;v+=step)for(int u=-16;u<16;u+=step){
     std::array<Sample,8>s;for(int k=0;k<8;k++){int t=((k>>2)&1)?0:-step;s[k]=sample(u+(k&1)*step,v+((k>>1)&1)*step,t,t==0?-.25f*step:float(t));}regular(s,mesh);
    }
    size_t fine_count=mesh.size();
    for(int v=-16;v<16;v+=2*step)for(int u=-16;u<16;u+=2*step){
     std::array<Sample,13>s;for(int k=0;k<9;k++)s[k]=sample(u+(k%3)*step,v+(k/3)*step,0,-.25f*step);
     for(int k=0;k<4;k++)s[9+k]=sample(u+(k&1)*2*step,v+((k>>1)&1)*2*step,0,0);transition(s,mesh);
    }
    size_t transition_count=mesh.size()-fine_count;double transition_residual=0;
    for(size_t i=fine_count;i<mesh.size();i++){
     P midpoint{};for(int k=0;k<3;k++){for(int a=0;a<3;a++)midpoint[a]+=mesh[i][k][a]/3.f;transition_residual=std::max(transition_residual,std::abs(field(w,mesh[i][k])));}
     transition_residual=std::max(transition_residual,std::abs(field(w,midpoint)));
    }
    for(int v=-16;v<16;v+=2*step)for(int u=-16;u<16;u+=2*step){
     std::array<Sample,8>s;for(int k=0;k<8;k++){int t=((k>>2)&1)*2*step;s[k]=sample(u+(k&1)*2*step,v+((k>>1)&1)*2*step,t,float(t));}regular(s,mesh);
    }
    Audit a=audit(mesh,point(-16,-16,float(-step)),point(16,16,float(2*step)));
    bool changed=edited&&mesh!=previous[face*4+si];if(!edited)previous[face*4+si]=mesh;
    bool passed=!(a.open||a.overused||a.winding||a.degenerate);failures+=!passed;
    printf("{\"site\":%d,\"center_y\":%.0f,\"edited\":%d,\"face\":%d,\"fine_step\":%d,\"sample_queries\":%d,\"zero_queries\":%d,\"fine_triangles\":%zu,\"transition_triangles\":%zu,\"coarse_triangles\":%zu,\"boundary_displacement_m\":%.3f,\"transition_max_sampled_abs_density\":%.9g,\"mesh_changed_after_edit\":%s,\"internal_open_edges\":%d,\"overused_edges\":%d,\"winding_errors\":%d,\"degenerate_triangles\":%d,\"passed\":%s}\n",site,center[1],edited,face,step,queries,zeros,fine_count,transition_count,mesh.size()-fine_count-transition_count,.25*step,transition_residual,changed?"true":"false",a.open,a.overused,a.winding,a.degenerate,passed?"true":"false");fflush(stdout);
   }
  }w.release();
 }return failures?1:0;
}
