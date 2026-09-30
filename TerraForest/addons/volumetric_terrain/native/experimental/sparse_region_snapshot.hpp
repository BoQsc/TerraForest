// SPDX-License-Identifier: 0BSD
#pragma once
#include "world_region_sampler.hpp"

namespace terraforest::experimental {
// Geometry-only bounded owner. Caller protects World during capture; no source
// pointers survive capture. Generation stays outside that protected interval.
class SparseRegionSnapshot {
 FallibleBuffer<Cave> caves_;
 FallibleBuffer<i16> pages_;
 int indices_[153]={}; // At most 3 x 3 x 17 intersecting pages for width <= 32.
 int x_=0,z_=0,size_=0,px_=0,pz_=0,nx_=0,nz_=0,seed_=0,revision_=-1;
 int lookups_=0;
 MeshStatus status_=MeshStatus::invalid_input;
public:
 SparseRegionSnapshot()=default;
 SparseRegionSnapshot(const SparseRegionSnapshot&)=delete;
 SparseRegionSnapshot&operator=(const SparseRegionSnapshot&)=delete;
 SparseRegionSnapshot(SparseRegionSnapshot&&other)noexcept{*this=std::move(other);}
 SparseRegionSnapshot&operator=(SparseRegionSnapshot&&other)noexcept{
  if(this==&other)return *this;
  caves_=std::move(other.caves_);pages_=std::move(other.pages_);
  std::copy(other.indices_,other.indices_+153,indices_);
  x_=other.x_;z_=other.z_;size_=other.size_;px_=other.px_;pz_=other.pz_;
  nx_=other.nx_;nz_=other.nz_;seed_=other.seed_;revision_=other.revision_;
  lookups_=other.lookups_;status_=other.status_;
  other.status_=MeshStatus::invalid_input;other.revision_=-1;other.lookups_=0;
  return *this;
 }
 int revision()const{return revision_;}
 int lookups()const{return lookups_;}
 size_t bytes()const{return caves_.size()*sizeof(Cave)+pages_.size()*sizeof(i16)+sizeof(indices_);}
 MeshStatus capture(const World&w,int x,int z,int size,const MeshLimits&limits=MeshLimits{}){
  caves_.clear();pages_.clear();revision_=-1;lookups_=0;status_=MeshStatus::invalid_input;
  if(!valid_region(x,z,size,limits)||!w.edit_columns||w.caves.n>64)return status_;
  if(limits.cancelled())return status_=MeshStatus::cancelled;
  x_=x;z_=z;size_=size;px_=x>>4;pz_=z>>4;
  nx_=((x+size)>>4)-px_+1;nz_=((z+size)>>4)-pz_+1;
  caves_.set_allocator(limits.sampler_allocator);pages_.set_allocator(limits.sampler_allocator);
  int sources[153],count=0,at=0;constexpr int np=WORLD/PAGE+1;
  for(int y=0;y<=WORLD_Y/PAGE;y++)for(int dz=0;dz<nz_;dz++)for(int dx=0;dx<nx_;dx++){
   if(limits.cancelled())return status_=MeshStatus::cancelled;
   int source=w.pages_by_key.get(u32(px_+dx+np*(pz_+dz+np*y))+1);lookups_++;
   indices_[at++]=source<0?-1:count;
   if(source>=0)sources[count++]=source;
  }
  if(!caves_.resize(w.caves.n)||!pages_.resize(size_t(count)*PAGE_SAMPLES)){
   caves_.clear();pages_.clear();return status_=MeshStatus::allocation_failed;
  }
  for(int i=0;i<w.caves.n;i++)caves_[i]=w.caves[i];
  for(int i=0;i<count;i++){
   if(limits.cancelled()){caves_.clear();pages_.clear();return status_=MeshStatus::cancelled;}
   std::copy(w.pages[sources[i]].d,w.pages[sources[i]].d+PAGE_SAMPLES,pages_.data()+size_t(i)*PAGE_SAMPLES);
  }
  if(limits.cancelled()){caves_.clear();pages_.clear();return status_=MeshStatus::cancelled;}
  seed_=w.seed;revision_=w.revision;return status_=MeshStatus::ok;
 }
 Result mesh(const MeshLimits&limits=MeshLimits{})const{
  Result failed;if(status_!=MeshStatus::ok){failed.status=status_;return failed;}
  if(limits.cancelled()){failed.status=MeshStatus::cancelled;return failed;}
  // Non-owning procedural view into this snapshot only. Never init/release it.
  World generator;generator.seed=seed_;generator.caves.p=const_cast<Cave*>(caves_.data());generator.caves.n=int(caves_.size());
  FallibleBuffer<float> planes,heights;planes.set_allocator(limits.sampler_allocator);heights.set_allocator(limits.sampler_allocator);
  int n=size_+1;size_t plane=size_t(n)*n;
  if(!planes.resize(2*plane)||!heights.resize(plane)){failed.status=MeshStatus::allocation_failed;return failed;}
  for(int z=0;z<n;z++)for(int x=0;x<n;x++)heights[x+n*z]=generator.height(float(x_+x),float(z_+z));
  auto fill=[&](int y,float*out){
   for(int z=0;z<n;z++)for(int x=0;x<n;x++){
    int wx=x_+x,wz=z_+z;
    int page=indices_[((wx>>4)-px_)+nx_*(((wz>>4)-pz_)+nz_*(y>>4))];
    float d=page<0?generator.base({float(wx),float(y),float(wz)},heights[x+n*z]):float(pages_[size_t(page)*PAGE_SAMPLES+(wx&15)+16*((wz&15)+16*(y&15))])/SDF_SCALE;
    out[x+n*z]=density_value(d);
   }
  };
  fill(0,planes.data());fill(1,planes.data()+plane);
  return mesh_layers(x_,z_,size_,true,[&](int y){
   if(y){std::copy(planes.begin()+plane,planes.end(),planes.begin());fill(y+1,planes.data()+plane);}
   return planes.data();
  },limits);
 }
};
}
