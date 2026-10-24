// SPDX-License-Identifier: 0BSD
#pragma once
#include "core.h"
#include "generation_parallel.hpp"
#include <godot_cpp/variant/variant.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <vector>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <chrono>
// Cartographic base survey only. No density pages, meshes or renderer residency.
// Called on an isolated TerrainCore from the map worker; never borrow the live worker.
static godot::Dictionary terraforest_survey_map(const World &w,int64_t size){
 godot::Dictionary out;out["ok"]=false;
 if(size<64||size>512)return out;
 auto start=std::chrono::steady_clock::now();
 std::vector<float> heights(size_t(size)*size);
 float step=float(WORLD)/float(size);
 int workers=terraforest::generation_parallel_for(int(size*size),[&](int index){
  int x=index%size,z=index/size;heights[index]=w.height((x+.5f)*step,(z+.5f)*step);
 });
 godot::PackedByteArray pixels;if(pixels.resize(size*size*4)!=godot::OK)return out;
 auto *p=pixels.ptrw();
 for(int z=0;z<size;++z)for(int x=0;x<size;++x){
  float h=heights[x+z*size];
  float dx=(heights[mn(x+1,int(size)-1)+z*size]-heights[mx(x-1,0)+z*size])/(2*step);
  float dz=(heights[x+mn(z+1,int(size)-1)*size]-heights[x+mx(z-1,0)*size])/(2*step);
  float shade=clampf(.88f+(-dx-dz)*.22f,.52f,1.12f),t=clampf((h-40)/150,0,1);
  float r=90+t*86,g=119+t*35,b=83+t*52;
  // Contour bands remain subtle so roads and labels keep their contrast.
  if(h>0&&int(h)%20==0)shade*=.9f;
  size_t at=(x+z*size)*4;p[at]=u8(clampf(r*shade,0,255));p[at+1]=u8(clampf(g*shade,0,255));p[at+2]=u8(clampf(b*shade,0,255));p[at+3]=255;
 }
 out["ok"]=true;out["pixels"]=pixels;out["size"]=size;out["workers"]=workers;
 out["generation_ms"]=std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-start).count();return out;
}

// Bounded live-world patch. Run only on the ordered terrain worker.
static godot::Dictionary terraforest_survey_patch(const World &w,int size,int ox,int oz,int width,int height){
 godot::Dictionary out;out["ok"]=false;
 if(size<64||size>512||width<1||height<1||width>4||height>4||ox<0||oz<0||ox+width>size||oz+height>size)return out;
 auto start=std::chrono::steady_clock::now();float step=float(WORLD)/size;
 float heights[36];u8 materials[36];int stride=width+2;
 for(int z=-1;z<=height;++z)for(int x=-1;x<=width;++x){
  float wx=(clampf(float(ox+x),0,float(size-1))+.5f)*step,wz=(clampf(float(oz+z),0,float(size-1))+.5f)*step;
  int ix=fl(wx),iz=fl(wz);float dx=wx-ix,dz=wz-iz;
  auto sample=[&](int y,u8 &material){float value=0,largest=-1;material=0;
   for(int k=0;k<4;++k){float weight=(k&1?dx:1-dx)*(k&2?dz:1-dz);if(weight<=0)continue;
    u8 m=0;float d=w.sample(ix+(k&1),y,iz+((k>>1)&1),&m);value+=d*weight;
    if(d<0&&weight>largest){largest=weight;material=m;}}
   return value;};
  float top=0,above=1;u8 material=0;
  for(int y=WORLD_Y-1;y>=0;--y){u8 m=0;float below=sample(y,m);
   if(below<0){top=float(y)+clampf(-below/(above-below),0,1);material=m;break;}above=below;}
  int at=(x+1)+(z+1)*stride;heights[at]=top;materials[at]=material;
 }
 godot::PackedByteArray pixels;pixels.resize(width*height*4);auto*p=pixels.ptrw();
 for(int z=0;z<height;++z)for(int x=0;x<width;++x){int at=x+1+(z+1)*stride;float h=heights[at];
  float dx=(heights[at+1]-heights[at-1])/(2*step),dz=(heights[at+stride]-heights[at-stride])/(2*step);
  float shade=clampf(.88f+(-dx-dz)*.22f,.52f,1.12f),t=clampf((h-40)/150,0,1);
  float r=90+t*86,g=119+t*35,b=83+t*52;if(h>0&&int(h)%20==0)shade*=.9f;
  if(materials[at]==4){r=75;g=78;b=78;}else if(materials[at]==3){r=123;g=119;b=109;}
  size_t dst=(x+z*width)*4;p[dst]=u8(clampf(r*shade,0,255));p[dst+1]=u8(clampf(g*shade,0,255));p[dst+2]=u8(clampf(b*shade,0,255));p[dst+3]=255;
 }
 out["ok"]=true;out["pixels"]=pixels;out["revision"]=w.revision;
 out["generation_ms"]=std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-start).count();return out;
}

// Top-down visibility at exact water sample coordinates. Bounded to 16 points
// on the ordered worker. Scan above the point, including cave/overhang roofs;
// generated height alone cannot establish visibility after terrain edits.
static godot::Dictionary terraforest_survey_water_visibility(const World &w,const godot::PackedVector3Array &points){
 godot::Dictionary out;out["ok"]=false;
 if(points.is_empty()||points.size()>256)return out;
 for(int i=0;i<points.size();++i){auto p=points[i];if(!p.is_finite()||p.x<0||p.z<0||p.x>=WORLD-1||p.z>=WORLD-1||p.y<0||p.y>=WORLD_Y-1)return out;}
 auto start=std::chrono::steady_clock::now();godot::PackedByteArray visible;int slow=0;
 for(int i=0;i<points.size();++i){auto p=points[i];int ix=fl(p.x),iz=fl(p.z);float dx=p.x-ix,dz=p.z-iz;
  auto sample=[&](int y){float d=0;for(int k=0;k<4;++k){float weight=(k&1?dx:1-dx)*(k&2?dz:1-dz);if(weight>0)d+=w.sample(ix+(k&1),y,iz+((k>>1)&1))*weight;}return d;};
  bool pristine=surrounding_coast(w.generator_id)&&p.y==40;
  for(int k=0;k<4&&pristine;++k){int x=ix+(k&1),z=iz+((k>>1)&1);
   if(w.edit_columns[(x>>4)+WORLD_PAGE_COLUMNS*(z>>4)]||w.block_columns[(x>>5)+64*(z>>5)].n)pristine=false;
  }
  if(pristine){
   float highest=-1;for(int k=0;k<4;++k)highest=mx(highest,w.height(ix+(k&1),iz+((k>>1)&1)));
   if(highest<40){visible.push_back(1);continue;}
   if(sample(40)*.9999f+sample(41)*.0001f<0){visible.push_back(0);continue;}
  }
  if(slow==16)break;++slow;
  float y=mn(float(WORLD_Y-1),float(p.y)+.0001f);int bottom=fl(y);float t=y-bottom;
  bool open=sample(bottom)*(1-t)+sample(mn(bottom+1,WORLD_Y-1))*t>=0;
  for(int h=bottom+1;open&&h<WORLD_Y;++h)if(sample(h)<0)open=false;
  visible.push_back(open?1:0);
 }
 out["ok"]=true;out["visible"]=visible;out["revision"]=w.revision;
 out["generation_ms"]=std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-start).count();return out;
}
