// SPDX-License-Identifier: 0BSD
#include "dual_probe_world_field.hpp"
#include "dual_probe_audit.hpp"
#include <cstdio>
using namespace dual_probe;
using Triangle=std::array<P,3>;
static bool ray_hit(P origin,int axis,const Triangle&t,double&distance){
 double a[3],b[3],normal[3],numerator=0;
 for(int k=0;k<3;k++){a[k]=t[1][k]-t[0][k];b[k]=t[2][k]-t[0][k];}
 for(int k=0;k<3;k++){normal[k]=a[(k+1)%3]*b[(k+2)%3]-a[(k+2)%3]*b[(k+1)%3];numerator+=normal[k]*(t[0][k]-origin[k]);}
 if(std::abs(normal[axis])<1e-12)return false;distance=numerator/normal[axis];if(distance<0||distance>8)return false;origin[axis]+=distance;
 double aa=0,ab=0,bb=0,ap=0,bp=0;for(int k=0;k<3;k++){double p=origin[k]-t[0][k];aa+=a[k]*a[k];ab+=a[k]*b[k];bb+=b[k]*b[k];ap+=a[k]*p;bp+=b[k]*p;}
 double denominator=aa*bb-ab*ab;if(denominator<=0)return false;double u=(bb*ap-ab*bp)/denominator,v=(aa*bp-ab*ap)/denominator;return u>=-1e-9&&v>=-1e-9&&u+v<=1+1e-9;
}
template<class Field>static std::vector<double> field_roots(Field field,P origin,int axis){
 std::vector<double> roots;double old=field(origin);
 for(int i=1;i<=128;i++){P p=origin;p[axis]+=i/16.;double value=field(p);if((old<0)!=(value<0)){double low=(i-1)/16.,high=i/16.;for(int j=0;j<48;j++){double mid=(low+high)*.5;p=origin;p[axis]+=mid;if((field(p)<0)==(old<0))low=mid;else high=mid;}roots.push_back((low+high)*.5);}old=value;}return roots;
}
template<class Field>static int inspect(const char*kind,Field field,bool detailed){
 std::vector<Box> regions={{{24,24,24},{40,40,40}}};if(detailed)regions.push_back({{40,32,32},{48,40,40}});
 double start=clock_ms();dual_probe::Mesh<Field> mesh(field,64,regions);double construction=clock_ms()-start;
 std::vector<Triangle> triangles;for(size_t e=0;e<mesh.edge_count();e++){auto polygon=mesh.polygon(int(e));for(size_t i=1;i+1<polygon.size();i++)triangles.push_back({mesh.position(polygon[0]),mesh.position(polygon[i]),mesh.position(polygon[i+1])});}
 bool present=true;double maximum=0;int reference_counts[3]={},mesh_counts[3]={};double error[3]={};
 for(int axis=0;axis<3;axis++){P origin={44,36,36};origin[axis]-=4;auto reference=field_roots(field,origin,axis);std::vector<double> hits;
  for(const auto&t:triangles){double distance=0;if(ray_hit(origin,axis,t,distance))hits.push_back(distance);}std::sort(hits.begin(),hits.end());hits.erase(std::unique(hits.begin(),hits.end(),[](double a,double b){return std::abs(a-b)<1e-6;}),hits.end());reference_counts[axis]=int(reference.size());mesh_counts[axis]=int(hits.size());
  if(reference.size()!=2||hits.size()!=reference.size()){present=false;error[axis]=-1;continue;}for(size_t i=0;i<hits.size();i++)error[axis]=std::max(error[axis],std::abs(hits[i]-reference[i]));maximum=std::max(maximum,error[axis]);
 }
 auto a=audit(mesh);bool topology=!(a.open||a.overused||a.winding||a.degenerate||a.links)&&!mesh.unmapped_crossings()&&!mesh.unrepresented_loops();bool passed=present&&maximum<=.25&&topology&&mesh.valid_ownership()&&mesh.valid_storage();
 printf("{\"kind\":\"%s\",\"requested_detail\":%s,\"leaves\":%zu,\"triangles\":%zu,\"construction_ms\":%.6f,\"field_hits\":[%d,%d,%d],\"mesh_hits\":[%d,%d,%d],\"ray_errors_m\":[%.9g,%.9g,%.9g],\"feature_present\":%s,\"topology_passed\":%s,\"passed\":%s}\n",kind,detailed?"true":"false",mesh.cells.size(),triangles.size(),construction,reference_counts[0],reference_counts[1],reference_counts[2],mesh_counts[0],mesh_counts[1],mesh_counts[2],error[0],error[1],error[2],present?"true":"false",topology?"true":"false",passed?"true":"false");return !passed;
}
int main(){
 tr_alloc=std::malloc;tr_realloc=std::realloc;tr_free=std::free;int failures=0;
 auto cavity=[](P p){double d=(p[0]-44)*(p[0]-44)+(p[1]-36)*(p[1]-36)+(p[2]-36)*(p[2]-36);return std::max(-4.,std::min(4.,2.5-std::sqrt(d)));};
 for(bool detailed:{false,true})failures+=inspect("analytic_cavity",cavity,detailed);
 World world;world.init();P anchor={1024,double(int(world.height(1024,1024))-16),1024};WorldField field{&world,{anchor[0]-32,anchor[1]-32,anchor[2]-32},{}};
 V3 p={float(anchor[0]+12),float(anchor[1]+4),float(anchor[2]+4)},lo,hi;int changes=0;if(!world.edit(p,p,2.5f,0,false,1,lo,hi,changes)||!changes)return 2;
 for(bool detailed:{false,true})failures+=inspect("world_cavity",field,detailed);world.release();return failures?1:0;
}
