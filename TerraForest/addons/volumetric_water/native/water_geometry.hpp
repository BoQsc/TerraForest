// SPDX-License-Identifier: 0BSD
#pragma once
#include <godot_cpp/variant/vector3i.hpp>
#include <array>
#include <algorithm>
#include <godot_cpp/variant/vector3.hpp>
namespace terraforest {
// Shared by connectivity, rendering, point queries and volume integration.
inline constexpr int lake_tets[6][4]={{0,1,3,7},{0,1,5,7},{0,2,3,7},{0,2,6,7},{0,4,5,7},{0,4,6,7}};
inline godot::Vector3i lake_corner(int c){return godot::Vector3i(c&1,(c>>1)&1,(c>>2)&1);}
inline int lake_tetra(const godot::Vector3 &p,float *weights){
 std::array<int,3> axes={0,1,2};
 std::sort(axes.begin(),axes.end(),[&](int a,int b){return p[a]>p[b] || (p[a]==p[b] && a<b);});
 const int a=1<<axes[0],b=a|(1<<axes[1]);
 weights[0]=1-p[axes[0]];weights[1]=p[axes[0]]-p[axes[1]];
 weights[2]=p[axes[1]]-p[axes[2]];weights[3]=p[axes[2]];
 for(int t=0;t<6;++t)if(lake_tets[t][1]==a&&lake_tets[t][2]==b)return t;
 return 0;
}
struct LakeFaceLink {int x=0,y=0,z=0,t=-1;};
inline const std::array<std::array<LakeFaceLink,4>,6> &lake_links(){
 static const auto links=[](){
  std::array<std::array<LakeFaceLink,4>,6> out{};
  const godot::Vector3i shifts[]={godot::Vector3i(),godot::Vector3i(1,0,0),godot::Vector3i(-1,0,0),godot::Vector3i(0,1,0),godot::Vector3i(0,-1,0),godot::Vector3i(0,0,1),godot::Vector3i(0,0,-1)};
  for(int t=0;t<6;++t)for(int f=0;f<4;++f){
   for(const auto &shift:shifts)for(int nt=0;nt<6;++nt)for(int nf=0;nf<4;++nf){
    if(shift==godot::Vector3i() && nt==t)continue;
    int matches=0;
    for(int a=0;a<4;++a)if(a!=f)for(int b=0;b<4;++b)if(b!=nf)
     if(lake_corner(lake_tets[t][a])==shift+lake_corner(lake_tets[nt][b]))++matches;
    if(matches==3)out[t][f]={shift.x,shift.y,shift.z,nt};
   }
  }
  return out;
 }();return links;
}
}
