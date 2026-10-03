// SPDX-License-Identifier: 0BSD
#pragma once
#include "incremental_dual_probe.hpp"
#include <cstdio>
namespace dual_probe {
struct Audit{int open=0,overused=0,winding=0,degenerate=0,links=0;};
template<class Field>static Audit audit(const dual_probe::Mesh<Field>&mesh){
 using E=std::array<P,2>;struct Use{int count=0,balance=0;};std::map<E,Use> edges;std::map<P,std::vector<E>> links;std::map<P,unsigned> boundary;Audit out;
 for(const auto&c:mesh.cells)if(c.active){unsigned mask=0;for(int k=0;k<3;k++){if(c.lo[k]==0)mask|=1u<<(2*k);if(c.lo[k]+c.size==mesh.side)mask|=2u<<(2*k);}for(P vertex:c.vertices)boundary[vertex]|=mask;}
 for(size_t id=0;id<mesh.edge_count();id++){auto poly=mesh.polygon(int(id));for(size_t t=1;t+1<poly.size();t++){
  P p[3]={mesh.position(poly[0]),mesh.position(poly[t]),mesh.position(poly[t+1])};double a[3],b[3],area=0;for(int k=0;k<3;k++){a[k]=p[1][k]-p[0][k];b[k]=p[2][k]-p[0][k];}for(int k=0;k<3;k++){double v=a[(k+1)%3]*b[(k+2)%3]-a[(k+2)%3]*b[(k+1)%3];area+=v*v;}out.degenerate+=area==0;
  for(int k=0;k<3;k++){P a=p[k],b=p[(k+1)%3];bool reverse=b<a;if(reverse)std::swap(a,b);auto&u=edges[{a,b}];u.count++;u.balance+=reverse?-1:1;links[p[k]].push_back({p[(k+1)%3],p[(k+2)%3]});}
 }}
 int witnesses=0;
 for(const auto&item:edges){const auto&e=item.first;const auto&u=item.second;out.overused+=u.count>2;out.winding+=u.count==2&&u.balance!=0;out.open+=u.count==1&&!(boundary[e[0]]&boundary[e[1]]);
  if(u.count>2&&witnesses++<2){fprintf(stderr,"{\"kind\":\"overused_edge\",\"extent\":%d,\"incidence\":%d,\"cells\":[",mesh.side,u.count);int count=0;for(const auto&c:mesh.cells)if(c.vertex==e[0]||c.vertex==e[1]){unsigned signs=0;for(int k=0;k<8;k++)if(mesh.field({double(c.lo[0]+(k&1)*c.size),double(c.lo[1]+((k>>1)&1)*c.size),double(c.lo[2]+((k>>2)&1)*c.size)})<0)signs|=1u<<k;fprintf(stderr,"%s{\"lo\":[%d,%d,%d],\"size\":%d,\"signs\":%u}",count++?",":"",c.lo[0],c.lo[1],c.lo[2],c.size,signs);}fprintf(stderr,"]}\n");}
 }
 for(const auto&item:links){std::map<P,std::vector<P>> graph;for(auto e:item.second){graph[e[0]].push_back(e[1]);graph[e[1]].push_back(e[0]);}bool bad=false;int endpoints=0;for(const auto&v:graph){bad|=v.second.size()>2;endpoints+=v.second.size()==1;}bad|=boundary[item.first]?(endpoints!=0&&endpoints!=2):endpoints!=0;std::set<P> seen;std::vector<P> todo{graph.begin()->first};while(!todo.empty()){P p=todo.back();todo.pop_back();if(!seen.insert(p).second)continue;for(P q:graph[p])todo.push_back(q);}bad|=seen.size()!=graph.size();out.links+=bad;}return out;
}
} // namespace dual_probe
