// SPDX-License-Identifier: 0BSD
// Included inside terraforest. Six consistent tetrahedra share cube diagonal 0--7.
int NativeLakeVolume::build_boundary_volume(){
 boundary_mask_.reset(new(std::nothrow) uint8_t[count_]());
 std::unique_ptr<uint32_t[]> pending(new(std::nothrow) uint32_t[size_t(count_)*6]);
 if(!boundary_mask_||!pending)return -1;
 const Vector3 local=(seed_-origin_)/spacing_;const Vector3i cell=Vector3i(local.floor());
 float weights[4];const int seed_t=lake_tetra(local-Vector3(cell),weights);
 float value=0;for(int k=0;k<4;++k){const auto c=cell+lake_corner(lake_tets[seed_t][k]);value+=weights[k]*density_[node(c.x,c.y,c.z)];}
 if(value<=0)return -2;
 uint32_t head=0,tail=1;const auto seed_id=index(cell.x,cell.y,cell.z);
 pending[0]=seed_id*6+seed_t;boundary_mask_[seed_id]=uint8_t(1<<seed_t);
 const float fill=(level_-origin_.y)/spacing_;
 const auto &links=lake_links();
 while(head<tail){
  const uint32_t item=pending[head++],id=item/6;const int t=item%6;
  const int x=id%size_.x,y=(id/size_.x)%size_.y,z=id/(size_.x*size_.y);
  for(int f=0;f<4;++f){
   float heights[3],values[3];int n=0;
   for(int k=0;k<4;++k)if(k!=f){const auto c=lake_corner(lake_tets[t][k]);heights[n]=y+c.y;values[n++]=density_[node(x+c.x,y+c.y,z+c.z)];}
   if(std::min({heights[0],heights[1],heights[2]})>=fill)continue;
   float maximum=-INFINITY;
   for(int k=0;k<3;++k){
    if(heights[k]<=fill)maximum=std::max(maximum,values[k]);
    const int j=(k+1)%3;
    if((heights[k]<fill)!=(heights[j]<fill) && heights[k]!=heights[j]){
     const float a=(fill-heights[k])/(heights[j]-heights[k]);
     maximum=std::max(maximum,values[k]+a*(values[j]-values[k]));
    }
   }
   if(maximum<=0)continue;
   const auto link=links[t][f];if(link.t<0)return -1;
   const int nx=x+link.x,ny=y+link.y,nz=z+link.z;
   if(nx<0||ny<0||nz<0||nx>=size_.x||ny>=size_.y||nz>=size_.z)return -3;
   const auto next=index(nx,ny,nz);const uint8_t bit=uint8_t(1<<link.t);
   if(!(boundary_mask_[next]&bit)){boundary_mask_[next]|=bit;pending[tail++]=next*6+link.t;}
  }
 }
 return 1;
}
bool NativeLakeVolume::boundary_contains(const Vector3 &point) const {
 if(!boundary_mask_||!query_density_)return false;
 const Vector3 p=(point-origin_)/spacing_;
 if(p.x<0||p.y<0||p.z<0||p.x>=size_.x||p.y>=size_.y||p.z>=size_.z)return false;
 const Vector3i cell=Vector3i(p.floor());float weights[4];const int t=lake_tetra(p-Vector3(cell),weights);
 if(!(boundary_mask_[index(cell.x,cell.y,cell.z)]&(1<<t)))return false;
 float value=0;for(int k=0;k<4;++k){const auto c=cell+lake_corner(lake_tets[t][k]);value+=weights[k]*query_density_[node(c.x,c.y,c.z)];}
 return value>0;
}
