// SPDX-License-Identifier: 0BSD
#include "../../addons/volumetric_terrain/native/core.h"
#include "../../addons/volumetric_terrain/native/surface_cell.hpp"
#include <cstdio>
#include <cstring>
#include <cstdint>
static V3 previous(const float*d,unsigned signs){
 static const int edges[12][2]={{0,1},{2,3},{4,5},{6,7},{0,2},{1,3},{4,6},{5,7},{0,4},{1,5},{2,6},{3,7}};
   V3 p{};int count=0;for(int e=0;e<12;e++){int a=edges[e][0],b=edges[e][1];if(((signs>>a)&1)==((signs>>b)&1))continue;float t=d[a]/(d[a]-d[b]);V3 va={float(a&1),float((a>>1)&1),float((a>>2)&1)},vb={float(b&1),float((b>>1)&1),float((b>>2)&1)};p=p+va+(vb-va)*t;count++;}

   if(!count)return p;p=p/float(count);
 return p;
}
struct Face {int axis,a,b,c,d;bool reverse;};
static bool face_probe(){
 unsigned cases=0;
 for(unsigned mask=0;mask<256;mask++)for(int missing=-1;missing<27;missing++){
  auto lookup=[&](int x,int y,int z){int id=x+1+3*(y+1)+9*(z+1);return id==missing?-1:id;};
  Face expected[3],actual[3];int ne=0,na=0;
  for(int axis=0;axis<3;axis++){
   int other=axis==0?1:(axis==1?2:4);if((mask&1)==((mask>>other)&1))continue;
   int a,b,c=lookup(0,0,0),d;
   if(axis==0){a=lookup(0,-1,-1);b=lookup(0,0,-1);d=lookup(0,-1,0);}
   else if(axis==1){a=lookup(-1,0,-1);b=lookup(-1,0,0);d=lookup(0,0,-1);}
   else{a=lookup(-1,-1,0);b=lookup(0,-1,0);d=lookup(-1,0,0);}
   if(a>=0&&b>=0&&c>=0&&d>=0)expected[ne++]={axis,a,b,c,d,(mask&1)==0};
  }
  terraforest::surface_cell_faces(0,0,0,mask,lookup,[&](int axis,int a,int b,int c,int d,bool reverse){actual[na++]={axis,a,b,c,d,reverse};});
  if(ne!=na)return false;
  for(int i=0;i<ne;i++){auto a=actual[i],e=expected[i];if(a.axis!=e.axis||a.a!=e.a||a.b!=e.b||a.c!=e.c||a.d!=e.d||a.reverse!=e.reverse)return false;}
  cases++;
 }
 std::printf("PASS %u connectivity cases: ownership, winding and missing neighbours\n",cases);return true;
}
static bool quad_probe(){
 for(int shape=0;shape<3;shape++)for(int reverse=0;reverse<2;reverse++){
  V3 points[4]={{0,0,0},{0,0,1},{1,0,1},{1,0,0}};
  if(shape==1)points[2].y=2;
  if(shape==2)points[1].y=2;
  int expected[6],actual[6],n=0;int a=0,b=1,c=2,d=3;
  if(reverse){int temp=b;b=d;d=temp;}
  if(dot(points[a]-points[c],points[a]-points[c])<=dot(points[b]-points[d],points[b]-points[d])){
   int sequence[6]={a,c,b,a,d,c};for(int i=0;i<6;i++)expected[i]=sequence[i];
  }else{int sequence[6]={a,d,b,b,d,c};for(int i=0;i<6;i++)expected[i]=sequence[i];}
  terraforest::surface_quad(0,1,2,3,reverse,[&](int i){return points[i];},[&](int a,int b,int c){actual[n++]=a;actual[n++]=b;actual[n++]=c;});
  if(n!=6)return false;for(int i=0;i<6;i++)if(actual[i]!=expected[i])return false;
 }
 std::puts("PASS six quad cases: both diagonals, flat tie and reversed winding");return true;
}
int main(){
 if(!face_probe())return 3;
 if(!quad_probe())return 4;
 unsigned cases=0;uint32_t random=71237;
 for(unsigned mask=0;mask<256;mask++)for(int sample=0;sample<128;sample++){
  float d[8];for(int k=0;k<8;k++){
   random=random*1664525u+1013904223u;
   float magnitude=sample==0?1.f:float(1+(random%100000))/1024.f;
   d[k]=(mask&(1u<<k))?-magnitude:(sample==1?0.f:magnitude);
  }
  V3 a=previous(d,mask),b=terraforest::surface_cell_vertex<V3>(d,mask);
  if(std::memcmp(&a,&b,sizeof(V3))){std::printf("FAIL mask=%u sample=%d\n",mask,sample);return 1;}
  if(mask!=0&&mask!=255&&(b.x<0||b.x>1||b.y<0||b.y>1||b.z<0||b.z>1))return 2;
  cases++;
 }
 std::printf("PASS %u surface-cell cases: bit-identical to live terrain calculation\n",cases);
}
