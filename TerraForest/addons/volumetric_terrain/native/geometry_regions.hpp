// Worker-owned reconstruction cache; implementation included by core.cpp only.
#pragma once
#include <new>
constexpr int GEOMETRY_SLOTS=512,GEOMETRY_GRID=129;
constexpr u64 GEOMETRY_BUDGET=32u*1024u*1024u;
struct GeometryRegion {
 List<Vertex> vertices;
 int x=0,z=0;
 int dirty_xz[4]={};
 int dirty_y0=0,dirty_y1=0;
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
static void dirty_reconstruction(GeometryCache &cache,GeometryRegion &r,int x0,int z0,int x1,int z1,int bottom,int top){
 const int bounds[]={imx(r.x,x0),imx(r.z,z0),imn(r.x+15,x1),imn(r.z+15,z1)};
 if(!r.dirty){
  copy_bytes(r.dirty_xz,bounds,sizeof(bounds));r.dirty_y0=bottom;r.dirty_y1=top;
  r.dirty=true;++cache.invalidations;
 }else{
  for(int axis=0;axis<2;++axis){
   r.dirty_xz[axis]=imn(r.dirty_xz[axis],bounds[axis]);
   r.dirty_xz[axis+2]=imx(r.dirty_xz[axis+2],bounds[axis+2]);
  }
  r.dirty_y0=imn(r.dirty_y0,bottom);r.dirty_y1=imx(r.dirty_y1,top);
 }
}
void invalidate_geometry_cache(const World&w,V3 lo,V3 hi){
 if(!w.geometry_cache)return;
 for(auto&r:w.geometry_cache->regions){
  if(!r.present||r.x>hi.x+1||r.x+16<lo.x||r.z>hi.z+1||r.z+16<lo.z)continue;
  dirty_reconstruction(*w.geometry_cache,r,fl(lo.x)-1,fl(lo.z)-1,fl(hi.x)+1,fl(hi.z)+1,
                       imx(0,fl(lo.y)-1),imn(WORLD_Y-1,fl(hi.y)+1));
 }
}
static void invalidate_written_samples(const World &w,const TerrainEditWrites &writes){
 auto *cache=w.geometry_cache;
 if(!cache)return;
 for(int i=0;i<writes.records.n;++i){
  const auto &record=writes.records[i];
  // Page admission already invalidates its full procedural extraction band.
  // Exact cubes are appended downstream of the cached density vertices.
  if(record.detail>=TerrainEditWrites::PAGE_ADMITTED)continue;
  const int x=record.address&2047,z=(record.address>>11)&2047;
  const int bottom=imx(0,int(record.address>>22)-1),top=imn(WORLD_Y-1,int(record.detail)+1);
  for(int rz=(z-1)>>4;rz<=(z+1)>>4;++rz)for(int rx=(x-1)>>4;rx<=(x+1)>>4;++rx){
   int slot=int(cache->index[geometry_key(rx*16,rz*16)])-1;
   if(slot>=0)dirty_reconstruction(*cache,cache->regions[slot],x-1,z-1,x+1,z+1,bottom,top);
  }
 }
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
 // Match extraction order, including separate components of the same cell.
 if(a.cz!=b.cz)return a.cz<b.cz;if(a.cx!=b.cx)return a.cx<b.cx;if(a.cy!=b.cy)return a.cy<b.cy;
 return ((a.mask>>8)&(~(a.mask>>8)+1))<((b.mask>>8)&(~(b.mask>>8)+1));
}
static void order_vertices(Vertex*p,int lo,int hi){
 while(lo<hi){Vertex pivot=p[(lo+hi)/2];int i=lo,j=hi;
  while(i<=j){while(vertex_before(p[i],pivot))i++;while(vertex_before(pivot,p[j]))j--;if(i<=j){Vertex swap=p[i];p[i++]=p[j];p[j--]=swap;}}
  if(j-lo<hi-i){if(lo<j)order_vertices(p,lo,j);lo=i;}else{if(i<hi)order_vertices(p,i,hi);hi=j;}
 }
}
// Merge in extraction order. An unchanged crossing has exactly the same
// representative and component mask, even when first page admission expanded
// the search band. Newly discovered crossings keep the current revision.
static void inherit_face_recipes(const GeometryRegion&old,List<Vertex>&vertices){
 int at=0;
 for(int i=0;i<vertices.n&&at<old.vertices.n;++i){
  auto&v=vertices[i];
  if(v.cx<old.x||v.cx>=old.x+16||v.cz<old.z||v.cz>=old.z+16)continue;
  while(at<old.vertices.n&&vertex_before(old.vertices[at],v))++at;
  if(at==old.vertices.n)break;
  const auto&u=old.vertices[at];
  if(u.cx!=v.cx||u.cy!=v.cy||u.cz!=v.cz||u.mask!=v.mask||
     u.p.x!=v.p.x||u.p.y!=v.p.y||u.p.z!=v.p.z||
     u.n.x!=v.n.x||u.n.y!=v.n.y||u.n.z!=v.n.z||u.material!=v.material)continue;
  v.geometry_revision=u.geometry_revision;v.face_revision=u.face_revision;v.face_splits=u.face_splits;
 }
}
static void inherit_available_recipes(const World&w,int ox,int oz,int size,Mesh&m){
 const auto*c=w.geometry_cache;if(!c)return;
 for(int z=fl(float(oz-1)/16)*16;z<oz+size;z+=16)for(int x=fl(float(ox-1)/16)*16;x<ox+size;x+=16){
  int slot=int(c->index[geometry_key(x,z)])-1;
  if(slot>=0)inherit_face_recipes(c->regions[slot],m.v);
 }
}
// Transfer a complete 16 m column, preserving the ordinary cache budget.
static const List<Vertex>* retain_geometry_column(GeometryCache&c,int x,int z,List<Vertex>&vertices){
 int key=geometry_key(x,z),slot=int(c.index[key])-1;
 u64 bytes=u64(vertices.cap)*sizeof(Vertex);
 if(slot>=0)discard_region(c,slot,false);
 if(bytes>c.budget){++c.bypasses;return &vertices;}
 while(c.bytes+bytes>c.budget){int victim=geometry_victim(c);if(victim<0)break;discard_region(c,victim,true);}
 slot=-1;for(int i=0;i<GEOMETRY_SLOTS;i++)if(!c.regions[i].present){slot=i;break;}
 if(slot<0){slot=geometry_victim(c);discard_region(c,slot,true);}
 auto&r=c.regions[slot];r.x=x;r.z=z;r.used=++c.clock;r.present=true;r.dirty=false;
 r.vertices=vertices;vertices=List<Vertex>{};c.index[key]=u16(slot+1);c.bytes+=bytes;c.entries++;
 return &r.vertices;
}
// A resident mesh already contains every original cell representative in its
// interior. Water can reuse these columns without extracting the surrounding
// owners merely to read their one-cell rims.
static bool remember_surface_columns(const World&w,int ox,int oz,int size,const Mesh&m){
 auto*c=ensure_geometry_cache(w);if(!c)return false;
 for(int z=oz;z<oz+size;z+=16)for(int x=ox;x<ox+size;x+=16){
  List<Vertex> column;
  for(int i=0;i<m.v.n;i++){
   const auto&v=m.v[i];
   if(v.mask&&v.cx>=x&&v.cx<x+16&&v.cz>=z&&v.cz<z+16)column.push(v);
  }
  if(tr_oom){column.release();return false;}
  retain_geometry_column(*c,x,z,column);column.release();
 }
 return true;
}
static bool has_surface_columns(const World&w,int ox,int oz,int size,bool allow_dirty=false){
 const auto*c=w.geometry_cache;if(!c)return false;
 for(int z=fl(float(oz-1)/16)*16;z<oz+size&&z<=WORLD;z+=16)
  for(int x=fl(float(ox-1)/16)*16;x<ox+size&&x<=WORLD;x+=16){
   int slot=int(c->index[geometry_key(x,z)])-1;
   if(slot<0||(!allow_dirty&&c->regions[slot].dirty))return false;
  }
 return true;
}
static const List<Vertex>* geometry_column(const World&w,GeometryCache &c,int x,int z,u32 epoch,Mesh &temporary){
  int key=geometry_key(x,z),slot=int(c.index[key])-1;
  const List<Vertex>*selected=nullptr;
  if(slot>=0&&!c.regions[slot].dirty){c.hits++;selected=&c.regions[slot].vertices;c.regions[slot].used=++c.clock;}
  else{
   c.misses++;
   if(slot>=0){
    const auto&r=c.regions[slot];
    if(!extract_vertices(w,x,z,16,temporary,epoch,r.dirty_y0+1,r.dirty_y1+1,nullptr,nullptr,r.dirty_xz))return nullptr;
    inherit_face_recipes(r,temporary.v);
    for(int i=0;i<r.vertices.n;++i){
     const auto&v=r.vertices[i];
     if(v.cx<r.dirty_xz[0]||v.cx>r.dirty_xz[2]||v.cz<r.dirty_xz[1]||v.cz>r.dirty_xz[3]||v.cy<r.dirty_y0||v.cy>r.dirty_y1)temporary.v.push(v);
    }
    if(tr_oom)return nullptr;
    if(temporary.v.n>1)order_vertices(temporary.v.p,0,temporary.v.n-1);
   }else if(!extract_vertices(w,x,z,16,temporary,epoch))return nullptr;
   // Drop halo representatives: every cached cell has exactly one owner.
   int count=0;for(int i=0;i<temporary.v.n;i++){const Vertex&v=temporary.v[i];if(v.cx>=x&&v.cx<x+16&&v.cz>=z&&v.cz<z+16)temporary.v[count++]=v;}temporary.v.n=count;
   selected=retain_geometry_column(c,x,z,temporary.v);
  }
  return selected;
}
bool extract_surface_column(const World&w,int x,int z,u32 epoch,List<Vertex> &out){
 if(!ensure_geometry_cache(w)||cancelled(w,epoch))return false;
 Mesh temporary;
 const auto *column=geometry_column(w,*w.geometry_cache,x,z,epoch,temporary);
 if(column){
  out.resize(column->n);
  if(!tr_oom&&out.n)copy_bytes(out.p,column->p,sizeof(Vertex)*out.n);
 }
 temporary.release();
 return column&&!tr_oom&&!cancelled(w,epoch);
}
static bool cached_vertices(const World&w,int ox,int oz,int size,Mesh&m,u32 epoch,int y_begin=0,int y_end=WORLD_Y){
 if(!ensure_geometry_cache(w))return false;
 auto&c=*w.geometry_cache;
 const int first_x=fl(float(ox-1)/16)*16,first_z=fl(float(oz-1)/16)*16;
 for(int z=first_z;z<oz+size&&z<=WORLD;z+=16)for(int x=first_x;x<ox+size&&x<=WORLD;x+=16){
  if(cancelled(w,epoch))return false;
  Mesh temporary;
  const auto *selected=geometry_column(w,c,x,z,epoch,temporary);
  if(!selected){temporary.release();return false;}
  for(int i=0;i<selected->n;i++){const Vertex&v=(*selected)[i];if(v.cx>=ox-1&&v.cx<ox+size&&v.cz>=oz-1&&v.cz<oz+size&&v.cy>=y_begin-1&&v.cy<y_end)m.v.push(v);}
  temporary.release();if(tr_oom)return false;
 }
 // Preserve the original z/x/y order, hence triangulation, simplification and
 // shading decisions. Reuse does not silently alter topology or material output.
 if(m.v.n>1)order_vertices(m.v.p,0,m.v.n-1);
 return !cancelled(w,epoch);
}

// The worker can repair just the invalidated cells on its immutable field.
// Copy only columns read by this group, under the existing per-core budget.
bool copy_surface_columns(const World&source,World&dest,int ox,int oz,int width,int depth){
 if(!source.geometry_cache)return true;
 for(const auto&r:source.geometry_cache->regions){
  if(!r.present||r.x+16<ox||r.z+16<oz||r.x>=ox+width||r.z>=oz+depth)continue;
  auto*c=ensure_geometry_cache(dest);if(!c)return false;
  List<Vertex> vertices;vertices.resize(r.vertices.n);
  if(tr_oom){vertices.release();return false;}
  if(r.vertices.n)copy_bytes(vertices.p,r.vertices.p,sizeof(Vertex)*r.vertices.n);
  retain_geometry_column(*c,r.x,r.z,vertices);vertices.release();
  const int slot=int(c->index[geometry_key(r.x,r.z)])-1;
  if(slot>=0&&r.dirty){
   auto&copy=c->regions[slot];copy.dirty=true;copy.dirty_y0=r.dirty_y0;copy.dirty_y1=r.dirty_y1;
   copy_bytes(copy.dirty_xz,r.dirty_xz,sizeof(r.dirty_xz));
  }
 }
 return !tr_oom;
}
