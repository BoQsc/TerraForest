// Geometry feasibility probe, not a runtime cache or publication implementation.
#include "experimental/region_surface.hpp"
#include "experimental/region_dependencies.hpp"
#include "meshoptimizer.h"
#include <array>
#include <map>
#include <vector>
#include <chrono>
#include <cstdio>
#include <cstring>
using namespace terraforest::experimental;
using Point=std::array<float,3>;
using Edge=std::array<Point,2>;
using Edges=std::map<Edge,int>;
static double tick(){return std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now().time_since_epoch()).count();}
static Point point(V3 p){return {p.x,p.y,p.z};}
static Edges boundary(const Result&r,const std::vector<u32>&indices){
 Edges edges;
 for(size_t i=0;i<indices.size();i+=3)for(int k=0;k<3;k++){
  Point a=point(r.p[indices[i+k]]),b=point(r.p[indices[i+(k+1)%3]]);
  if(b<a)std::swap(a,b);edges[{a,b}]++;
 }
 for(auto it=edges.begin();it!=edges.end();)if(it->second==2)it=edges.erase(it);else ++it;
 return edges;
}
static Edges wall(const Edges&edges,int axis,float plane){
 Edges out;for(const auto&e:edges)if(e.first[0][axis]==plane&&e.first[1][axis]==plane)out.insert(e);return out;
}
struct Tile{
 RegionSurface surface;std::vector<u32> visible;Edges edges;
 size_t fine_triangles=0;bool border_ok=false;
 double build_ms=0,simplify_ms=0;
};
static Tile build(const World&w,int x,int z,bool coarse){
 Tile t;double begin=tick();t.surface=build_world_surface(w,x,z,32);t.build_ms=tick()-begin;
 if(!t.surface.ready())return t;
 const auto&r=t.surface.geometry;t.fine_triangles=r.indices.size()/3;
 std::vector<u32> original(r.indices.begin(),r.indices.end());t.visible=original;
 if(coarse&&!original.empty()){
  begin=tick();float error=0;
  size_t count=meshopt_simplify(t.visible.data(),original.data(),original.size(),&r.p[0].x,r.p.size(),sizeof(V3),
      std::max(size_t(12),original.size()/48*3),.05f,meshopt_SimplifyLockBorder|meshopt_SimplifyErrorAbsolute,&error);
  t.visible.resize(count);t.simplify_ms=tick()-begin;
 }
 t.edges=boundary(r,t.visible);auto before=boundary(r,original);t.border_ok=t.edges==before;
 for(const auto&e:before)if(e.second>2)t.border_ok=false;
 for(const auto&e:t.edges)if(e.second>2)t.border_ok=false;
 if(!t.border_ok){
  int witnesses=0;auto all=before;for(const auto&e:t.edges)all.emplace(e.first,0);
  for(const auto&e:all){auto found=t.edges.find(e.first);int after=found==t.edges.end()?0:found->second;
   if(after==e.second)continue;
   const auto&a=e.first[0];const auto&b=e.first[1];
   fprintf(stderr,"{\"kind\":\"border_witness\",\"x\":%d,\"z\":%d,\"before_count\":%d,\"after_count\":%d,\"a\":[%.9g,%.9g,%.9g],\"b\":[%.9g,%.9g,%.9g]}\n",x,z,e.second,after,a[0],a[1],a[2],b[0],b[1],b[2]);
   if(++witnesses==3)break;
  }
 }
 return t;
}
static size_t packed_bytes(const Tile&t){
 std::vector<bool> used(t.surface.geometry.p.size());size_t count=0;
 for(u32 i:t.visible)if(!used[i]){used[i]=true;count++;}
 // Existing v5 render channels: 56 bytes/vertex plus 4 bytes/index.
 return count*56+t.visible.size()*4;
}
static int geometry_failures(const std::vector<Tile>&tiles,int origin){
 int failures=0;
 for(int z=0;z<8;z++)for(int x=0;x<8;x++){
  const auto&t=tiles[x+8*z];failures+=!t.border_ok;
  for(int axis:{0,2}){
   if((axis==0?x:z)==7)continue;
   float plane=float(origin+((axis==0?x:z)+1)*32);
   auto a=wall(t.edges,axis,plane),b=wall(tiles[x+8*z+(axis==0?1:8)].edges,axis,plane);
   if(a==b)continue;failures++;
   int witnesses=0;
   for(int direction=0;direction<2;direction++){
    const auto&from=direction?b:a;const auto&to=direction?a:b;
    for(const auto&e:from){auto found=to.find(e.first);int other=found==to.end()?0:found->second;if(other==e.second)continue;
     const auto&p=e.first[0];const auto&q=e.first[1];
     fprintf(stderr,"{\"kind\":\"neighbor_witness\",\"x\":%d,\"z\":%d,\"axis\":%d,\"direction\":%d,\"count\":%d,\"other_count\":%d,\"a\":[%.9g,%.9g,%.9g],\"b\":[%.9g,%.9g,%.9g]}\n",origin+x*32,origin+z*32,axis,direction,e.second,other,p[0],p[1],p[2],q[0],q[1],q[2]);
     if(++witnesses>=3)break;
    }if(witnesses>=3)break;
   }
  }
 }return failures;
}
int main(){
 tr_alloc=std::malloc;tr_realloc=std::realloc;tr_free=std::free;int failures=0;
 for(int origin:{896,1280}){
  World w;w.init();std::vector<Tile> tiles;tiles.reserve(64);
  double begin=tick(),build_ms=0,simplify_ms=0;size_t fine=0,coarse=0,bytes=0;
  for(int z=0;z<8;z++)for(int x=0;x<8;x++){
   auto t=build(w,origin+x*32,origin+z*32,true);if(!t.surface.ready())return 2;
   build_ms+=t.build_ms;simplify_ms+=t.simplify_ms;fine+=t.fine_triangles;coarse+=t.visible.size()/3;bytes+=packed_bytes(t);tiles.push_back(std::move(t));
  }
  double cold=tick()-begin;int seams=geometry_failures(tiles,origin);failures+=seams;
  Mesh legacy;begin=tick();bool legacy_ok=build_patch(w,origin,origin,256,8,legacy);double legacy_ms=tick()-begin;
  printf("{\"kind\":\"cold\",\"origin\":%d,\"regions\":64,\"surface_ms\":%.6f,\"simplify_ms\":%.6f,\"probe_total_ms\":%.6f,\"fine_triangles\":%zu,\"coarse_triangles\":%zu,\"packed_render_bytes\":%zu,\"legacy_ms\":%.6f,\"legacy_triangles\":%d,\"legacy_ok\":%s,\"geometry_failures\":%d}\n",origin,build_ms,simplify_ms,cold,fine,coarse,bytes,legacy_ms,legacy.i.n/3,legacy_ok?"true":"false",seams);fflush(stdout);legacy.release();failures+=!legacy_ok;
  for(int placement=0;placement<3;placement++){
   // Separate locations within the same large patch; each edit retains earlier edits.
   int x=origin+(placement==0?48:placement==1?96:128),z=origin+(placement==2?96:48);
   V3 p={float(x),w.height(float(x),float(z))-1,float(z)},lo,hi;int changes=0;
   begin=tick();bool changed=w.edit(p,p,2.5f,0,false,1,lo,hi,changes);double edit_ms=tick()-begin;
   int selected=0;double local_ms=0,local_surface_ms=0;size_t changed_bytes=0,local_triangles=0;
   for(auto&t:tiles){
    auto&s=t.surface;
    if(!edit_affects_region_normals(s.x,s.z,32,lo,hi))continue;
    selected++;begin=tick();auto replacement=build(w,s.x,s.z,false);local_ms+=tick()-begin;
    if(!replacement.surface.ready())return 3;
    local_surface_ms+=replacement.build_ms;changed_bytes+=packed_bytes(replacement);local_triangles+=replacement.visible.size()/3;t=std::move(replacement);
   }
   // A complete fresh reconstruction is an independent invalidation oracle;
   // its cost is excluded from the measured local reconstruction interval.
   int stale=0;
   for(const auto&t:tiles){const auto&s=t.surface;auto fresh=build_world_surface(w,s.x,s.z,32);
    stale+=!fresh.ready()||fresh.geometry.p!=s.geometry.p||fresh.geometry.indices!=s.geometry.indices||fresh.normals.values!=s.normals.values;
   }
   seams=geometry_failures(tiles,origin);size_t visible=0;for(const auto&t:tiles)visible+=t.visible.size()/3;
   bool ok=changed&&selected==(1<<placement)&&!seams&&!stale;failures+=!ok;
   printf("{\"kind\":\"edit\",\"origin\":%d,\"placement\":%d,\"selected\":%d,\"edit_ms\":%.6f,\"local_surface_ms\":%.6f,\"local_surface_and_boundary_ms\":%.6f,\"changed_render_bytes\":%zu,\"changed_triangles\":%zu,\"visible_triangles\":%zu,\"stale_regions\":%d,\"geometry_failures\":%d,\"passed\":%s}\n",origin,placement,selected,edit_ms,local_surface_ms,local_ms,changed_bytes,local_triangles,visible,stale,seams,ok?"true":"false");fflush(stdout);
  }
  w.release();
 }
 return failures?1:0;
}
