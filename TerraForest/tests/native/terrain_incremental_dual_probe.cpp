// SPDX-License-Identifier: 0BSD
#include "core.h"
#include "incremental_dual_probe.hpp"
#include <chrono>
#include <cstdio>
using namespace dual_probe;
static double now(){return std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now().time_since_epoch()).count();}
static double canonical(float density){float v=std::max(-4.f,std::min(4.f,density))*1024.f;int q=int(v>=0?v+.5f:v-.5f);return q?double(q)/1024:.5/1024;}
struct Audit{int open=0,overused=0,winding=0,degenerate=0,links=0;};
template<class Field>static Audit audit(const dual_probe::Mesh<Field>&mesh){
 using E=std::array<P,2>;struct Use{int count=0,balance=0;};std::map<E,Use> edges;std::map<P,std::vector<E>> links;std::map<P,unsigned> boundary;Audit out;
 for(const auto&c:mesh.cells)if(c.active){unsigned mask=0;for(int k=0;k<3;k++){if(c.lo[k]==0)mask|=1u<<(2*k);if(c.lo[k]+c.size==mesh.side)mask|=2u<<(2*k);}boundary[c.vertex]|=mask;}
 for(size_t id=0;id<mesh.edges.size();id++){auto poly=mesh.polygon(int(id));for(size_t t=1;t+1<poly.size();t++){
  P p[3]={mesh.cells[poly[0]].vertex,mesh.cells[poly[t]].vertex,mesh.cells[poly[t+1]].vertex};double a[3],b[3],area=0;for(int k=0;k<3;k++){a[k]=p[1][k]-p[0][k];b[k]=p[2][k]-p[0][k];}for(int k=0;k<3;k++){double v=a[(k+1)%3]*b[(k+2)%3]-a[(k+2)%3]*b[(k+1)%3];area+=v*v;}out.degenerate+=area==0;
  for(int k=0;k<3;k++){P a=p[k],b=p[(k+1)%3];bool reverse=b<a;if(reverse)std::swap(a,b);auto&u=edges[{a,b}];u.count++;u.balance+=reverse?-1:1;links[p[k]].push_back({p[(k+1)%3],p[(k+2)%3]});}
 }}
 int witnesses=0;
 for(const auto&item:edges){const auto&e=item.first;const auto&u=item.second;out.overused+=u.count>2;out.winding+=u.count==2&&u.balance!=0;out.open+=u.count==1&&!(boundary[e[0]]&boundary[e[1]]);
  if(u.count>2&&witnesses++<2){fprintf(stderr,"{\"kind\":\"overused_edge\",\"extent\":%d,\"incidence\":%d,\"cells\":[",mesh.side,u.count);int count=0;for(const auto&c:mesh.cells)if(c.vertex==e[0]||c.vertex==e[1]){unsigned signs=0;for(int k=0;k<8;k++)if(mesh.field({double(c.lo[0]+(k&1)*c.size),double(c.lo[1]+((k>>1)&1)*c.size),double(c.lo[2]+((k>>2)&1)*c.size)})<0)signs|=1u<<k;fprintf(stderr,"%s{\"lo\":[%d,%d,%d],\"size\":%d,\"signs\":%u}",count++?",":"",c.lo[0],c.lo[1],c.lo[2],c.size,signs);}fprintf(stderr,"]}\n");}
 }
 for(const auto&item:links){std::map<P,std::vector<P>> graph;for(auto e:item.second){graph[e[0]].push_back(e[1]);graph[e[1]].push_back(e[0]);}bool bad=false;int endpoints=0;for(const auto&v:graph){bad|=v.second.size()>2;endpoints+=v.second.size()==1;}bad|=boundary[item.first]?(endpoints!=0&&endpoints!=2):endpoints!=0;std::set<P> seen;std::vector<P> todo{graph.begin()->first};while(!todo.empty()){P p=todo.back();todo.pop_back();if(!seen.insert(p).second)continue;for(P q:graph[p])todo.push_back(q);}bad|=seen.size()!=graph.size();out.links+=bad;}return out;
}
template<class Field,class Edit>static int run(const char*kind,int extent,Field field,Edit edit){
 double start=now();dual_probe::Mesh<Field> mesh(field,extent);double cold=now()-start;int failures=0;
 for(int iteration=0;iteration<4;iteration++){
  double edit_ms=0,oracle_ms=0;bool equal=true,changed=true;
  if(iteration){Box box;changed=edit(iteration,box);start=now();mesh.edit(box);edit_ms=now()-start;start=now();dual_probe::Mesh<Field> fresh(field,extent);oracle_ms=now()-start;equal=mesh.same(fresh);}
  auto a=audit(mesh);bool passed=equal&&changed&&!(a.open||a.overused||a.winding||a.degenerate||a.links);failures+=!passed;
  printf("{\"kind\":\"%s\",\"extent\":%d,\"edit\":%d,\"leaves\":%zu,\"shared_edges\":%zu,\"triangles\":%zu,\"cold_ms\":%.6f,\"local_update_ms\":%.6f,\"oracle_ms\":%.6f,\"candidate_edges\":%zu,\"reevaluated_edges\":%zu,\"refitted_cells\":%zu,\"affected_faces\":%zu,\"local_samples\":%zu,\"fresh_equal\":%s,\"edit_changed\":%s,\"internal_open_edges\":%d,\"overused_edges\":%d,\"winding_errors\":%d,\"degenerate_triangles\":%d,\"invalid_vertex_links\":%d,\"passed\":%s}\n",kind,extent,iteration,mesh.cells.size(),mesh.edges.size(),mesh.triangles(),cold,edit_ms,oracle_ms,mesh.last.candidates,mesh.last.edges,mesh.last.cells,mesh.last.faces,mesh.last.samples,equal?"true":"false",changed?"true":"false",a.open,a.overused,a.winding,a.degenerate,a.links,passed?"true":"false");fflush(stdout);
 }return failures;
}
int main(){
 tr_alloc=std::malloc;tr_realloc=std::realloc;tr_free=std::free;int failures=0;
 for(int extent:{32,64,128}){
  std::vector<P> cuts;double center=extent*.5;
  auto field=[&](P p){double r=0;for(int k=0;k<3;k++)r+=(p[k]-center)*(p[k]-center);double d=std::max(-4.,std::min(4.,std::sqrt(r)-12));for(P c:cuts){r=0;for(int k=0;k<3;k++)r+=(p[k]-c[k])*(p[k]-c[k]);d=std::max(d,std::min(4.,2.5-std::sqrt(r)));}return d;};
  auto edit=[&](int n,Box&box){P c={center+(n>=2?8:0),center-(n==3?8:0),center+(n==3?8:0)};cuts.push_back(c);for(int k=0;k<3;k++){box.lo[k]=int(c[k])-7;box.hi[k]=int(c[k])+7;}return true;};
  failures+=run("sphere",extent,field,edit);
  World world;world.init();P anchor={1024,double(int(world.height(1024,1024))-1),1024};
  auto terrain=[&](P p){for(int k=0;k<3;k++)p[k]+=anchor[k]-center;int x=int(std::floor(p[0])),y=int(std::floor(p[1])),z=int(std::floor(p[2]));if(p[0]==x&&p[1]==y&&p[2]==z)return canonical(world.sample(x,y,z));double d=0;for(int k=0;k<8;k++){int dx=k&1,dy=(k>>1)&1,dz=(k>>2)&1;d+=(dx?p[0]-x:1-(p[0]-x))*(dy?p[1]-y:1-(p[1]-y))*(dz?p[2]-z:1-(p[2]-z))*canonical(world.sample(x+dx,y+dy,z+dz));}return d;};
  auto terrain_edit=[&](int n,Box&box){V3 p={float(anchor[0]+(n>=2?8:0)),float(anchor[1]-(n>=2?8:0)),float(anchor[2]+(n==3?8:0))},lo,hi;int changes=0;bool changed=world.edit(p,p,2.5f,0,false,1,lo,hi,changes);float low[3]={lo.x,lo.y,lo.z},high[3]={hi.x,hi.y,hi.z};for(int k=0;k<3;k++){box.lo[k]=int(std::floor(low[k]-anchor[k]+center));box.hi[k]=int(std::ceil(high[k]-anchor[k]+center));}return changed&&changes>0;};
  failures+=run("world",extent,terrain,terrain_edit);world.release();
 }return failures?1:0;
}
