// SPDX-License-Identifier: 0BSD
#pragma once
#include "core.h"
#include <godot_cpp/variant/variant.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <vector>
#include <chrono>
// Cartographic base survey only. No density pages, meshes or renderer residency.
// Called on an isolated TerrainCore from the map worker; never borrow the live worker.
static godot::Dictionary terraforest_survey_map(const World &w,int64_t size){
 godot::Dictionary out;out["ok"]=false;
 if(size<64||size>512)return out;
 auto start=std::chrono::steady_clock::now();
 std::vector<float> heights(size_t(size)*size);
 float step=float(WORLD)/float(size);
 for(int z=0;z<size;++z)for(int x=0;x<size;++x)heights[x+z*size]=w.height((x+.5f)*step,(z+.5f)*step);
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
  for(int i=0;i<w.basin_count;++i){
   float wx=(x+.5f)*step-w.basins[i].x,wz=(z+.5f)*step-w.basins[i].z;
   float radius=w.generator_id>=LAKE_WORLD_GENERATOR_ID&&i==0?80.f:24.f;
   if(wx*wx+wz*wz<radius*radius&&h<w.basins[i].level){r=54;g=117;b=140;shade=1;break;}
  }
  size_t at=(x+z*size)*4;p[at]=u8(clampf(r*shade,0,255));p[at+1]=u8(clampf(g*shade,0,255));p[at+2]=u8(clampf(b*shade,0,255));p[at+3]=255;
 }
 out["ok"]=true;out["pixels"]=pixels;out["size"]=size;
 out["generation_ms"]=std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-start).count();return out;
}
