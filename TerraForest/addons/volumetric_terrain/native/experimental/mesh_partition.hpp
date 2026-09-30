// SPDX-License-Identifier: 0BSD
#pragma once
#include "../core.h"
#include "snapshot_memory_budget.hpp"
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <cmath>

namespace terraforest::experimental {
struct PartitionLimits {
 size_t workspace_bytes=128*1024*1024,output_bytes=128*1024*1024;
 BufferAllocator allocator;
 bool(*cancelled)(void*)=nullptr;void*context=nullptr;
};
struct PartitionStats{size_t workspace_peak=0,denied=0;bool cancelled=false;};
template<class T>struct PartitionList {
 FallibleBuffer<T> values;int n=0;
 void configure(BufferAllocator allocator){values.set_allocator(allocator);n=0;}
 bool resize(int size){if(!values.resize(size))return false;n=size;return true;}
 bool push(const T&v){if(values.size()==values.capacity()&&!values.reserve(values.capacity()+values.capacity()/2+16))return false;values.push_back(v);n++;return true;}
 void release(){values.clear();n=0;}
 T&operator[](size_t at){return values[at];}
};
struct PartitionMesh{PartitionList<Vertex> v;PartitionList<u32> i;void release(){v.release();i.release();}};
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
static godot::Array partition_mesh(const godot::PackedByteArray&packet,const PartitionLimits&limits={},PartitionStats*stats=nullptr){
 SnapshotMemoryBudget budget(limits.workspace_bytes,limits.allocator);
 struct Report{SnapshotMemoryBudget&budget;PartitionStats*stats;~Report(){if(stats){stats->workspace_peak=budget.peak();stats->denied=budget.denied();}}}report{budget,stats};
 auto cancelled=[&](){bool value=limits.cancelled&&limits.cancelled(limits.context);if(value&&stats)stats->cancelled=true;return value;};
 if(cancelled())return {};
 if(packet.size()<36||packet.size()>64*1024*1024)return {};
 Reader header{packet.ptr(),int(packet.size())};
 if(header.u()!=MESH_MAGIC||header.u()!=5)return {};
 u32 x=header.u(),z=header.u(),size=header.u(),step=header.u(),nv=header.u(),ni=header.u(),nf=header.u();
 if((size!=32&&size!=64&&size!=128&&size!=256)||x>=2048||z>=2048||x%size||z%size||step<1||step>8||nv>1000000||ni>1500000||ni%3||nf>ni||nf%3||36+u64(nv)*56+u64(ni)*4+u64(nf)*12!=u64(packet.size()))return {};
 PartitionMesh source,children[4];PartitionList<u32> original_indices;
 source.v.configure(budget.allocator());source.i.configure(budget.allocator());original_indices.configure(budget.allocator());
 for(auto&m:children){m.v.configure(budget.allocator());m.i.configure(budget.allocator());}
 auto cleanup=[&](){source.release();original_indices.release();for(auto&m:children)m.release();};
 if(!source.v.resize(int(nv))||!source.i.resize(int(ni))||!original_indices.resize(int(nv*4))){cleanup();return {};}
 for(int i=0;i<original_indices.n;i++)original_indices[i]=0xffffffffu;
 Reader r{packet.ptr(),int(packet.size()),36};
 for(u32 i=0;i<nv;i++){source.v[i].p=r.vec();source.v[i].cx=int(i);source.v[i].cy=1;}
 for(u32 i=0;i<nv;i++)source.v[i].n=r.vec();
 for(u32 i=0;i<nv;i++){source.v[i].sky=r.f();source.v[i].sun=r.f();}
 for(u32 i=0;i<nv;i++){source.v[i].material=r.f();float lod=r.f();if(!std::isfinite(lod)){cleanup();return {};}}
 for(u32 i=0;i<nv;i++){source.v[i].blend=r.vec();source.v[i].substrate=r.f();}
 for(u32 i=0;i<nv;i++){
  if((i&255)==0&&cancelled()){cleanup();return {};}
  const auto&v=source.v[i];
  if(ab(v.p.x)>10000||ab(v.p.y)>10000||ab(v.p.z)>10000){cleanup();return {};}
  for(float value:{v.p.x,v.p.y,v.p.z,v.n.x,v.n.y,v.n.z,v.sky,v.sun,v.material,v.blend.x,v.blend.y,v.blend.z,v.substrate})
   if(!std::isfinite(value)){cleanup();return {};}
 }
 for(u32 i=0;i<ni;i++){source.i[i]=r.u();if(source.i[i]>=nv){cleanup();return {};}}
 const float px=float(x+size/2),pz=float(z+size/2);
 for(u32 i=0;i<ni;i+=3){
  if((i%768)==0&&cancelled()){cleanup();return {};}
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
     if(index==0xffffffffu){index=u32(m.v.n);if(!m.v.push(v)){cleanup();return {};}if(v.cy==1)original_indices[child*nv+u32(v.cx)]=index;}
     if(!m.i.push(index)){cleanup();return {};}
    }
   }
  }
 }
 godot::Array result;u64 encoded_total=0;
 for(int child=0;child<4;child++){
  if(cancelled()){cleanup();return {};}
  auto&m=children[child];const u32 faces=size/2<=32&&step==1?u32(m.i.n):0;
  const u64 length=36+u64(m.v.n)*56+u64(m.i.n)*4+u64(faces)*12;
  if(encoded_total>limits.output_bytes||length>limits.output_bytes-encoded_total){cleanup();return {};}
  encoded_total+=length;godot::PackedByteArray bytes;
  if(bytes.resize(int64_t(length))!=godot::OK){cleanup();return {};}
  u8*out=bytes.ptrw();size_t at=0;
  auto write=[&](const void*p,size_t n){copy_bytes(out+at,p,n);at+=n;};
  auto integer=[&](u32 v){write(&v,4);};auto scalar=[&](float v){write(&v,4);};auto vector=[&](V3 v){write(&v,12);};
  for(u32 value:{MESH_MAGIC,5u,x+(child&1)*size/2,z+((child>>1)&1)*size/2,size/2,step,u32(m.v.n),u32(m.i.n),faces})integer(value);
  // Check between bounded batches even during large planar-channel copies.
  for(int channel=0;channel<5;channel++)for(int i=0;i<m.v.n;i++){
   if((i&255)==0&&cancelled()){cleanup();return {};}
   const auto&v=m.v[i];
   if(channel==0)vector(v.p);
   else if(channel==1)vector(v.n);
   else if(channel==2){scalar(v.sky);scalar(v.sun);}
   else if(channel==3){scalar(v.material>=5?v.material:0.f);scalar(float(step));}
   else{vector(v.blend);scalar(v.substrate);}
  }
  for(int i=0;i<m.i.n;i++){if((i&255)==0&&cancelled()){cleanup();return {};}integer(m.i[i]);}
  for(u32 i=0;i<faces;i++){if((i&255)==0&&cancelled()){cleanup();return {};}vector(m.v[m.i[i]].p);}
  result.push_back(bytes);
 }
 cleanup();if(cancelled())return {};return result;
}
}
