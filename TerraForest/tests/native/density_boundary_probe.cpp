// SPDX-License-Identifier: 0BSD
#include "../../addons/volumetric_terrain/native/density_surface.hpp"
#include <vector>
#include <map>
#include <cstdio>
#include <cmath>
using namespace terraforest;
struct Vertex {int cx,cy,cz;unsigned mask;V3 p;};
int main(){
 int failures=0,checked=0;
 for(int variant=0;variant<3;variant++)for(unsigned config=1;config<256;config++){
  std::vector<Vertex> vertices;std::map<int,int> starts,midpoints;float field[64];
  auto key=[](int x,int y,int z){return x+4*(y+4*z);};
  for(int z=0;z<3;z++)for(int y=0;y<3;y++)for(int x=0;x<3;x++){
   float d[8];unsigned signs=0;
   for(int k=0;k<8;k++){
    int xx=x+(k&1),yy=y+((k>>1)&1),zz=z+((k>>2)&1);
    d[k]=1;
    if(xx>=1&&xx<=2&&yy>=1&&yy<=2&&zz>=1&&zz<=2){
     int bit=(xx-1)+2*(yy-1)+4*(zz-1);float magnitude=variant==0?1.f:.2f+float((bit*7+variant*3)%11)*.17f;
     d[k]=(config&(1u<<bit))?-magnitude:magnitude;
    }
    field[key(xx,yy,zz)]=d[k];
    if(d[k]<0)signs|=1u<<k;
   }
   starts[key(x,y,z)]=int(vertices.size());unsigned used=0;
   extract_density_components(d,signs,false,[&](const DensitySurfaceVertex &v,unsigned mask){
    if(used&(mask>>8))failures++;used|=mask>>8;
    if(!std::isfinite(v.position.x+v.position.y+v.position.z))failures++;
    vertices.push_back({x,y,z,mask,v.position+V3{float(x),float(y),float(z)}});
   });
  }
  std::map<std::pair<int,int>,int> edges,balance;
  connect_material_surface(int(vertices.size()),{0,3,0,3,0,3},[&](int i)->const Vertex&{return vertices[i];},
   [&](int x,int y,int z,int ax,int ay,int az,int axis){
    if(x<0||y<0||z<0||x>=3||y>=3||z>=3)return -1;
    unsigned edge=1u<<(8+density_edge_index((ax-x)+2*(ay-y)+4*(az-z),axis));
    for(int i=starts[key(x,y,z)];i<int(vertices.size());i++){
     const auto &v=vertices[i];if(v.cx!=x||v.cy!=y||v.cz!=z)break;if(v.mask&edge)return i;
    }return -1;
   },[](int,int,int,int){return true;},
   [&](int x,int y,int z,int axis,int ex,int ey,int ez,int edge_axis,int,int){
    unsigned arc=0;V3 p=density_face_arc(x,y,z,axis,ex,ey,ez,edge_axis,[&](int xx,int yy,int zz){return field[key(xx,yy,zz)];},arc);
    int idkey=(key(x,y,z)*3+axis)*4+arc;auto found=midpoints.find(idkey);if(found!=midpoints.end())return found->second;
    int id=int(vertices.size());vertices.push_back({x,y,z,0,p});midpoints[idkey]=id;return id;
   },[&](int a,int b,int c,int d,bool reverse,const int *middle){
    surface_split_quad(a,b,c,d,reverse,middle,[&](int i){return vertices[i].p;},
     [&](int a,int b,int c,int d){V3 p=(vertices[a].p+vertices[b].p+vertices[c].p+vertices[d].p)*.25f;
      int id=int(vertices.size());vertices.push_back({0,0,0,0,p});return id;},[&](int a,int b,int c){
     V3 ab=vertices[b].p-vertices[a].p,ac=vertices[c].p-vertices[a].p;V3 n=cross(ab,ac);if(dot(n,n)<1e-14f)failures++;
     int t[3]={a,b,c};for(int j=0;j<3;j++){int u=t[j],v=t[(j+1)%3];edges[{std::min(u,v),std::max(u,v)}]++;balance[{std::min(u,v),std::max(u,v)}]+=u<v?1:-1;}
    });
   });
  int bad=0;for(auto &e:edges)if(e.second!=2||balance[e.first]!=0)bad++;
  if(bad){printf("FAIL config=%u variant=%d bad_edges=%d\n",config,variant,bad);failures++;}
  checked++;
 }
 printf("DENSITY_BOUNDARY checked=%d failures=%d\n",checked,failures);return failures?1:0;
}
