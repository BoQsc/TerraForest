// SPDX-License-Identifier: 0BSD
// Independent feasibility prototype. No runtime integration or third-party tables.
#pragma once
#include <array>
#include <vector>
#include <map>
#include <set>
#include <cmath>
#include <algorithm>
#include <cstdint>
namespace dual_probe {
using P=std::array<double,3>;using I=std::array<int,3>;using Key=std::array<int,5>;
struct Box{I lo,hi;};
static bool overlap(Box a,Box b){for(int k=0;k<3;k++)if(a.lo[k]>b.hi[k]||b.lo[k]>a.hi[k])return false;return true;}
struct Cell{I lo;int size;std::vector<int> edges;P vertex{};bool active=false;};
struct Edge{I lo;int axis,size;std::array<int,4> cells;Box dependency;P point{},normal{};bool active=false,negative=false;};
struct Work{size_t candidates=0,edges=0,cells=0,faces=0,samples=0;};
static int floor_div(int x,int d){int q=x/d;return q-(x<0&&x%d!=0);}
template<class Field>struct Mesh {
 Field field;int side;std::vector<Cell> cells;std::vector<Edge> edges;
 std::map<std::array<int,4>,int> lookup;std::map<I,std::vector<int>> buckets;
 size_t samples=0;Work last;
 Mesh(Field f,int extent):field(f),side(extent){subdivide({0,0,0},side);make_edges();for(auto&e:edges)evaluate(e);for(size_t c=0;c<cells.size();c++)fit(int(c));}
 void subdivide(I lo,int size){
  int center=side/2;bool near=true;for(int k=0;k<3;k++)near&=lo[k]<center+8&&lo[k]+size>center-8;
  if(size>8||(near&&size>1)){int half=size/2;for(int k=0;k<8;k++)subdivide({lo[0]+(k&1)*half,lo[1]+((k>>1)&1)*half,lo[2]+((k>>2)&1)*half},half);return;}
  int id=int(cells.size());cells.push_back({lo,size});lookup[{lo[0],lo[1],lo[2],size}]=id;
 }
 int owner(I p)const{
  for(int k=0;k<3;k++)if(p[k]<0||p[k]>=side)return -1;
  for(int size=1;size<=8;size*=2){auto it=lookup.find({p[0]/size*size,p[1]/size*size,p[2]/size*size,size});if(it!=lookup.end())return it->second;}return -1;
 }
 std::array<int,4> incident(I p,int axis,int size)const{
  int b=(axis+1)%3,c=(axis+2)%3;const int db[4]={-1,0,0,-1},dc[4]={-1,-1,0,0};std::array<int,4> ids;
  for(int i=0;i<4;i++){I q=p;q[axis]+=(size-1)/2;q[b]+=db[i];q[c]+=dc[i];ids[i]=owner(q);}return ids;
 }
 void divide_edge(I p,int axis,int size,std::set<Key>&keys){
  auto ids=incident(p,axis,size);int minimum=size;for(int id:ids)if(id>=0)minimum=std::min(minimum,cells[id].size);
  if(minimum<size){divide_edge(p,axis,size/2,keys);p[axis]+=size/2;divide_edge(p,axis,size/2,keys);return;}
  for(int id:ids)if(id<0)return;keys.insert({axis,p[0],p[1],p[2],size});
 }
 void make_edges(){
  std::set<Key> keys;
  for(const auto&c:cells)for(int a=0;a<3;a++)for(int b=0;b<2;b++)for(int d=0;d<2;d++){I p=c.lo;p[(a+1)%3]+=b*c.size;p[(a+2)%3]+=d*c.size;divide_edge(p,a,c.size,keys);}
  for(const auto&key:keys){I p={key[1],key[2],key[3]};int a=key[0],size=key[4],id=int(edges.size());auto ids=incident(p,a,size);Box dep{p,p};dep.hi[a]+=size;for(int k=0;k<3;k++){dep.lo[k]-=1;dep.hi[k]+=1;}edges.push_back({p,a,size,ids,dep});
   std::set<int> unique(ids.begin(),ids.end());for(int cell:unique)cells[cell].edges.push_back(id);
   for(int z=floor_div(dep.lo[2],4);z<=floor_div(dep.hi[2],4);z++)for(int y=floor_div(dep.lo[1],4);y<=floor_div(dep.hi[1],4);y++)for(int x=floor_div(dep.lo[0],4);x<=floor_div(dep.hi[0],4);x++)buckets[{x,y,z}].push_back(id);
  }
 }
 double sample(P p){samples++;double d=field(p);return d==0?.5/1024:d;}
 void evaluate(Edge&e){
  P a={double(e.lo[0]),double(e.lo[1]),double(e.lo[2])},b=a;b[e.axis]+=e.size;double da=sample(a),db=sample(b);e.active=(da<0)!=(db<0);e.negative=da<0;
  e.point={};e.normal={};if(!e.active)return;
  double t=da/(da-db);e.point=a;e.point[e.axis]+=t*e.size;double length=0;
  for(int k=0;k<3;k++){a=e.point;b=e.point;a[k]-=.5;b[k]+=.5;e.normal[k]=sample(b)-sample(a);length+=e.normal[k]*e.normal[k];}
  if(length>1e-24){for(double&v:e.normal)v/=std::sqrt(length);}else{e.normal={};e.normal[e.axis]=e.negative?1:-1;}
 }
 static bool solve(double a[3][3],double b[3],int n,double result[3]){
  for(int i=0;i<n;i++){int pivot=i;for(int j=i+1;j<n;j++)if(std::abs(a[j][i])>std::abs(a[pivot][i]))pivot=j;if(std::abs(a[pivot][i])<1e-14)return false;for(int k=0;k<n;k++)std::swap(a[i][k],a[pivot][k]);std::swap(b[i],b[pivot]);double d=a[i][i];for(int k=i;k<n;k++)a[i][k]/=d;b[i]/=d;for(int j=0;j<n;j++)if(j!=i){d=a[j][i];for(int k=i;k<n;k++)a[j][k]-=d*a[i][k];b[j]-=d*b[i];}}
  for(int i=0;i<n;i++)result[i]=b[i];return true;
 }
 void fit(int id){
  auto&cell=cells[id];double A[3][3]={},B[3]={};P mass{};int count=0;
  for(int index:cell.edges){const auto&e=edges[index];if(!e.active)continue;count++;double rhs=0;for(int k=0;k<3;k++){mass[k]+=e.point[k]-cell.lo[k];rhs+=e.normal[k]*(e.point[k]-cell.lo[k]);}for(int k=0;k<3;k++){B[k]+=e.normal[k]*rhs;for(int j=0;j<3;j++)A[k][j]+=e.normal[k]*e.normal[j];}}
  cell.active=count>0;cell.vertex={};if(!count)return;
  double lambda=count*1e-6;for(int k=0;k<3;k++){mass[k]/=count;A[k][k]+=lambda;B[k]+=lambda*mass[k];}
  double best=1e300;P chosen=mass;
  // Box-constrained least squares: free solution first, active bounds only
  // when necessary. Regularization selects a stable point for rank-deficient QEFs.
  for(int state=0;state<27;state++){int code=state,n=0,index[3];P p{};bool fixed[3];
   for(int k=0;k<3;k++){int mode=code%3;code/=3;fixed[k]=mode!=0;p[k]=mode==2?cell.size:0;if(!fixed[k])index[n++]=k;}
   double a[3][3]={},b[3]={},answer[3]={};for(int i=0;i<n;i++){int k=index[i];b[i]=B[k];for(int j=0;j<3;j++)if(fixed[j])b[i]-=A[k][j]*p[j];for(int j=0;j<n;j++)a[i][j]=A[k][index[j]];}
   if(n&&!solve(a,b,n,answer))continue;for(int i=0;i<n;i++)p[index[i]]=answer[i];bool valid=true;for(double v:p)valid&=v>=0&&v<=cell.size;if(!valid)continue;
   double error=0;for(int k=0;k<3;k++){error-=2*B[k]*p[k];for(int j=0;j<3;j++)error+=p[k]*A[k][j]*p[j];}if(error<best){best=error;chosen=p;}if(state==0)break;
  }
  for(int k=0;k<3;k++)cell.vertex[k]=cell.lo[k]+chosen[k];
 }
 std::vector<int> polygon(int id)const{
  const auto&e=edges[id];if(!e.active)return {};std::vector<int> p;for(int cell:e.cells)if(p.empty()||p.back()!=cell)p.push_back(cell);if(p.size()>1&&p.front()==p.back())p.pop_back();if(p.size()<3)return {};if(!e.negative)std::reverse(p.begin(),p.end());return p;
 }
 void edit(Box box){
  size_t before=samples;std::set<int> candidates,changed_cells,changed_faces;last={};
  for(int z=floor_div(box.lo[2],4);z<=floor_div(box.hi[2],4);z++)for(int y=floor_div(box.lo[1],4);y<=floor_div(box.hi[1],4);y++)for(int x=floor_div(box.lo[0],4);x<=floor_div(box.hi[0],4);x++){auto it=buckets.find({x,y,z});if(it!=buckets.end())candidates.insert(it->second.begin(),it->second.end());}
  last.candidates=candidates.size();for(int id:candidates){auto&e=edges[id];if(!overlap(e.dependency,box))continue;last.edges++;Edge old=e;evaluate(e);if(e.active==old.active&&e.negative==old.negative&&e.point==old.point&&e.normal==old.normal)continue;changed_faces.insert(id);for(int c:e.cells)changed_cells.insert(c);}
  for(int c:changed_cells){fit(c);for(int edge:cells[c].edges)changed_faces.insert(edge);}last.cells=changed_cells.size();last.faces=changed_faces.size();last.samples=samples-before;
 }
 size_t triangles()const{size_t n=0;for(size_t i=0;i<edges.size();i++){auto p=polygon(int(i));if(p.size()>2)n+=p.size()-2;}return n;}
 bool same(const Mesh&other)const{
  if(cells.size()!=other.cells.size()||edges.size()!=other.edges.size())return false;
  for(size_t i=0;i<cells.size();i++)if(cells[i].active!=other.cells[i].active||cells[i].vertex!=other.cells[i].vertex)return false;
  for(size_t i=0;i<edges.size();i++){const auto&a=edges[i];const auto&b=other.edges[i];if(a.active!=b.active||a.negative!=b.negative||a.point!=b.point||a.normal!=b.normal||polygon(int(i))!=other.polygon(int(i)))return false;}return true;
 }
};
} // namespace dual_probe
