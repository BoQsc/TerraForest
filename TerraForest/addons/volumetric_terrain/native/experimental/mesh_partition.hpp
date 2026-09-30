// SPDX-License-Identifier: 0BSD
#pragma once
#include "../core.h"
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <cmath>

namespace terraforest::experimental {
// Pure geometric partition: no field access, simplification or changed surface.
// Intersections use canonical endpoint order so adjacent children share bits.
static float component(V3 p,int axis){return axis==0?p.x:p.z;}
static Vertex intersection(Vertex a,Vertex b,int axis,float plane){
 if(component(a.p,axis)>component(b.p,axis)){auto swap=a;a=b;b=swap;}
 const double t=(double(plane)-component(a.p,axis))/(double(component(b.p,axis))-component(a.p,axis));
 auto lerp=[&](float x,float y){return float(double(x)+(double(y)-x)*t);};
 auto vec=[&](V3 x,V3 y){return V3{lerp(x.x,y.x),lerp(x.y,y.y),lerp(x.z,y.z)};};
 Vertex v;v.p=vec(a.p,b.p);if(axis==0)v.p.x=plane;else v.p.z=plane;
 v.n=vec(a.n,b.n);v.blend=vec(a.blend,b.blend);v.substrate=lerp(a.substrate,b.substrate);
 v.sky=lerp(a.sky,b.sky);v.sun=lerp(a.sun,b.sun);v.material=lerp(a.material,b.material);return v;
}
static int clip(const Vertex*input,int count,Vertex*output,int axis,float plane,bool upper){
 int n=0;
 for(int i=0;i<count;i++){
  const auto&a=input[i];const auto&b=input[(i+1)%count];
  float av=component(a.p,axis),bv=component(b.p,axis);
  bool ai=upper?av>=plane:av<=plane,bi=upper?bv>=plane:bv<=plane;
  if(ai)output[n++]=a;
  if(ai!=bi)output[n++]=intersection(a,b,axis,plane);
 }
 return n;
}
static godot::Array partition_mesh(const godot::PackedByteArray&packet){
 if(packet.size()<36||packet.size()>64*1024*1024)return {};
 Reader header{packet.ptr(),int(packet.size())};
 if(header.u()!=MESH_MAGIC||header.u()!=5)return {};
 u32 x=header.u(),z=header.u(),size=header.u(),step=header.u(),nv=header.u(),ni=header.u(),nf=header.u();
 if((size!=32&&size!=64&&size!=128&&size!=256)||x>=2048||z>=2048||x%size||z%size||step<1||step>8||nv>1000000||ni>1500000||ni%3||nf>ni||nf%3||36+u64(nv)*56+u64(ni)*4+u64(nf)*12!=u64(packet.size()))return {};
 Mesh source,children[4];List<u32> original_indices;tr_oom=false;source.v.resize(int(nv));source.i.resize(int(ni));original_indices.resize(int(nv*4));
 auto cleanup=[&](){source.release();original_indices.release();for(auto&m:children)m.release();};
 if(tr_oom){cleanup();return {};}
 for(int i=0;i<original_indices.n;i++)original_indices[i]=0xffffffffu;
 Reader r{packet.ptr(),int(packet.size()),36};
 for(u32 i=0;i<nv;i++){source.v[i].p=r.vec();source.v[i].cx=int(i);source.v[i].cy=1;}
 for(u32 i=0;i<nv;i++)source.v[i].n=r.vec();
 for(u32 i=0;i<nv;i++){source.v[i].sky=r.f();source.v[i].sun=r.f();}
 for(u32 i=0;i<nv;i++){source.v[i].material=r.f();float lod=r.f();if(!std::isfinite(lod)){cleanup();return {};}}
 for(u32 i=0;i<nv;i++){source.v[i].blend=r.vec();source.v[i].substrate=r.f();}
 for(u32 i=0;i<nv;i++){
  const auto&v=source.v[i];
  if(ab(v.p.x)>10000||ab(v.p.y)>10000||ab(v.p.z)>10000){cleanup();return {};}
  for(float value:{v.p.x,v.p.y,v.p.z,v.n.x,v.n.y,v.n.z,v.sky,v.sun,v.material,v.blend.x,v.blend.y,v.blend.z,v.substrate})
   if(!std::isfinite(value)){cleanup();return {};}
 }
 for(u32 i=0;i<ni;i++){source.i[i]=r.u();if(source.i[i]>=nv){cleanup();return {};}}
 const float px=float(x+size/2),pz=float(z+size/2);
 for(u32 i=0;i<ni;i+=3){
  Vertex triangle[3]={source.v[source.i[i]],source.v[source.i[i+1]],source.v[source.i[i+2]]};
  float minx=mn(triangle[0].p.x,mn(triangle[1].p.x,triangle[2].p.x)),maxx=mx(triangle[0].p.x,mx(triangle[1].p.x,triangle[2].p.x));
  float minz=mn(triangle[0].p.z,mn(triangle[1].p.z,triangle[2].p.z)),maxz=mx(triangle[0].p.z,mx(triangle[1].p.z,triangle[2].p.z));
  for(int child=0;child<4;child++){
   bool right=child&1,back=child&2;
   // A triangle coplanar with a split belongs to the upper half exactly once.
   if((right?maxx<px:minx>=px)||(back?maxz<pz:minz>=pz))continue;
   Vertex a[8],b[8];int count=clip(triangle,3,a,0,px,right);if(count<3)continue;
   count=clip(a,count,b,2,pz,back);if(count<3)continue;
   auto&m=children[child];
   for(int j=1;j+1<count;j++){
    V3 area=cross(b[j].p-b[0].p,b[j+1].p-b[0].p);if(dot(area,area)==0)continue;
    if(m.i.n>1500000-3){cleanup();return {};}
    for(int at:{0,j,j+1}){
     const auto&v=b[at];u32 index=0xffffffffu;
     if(v.cy==1)index=original_indices[child*nv+u32(v.cx)];
     if(index==0xffffffffu){index=u32(m.v.n);m.v.push(v);if(v.cy==1)original_indices[child*nv+u32(v.cx)]=index;}
     m.i.push(index);
    }
    u64 allocated=u64(source.v.cap)*sizeof(Vertex)+u64(source.i.cap)*sizeof(u32)+u64(original_indices.cap)*sizeof(u32);
    for(auto&part:children)allocated+=u64(part.v.cap)*sizeof(Vertex)+u64(part.i.cap)*sizeof(u32);
    if(tr_oom||allocated>128*1024*1024){cleanup();return {};}
   }
  }
 }
 godot::Array result;u64 encoded_total=0;
 for(int child=0;child<4;child++){
  Bytes encoded;encode_mesh(children[child],int(x+(child&1)*size/2),int(z+((child>>1)&1)*size/2),int(size/2),int(step),encoded);
  encoded_total+=encoded.n;godot::PackedByteArray bytes;
  if(tr_oom||encoded_total>128*1024*1024||bytes.resize(encoded.n)!=godot::OK){encoded.release();cleanup();return {};}
  if(encoded.n)copy_bytes(bytes.ptrw(),encoded.p,encoded.n);encoded.release();result.push_back(bytes);
 }
 cleanup();return result;
}
}
