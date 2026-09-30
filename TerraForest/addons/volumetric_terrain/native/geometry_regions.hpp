// Worker-owned reconstruction cache; implementation included by core.cpp only.
#pragma once
#include <new>
constexpr int GEOMETRY_SLOTS=512,GEOMETRY_GRID=129;
constexpr u64 GEOMETRY_BUDGET=32u*1024u*1024u;
struct GeometryRegion {
 List<Vertex> vertices;
 int x=0,z=0;
 u64 used=0;
 bool present=false,dirty=false;
};
struct GeometryCache {
 GeometryRegion regions[GEOMETRY_SLOTS];
 u16 index[GEOMETRY_GRID*GEOMETRY_GRID];
 u64 clock=0,hits=0,misses=0,evictions=0,invalidations=0,bypasses=0,bytes=0,entries=0;
 u64 budget=GEOMETRY_BUDGET;
};
static GeometryCache* ensure_geometry_cache(const World&w){
 if(!w.geometry_cache){
  void*p=tr_alloc(sizeof(GeometryCache));if(!p){tr_oom=true;return nullptr;}
  w.geometry_cache=new(p) GeometryCache{};
 }
 return w.geometry_cache;
}
static int geometry_key(int x,int z){return (x/16+1)+GEOMETRY_GRID*(z/16+1);}
static void discard_region(GeometryCache&c,int slot,bool eviction){
 GeometryRegion&r=c.regions[slot];if(!r.present)return;
 c.index[geometry_key(r.x,r.z)]=0;c.bytes-=u64(r.vertices.cap)*sizeof(Vertex);c.entries--;
 r.vertices.release();r.present=false;r.dirty=false;
 if(eviction)c.evictions++;
}
void release_geometry_cache(const World&w){
 if(!w.geometry_cache)return;
 for(auto&r:w.geometry_cache->regions)r.vertices.release();
 tr_free(w.geometry_cache);w.geometry_cache=nullptr;
}
void invalidate_geometry_cache(const World&w,V3 lo,V3 hi){
 if(!w.geometry_cache)return;
 // A region owns cells [x,x+15], whose reconstruction reads samples [x,x+16].
 // Full vertical columns are cached; no assumptions about a heightfield here.
 for(auto&r:w.geometry_cache->regions)if(r.present&&!r.dirty&&r.x<=hi.x&&r.x+16>=lo.x&&r.z<=hi.z&&r.z+16>=lo.z){r.dirty=true;w.geometry_cache->invalidations++;}
}
void geometry_cache_stats(const World&w,Bytes&out){
 const GeometryCache*c=w.geometry_cache;
 u64 values[9]={c?c->hits:0,c?c->misses:0,c?c->evictions:0,c?c->invalidations:0,c?c->entries:0,c?c->bytes:0,c?c->budget:GEOMETRY_BUDGET,c?sizeof(GeometryCache)+c->bytes:0,c?c->bypasses:0};
 out.raw(values,sizeof(values));
}
static int geometry_victim(const GeometryCache&c){
 int slot=-1;u64 age=~u64(0);
 for(int i=0;i<GEOMETRY_SLOTS;i++)if(c.regions[i].present&&c.regions[i].used<age){age=c.regions[i].used;slot=i;}
 return slot;
}
static bool configure_geometry_cache(const World&w,u32 budget){
 if(budget<65536||budget>GEOMETRY_BUDGET)return false;
 auto*c=ensure_geometry_cache(w);if(!c)return false;c->budget=budget;
 while(c->bytes>c->budget){int slot=geometry_victim(*c);if(slot<0)return false;discard_region(*c,slot,true);}
 return true;
}
static bool vertex_before(const Vertex&a,const Vertex&b){
 return a.cz!=b.cz?a.cz<b.cz:(a.cx!=b.cx?a.cx<b.cx:a.cy<b.cy);
}
static void order_vertices(Vertex*p,int lo,int hi){
 while(lo<hi){Vertex pivot=p[(lo+hi)/2];int i=lo,j=hi;
  while(i<=j){while(vertex_before(p[i],pivot))i++;while(vertex_before(pivot,p[j]))j--;if(i<=j){Vertex swap=p[i];p[i++]=p[j];p[j--]=swap;}}
  if(j-lo<hi-i){if(lo<j)order_vertices(p,lo,j);lo=i;}else{if(i<hi)order_vertices(p,i,hi);hi=j;}
 }
}
static bool cached_vertices(const World&w,int ox,int oz,int size,Mesh&m,u32 epoch){
 if(!ensure_geometry_cache(w))return false;
 auto&c=*w.geometry_cache;
 const int first_x=fl(float(ox-1)/16)*16,first_z=fl(float(oz-1)/16)*16;
 for(int z=first_z;z<oz+size&&z<=WORLD;z+=16)for(int x=first_x;x<ox+size&&x<=WORLD;x+=16){
  if(cancelled(w,epoch))return false;
  int key=geometry_key(x,z),slot=int(c.index[key])-1;
  Mesh temporary;const List<Vertex>*selected=nullptr;
  if(slot>=0&&!c.regions[slot].dirty){c.hits++;selected=&c.regions[slot].vertices;c.regions[slot].used=++c.clock;}
  else{
   c.misses++;
   if(!extract_vertices(w,x,z,16,temporary,epoch)){temporary.release();return false;}
   // Drop halo representatives: every cached cell has exactly one owner.
   int count=0;for(int i=0;i<temporary.v.n;i++){const Vertex&v=temporary.v[i];if(v.cx>=x&&v.cx<x+16&&v.cz>=z&&v.cz<z+16)temporary.v[count++]=v;}temporary.v.n=count;
   u64 bytes=u64(temporary.v.cap)*sizeof(Vertex);
   if(slot>=0)discard_region(c,slot,false);
   if(bytes>c.budget){c.bypasses++;selected=&temporary.v;}
   else{
    while(c.bytes+bytes>c.budget){int victim=geometry_victim(c);if(victim<0)break;discard_region(c,victim,true);}
    slot=-1;for(int i=0;i<GEOMETRY_SLOTS;i++)if(!c.regions[i].present){slot=i;break;}
    if(slot<0){slot=geometry_victim(c);discard_region(c,slot,true);}
    auto&r=c.regions[slot];r.x=x;r.z=z;r.used=++c.clock;r.present=true;r.dirty=false;
    r.vertices=temporary.v;temporary.v=List<Vertex>{};c.index[key]=u16(slot+1);c.bytes+=bytes;c.entries++;
    selected=&r.vertices;
   }
  }
  for(int i=0;i<selected->n;i++){const Vertex&v=(*selected)[i];if(v.cx>=ox-1&&v.cx<ox+size&&v.cz>=oz-1&&v.cz<oz+size)m.v.push(v);}
  temporary.release();if(tr_oom)return false;
 }
 // Preserve the original z/x/y order, hence triangulation, simplification and
 // shading decisions. Reuse does not silently alter topology or material output.
 if(m.v.n>1)order_vertices(m.v.p,0,m.v.n-1);
 return !cancelled(w,epoch);
}
