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
inline bool extract_density_surface(const float *d,unsigned signs,bool refine,DensitySurfaceVertex &out){
 if(signs==0||signs==255)return false;
   V3 p=surface_cell_vertex<V3>(d,signs);
   if(refine){
    for(int iteration=0;iteration<4;iteration++){
     float value=0;V3 grad{};
     for(int k=0;k<8;k++){
      float xx=k&1?p.x:1-p.x,yy=k&2?p.y:1-p.y,zz=k&4?p.z:1-p.z;
      value+=d[k]*xx*yy*zz;
      grad.x+=d[k]*(k&1?1.f:-1.f)*yy*zz;
      grad.y+=d[k]*(k&2?1.f:-1.f)*xx*zz;
      grad.z+=d[k]*(k&4?1.f:-1.f)*xx*yy;
     }
     float g2=dot(grad,grad);if(g2<1e-8f||ab(value)<.0005f)break;
     V3 delta=grad*(value/g2);float dl=length(delta);if(dl>.2f)delta=delta*(.2f/dl);
     p={clampf(p.x-delta.x,.001f,.999f),clampf(p.y-delta.y,.001f,.999f),clampf(p.z-delta.z,.001f,.999f)};
    }
   }
 out.position=p;out.normal=density_surface_normal(d,p);return true;
}
// Disconnected occupied corners need independent representatives. Collapsing
// them creates a four-face edge when an excavation leaves a diagonal contact.
template<class Emit>
inline void extract_density_components(const float *d,unsigned signs,bool refine,Emit emit){
 if(signs==0||signs==255)return;
 unsigned masks[8];int count=surface_components(signs,masks,[](int,int){return true;});
 for(int i=0;i<count;i++){DensitySurfaceVertex vertex;
  if(extract_density_surface(d,masks[i],refine,vertex))emit(vertex,masks[i]);
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
// A multi-component cell selects each neighbour representative using the wet
// endpoint shared by all four cells around the material-crossing edge.
template<class Cells,class Lookup,class FaceAllowed,class Emit>
inline void connect_material_surface(int count,SurfaceOwnership owned,Cells cell,Lookup lookup,FaceAllowed allowed,Emit emit){
 for(int j=0;j<count;++j){
  const auto &v=cell(j);int x=v.cx,y=v.cy,z=v.cz;
  if(!owned.contains(x,y,z))continue;
  surface_component_faces(x,y,z,v.mask,
   [&](int xx,int yy,int zz,int axis){
    int ax=x,ay=y,az=z;
    if(!(v.mask&1)){if(axis==0)++ax;else if(axis==1)++ay;else ++az;}
    return lookup(xx,yy,zz,ax,ay,az);
   },
   [&](int axis,int a,int b,int c,int d,bool reverse){if(allowed(axis,x,y,z))emit(a,b,c,d,reverse);});
 }
}

}
