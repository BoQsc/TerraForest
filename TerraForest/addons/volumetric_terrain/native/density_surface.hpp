// SPDX-License-Identifier: 0BSD
#pragma once
#include "platform.h"
#include "surface_cell.hpp"
// Complete density reconstruction and topology stage shared by material fields.
// Storage adapters enumerate candidate cells (including a one-cell negative halo),
// supply immutable corner densities, and retain representative coordinates/masks.
// Material classification, collision, shading and simplification stay outside.
// This stage does not invent sub-grid interfaces: callers must represent them.
namespace terraforest {
struct DensitySurfaceVertex { V3 position,normal; };
inline V3 density_surface_normal(const float*d,V3 p){
 V3 g{};for(int i=0;i<8;i++){float wx=i&1?p.x:1-p.x,wy=i&2?p.y:1-p.y,wz=i&4?p.z:1-p.z;
  g.x+=d[i]*(i&1?1.f:-1.f)*wy*wz;g.y+=d[i]*(i&2?1.f:-1.f)*wx*wz;g.z+=d[i]*(i&4?1.f:-1.f)*wx*wy;}
 return normal(g);
}
// Representatives belong to connected crossing-edge loops, not occupied
// corner groups: separate air pockets can also require separate boundaries.
// Low eight mask bits retain signs; upper twelve select this boundary's edges.
inline int density_edge_index(int corner,int axis){
 return axis==0?((corner>>1)&1)+2*((corner>>2)&1):
        axis==1?4+(corner&1)+2*((corner>>2)&1):8+(corner&1)+2*((corner>>1)&1);
}
template<class Emit>
inline void extract_density_components(const float *d,unsigned signs,bool refine,Emit emit){
 if(signs==0||signs==255)return;
 static constexpr int edges[12][2]={{0,1},{2,3},{4,5},{6,7},{0,2},{1,3},{4,6},{5,7},{0,4},{1,5},{2,6},{3,7}};
 // Both sides of a shared face use the same global axis order.
 static constexpr int faces[6][4]={{0,2,6,4},{1,3,7,5},{0,1,5,4},{2,3,7,6},{0,1,3,2},{4,5,7,6}};
 unsigned crossing=0,links[12]={};
 for(int e=0;e<12;e++)if(((signs>>edges[e][0])&1)!=((signs>>edges[e][1])&1))crossing|=1u<<e;
 auto join=[&](int a,int b){links[a]|=1u<<b;links[b]|=1u<<a;};
 for(const auto &f:faces){
  int fe[4],active[4],n=0;
  for(int j=0;j<4;j++){
   int a=f[j],b=f[(j+1)&3],axis=(a^b)==1?0:(a^b)==2?1:2;
   fe[j]=density_edge_index(a&b,axis);if(crossing&(1u<<fe[j]))active[n++]=fe[j];
  }
  if(n==2)join(active[0],active[1]);
  else if(n==4){
   double determinant=double(d[f[0]])*d[f[2]]-double(d[f[1]])*d[f[3]];
   if(determinant>=0){join(fe[0],fe[1]);join(fe[2],fe[3]);}
   else {join(fe[3],fe[0]);join(fe[1],fe[2]);}
  }
 }
 unsigned unseen=crossing;
 while(unseen){
  unsigned component=unseen&(~unseen+1),frontier=component;unseen^=component;
  while(frontier){unsigned next=0;for(int e=0;e<12;e++)if(frontier&(1u<<e))next|=links[e];
   next&=unseen;unseen^=next;component|=next;frontier=next;}
  V3 p{};int count=0;
  for(int e=0;e<12;e++)if(component&(1u<<e)){
   int a=edges[e][0],b=edges[e][1];float t=d[a]/(d[a]-d[b]);
   V3 va={float(a&1),float((a>>1)&1),float((a>>2)&1)},vb={float(b&1),float((b>>1)&1),float((b>>2)&1)};
   p=p+va+(vb-va)*t;++count;
  }
  p=p/float(count);
  if(refine)for(int iteration=0;iteration<4;iteration++){
   float value=0;V3 grad{};
   for(int k=0;k<8;k++){
    float xx=k&1?p.x:1-p.x,yy=k&2?p.y:1-p.y,zz=k&4?p.z:1-p.z;
    value+=d[k]*xx*yy*zz;grad.x+=d[k]*(k&1?1.f:-1.f)*yy*zz;
    grad.y+=d[k]*(k&2?1.f:-1.f)*xx*zz;grad.z+=d[k]*(k&4?1.f:-1.f)*xx*yy;
   }
   float g2=dot(grad,grad);if(g2<1e-8f||ab(value)<.0005f)break;
   V3 delta=grad*(value/g2);float dl=length(delta);if(dl>.2f)delta=delta*(.2f/dl);
   p={clampf(p.x-delta.x,.001f,.999f),clampf(p.y-delta.y,.001f,.999f),clampf(p.z-delta.z,.001f,.999f)};
  }
  emit(DensitySurfaceVertex{p,density_surface_normal(d,p)},signs|(component<<8));
 }
}
// Enumerate all owned cells and connect to retained halo representatives. The
// storage adapter supplies indexing and emission, so no engine object or heap
// allocation is required by the mesher itself.
struct SurfaceOwnership {
 int x_begin,x_end,y_begin,y_end,z_begin,z_end;
 bool contains(int x,int y,int z)const {
  return x>=x_begin&&x<x_end&&y>=y_begin&&y<y_end&&z>=z_begin&&z<z_end;
 }
};
template<class Cells,class Lookup,class FaceAllowed,class Emit>
inline void connect_density_surface(int count,SurfaceOwnership owned,Cells cell,Lookup lookup,FaceAllowed allowed,Emit emit){
 for(int j=0;j<count;++j){
  const auto &v=cell(j);int x=v.cx,y=v.cy,z=v.cz;
  if(!owned.contains(x,y,z))continue;
  surface_cell_faces(x,y,z,v.mask,
   [&](int xx,int yy,int zz){return xx==x&&yy==y&&zz==z?j:lookup(xx,yy,zz);},
   [&](int axis,int a,int b,int c,int d,bool reverse){
    if(allowed(axis,x,y,z))emit(a,b,c,d,reverse);
   });
 }
}
// A checkerboard face has two distinct contour arcs. Retain a separate point
// on each arc instead of collapsing both to the same dual edge.
template<class Sample>
inline V3 density_face_arc(int x,int y,int z,int axis,int ex,int ey,int ez,int edge_axis,Sample sample,unsigned &arc){
 int u=axis==0?1:0,v=axis==2?1:2;
 int corners[4][3]={{x,y,z},{x,y,z},{x,y,z},{x,y,z}};
 corners[1][u]++;corners[2][u]++;corners[2][v]++;corners[3][v]++;
 float d[4];for(int j=0;j<4;j++)d[j]=sample(corners[j][0],corners[j][1],corners[j][2]);
 int e=0;for(int j=0;j<4;j++){
  int k=(j+1)&3,a[3];for(int q=0;q<3;q++)a[q]=imn(corners[j][q],corners[k][q]);
  int direction=(j&1)?v:u;if(direction==edge_axis&&a[0]==ex&&a[1]==ey&&a[2]==ez){e=j;break;}
 }
 bool diagonal02=double(d[0])*d[2]-double(d[1])*d[3]>=0;
 int other=diagonal02?(e^1):(3-e);arc=unsigned(imn(e,other));
 V3 p{};
 int pair[2]={e,other};for(int edge:pair){int k=(edge+1)&3;float t=d[edge]/(d[edge]-d[k]);
  V3 a={float(corners[edge][0]),float(corners[edge][1]),float(corners[edge][2])};
  V3 b={float(corners[k][0]),float(corners[k][1]),float(corners[k][2])};p=p+a+(b-a)*t;}
 return p*.5f;
}
template<class Position,class Center,class Emit>
inline void surface_split_quad(int a,int b,int c,int d,bool reverse,const int *middle,Position position,Center center,Emit emit){
 if(middle[0]<0&&middle[1]<0&&middle[2]<0&&middle[3]<0){surface_quad(a,b,c,d,reverse,position,emit);return;}
 int base[4]={a,b,c,d},polygon[8],n=0;
 for(int i=0;i<4;i++){polygon[n++]=base[i];if(middle[i]>=0)polygon[n++]=middle[i];}
 int hub=center(a,b,c,d);
 for(int i=0;i<n;i++){int u=polygon[i],v=polygon[(i+1)%n];if(reverse)emit(hub,u,v);else emit(hub,v,u);}
}
// Select neighbours by crossing edge, and subdivide only ambiguous dual edges.
template<class Cells,class Lookup,class FaceAllowed,class Split,class Emit>
inline void connect_material_surface(int count,SurfaceOwnership owned,Cells cell,Lookup lookup,FaceAllowed allowed,Split split,Emit emit){
 static constexpr int offsets[3][3][3]={{{0,-1,-1},{0,0,-1},{0,-1,0}},{{-1,0,-1},{-1,0,0},{0,0,-1}},{{-1,-1,0},{0,-1,0},{-1,0,0}}};
 static constexpr int faces[6][4]={{0,2,6,4},{1,3,7,5},{0,1,5,4},{2,3,7,6},{0,1,3,2},{4,5,7,6}};
 for(int j=0;j<count;++j){
  const auto v=cell(j);int x=v.cx,y=v.cy,z=v.cz;
  if(!owned.contains(x,y,z))continue;
  for(int axis=0;axis<3;axis++){
   if(!(v.mask&(1u<<(8+axis*4)))||!allowed(axis,x,y,z))continue;
   const auto &o=offsets[axis];
   int a=lookup(x+o[0][0],y+o[0][1],z+o[0][2],x,y,z,axis);
   int b=lookup(x+o[1][0],y+o[1][1],z+o[1][2],x,y,z,axis);
   int d=lookup(x+o[2][0],y+o[2][1],z+o[2][2],x,y,z,axis);
   if(a<0||b<0||d<0)continue;
   int ids[4]={a,b,j,d},middle[4]={-1,-1,-1,-1};
   for(int k=0;k<4;k++){
    const auto left=cell(ids[k]),right=cell(ids[(k+1)&3]);
    int normal_axis=left.cx!=right.cx?0:left.cy!=right.cy?1:2;
    int low[3]={left.cx,left.cy,left.cz},high[3]={right.cx,right.cy,right.cz};
    const auto &f=faces[normal_axis*2+(low[normal_axis]<high[normal_axis]?1:0)];unsigned face=0;
    for(int q=0;q<4;q++)face|=((left.mask>>f[q])&1)<<q;
    if(face!=5&&face!=10)continue;
    middle[k]=split(imx(low[0],high[0]),imx(low[1],high[1]),imx(low[2],high[2]),normal_axis,x,y,z,axis,ids[k],ids[(k+1)&3]);
   }
   emit(a,b,j,d,(v.mask&1)==0,middle);
  }
 }
}
}
