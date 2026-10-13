// SPDX-License-Identifier: 0BSD
#pragma once
// Geometry-only surface-nets cell representative. Corner bits are X,Y,Z.
// Caller supplies finite densities and their negative-sample mask. No terrain
// storage, material, engine, allocator or simulation dependency.
namespace terraforest {
// The reconstruction consumes material-boundary crossings. Density fields supply
// linearly interpolated crossings; sub-grid materials may supply exact crossings.
// This keeps topology and vertex aggregation common without rounding away volume.
template<class Vec,class AddCrossing>
inline Vec surface_crossing_vertex(unsigned signs,AddCrossing add){
 static constexpr int edges[12][2]={{0,1},{2,3},{4,5},{6,7},{0,2},{1,3},{4,6},{5,7},{0,4},{1,5},{2,6},{3,7}};
 Vec p{};int count=0;
 for(int e=0;e<12;e++){
  int a=edges[e][0],b=edges[e][1];
  if(((signs>>a)&1)==((signs>>b)&1))continue;
  p=add(p,a,b);count++;
 }
 return count?p/float(count):p;
}
template<class Vec>
inline Vec surface_cell_vertex(const float *d,unsigned signs) {
 return surface_crossing_vertex<Vec>(signs,[&](Vec p,int a,int b){
  float t=d[a]/(d[a]-d[b]);
  Vec va={float(a&1),float((a>>1)&1),float((a>>2)&1)},vb={float(b&1),float((b>>1)&1),float((b>>2)&1)};
  return p+va+(vb-va)*t;
 });
}
// Emit the three owned dual faces around a cell's minimum lattice corner.
// Lookup returns a vertex index or -1 for absent cells. Domain ownership and
// boundary guards stay with the caller; ghost cells may have negative indices.
template<class Lookup,class Emit>
inline void surface_cell_faces(int x,int y,int z,unsigned signs,Lookup lookup,Emit emit){
 static constexpr int offsets[3][3][3]={
  {{0,-1,-1},{0,0,-1},{0,-1,0}},
  {{-1,0,-1},{-1,0,0},{0,0,-1}},
  {{-1,-1,0},{0,-1,0},{-1,0,0}}
 };
 for(int axis=0;axis<3;axis++){
  int other=1<<axis;if((signs&1)==((signs>>other)&1))continue;
  const auto &o=offsets[axis];
  int a=lookup(x+o[0][0],y+o[0][1],z+o[0][2]);
  int b=lookup(x+o[1][0],y+o[1][1],z+o[1][2]);
  int c=lookup(x,y,z);
  int d=lookup(x+o[2][0],y+o[2][1],z+o[2][2]);
  if(a>=0&&b>=0&&c>=0&&d>=0)emit(axis,a,b,c,d,(signs&1)==0);
 }
}
// Clockwise Godot triangles with the shorter geometric diagonal. Both terrain
// and water use this rule so warped quads are not split by different policies.
template<class Position,class Emit>
inline void surface_quad(int a,int b,int c,int d,bool reverse,Position position,Emit emit){
 if(reverse){int tmp=b;b=d;d=tmp;}
 auto ac=position(a)-position(c),bd=position(b)-position(d);
 auto squared=[](const auto &v){return v.x*v.x+v.y*v.y+v.z*v.z;};
 if(squared(ac)<=squared(bd)){
  emit(a,c,b);emit(a,d,c);
 }else{
  emit(a,d,b);emit(b,d,c);
 }
}
}
