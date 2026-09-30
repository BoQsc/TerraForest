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
#include <unordered_map>
#include <chrono>
#include <cstring>
namespace dual_probe {
using P=std::array<double,3>;using I=std::array<int,3>;using Key=std::array<int,5>;
struct Box{I lo,hi;};
static bool overlap(Box a,Box b){for(int k=0;k<3;k++)if(a.lo[k]>b.hi[k]||b.lo[k]>a.hi[k])return false;return true;}
struct Cell{I lo;int size;std::vector<int> edges;P vertex{};bool active=false;std::vector<P> vertices;std::map<int,int> edge_component;int unrepresented_loops=0;};
struct Edge{I lo;int axis,size;std::array<int,4> cells;Box dependency;P point{},normal{};bool active=false,negative=false;};
struct Work{size_t candidates=0,edges=0,cells=0,faces=0,samples=0;};
static int floor_div(int x,int d){int q=x/d;return q-(x<0&&x%d!=0);}
struct IHash{size_t operator()(const I&p)const{return size_t(uint32_t(p[0])*73856093u^uint32_t(p[1])*19349663u^uint32_t(p[2])*83492791u);}};
static uint64_t cell_key(I p,int size){return uint64_t(p[0])|(uint64_t(p[1])<<16)|(uint64_t(p[2])<<32)|(uint64_t(size)<<48);}
static double clock_ms(){return std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now().time_since_epoch()).count();}
template<class Field>struct Mesh {
 Field field;int side;std::vector<Cell> cells;std::vector<Edge> edges;
 std::unordered_map<uint64_t,int> lookup;std::unordered_map<I,std::vector<int>,IHash> buckets;
 size_t samples=0;Work last;std::array<double,4> cold_stages{};
 Mesh(Field f,int extent):field(f),side(extent){double t=clock_ms();subdivide({0,0,0},side);cold_stages[0]=clock_ms()-t;t=clock_ms();make_edges();cold_stages[1]=clock_ms()-t;t=clock_ms();for(auto&e:edges)evaluate(e);cold_stages[2]=clock_ms()-t;t=clock_ms();for(size_t c=0;c<cells.size();c++)fit(int(c));cold_stages[3]=clock_ms()-t;}
 void subdivide(I lo,int size){
  int center=side/2;bool near=true;for(int k=0;k<3;k++)near&=lo[k]<center+8&&lo[k]+size>center-8;
  if(size>8||(near&&size>1)){int half=size/2;for(int k=0;k<8;k++)subdivide({lo[0]+(k&1)*half,lo[1]+((k>>1)&1)*half,lo[2]+((k>>2)&1)*half},half);return;}
  int id=int(cells.size());cells.push_back({lo,size});lookup[cell_key(lo,size)]=id;
 }
 int owner(I p)const{
  for(int k=0;k<3;k++)if(p[k]<0||p[k]>=side)return -1;
  for(int size=1;size<=8;size*=2){auto it=lookup.find(cell_key({p[0]/size*size,p[1]/size*size,p[2]/size*size},size));if(it!=lookup.end())return it->second;}return -1;
 }
 std::array<int,4> incident(I p,int axis,int size)const{
  int b=(axis+1)%3,c=(axis+2)%3;const int db[4]={-1,0,0,-1},dc[4]={-1,-1,0,0};std::array<int,4> ids;
  for(int i=0;i<4;i++){I q=p;q[axis]+=(size-1)/2;q[b]+=db[i];q[c]+=dc[i];ids[i]=owner(q);}return ids;
 }
 void divide_edge(I p,int axis,int size,std::vector<Key>&keys){
  for(int k=0;k<3;k++)if(k!=axis&&(p[k]==0||p[k]==side))return;
  for(int offset=0;offset<size;offset++){keys.push_back({axis,p[0],p[1],p[2],1});p[axis]++;}
 }
 void make_edges(){
  std::vector<Key> keys;
  for(const auto&c:cells)for(int a=0;a<3;a++)for(int b=0;b<2;b++)for(int d=0;d<2;d++){I p=c.lo;p[(a+1)%3]+=b*c.size;p[(a+2)%3]+=d*c.size;divide_edge(p,a,c.size,keys);}
  std::sort(keys.begin(),keys.end());keys.erase(std::unique(keys.begin(),keys.end()),keys.end());edges.reserve(keys.size());
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
 P fit_group(int id,const std::vector<int>&group){
  auto&cell=cells[id];double A[3][3]={},B[3]={};P mass{};int count=0;
  for(int index:group){const auto&e=edges[index];if(!e.active)continue;count++;double rhs=0;for(int k=0;k<3;k++){mass[k]+=e.point[k]-cell.lo[k];rhs+=e.normal[k]*(e.point[k]-cell.lo[k]);}for(int k=0;k<3;k++){B[k]+=e.normal[k]*rhs;for(int j=0;j<3;j++)A[k][j]+=e.normal[k]*e.normal[j];}}
  if(!count)return {};
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
  for(int k=0;k<3;k++)chosen[k]+=cell.lo[k];return chosen;
 }
 void fit(int id){
  auto&cell=cells[id];cell.active=false;cell.vertex={};cell.vertices.clear();cell.edge_component.clear();cell.unrepresented_loops=0;
  bool active=false;for(int e:cell.edges)active|=edges[e].active;if(!active)return;
  // Trace surface components on a canonically triangulated unit boundary.
  // Adjacent cells sample the same face triangulation and zero tie rule.
  using Segment=std::array<I,2>;std::map<Segment,int> nodes;std::vector<int> parent;std::map<I,double> density;
  auto root=[&](int n){while(parent[n]!=n){parent[n]=parent[parent[n]];n=parent[n];}return n;};
  auto node=[&](I a,I b){if(b<a)std::swap(a,b);Segment key{a,b};auto it=nodes.find(key);if(it!=nodes.end())return it->second;int n=int(parent.size());nodes[key]=n;parent.push_back(n);return n;};
  auto value=[&](I p){auto it=density.find(p);if(it!=density.end())return it->second;double d=sample({double(p[0]),double(p[1]),double(p[2])});density[p]=d;return d;};
  for(int axis=0;axis<3;axis++)for(int side=0;side<2;side++)for(int v=0;v<cell.size;v++)for(int u=0;u<cell.size;u++){
   int b=(axis+1)%3,c=(axis+2)%3;I p[4];const int du[4]={0,1,1,0},dv[4]={0,0,1,1};double d[4];
   for(int k=0;k<4;k++){p[k]=cell.lo;p[k][axis]+=side*cell.size;p[k][b]+=u+du[k];p[k][c]+=v+dv[k];d[k]=value(p[k]);}
   for(int t=0;t<2;t++){int corners[3]={0,t+1,t+2},crossings[2],count=0;for(int k=0;k<3;k++){int a=corners[k],b=corners[(k+1)%3];if((d[a]<0)!=(d[b]<0))crossings[count++]=node(p[a],p[b]);}if(count==2){int a=root(crossings[0]),b=root(crossings[1]);if(a!=b)parent[b]=a;}}
  }
  std::map<int,std::vector<int>> groups;
  for(int index:cell.edges){const auto&e=edges[index];if(!e.active)continue;I a=e.lo,b=a;b[e.axis]+=e.size;auto it=nodes.find({a,b});
   // A missing boundary node is kept separate so an incomplete face contract
   // cannot silently collapse it into another surface component.
   int component=it==nodes.end()?-index-1:root(it->second);groups[component].push_back(index);
  }
  std::set<int> boundary_components;for(size_t n=0;n<parent.size();n++)boundary_components.insert(root(int(n)));for(int component:boundary_components)cell.unrepresented_loops+=groups.find(component)==groups.end();
  std::vector<std::vector<int>> ordered;for(auto&item:groups)ordered.push_back(std::move(item.second));std::sort(ordered.begin(),ordered.end(),[](const auto&a,const auto&b){return a[0]<b[0];});
  for(const auto&group:ordered){int component=int(cell.vertices.size());cell.vertices.push_back(fit_group(id,group));for(int e:group)cell.edge_component[e]=component;}
  cell.active=!cell.vertices.empty();if(cell.active)cell.vertex=cell.vertices[0];
 }
 using Vertex=std::array<int,2>;
 P position(Vertex v)const{return cells[v[0]].vertices[v[1]];}
 std::vector<Vertex> polygon(int id)const{
  const auto&e=edges[id];if(!e.active)return {};std::vector<Vertex> p;for(int cell:e.cells){auto it=cells[cell].edge_component.find(id);if(it==cells[cell].edge_component.end())return {};Vertex v={cell,it->second};if(p.empty()||p.back()!=v)p.push_back(v);}if(p.size()>1&&p.front()==p.back())p.pop_back();if(p.size()<3)return {};if(!e.negative)std::reverse(p.begin(),p.end());return p;
 }
 void edit(Box box){
  size_t before=samples;std::set<int> candidates,changed_cells,changed_faces;last={};
  for(int z=floor_div(box.lo[2],4);z<=floor_div(box.hi[2],4);z++)for(int y=floor_div(box.lo[1],4);y<=floor_div(box.hi[1],4);y++)for(int x=floor_div(box.lo[0],4);x<=floor_div(box.hi[0],4);x++){auto it=buckets.find({x,y,z});if(it!=buckets.end())candidates.insert(it->second.begin(),it->second.end());}
  last.candidates=candidates.size();for(int id:candidates){auto&e=edges[id];if(!overlap(e.dependency,box))continue;last.edges++;Edge old=e;evaluate(e);if(e.active==old.active&&e.negative==old.negative&&e.point==old.point&&e.normal==old.normal)continue;changed_faces.insert(id);for(int c:e.cells)changed_cells.insert(c);}
  // Face connectivity depends on boundary samples beyond active crossing edges.
  // Gather owners near edited samples even if their existing crossings did not move.
  for(int z=std::max(0,box.lo[2]-1);z<=std::min(side-1,box.hi[2]);z++)for(int y=std::max(0,box.lo[1]-1);y<=std::min(side-1,box.hi[1]);y++)for(int x=std::max(0,box.lo[0]-1);x<=std::min(side-1,box.hi[0]);x++){int id=owner({x,y,z});if(id>=0&&cells[id].active)changed_cells.insert(id);}
  for(int c:changed_cells){auto old_vertices=cells[c].vertices;auto old_components=cells[c].edge_component;fit(c);if(old_vertices==cells[c].vertices&&old_components==cells[c].edge_component)continue;for(int edge:cells[c].edges)changed_faces.insert(edge);}last.cells=changed_cells.size();last.faces=changed_faces.size();last.samples=samples-before;
 }
 size_t triangles()const{size_t n=0;for(size_t i=0;i<edges.size();i++){auto p=polygon(int(i));if(p.size()>2)n+=p.size()-2;}return n;}
 size_t unmapped_crossings()const{size_t n=0;for(size_t i=0;i<edges.size();i++)if(edges[i].active)for(int cell:edges[i].cells)n+=cells[cell].edge_component.find(int(i))==cells[cell].edge_component.end();return n;}
 size_t unrepresented_loops()const{size_t n=0;for(const auto&cell:cells)n+=cell.unrepresented_loops;return n;}
 size_t edge_payload_bytes()const{return edges.capacity()*sizeof(Edge);}
 size_t dependency_payload_bytes()const{size_t n=0;for(const auto&item:buckets)n+=item.second.capacity()*sizeof(int);for(const auto&c:cells)n+=c.edges.capacity()*sizeof(int);return n;}
 uint64_t fingerprint()const{
  uint64_t hash=14695981039346656037ull;auto add=[&](uint64_t bits){for(int i=0;i<8;i++){hash^=(bits>>(i*8))&255;hash*=1099511628211ull;}};
  auto point=[&](P p){for(double v:p){uint64_t bits;std::memcpy(&bits,&v,8);add(bits);}};
  for(const auto&c:cells){add(c.vertices.size());for(P p:c.vertices)point(p);add(c.edge_component.size());for(const auto&item:c.edge_component){add(item.first);add(item.second);}}
  for(size_t i=0;i<edges.size();i++){const auto&e=edges[i];add(e.active);add(e.negative);point(e.point);point(e.normal);auto p=polygon(int(i));add(p.size());for(Vertex v:p){add(v[0]);add(v[1]);}}return hash;
 }
 bool same(const Mesh&other)const{
  if(cells.size()!=other.cells.size()||edges.size()!=other.edges.size())return false;
  for(size_t i=0;i<cells.size();i++)if(cells[i].active!=other.cells[i].active||cells[i].vertices!=other.cells[i].vertices||cells[i].edge_component!=other.cells[i].edge_component||cells[i].unrepresented_loops!=other.cells[i].unrepresented_loops)return false;
  for(size_t i=0;i<edges.size();i++){const auto&a=edges[i];const auto&b=other.edges[i];if(a.active!=b.active||a.negative!=b.negative||a.point!=b.point||a.normal!=b.normal||polygon(int(i))!=other.polygon(int(i)))return false;}return true;
 }
};
} // namespace dual_probe
