// Diagnostic only: bracketed root on frozen short segments, not a general raycaster.
#include "experimental/region_mesher.hpp"
#include <cstdio>
#include <cstdlib>
#include <cmath>
static double density(const World&w,V3 p){
 int x=fl(p.x),y=fl(p.y),z=fl(p.z);double dx=p.x-x,dy=p.y-y,dz=p.z-z,value=0;
 for(int k=0;k<8;k++){
  float raw=clampf(w.sample(x+(k&1),y+((k>>1)&1),z+((k>>2)&1)),-SDF_BAND,SDF_BAND)*SDF_SCALE;
  int q=int(raw>=0?raw+.5f:raw-.5f);
  value+=double(q)/SDF_SCALE*(k&1?dx:1-dx)*(k&2?dy:1-dy)*(k&4?dz:1-dz);
 }
 return value;
}
int main(int argc,char**argv){
 if(argc!=2)return 2;FILE*f=fopen(argv[1],"r");if(!f)return 2;
 tr_alloc=std::malloc;tr_realloc=std::realloc;tr_free=std::free;
 int id,site;V3 a,b,c;
 while(fscanf(f,"%d %d %f %f %f %f %f %f %f %f %f",&id,&site,&a.x,&a.y,&a.z,&b.x,&b.y,&b.z,&c.x,&c.y,&c.z)==11){
  World w;w.init(1703);
  if(site==2){V3 p{1296,w.height(1296,1296),1296},lo,hi;int changes;if(!w.edit(p,p,5,0,false,1,lo,hi,changes)||!changes)return 3;}
  V3 center=(a+b+c)/3.f,normal=::normal(cross(b-a,c-a)),start=center+normal*.02f,end=center-normal*.02f;
  double d0=density(w,start),d1=density(w,end),dc=density(w,center);
  bool bracket=d0==0||d1==0||(d0<0)!=(d1<0);double distance=-1,root_density=0;
  if(bracket){
   double lo=0,hi=1,left=d0;
   for(int iteration=0;iteration<30;iteration++){
    double t=(lo+hi)*.5;V3 p=start+(end-start)*float(t);double d=density(w,p);
    if(d==0){lo=hi=t;break;}
    if((d<0)==(left<0)){lo=t;left=d;}else hi=t;
   }
   V3 root=start+(end-start)*float((lo+hi)*.5);distance=length(root-center);root_density=density(w,root);
  }
  bool air_clear=density(w,start+normal*.1f)>0&&density(w,end+normal*.1f)>0;
  bool solid_clear=density(w,start-normal*.1f)<0&&density(w,end-normal*.1f)<0;
  printf("{\"id\":%d,\"bracketed\":%s,\"air_control_clear\":%s,\"solid_control_clear\":%s,\"start_density\":%.12g,\"end_density\":%.12g,\"center_density\":%.12g,\"root_density\":%.12g,\"distance\":%.12g}\n",id,bracket?"true":"false",air_clear?"true":"false",solid_clear?"true":"false",d0,d1,dc,root_density,distance);
  w.release();
 }
 fclose(f);return 0;
}
