#include "transvoxel_probe_cells.hpp"
struct Check{int internal_open=0,overused=0,winding=0,degenerate=0;};
static Check check(const std::vector<T>&mesh,int orientation,float origin){
 struct EdgeUse{int count=0,balance=0;};std::map<E,EdgeUse> edges;Check out;
 for(const T&t:mesh){
  double a[3],b[3],cross[3];for(int k=0;k<3;k++){a[k]=double(t[1][k])-t[0][k];b[k]=double(t[2][k])-t[0][k];}
  for(int k=0;k<3;k++)cross[k]=a[(k+1)%3]*b[(k+2)%3]-a[(k+2)%3]*b[(k+1)%3];
  if(cross[0]*cross[0]+cross[1]*cross[1]+cross[2]*cross[2]==0)out.degenerate++;
  for(int k=0;k<3;k++){P a=t[k],b=t[(k+1)%3];bool reverse=b<a;if(reverse)std::swap(a,b);auto&e=edges[{a,b}];e.count++;e.balance+=reverse?-1:1;}
 }
 P low=transform({0,0,-1},orientation,origin),high=transform({2,2,3},orientation,origin);
 for(const auto&item:edges){const auto&e=item.first;const auto&use=item.second;
  if(use.count>2)out.overused++;
  if(use.count==2&&use.balance)out.winding++;
  if(use.count==1){bool exterior=false;for(int k=0;k<3;k++)exterior|=e[0][k]==e[1][k]&&(e[0][k]==low[k]||e[0][k]==high[k]);out.internal_open+=!exterior;}
 }return out;
}
int main(){
 int failures=0,total=0;
 for(int magnitude=0;magnitude<5;magnitude++)for(int orientation=0;orientation<6;orientation++){
  Check sum;int bad_cases=0,first=-1;
  for(unsigned pattern=0;pattern<512;pattern++){
   float d[9];for(unsigned i=0;i<9;i++){
    float amount=magnitude==0?1.f:magnitude==1?float(1+(i*13+pattern*7)%31)/8.f:((i+pattern)%3?4.f:.5f/1024);
    d[i]=(pattern&(1u<<i))?-amount:amount;
    if(magnitude>=3&&(i+pattern)%3==0)d[i]=0.f;
   }
   float origin=magnitude>=2?1920.f:0.f;
   auto sample=[&](int x,int y,float z){return Sample{transform({float(x),float(y),z},orientation,origin),d[x+y*3]};};
   std::vector<T> mesh;
   for(int y=0;y<2;y++)for(int x=0;x<2;x++){
    std::array<Sample,8>s;for(int k=0;k<8;k++)s[k]=sample(x+(k&1),y+((k>>1)&1),float(-1+((k>>2)&1)));regular(s,mesh,magnitude!=3);
   }
   std::array<Sample,13>s;for(int i=0;i<9;i++)s[i]=sample(i%3,i/3,0);
   for(int i=0;i<4;i++)s[9+i]=sample((i&1)*2,((i>>1)&1)*2,1);
   transition(s,mesh,magnitude!=3);
   std::array<Sample,8>coarse;for(int k=0;k<8;k++)coarse[k]=sample((k&1)*2,((k>>1)&1)*2,float(1+((k>>2)&1)*2));regular(coarse,mesh,magnitude!=3);
   Check c=check(mesh,orientation,origin);bool bad=c.internal_open||c.overused||c.winding||c.degenerate;
   if(bad&&first<0)first=int(pattern);bad_cases+=bad;failures+=bad;total++;
   sum.internal_open+=c.internal_open;sum.overused+=c.overused;sum.winding+=c.winding;sum.degenerate+=c.degenerate;
  }
  printf("{\"magnitude\":%d,\"face\":%d,\"cases\":512,\"failed_cases\":%d,\"first_failed_pattern\":%d,\"internal_open_edges\":%d,\"overused_edges\":%d,\"winding_errors\":%d,\"degenerate_triangles\":%d}\n",magnitude,orientation,bad_cases,first,sum.internal_open,sum.overused,sum.winding,sum.degenerate);
 }
 return failures?1:0;
}
