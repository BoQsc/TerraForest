// Diagnostic only: bracketed root on frozen short segments, not a general raycaster.
#include "experimental/region_mesher.hpp"
#include "experimental/density_ray.hpp"
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
 using namespace terraforest::experimental;
 int controls=0;
 auto plane=[](int x,int,int){return 4.25-x;};
 auto hit=[&](DensityHit r,double expected){controls++;return r.status==RayStatus::hit&&std::abs(r.fraction-expected)<1e-9;};
 if(!hit(trace_density({0,10,10},{10,10,10},plane),.425)||!hit(trace_density({10,10,10},{0,10,10},plane),.575))return 10;
 if(!hit(trace_density({-2,10,10},{10,10,10},plane),6.25/12))return 11;
 if(!hit(trace_density({0,0,0},{1,1,1},[](int x,int y,int z){return (x-.2)*(y-.5)*(z-.8);}),.2))return 12;
 if(!hit(trace_density({0,0,0},{1,1,1},[](int x,int y,int){return (x-.5)*(y-.5);}),.5))return 13;
 if(!hit(trace_density({1,1,1},{0,0,0},[](int x,int y,int z){return (x-.2)*(y-.5)*(z-.8);}),.2))return 14;
 if(!hit(trace_density({0,1,1},{2,1,1},[](int x,int,int){return 1.-x;}),.5))return 15;
 if(!hit(trace_density({4.25f,10,10},{10,10,10},plane),0))return 16;
 RayControl limited;limited.max_cells=4;
 if(trace_density({0,10,10},{10,10,10},plane,limited).status!=RayStatus::work_limit)return 17;controls++;
 limited.max_cells=5;if(!hit(trace_density({0,10,10},{10,10,10},plane,limited),.425))return 18;
 int cancel_calls=0;RayControl cancelled;cancelled.context=&cancel_calls;cancelled.cancel=[](void*p){return ++*static_cast<int*>(p)==6;};
 if(trace_density({0,10,10},{10,10,10},plane,cancelled).status!=RayStatus::cancelled)return 19;controls++;
 if(trace_density({0,10,10},{10,10,10},[](int,int,int){return 1.;}).status!=RayStatus::miss)return 20;controls++;
 if(trace_density({0,10,10},{0,10,10},plane).status!=RayStatus::invalid_input)return 21;controls++;
 if(trace_density({0,10,10},{10,10,10},[](int,int,int){return std::numeric_limits<double>::quiet_NaN();}).status!=RayStatus::invalid_input)return 22;controls++;
 int sampled=0;
 if(trace_density({-2,0,0},{-1,0,0},[&](int,int,int){sampled++;return 0.;}).status!=RayStatus::miss||sampled)return 23;controls++;
 if(trace_density({-2,std::numeric_limits<float>::quiet_NaN(),0},{-2,0,0},plane).status!=RayStatus::invalid_input)return 24;controls++;
 if(!hit(trace_density({1999,10,10},{2001,10,10},[](int x,int,int){return 2000.-x;}),.5))return 25;
 limited.max_cells=0;
 if(trace_density({0,10,10},{10,10,10},plane,limited).status!=RayStatus::work_limit)return 26;controls++;
 fprintf(stderr,"{\"analytic_controls\":%d,\"passed\":true}\n",controls);
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
  DensityHit traced=trace_world_density(w,start,end);
  Bytes request,reply;request.u(23);request.vec(start);request.vec(end);request.u(4096);request.u(terrain_build_epoch(&w));
  process_request(w,request.p,request.n,reply);Reader wire{reply.p,reply.n};
  if(reply.n!=40||wire.u()!=REPLY_MAGIC||wire.u()!=23||wire.u()!=0||wire.u()!=u32(w.revision)||wire.u()!=0||wire.u()!=traced.cells)return 27;
  float fraction=wire.f();V3 position=wire.vec();
  if(!wire.good||fraction!=float(traced.fraction)||length(position-traced.position)!=0)return 28;
  reply.release();request.release();
  printf("{\"query_id\":%d,\"wire_parity\":true,\"hit\":%s,\"distance\":%.12g,\"cells\":%zu}\n",id,traced.status==RayStatus::hit?"true":"false",length(traced.position-center),traced.cells);
  printf("{\"id\":%d,\"bracketed\":%s,\"air_control_clear\":%s,\"solid_control_clear\":%s,\"start_density\":%.12g,\"end_density\":%.12g,\"center_density\":%.12g,\"root_density\":%.12g,\"distance\":%.12g}\n",id,bracket?"true":"false",air_clear?"true":"false",solid_clear?"true":"false",d0,d1,dc,root_density,distance);
  w.release();
 }
 fclose(f);return 0;
}
