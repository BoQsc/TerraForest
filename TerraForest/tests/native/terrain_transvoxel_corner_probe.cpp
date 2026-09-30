// SPDX-License-Identifier: 0BSD
// Six transition faces around a fine cube, with a complete coarse shell.
#include "core.h"
#include "transvoxel_probe_cells.hpp"
#include <set>
#include <cstring>
static double triangle_distance(P p,const T&t){
 double ab[3],ac[3],ap[3],d00=0,d01=0,d11=0,d20=0,d21=0;
 for(int k=0;k<3;k++){ab[k]=double(t[1][k])-t[0][k];ac[k]=double(t[2][k])-t[0][k];ap[k]=double(p[k])-t[0][k];d00+=ab[k]*ab[k];d01+=ab[k]*ac[k];d11+=ac[k]*ac[k];d20+=ap[k]*ab[k];d21+=ap[k]*ac[k];}
 double den=d00*d11-d01*d01;
 if(den>0){double v=(d11*d20-d01*d21)/den,w=(d00*d21-d01*d20)/den;if(v>=0&&w>=0&&v+w<=1){double d=0;for(int k=0;k<3;k++){double q=ap[k]-v*ab[k]-w*ac[k];d+=q*q;}return std::sqrt(d);}}
 double best=1e30;
 for(int edge=0;edge<3;edge++){double length=0,dot=0;for(int k=0;k<3;k++){double v=double(t[(edge+1)%3][k])-t[edge][k];length+=v*v;dot+=(double(p[k])-t[edge][k])*v;}double fraction=length?std::max(0.,std::min(1.,dot/length)):0,d=0;for(int k=0;k<3;k++){double q=double(p[k])-t[edge][k]-fraction*(double(t[(edge+1)%3][k])-t[edge][k]);d+=q*q;}best=std::min(best,std::sqrt(d));}return best;
}
static double sphere_field(P p,int fixture,int step){
 double x=p[0]-1.5*step,y=p[1]+.5*step,z=p[2]-.75*step;return std::sqrt(x*x+y*y+z*z)-(2.5+.5*(fixture-12))*step;
}
struct Audit{int open=0,overused=0,winding=0,degenerate=0,vertex_links=0;};
static Audit audit(const std::vector<T>&mesh,P low,P high){
 struct Use{int count=0,balance=0;};std::map<E,Use> edges;
 std::map<P,std::vector<E>> links;Audit out;
 auto exterior=[&](P p){for(int k=0;k<3;k++)if(p[k]==low[k]||p[k]==high[k])return true;return false;};
 for(const auto&t:mesh){
  double a[3],b[3],area=0;for(int k=0;k<3;k++){a[k]=double(t[1][k])-t[0][k];b[k]=double(t[2][k])-t[0][k];}
  for(int k=0;k<3;k++){double v=a[(k+1)%3]*b[(k+2)%3]-a[(k+2)%3]*b[(k+1)%3];area+=v*v;}out.degenerate+=area==0;
  for(int k=0;k<3;k++){
   P a=t[k],b=t[(k+1)%3];bool reverse=b<a;if(reverse)std::swap(a,b);auto&u=edges[{a,b}];u.count++;u.balance+=reverse?-1:1;
   links[t[k]].push_back({t[(k+1)%3],t[(k+2)%3]});
  }
 }
 for(const auto&item:edges){const auto&e=item.first;const auto&u=item.second;
  out.overused+=u.count>2;out.winding+=u.count==2&&u.balance!=0;
  if(u.count==1){bool boundary=false;for(int k=0;k<3;k++)boundary|=e[0][k]==e[1][k]&&(e[0][k]==low[k]||e[0][k]==high[k]);out.open+=!boundary;}
 }
 for(const auto&item:links){
  std::map<P,std::vector<P>> graph;for(const auto&e:item.second){graph[e[0]].push_back(e[1]);graph[e[1]].push_back(e[0]);}
  bool bad=false;int endpoints=0;for(const auto&v:graph){endpoints+=v.second.size()==1;bad|=v.second.empty()||v.second.size()>2;}
  bad|=exterior(item.first)?(endpoints!=0&&endpoints!=2):endpoints!=0;
  std::set<P> visited;std::vector<P> pending{graph.begin()->first};
  while(!pending.empty()){P p=pending.back();pending.pop_back();if(!visited.insert(p).second)continue;for(const auto&next:graph[p])pending.push_back(next);}
  bad|=visited.size()!=graph.size();out.vertex_links+=bad;
 }return out;
}
template<class Field>static std::vector<T> build(Field density,P center,int radius,int step,size_t&fine,size_t&joins,bool projected){
 std::vector<T> mesh;
 struct Context{Field*field;P center;};Context context{&density,center};
 VertexProjection project=[](P reference,P displaced,void*opaque){
  if(reference==displaced)return reference;
  const auto&ctx=*static_cast<Context*>(opaque);P local;for(int k=0;k<3;k++)local[k]=reference[k]-ctx.center[k];double normal[3],length=0,dot=0;
  for(int k=0;k<3;k++){P a=local,b=local;a[k]-=.25f;b[k]+=.25f;normal[k]=double((*ctx.field)(b))-(*ctx.field)(a);length+=normal[k]*normal[k];dot+=normal[k]*(double(displaced[k])-reference[k]);}
  if(length>1e-20)for(int k=0;k<3;k++)displaced[k]=float(double(displaced[k])-normal[k]*dot/length);return displaced;
 };
 if(!projected)project=nullptr;
 auto sample=[&](P local,bool moved){P p=local,reference=local;float d=density(local);for(int k=0;k<3;k++){if(moved&&std::abs(p[k])==radius)p[k]-=std::copysign(.25f*step,p[k]);p[k]+=center[k];reference[k]+=center[k];}return Sample{p,d,reference};};
 for(int z=-radius;z<radius;z+=step)for(int y=-radius;y<radius;y+=step)for(int x=-radius;x<radius;x+=step){
  std::array<Sample,8>s;for(int k=0;k<8;k++)s[k]=sample({float(x+(k&1)*step),float(y+((k>>1)&1)*step),float(z+((k>>2)&1)*step)},true);regular(s,mesh,true,project,&context);
 }fine=mesh.size();
 for(int face=0;face<6;face++)for(int v=-radius;v<radius;v+=2*step)for(int u=-radius;u<radius;u+=2*step){
  std::array<Sample,13>s;
  for(int k=0;k<9;k++)s[k]=sample(transform({float(u+(k%3)*step),float(v+(k/3)*step),float(radius)},face,0),true);
  for(int k=0;k<4;k++)s[9+k]=sample(transform({float(u+(k&1)*2*step),float(v+((k>>1)&1)*2*step),float(radius)},face,0),false);
  size_t before=mesh.size();transition(s,mesh,true,project,&context);if(face&1)for(size_t i=before;i<mesh.size();i++)std::swap(mesh[i][1],mesh[i][2]);
 }joins=mesh.size()-fine;
 for(int z=-radius-2*step;z<radius+2*step;z+=2*step)for(int y=-radius-2*step;y<radius+2*step;y+=2*step)for(int x=-radius-2*step;x<radius+2*step;x+=2*step){
  if(x>=-radius&&x<radius&&y>=-radius&&y<radius&&z>=-radius&&z<radius)continue;
  std::array<Sample,8>s;for(int k=0;k<8;k++)s[k]=sample({float(x+(k&1)*2*step),float(y+((k>>1)&1)*2*step),float(z+((k>>2)&1)*2*step)},false);regular(s,mesh,true,project,&context);
 }return mesh;
}
static int emit(const char*kind,int id,int edited,int step,P center,int radius,const std::vector<T>&mesh,size_t fine,size_t joins,int changes=0,bool changed=false){
 P low=center,high=center;for(int k=0;k<3;k++){low[k]-=radius+2*step;high[k]+=radius+2*step;}auto a=audit(mesh,low,high);
 bool passed=!(a.open||a.overused||a.winding||a.degenerate||a.vertex_links)&&(!edited||changes>0)&&(edited&&step==1?changed:true);
 double surface_error=-1,coverage_error=-1;
 if(kind[0]=='s'&&(id<4||id>=12)){
  surface_error=0;
  for(const auto&t:mesh){P points[4]={t[0],t[1],t[2],{}};for(int k=0;k<3;k++)points[3][k]=(t[0][k]+t[1][k]+t[2][k])/3.f;
   for(P p:points){for(int k=0;k<3;k++)p[k]-=center[k];double d=id<4?(p[0]+(id&1?-1:1)*p[1]+(id&2?-1:1)*p[2]-.25*step)/std::sqrt(3.):sphere_field(p,id,step);surface_error=std::max(surface_error,std::abs(d));}
  }
  if(id>=12){coverage_error=0;double r=(2.5+.5*(id-12))*step;
   for(int lat=0;lat<=12;lat++)for(int lon=0;lon<24;lon++){double a=3.141592653589793*lat/12,b=6.283185307179586*lon/24;
    P p={float(center[0]+1.5*step+r*std::sin(a)*std::cos(b)),float(center[1]-.5*step+r*std::cos(a)),float(center[2]+.75*step+r*std::sin(a)*std::sin(b))};double best=1e30;for(const auto&t:mesh)best=std::min(best,triangle_distance(p,t));coverage_error=std::max(coverage_error,best);
   }
  }
 }
 printf("{\"kind\":\"%s\",\"id\":%d,\"edited\":%d,\"step\":%d,\"changed_samples\":%d,\"mesh_changed\":%s,\"fine_triangles\":%zu,\"transition_triangles\":%zu,\"coarse_triangles\":%zu,\"internal_open_edges\":%d,\"overused_edges\":%d,\"winding_errors\":%d,\"degenerate_triangles\":%d,\"invalid_vertex_links\":%d,\"max_sampled_mesh_to_analytic_m\":%.9g,\"max_sampled_sphere_to_mesh_m\":%.9g,\"passed\":%s}\n",kind,id,edited,step,changes,changed?"true":"false",fine,joins,mesh.size()-fine-joins,a.open,a.overused,a.winding,a.degenerate,a.vertex_links,surface_error,coverage_error,passed?"true":"false");fflush(stdout);return !passed;
}
int main(int argc,char**argv){
 if(argc>2||(argc==2&&std::strcmp(argv[1],"--unprojected")))return 3;
 bool projected=argc==1;
 // A pair of closed tetrahedra touching at one vertex must fail the vertex
 // link check even though every edge is paired. Removing a face must also fail.
 std::vector<T> witness;
 const P points[4]={{0,0,0},{1,0,0},{0,1,0},{0,0,1}};const int faces[4][3]={{0,2,1},{0,1,3},{0,3,2},{1,2,3}};
 for(int sign:{1,-1})for(const auto&face:faces){T t;for(int k=0;k<3;k++)for(int a=0;a<3;a++)t[k][a]=sign*points[face[k]][a];if(sign<0)std::swap(t[1],t[2]);witness.push_back(t);}
 auto pinched=audit(witness,{-2,-2,-2},{2,2,2});if(pinched.vertex_links!=1||pinched.open||pinched.overused||pinched.winding||pinched.degenerate)return 4;
 witness.pop_back();auto hole=audit(witness,{-2,-2,-2},{2,2,2});if(hole.open!=3||!hole.vertex_links)return 5;
 tr_alloc=std::malloc;tr_realloc=std::realloc;tr_free=std::free;int failures=0;
 for(int fixture=0;fixture<16;fixture++)for(int step:{1,2,4}){
  if(fixture>=4&&fixture<12&&step!=1)continue;
  auto density=[&](P p){
   if(fixture<4)return std::max(-4.f,std::min(4.f,(p[0]+(fixture&1?-1:1)*p[1]+(fixture&2?-1:1)*p[2]-.25f*step)/std::sqrt(3.f)));
   if(fixture>=12)return float(std::max(-4.,std::min(4.,sphere_field(p,fixture,step))));
   // Integer-lattice hash fields force transitions on all faces, edges and corners.
   unsigned h=unsigned(int(p[0]))*73856093u^unsigned(int(p[1]))*19349663u^unsigned(int(p[2]))*83492791u^unsigned(fixture)*2654435761u;
   h^=h>>16;h*=2246822519u;h^=h>>13;return float(int(h%8193)-4096)/1024;
  };size_t fine=0,joins=0;auto mesh=build(density,{1920,128,1920},4*step,step,fine,joins,projected);
  failures+=emit("synthetic",fixture,0,step,{1920,128,1920},4*step,mesh,fine,joins);
 }
 for(int site:{1024,1408}){
  World w;w.init();P center={float(site),float(int(w.height(float(site),float(site)))-1),float(site)};
  std::vector<T> previous[3];
  for(int edited=0;edited<4;edited++){
   int changes=0;
   // Successive excavation at the interior, a face, then a three-face corner.
   if(edited){float offset=edited==3?16.f:0.f;V3 p={center[0]+(edited>=2?16.f:0.f),center[1]-(edited==3?16.f:edited==2?12.f:0.f),center[2]+offset},lo,hi;w.edit(p,p,3.5f,0,false,1,lo,hi,changes);}
   for(int step:{1,2,4}){
    auto density=[&](P p){for(int k=0;k<3;k++)p[k]+=center[k];int x=int(std::floor(p[0])),y=int(std::floor(p[1])),z=int(std::floor(p[2]));
     if(p[0]==x&&p[1]==y&&p[2]==z)return w.sample(x,y,z);
     double value=0;for(int k=0;k<8;k++){int dx=k&1,dy=(k>>1)&1,dz=(k>>2)&1;double wx=dx?p[0]-x:1-(p[0]-x),wy=dy?p[1]-y:1-(p[1]-y),wz=dz?p[2]-z:1-(p[2]-z);value+=wx*wy*wz*w.sample(x+dx,y+dy,z+dz);}return float(value);
    };size_t fine=0,joins=0;
    auto mesh=build(density,center,16,step,fine,joins,projected);int slot=step==1?0:step==2?1:2;bool changed=edited&&mesh!=previous[slot];failures+=emit("world",site,edited,step,center,16,mesh,fine,joins,changes,changed);previous[slot]=std::move(mesh);
   }
  }w.release();
 }return failures?1:0;
}
