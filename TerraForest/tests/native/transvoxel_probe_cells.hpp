// SPDX-License-Identifier: 0BSD
#pragma once
// Exhaustive local interface feasibility test. No runtime integration yet.
#include "vendor/transvoxel/Transvoxel.cpp"
#include <array>
#include <map>
#include <vector>
#include <algorithm>
#include <cmath>
#include <cstdio>
using P=std::array<float,3>;
using T=std::array<P,3>;
using E=std::array<P,2>;
struct Sample{P p;float d;};
static P crossing(Sample a,Sample b){
 if(b.p<a.p)std::swap(a,b);
 double t=double(a.d)/(double(a.d)-b.d);P p;
 for(int k=0;k<3;k++)p[k]=float(a.p[k]+(double(b.p[k])-a.p[k])*t);
 return p;
}
static P transform(P p,int orientation,float origin){
 // Six faces: cyclic rotation (det +1), optionally reflect all coordinates
 // (det -1). The latter reverses all triangles in the assembled fixture.
 P q;for(int k=0;k<3;k++)q[k]=origin+(orientation&1?-1.f:1.f)*p[(k+orientation/2)%3];return q;
}
static void regular(std::array<Sample,8>s,std::vector<T>&mesh,bool bias_zero=true){
 // A shared tie rule is required on both sides of every interface. Keep an
 // explicit raw mode for the rejection fixture, never silently drop triangles.
 if(bias_zero)for(auto&v:s)if(v.d==0)v.d=.5f/1024;
 unsigned code=0;for(int i=0;i<8;i++)if(s[i].d<0)code|=1u<<i;
 const auto&data=regularCellData[regularCellClass[code]];P vertices[12];
 for(int i=0;i<data.GetVertexCount();i++){unsigned edge=regularVertexData[code][i]&255;vertices[i]=crossing(s[edge>>4],s[edge&15]);}
 for(int i=0;i<data.GetTriangleCount();i++)mesh.push_back({vertices[data.vertexIndex[i*3]],vertices[data.vertexIndex[i*3+1]],vertices[data.vertexIndex[i*3+2]]});
}
static void transition(std::array<Sample,13>s,std::vector<T>&mesh,bool bias_zero=true){
 if(bias_zero)for(auto&v:s)if(v.d==0)v.d=.5f/1024;
 constexpr int bit_sample[9]={0,1,2,5,8,7,6,3,4};unsigned code=0;
 for(int i=0;i<9;i++)if(s[bit_sample[i]].d<0)code|=1u<<i;
 unsigned type=transitionCellClass[code];const auto&data=transitionCellData[type&127];P vertices[12];
 for(int i=0;i<data.GetVertexCount();i++){unsigned edge=transitionVertexData[code][i]&255;vertices[i]=crossing(s[edge>>4],s[edge&15]);}
 for(int i=0;i<data.GetTriangleCount();i++){
  T t={vertices[data.vertexIndex[i*3]],vertices[data.vertexIndex[i*3+1]],vertices[data.vertexIndex[i*3+2]]};
  if(type&128)std::swap(t[1],t[2]);mesh.push_back(t);
 }
}
