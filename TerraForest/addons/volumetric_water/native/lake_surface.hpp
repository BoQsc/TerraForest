// SPDX-License-Identifier: 0BSD
// Fill-level section of the same connected tetrahedra used by point queries.
Array NativeLakeVolume::build_smooth_surface() const {
 Array arrays;arrays.resize(Mesh::ARRAY_MAX);
 PackedVector3Array vertices,normals;PackedVector2Array uv;PackedInt32Array indices;
 const int width=size_.x,depth=size_.z,y=int(std::ceil((level_-origin_.y)/spacing_))-1;
 const float fy=(level_-origin_.y)/spacing_-y;
 std::vector<uint8_t> full(size_t(width)*depth,0);
 struct Point {Vector2 p;float d;};
 auto emit=[&](const Point *points,int count){
  const int base=vertices.size();
  for(int k=0;k<count;++k){Vector3 p(origin_.x+points[k].p.x*spacing_,level_,origin_.z+points[k].p.y*spacing_);vertices.push_back(p);normals.push_back(Vector3(0,1,0));uv.push_back(Vector2(p.x,p.z));}
  for(int k=1;k+1<count;++k)if(std::abs((points[k].p-points[0].p).cross(points[k+1].p-points[0].p))>1e-8f){indices.push_back(base);indices.push_back(base+k);indices.push_back(base+k+1);}
 };
 for(int z=0;z<depth;++z)for(int x=0;x<width;++x){
  Point polygons[6][6];int counts[6]={};bool complete=true;
  const uint8_t mask=boundary_mask_[index(x,y,z)];if(!mask)continue;
  for(int t=0;t<6;++t){
   auto add=[&](const Vector2 &p,float d){for(int k=0;k<counts[t];++k)if(polygons[t][k].p.distance_squared_to(p)<1e-12f)return;polygons[t][counts[t]++]={p,d};};
   Vector3 p[4];float d[4];
   for(int k=0;k<4;++k){const auto c=lake_corner(lake_tets[t][k]);p[k]=Vector3(c);d[k]=density_[node(x+c.x,y+c.y,z+c.z)];if(std::abs(p[k].y-fy)<1e-6f)add(Vector2(x+p[k].x,z+p[k].z),d[k]);}
   for(int a=0;a<4;++a)for(int b=a+1;b<4;++b)if((p[a].y<fy && p[b].y>fy)||(p[b].y<fy && p[a].y>fy)){
    const float blend=(fy-p[a].y)/(p[b].y-p[a].y);const Vector3 q=p[a]+(p[b]-p[a])*blend;add(Vector2(x+q.x,z+q.z),d[a]+(d[b]-d[a])*blend);
   }
   if(counts[t]<3){counts[t]=0;continue;}
   if(!(mask&(1<<t))){complete=false;counts[t]=0;continue;}
   Vector2 center;for(int k=0;k<counts[t];++k){center+=polygons[t][k].p;if(polygons[t][k].d<=0)complete=false;}center/=counts[t];
   std::sort(polygons[t],polygons[t]+counts[t],[&](const Point &a,const Point &b){return std::atan2(a.p.y-center.y,a.p.x-center.x)<std::atan2(b.p.y-center.y,b.p.x-center.x);});
  }
  if(complete){full[x+width*z]=1;continue;}
  for(int t=0;t<6;++t){
   Point clipped[8];int count=0;
   for(int k=0;k<counts[t];++k){const Point a=polygons[t][k],b=polygons[t][(k+1)%counts[t]];if(a.d>0)clipped[count++]=a;if((a.d>0)!=(b.d>0)){const float blend=a.d/(a.d-b.d);clipped[count++]={a.p+(b.p-a.p)*blend,0};}}
   if(count>=3)emit(clipped,count);
  }
 }
 for(int z=0;z<depth;++z)for(int x=0;x<width;++x){
  if(!full[x+width*z])continue;int end_x=x+1,end_z=z+1;
  while(end_x<width&&full[end_x+width*z])++end_x;
  while(end_z<depth){bool complete=true;for(int j=x;j<end_x;++j)if(!full[j+width*end_z]){complete=false;break;}if(!complete)break;++end_z;}
  for(int k=z;k<end_z;++k)std::fill(full.begin()+x+width*k,full.begin()+end_x+width*k,0);
  Point points[4]={{{float(x),float(z)},1},{{float(end_x),float(z)},1},{{float(end_x),float(end_z)},1},{{float(x),float(end_z)},1}};emit(points,4);
 }
 arrays[Mesh::ARRAY_VERTEX]=vertices;arrays[Mesh::ARRAY_NORMAL]=normals;arrays[Mesh::ARRAY_TEX_UV]=uv;arrays[Mesh::ARRAY_INDEX]=indices;return arrays;
}
