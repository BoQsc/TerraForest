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
#include <algorithm>
static float terrain_map_smooth(float value){return value*value*(3-2*value);}
static V3 terrain_map_color(const World &world,float x,float z,float height,float slope_x,float slope_z,int material){
 float up=1.f/__builtin_sqrtf(1+slope_x*slope_x+slope_z*slope_z);
 V3 color{91,115,61};
 float rock=1-terrain_map_smooth(clampf((up-.52f)/.24f,0,1));color=color*(1-rock)+V3{127,125,116}*rock;
 float beach=(1-terrain_map_smooth(clampf((height-42)/4,0,1)))*(1-terrain_map_smooth(clampf((mn(mn(x,z),mn(2000-x,2000-z))-130)/20,0,1)));
 if(surrounding_coast(world.generator_id))color=color*(1-beach)+V3{177,165,130}*beach;
 float snow=terrain_map_smooth(clampf((height-150)/35,0,1))*terrain_map_smooth(clampf((up-.60f)/.25f,0,1));
 if(world.generator_id>=7)color=color*(1-snow)+V3{202,206,204}*snow;
 if(material==4)color={54,57,58};else if(material==1||material==5)color={123,119,109};
 else if(material==3||material==7)color={91,100,107};else if(material==2||material==6)color={109,83,56};
 else if(material==8)color={81,94,107};else if(material==9)color={137,88,54};
 return color;
}
// Cartographic base survey only. No density pages, meshes or renderer residency.
// Called on an isolated TerrainCore from the map worker; never borrow the live worker.
static godot::Dictionary terraforest_survey_map(const World &w,int64_t size){
 godot::Dictionary out;out["ok"]=false;
 if(size<64||size>1024)return out;
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
  float shade=clampf(.88f+(-dx-dz)*.22f,.52f,1.12f);
  V3 color=terrain_map_color(w,(x+.5f)*step,(z+.5f)*step,h,dx,dz,0);float r=color.x,g=color.y,b=color.z;
  size_t at=(x+z*size)*4;p[at]=u8(clampf(r*shade,0,255));p[at+1]=u8(clampf(g*shade,0,255));p[at+2]=u8(clampf(b*shade,0,255));p[at+3]=255;
 }
 out["ok"]=true;out["pixels"]=pixels;out["size"]=size;out["workers"]=workers;
 out["generation_ms"]=std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-start).count();return out;
}

// Bounded live-world patch. Run only on the ordered terrain worker.
static int terrain_survey_ceiling(const World &world,int across,int depth){
 int ceiling=1;
 for(int corner=0;corner<4;corner++){
  int column=across+(corner&1),row=depth+((corner>>1)&1);
  ceiling=mx(ceiling,fl(world.height(column,row))+2);
  u32 pages=world.edit_columns[(column>>4)+WORLD_PAGE_COLUMNS*(row>>4)];
  for(int level=0;level<16;level++)if(pages&(1u<<level))ceiling=mx(ceiling,level*16+16);
  const auto &blocks=world.block_columns[(column>>5)+64*(row>>5)];
  for(int block=0;block<blocks.n;block++)ceiling=mx(ceiling,int((blocks[block]-1)>>22)+2);
 }
 return mn(WORLD_Y-1,ceiling);
}
static godot::Dictionary terraforest_survey_patch(const World &w,int size,int ox,int oz,int width,int height){
 godot::Dictionary out;out["ok"]=false;
 if(size<64||size>1024||width<1||height<1||width>16||height>16||ox<0||oz<0||ox+width>size||oz+height>size)return out;
 auto start=std::chrono::steady_clock::now();float step=float(WORLD)/size;
 float heights[324]{};u8 materials[1296]{};int stride=width+2;
 int samples=size>512?4:1;
 for(int z=-1;z<=height;++z)for(int x=-1;x<=width;++x){
  int at=(x+1)+(z+1)*stride;
  for(int sample_index=0;sample_index<samples;sample_index++){
  float fraction_x=samples==1?.5f:.25f+.5f*(sample_index&1),fraction_z=samples==1?.5f:.25f+.5f*(sample_index>>1);
  float wx=(clampf(float(ox+x),0,float(size-1))+fraction_x)*step,wz=(clampf(float(oz+z),0,float(size-1))+fraction_z)*step;
  int ix=fl(wx),iz=fl(wz);float dx=wx-ix,dz=wz-iz;
  auto sample=[&](int y,u8 &material){float value=0,largest=-1;material=0;
   for(int k=0;k<4;++k){float weight=(k&1?dx:1-dx)*(k&2?dz:1-dz);if(weight<=0)continue;
    u8 m=0;float d=w.sample(ix+(k&1),y,iz+((k>>1)&1),&m);value+=d*weight;
    if(d<0&&weight>largest){largest=weight;material=m;}}
   return value;};
  float top=0,above=1;u8 material=0;
  for(int y=terrain_survey_ceiling(w,ix,iz);y>=0;--y){u8 m=0;float below=sample(y,m);
   if(below<0){top=float(y)+clampf(-below/(above-below),0,1);material=m;break;}above=below;}
  heights[at]+=top/samples;materials[at*4+sample_index]=material;
  }
 }
 godot::PackedByteArray pixels;pixels.resize(width*height*4);auto*p=pixels.ptrw();
 for(int z=0;z<height;++z)for(int x=0;x<width;++x){int at=x+1+(z+1)*stride;float h=heights[at];
  float dx=(heights[at+1]-heights[at-1])/(2*step),dz=(heights[at+stride]-heights[at-stride])/(2*step);
  float shade=clampf(.88f+(-dx-dz)*.22f,.52f,1.12f);
  V3 color{};
  for(int sample_index=0;sample_index<samples;sample_index++)color=color+terrain_map_color(w,(ox+x+.5f)*step,(oz+z+.5f)*step,h,dx,dz,materials[at*4+sample_index])*(1.f/samples);
  float r=color.x,g=color.y,b=color.z;
  size_t dst=(x+z*width)*4;p[dst]=u8(clampf(r*shade,0,255));p[dst+1]=u8(clampf(g*shade,0,255));p[dst+2]=u8(clampf(b*shade,0,255));p[dst+3]=255;
 }
 out["ok"]=true;out["pixels"]=pixels;out["revision"]=w.revision;
 out["generation_ms"]=std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-start).count();return out;
}

static godot::Dictionary terraforest_survey_surface(const World &world){
 godot::PackedByteArray pixels;pixels.resize(256*256*4);auto *destination=pixels.ptrw();
 auto started=std::chrono::steady_clock::now();
 for(int row=0;row<256;row+=4)for(int column=0;column<256;column+=4){
  auto patch=terraforest_survey_patch(world,256,column,row,4,4);
  if(!bool(patch.get("ok",false)))return {};
  godot::PackedByteArray source=patch["pixels"];
  for(int local=0;local<4;local++)std::copy_n(source.ptr()+local*16,16,destination+((row+local)*256+column)*4);
 }
 godot::Dictionary result;result["ok"]=true;result["pixels"]=pixels;
 result["generation_ms"]=std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-started).count();return result;
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
  bool pristine=true;
  for(int k=0;k<4&&pristine;++k){int x=ix+(k&1),z=iz+((k>>1)&1);
   if(w.edit_columns[(x>>4)+WORLD_PAGE_COLUMNS*(z>>4)]||w.block_columns[(x>>5)+64*(z>>5)].n)pristine=false;
  }
  if(pristine){
   float highest=-1;for(int k=0;k<4;++k)highest=mx(highest,w.height(ix+(k&1),iz+((k>>1)&1)));
   if(highest<=p.y){visible.push_back(1);continue;}
   float probe=p.y+.0001f;int bottom=fl(probe);float blend=probe-bottom;
   if(sample(bottom)*(1-blend)+sample(bottom+1)*blend<-.001f){visible.push_back(0);continue;}
  }
  if(slow==16)break;++slow;
  float y=mn(float(WORLD_Y-1),float(p.y)+.0001f);int bottom=fl(y);float t=y-bottom;
  bool open=sample(bottom)*(1-t)+sample(mn(bottom+1,WORLD_Y-1))*t>=0;
  int ceiling=terrain_survey_ceiling(w,ix,iz);
  for(int h=bottom+1;open&&h<=ceiling;++h)if(sample(h)<0)open=false;
  visible.push_back(open?1:0);
 }
 out["ok"]=true;out["visible"]=visible;out["revision"]=w.revision;
 out["generation_ms"]=std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-start).count();return out;
}
