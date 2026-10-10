// SPDX-License-Identifier: 0BSD
#include "core.h"
#include "geology.hpp"
#if defined(TERRAFOREST_TYPED_BRIDGE)
#include <chrono>
#endif
static double mesh_clock_ms(){
#if defined(TERRAFOREST_TYPED_BRIDGE)
 return std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now().time_since_epoch()).count();
#else
 return 0;
#endif
}
void *(*tr_alloc)(size_t)=nullptr;
void *(*tr_realloc)(void *,size_t)=nullptr;
void (*tr_free)(void *)=nullptr;
#if defined(TERRAFOREST_TYPED_BRIDGE)
thread_local bool tr_oom=false;
#else
bool tr_oom=false;
#endif
// The worker alone owns World. This atomic counter is the ONLY main-thread
// write observed during a build. No shared mesh/world mutation or forced kill.
static u32 build_epoch_value=0;
u32 terrain_build_epoch(const World *w){return __atomic_load_n(w&&w->build_control?&w->build_control->epoch:&build_epoch_value,__ATOMIC_RELAXED);}
u32 terrain_cancel_builds(const World *w){return __atomic_add_fetch(w&&w->build_control?&w->build_control->epoch:&build_epoch_value,1u,__ATOMIC_RELAXED);}
static bool cancelled(const World &w,u32 epoch){return epoch!=0xffffffffu && terrain_build_epoch(&w)!=epoch;}
static constexpr int NP=126;
static float smooth(float t){return t*t*(3.f-2.f*t);}
static float noise(float x,float z,u32 seed){
 int a=fl(x),b=fl(z);float u=smooth(x-a),v=smooth(z-b);
 float h00=float(hash32(u32(a)*73856093u^u32(b)*19349663u^seed)&65535)/65535.f;
 float h10=float(hash32(u32(a+1)*73856093u^u32(b)*19349663u^seed)&65535)/65535.f;
 float h01=float(hash32(u32(a)*73856093u^u32(b+1)*19349663u^seed)&65535)/65535.f;
 float h11=float(hash32(u32(a+1)*73856093u^u32(b+1)*19349663u^seed)&65535)/65535.f;
 return ((h00+(h10-h00)*u)*(1-v)+(h01+(h11-h01)*u)*v)*2.f-1.f;
}
static float bump(float x,float z,float cx,float cz,float r,float height){
 float a=(x-cx)/r,b=(z-cz)/r,t=mx(0.f,1.f-a*a-b*b);return height*smooth(t);
}
float World::height(float x,float z)const{
 float h=49.f+noise(x/320.f,z/320.f,u32(seed))*20.f+noise(x/100.f,z/100.f,u32(seed)+1u)*8.f+noise(x/34.f,z/34.f,u32(seed)+2u)*2.5f;
 if(generator_id>=2){
  // Four seed-derived massifs, constant query work and no generated sample storage.
  for(u32 i=0;i<4;i++){
   u32 a=hash32(u32(seed)^0x6d2b79f5u^(i*0x9e3779b9u)),b=hash32(a);
   float cx=350.f+float(i&1)*1000.f+float(a&255),cz=350.f+float(i>>1)*1000.f+float((a>>8)&255);
   h+=bump(x,z,cx,cz,330.f+float(b&127),85.f+float((b>>8)&63));
  }
  h=clampf(h,18.f,225.f);
  for(int i=0;i<basin_count;i++){
   const auto &b=basins[i];float dx=x-b.x,dz=z-b.z,d2=dx*dx+dz*dz;
   if(d2>=1600.f)continue;
   // Closed rim at radius 24; outer annulus blends back into the landscape.
   if(d2<=576.f)return b.level-9.f+12.f*d2/576.f;
   float t=smooth((__builtin_sqrtf(d2)-24.f)/16.f);
   return (b.level+3.f)*(1.f-t)+h*t;
  }
  return h;
 }
 h+=bump(x,z,1000,850,480,128)+bump(x,z,440,440,390,85)+bump(x,z,1580,480,390,95)+bump(x,z,1480,1450,430,55);
 return clampf(h,18.f,225.f);
}
static float capsule(V3 p,V3 a,V3 b,float r){V3 pa=p-a,ba=b-a;float t=clampf(dot(pa,ba)/mx(dot(ba,ba),1e-8f),0,1);return length(pa-ba*t)-r;}
float World::base(V3 p,float h)const{
 float d=p.y-h;
 for(int i=0;i<caves.n;i++){
  const Cave&c=caves[i];
  if(p.x<mn(c.a.x,c.b.x)-c.r-5||p.x>mx(c.a.x,c.b.x)+c.r+5||p.z<mn(c.a.z,c.b.z)-c.r-5||p.z>mx(c.a.z,c.b.z)+c.r+5||p.y<mn(c.a.y,c.b.y)-c.r-5||p.y>mx(c.a.y,c.b.y)+c.r+5)continue;
  d=mx(d,-capsule(p,c.a,c.b,c.r));
 }
 d=mx(d,1.f-p.y);d=mx(d,p.y-255.f);d=mx(d,-p.x);d=mx(d,p.x-WORLD);d=mx(d,-p.z);d=mx(d,p.z-WORLD);
 return clampf(d,-SDF_BAND,SDF_BAND);
}
void World::init(int p_seed,u32 generator){
 seed=p_seed;generator_id=generator;basin_count=0;revision=edits=0;changed_samples=0;block_columns.resize(4096);
 edit_columns=(u32*)tr_alloc(NP*NP*sizeof(u32));if(edit_columns)zero_bytes(edit_columns,NP*NP*sizeof(u32));else tr_oom=true;
 if(generator_id==4){
  // Separate seed domains and quadrant placement keep basins away from caves.
  for(u32 i=0;i<4;i++){
   u32 h=hash32(u32(seed)^0x7a91c3b5u^(i*0x9e3779b9u));
   float x=180.f+float(i&1)*1000.f+float(h&63),z=180.f+float(i>>1)*1000.f+float((h>>8)&63);
   basins[i]={x,z,height(x,z)-3.f};
  }
  basin_count=4;
 }
 if(generator_id>=2){
  // Four connected entrance/tunnel/chamber systems. All capsules remain in the
  // canonical cave list used by density, mesh envelopes and visibility queries.
  for(u32 i=0;i<4;i++){
   u32 a=hash32(u32(seed)^0x6d2b79f5u^(i*0x9e3779b9u)),b=hash32(a),c=hash32(b);
   float x=350.f+float(i&1)*1000.f+float(a&255),z=350.f+float(i>>1)*1000.f+float((a>>8)&255);
   float side=(b&1)?1.f:-1.f;
   V3 entrance={x+side*230.f,0,z};entrance.y=height(entrance.x,entrance.z)-2.f;
   float floor=mx(25.f,mn(height(x,z)-45.f,75.f));
   V3 bend={x+side*110.f,floor+10.f,z+float(int(c&63)-31)},center={x,floor,z};
   caves.push({entrance,bend,7.f});caves.push({bend,center,9.f});
   caves.push({center,center,18.f+float((c>>8)&7)});
   V3 branch={x-side*110.f,floor-5.f,z+80.f};
   caves.push({center,branch,7.f});caves.push({branch,branch,14.f});
  }
  return;
 }
 // Explicit cave envelopes are derived from these same primitives, never hand-maintained elsewhere.
 V3 entrance={1050,height(1050,1210)-2,1210};
 caves.push({entrance,{1050,76,1115},7});caves.push({{1050,76,1115},{1020,66,1030},8});
 caves.push({{1020,66,1030},{985,61,985},11});caves.push({{985,61,985},{985,61,985},22});
 caves.push({{980,62,1000},{865,51,960},6});caves.push({{870,52,965},{805,47,1060},7});
 caves.push({{990,60,975},{1090,49,900},7});caves.push({{1090,49,900},{1090,49,900},17});
 V3 e2={480,height(480,800)-2,800};caves.push({e2,{460,54,690},6});caves.push({{460,54,690},{430,52,575},8});caves.push({{430,52,575},{420,52,550},18});
}
void World::release(){owned_heights.release();release_geometry_cache(*this);light_roofs.release();light_samples.release();light_tops.release();light_probe_ids.release();light_probes.release();lighting_revision=-1;for(int i=0;i<pages.n;i++){if(pages[i].d)tr_free(pages[i].d);if(pages[i].mat)tr_free(pages[i].mat);}pages.release();pages_by_key.release();blocks.release();caves.release();for(int i=0;i<block_columns.n;i++)block_columns[i].release();block_columns.release();if(edit_columns)tr_free(edit_columns);edit_columns=nullptr;}
static u32 page_key(int x,int y,int z){return u32(x+NP*(z+NP*y))+1;}
static void decode_page(u32 k,int&x,int&y,int&z){int v=int(k-1);x=v%NP;v/=NP;z=v%NP;y=v/NP;}
static u32 block_key(int x,int y,int z){return 1+u32(x|(z<<11)|(y<<22));}
static void decode_block(u32 key,int&x,int&y,int&z){u32 k=key-1;x=k&2047;z=(k>>11)&2047;y=(k>>22)&511;}
bool World::set_block(u32 key,int material){
 int old=blocks.get(key);if(old!=material)lighting_revision=-1;if(old<0){if(blocks.n>=2000000)return false;int x,y,z;decode_block(key,x,y,z);block_columns[(x>>5)+64*(z>>5)].push(key);}blocks.put(key,material);return !tr_oom;
}
void World::erase_block(u32 key){
 if(blocks.get(key)<0)return;lighting_revision=-1;int x,y,z;decode_block(key,x,y,z);auto&column=block_columns[(x>>5)+64*(z>>5)];for(int i=0;i<column.n;i++)if(column[i]==key){column[i]=column[column.n-1];column.n--;break;}blocks.erase(key);
}
static i16 quant(float f){float v=clampf(f,-SDF_BAND,SDF_BAND)*SDF_SCALE;return i16(v>=0?v+0.5f:v-0.5f);}
float World::sample(int x,int y,int z,u8*mat)const{
 if(mat)*mat=0;
 if(x<0||x>WORLD||z<0||z>WORLD||y<0||y>WORLD_Y)return SDF_BAND;
 int index=pages_by_key.get(page_key(x>>4,y>>4,z>>4));
 if(index>=0){const Page&p=pages[index];int j=(x&15)+16*((z&15)+16*(y&15));if(mat)*mat=p.mat[j];return float(p.d[j])/SDF_SCALE;}
 V3 point={float(x),float(y),float(z)};float h=height(point.x,point.z);
 if(mat&&generator_id>=3){float weight=geological_weight(point,h,u32(seed));*mat=weight>.5f?8:(weight<-.5f?9:0);}
 return base(point,h);
}
Page* World::ensure(int px,int py,int pz){
 u32 key=page_key(px,py,pz);int at=pages_by_key.get(key);if(at>=0)return &pages[at];if(pages.n>=MAX_PAGES)return nullptr;
 Page page;page.key=key;page.d=(i16*)tr_alloc(PAGE_SAMPLES*sizeof(i16));page.mat=(u8*)tr_alloc(PAGE_SAMPLES);
 if(!page.d||!page.mat){if(page.d)tr_free(page.d);if(page.mat)tr_free(page.mat);tr_oom=true;return nullptr;}
 zero_bytes(page.mat,PAGE_SAMPLES);
 for(int z=0;z<16;z++)for(int x=0;x<16;x++){
  float wx=float(px*16+x),wz=float(pz*16+z),h=height(wx,wz);
  for(int y=0;y<16;y++){
   int index=x+16*(z+16*y);V3 point={wx,float(py*16+y),wz};page.d[index]=quant(base(point,h));
   if(generator_id>=3){float weight=geological_weight(point,h,u32(seed));page.mat[index]=weight>.5f?8:(weight<-.5f?9:0);}
  }
 }
 int idx=pages.push(page);pages_by_key.put(key,idx);edit_columns[px+NP*pz]|=(1u<<py);return &pages[idx];
}
static float box_distance(V3 p,V3 c,float r){V3 q={ab(p.x-c.x)-r,ab(p.y-c.y)-r,ab(p.z-c.z)-r};return length({mx(q.x,0),mx(q.y,0),mx(q.z,0)})+mn(mx(q.x,mx(q.y,q.z)),0);}
static float road_bed_field(V3 p,V3 a,V3 b,float half_width,float depth,float shoulder=0){
 V3 axis={b.x-a.x,0,b.z-a.z},offset={p.x-a.x,0,p.z-a.z};
 float along=dot(offset,axis)/dot(axis,axis);
 float t=clampf(along,0.f,1.f);
 V3 nearest={a.x+axis.x*t,0,a.z+axis.z*t};
 // Keep the grade plane through the rounded footprint caps. Clamping the
 // elevation flattened each cap, leaving ledges at joined sloping sections.
 float top=a.y+(b.y-a.y)*along;
 float edge=length(V3{p.x-nearest.x,0,p.z-nearest.z})-half_width;
 if(shoulder>0){
  float drop=depth*clampf(edge/shoulder,0.f,1.f);
  return mx(edge-shoulder,mx((p.y-top+drop)/__builtin_sqrtf(1.f+(depth/shoulder)*(depth/shoulder)),top-depth-p.y));
 }
 return mx(edge,mx(p.y-top,top-depth-p.y));
}
bool World::edit(V3 a,V3 b,float radius,int shape,bool add,u8 material,V3&lo,V3&hi,int&changes,float depth,float clearance,float shoulder,u32 *removed_samples){
 if(removed_samples)zero_bytes(removed_samples,16*sizeof(u32));
 changes=0;radius=clampf(radius,0.5f,64.f);
 lo={mx(0,mn(a.x,b.x)-radius-SDF_BAND-1),mx(0,mn(a.y,b.y)-radius-SDF_BAND-1),mx(0,mn(a.z,b.z)-radius-SDF_BAND-1)};
 hi={mn(WORLD,mx(a.x,b.x)+radius+SDF_BAND+1),mn(255,mx(a.y,b.y)+radius+SDF_BAND+1),mn(WORLD,mx(a.z,b.z)+radius+SDF_BAND+1)};
 if(shape==2){float cap_rise=ab(b.y-a.y)*(radius+shoulder)/length(V3{b.x-a.x,0,b.z-a.z});lo.y=mx(0,mn(a.y,b.y)-cap_rise-depth-SDF_BAND-1);hi.y=mn(255,mx(a.y,b.y)+cap_rise+clearance+SDF_BAND+1);}
 if(shape==2&&shoulder>0){lo.x=mx(0,lo.x-shoulder);lo.z=mx(0,lo.z-shoulder);hi.x=mn(WORLD,hi.x+shoulder);hi.z=mn(WORLD,hi.z+shoulder);}
 if(lo.x>hi.x||lo.y>hi.y||lo.z>hi.z)return false;
 // Capacity check before mutation: fail the edit, never silently discard terrain.
 int need=0;for(int py=fl(lo.y)/16;py<=fl(hi.y)/16;py++)for(int pz=fl(lo.z)/16;pz<=fl(hi.z)/16;pz++)for(int px=fl(lo.x)/16;px<=fl(hi.x)/16;px++)if(pages_by_key.get(page_key(px,py,pz))<0)need++;
 if(pages.n+need>MAX_PAGES)return false;
 int x0=fl(lo.x),x1=fl(hi.x),y0=fl(lo.y),y1=fl(hi.y),z0=fl(lo.z),z1=fl(hi.z);
 for(int z=z0;z<=z1;z++)for(int x=x0;x<=x1;x++){
  float h=height(float(x),float(z));int lastpy=-1,idx=-1;
  for(int y=y0;y<=y1;y++){
   V3 p={float(x),float(y),float(z)};float brush=shape==2?road_bed_field(p,a,b,radius,depth,shoulder):(shape==1?box_distance(p,b,radius):capsule(p,a,b,radius));
   float cut=shape==2&&clearance>0?road_bed_field(p,a+V3{0,clearance,0},b+V3{0,clearance,0},radius,clearance):SDF_BAND+1;
   if(brush>SDF_BAND&&cut>SDF_BAND)continue;
   int py=y>>4;if(py!=lastpy){idx=pages_by_key.get(page_key(x>>4,py,z>>4));lastpy=py;}
   int j=(x&15)+16*((z&15)+16*(y&15));float old=idx<0?base(p,h):float(pages[idx].d[j])/SDF_SCALE;
   float value=add?mn(old,brush):mx(old,-brush);
   if(shape==2&&clearance>0)value=mx(value,-cut);
   if(y<=3)value=old; // Preserve the bottom solid slab; excavation cannot open the world underside.
   // Bedrock and exterior remain outside the writable field.
   if(x==0||x==WORLD||z==0||z==WORLD||y<=1||y>=255)value=mx(value,0.f);
   i16 q=quant(value),previous=quant(old);
   // Paving an already graded solid surface is still a material edit. Keep
   // cut walls, air and protected bedrock outside this repaint operation.
   bool repaint=shape==2&&brush<=0&&q<=0&&y>3&&(idx<0||pages[idx].mat[j]!=material);
   if(q==previous&&!repaint)continue;
   if(idx<0){Page* page=ensure(x>>4,py,z>>4);if(!page)return false;idx=pages_by_key.get(page_key(x>>4,py,z>>4));}
   // Count only newly excavated lattice samples, before material rewriting.
   // Existing air, band reshaping, paving and additive edits yield nothing.
   if(removed_samples&&!add&&shape<2&&previous<0&&q>=0){
    u8 source=pages[idx].mat[j];if(source<16)removed_samples[source]++;
   }
   pages[idx].d[j]=q;
   // Cut walls retain their substrate; pavement is limited to the bed.
   if((add||generator_id<3)&&!(shape==2&&clearance>0&&brush>0))pages[idx].mat[j]=material;
   pages[idx].geometry_digest_valid=false;changes++;
  }
 }
 // Construction is a separate exact grid. Smooth excavation removes whole intersected cubes,
 // rather than silently rounding them into the smooth density lattice.
 if(!add)for(int cz=fl(lo.z)/32;cz<=fl(hi.z)/32;cz++)for(int cx=fl(lo.x)/32;cx<=fl(hi.x)/32;cx++){
  auto&column=block_columns[cx+64*cz];int j=0;while(j<column.n){u32 key=column[j];int x,y,z;decode_block(key,x,y,z);V3 p={x+.5f,y+.5f,z+.5f};float d=shape==1?box_distance(p,b,radius):capsule(p,a,b,radius);if(d<=0){blocks.erase(key);column[j]=column[column.n-1];column.n--;changes++;}else j++;}
 }
 if(changes){invalidate_geometry_cache(*this,lo,hi);revision++;edits++;changed_samples+=changes;lighting_revision=-1;}return true;
}
static u32 checksum(const u8*p,int n){u32 h=2166136261u;for(int i=0;i<n;i++){h^=p[i];h*=16777619u;}return h;}
void World::serialize(Bytes&out)const{
 int start=out.n;
 out.u(SAVE_MAGIC);out.u(2);out.u(seed);out.u(pages.n);out.u(blocks.n);out.u(revision);out.u(edits);out.u(generator_id);
 for(int i=0;i<pages.n;i++){const Page&p=pages[i];out.u(p.key);out.raw(p.d,PAGE_SAMPLES*2);out.raw(p.mat,PAGE_SAMPLES);}
 for(int i=0;i<blocks.cap;i++)if(blocks.p[i].key&&blocks.p[i].key!=0xffffffffu){out.u(blocks.p[i].key);out.u(blocks.p[i].value);}
 out.u(checksum(out.p+start,out.n-start));
}
bool World::deserialize(const u8*data,int n){
 if(n<32)return false;u32 actual;copy_bytes(&actual,data+n-4,4);if(actual!=checksum(data,n-4))return false;
 Reader r{data,n-4};if(r.u()!=SAVE_MAGIC)return false;u32 format=r.u();if(format!=1&&format!=2)return false;
 int s=int(r.u()),pc=int(r.u()),bc=int(r.u()),rev=int(r.u()),ed=int(r.u());
 u32 generator=format==1?1:r.u();
 if(!r.good||generator<1||generator>4)return false;
 if(pc<0||pc>MAX_PAGES||bc<0||bc>2000000||i64(pc)*(4+PAGE_SAMPLES*3)+i64(bc)*8+(format==1?28:32)!=n-4)return false;
 World t;t.build_control=build_control;t.init(s,generator);t.revision=rev;t.edits=ed;t.surface_style=surface_style;
 for(int i=0;i<pc;i++){
  u32 k=r.u();int px,py,pz;decode_page(k,px,py,pz);if(!k||k>u32(NP*NP*17)||px<0||pz<0||py<0||px>=NP||pz>=NP||py>16||t.pages_by_key.get(k)>=0){t.release();return false;}
  Page p;p.key=k;p.d=(i16*)tr_alloc(PAGE_SAMPLES*2);p.mat=(u8*)tr_alloc(PAGE_SAMPLES);if(!p.d||!p.mat){if(p.d)tr_free(p.d);if(p.mat)tr_free(p.mat);t.release();return false;}
  copy_bytes(p.d,data+r.at,PAGE_SAMPLES*2);r.at+=PAGE_SAMPLES*2;copy_bytes(p.mat,data+r.at,PAGE_SAMPLES);r.at+=PAGE_SAMPLES;
  int id=t.pages.push(p);t.pages_by_key.put(k,id);t.edit_columns[px+NP*pz]|=1u<<py;
 }
 for(int i=0;i<bc;i++){u32 k=r.u(),v=r.u();int x,y,z;decode_block(k,x,y,z);if(!k||x>=WORLD||z>=WORLD||y<1||y>=255||v<1||v>3||t.blocks.get(k)>=0){t.release();return false;}t.set_block(k,v);}
 if(!r.good){t.release();return false;}release();*this=t;return true;
}

static V3 gradient(const float*d,V3 p){
 V3 g{};for(int i=0;i<8;i++){float wx=i&1?p.x:1-p.x,wy=i&2?p.y:1-p.y,wz=i&4?p.z:1-p.z;
  g.x+=d[i]*(i&1?1.f:-1.f)*wy*wz;g.y+=d[i]*(i&2?1.f:-1.f)*wx*wz;g.z+=d[i]*(i&4?1.f:-1.f)*wx*wy;}
 return normal(g);
}
static u32 cell_key(int x,int y,int z,int n){return u32((x+1)+(n+1)*((z+1)+(n+1)*y))+1;}
static void quad(Mesh&m,u32 a,u32 b,u32 c,u32 d,bool reverse){
 // Godot uses clockwise front faces. The input ring's mathematical normal is outward.
 if(reverse){u32 tmp=b;b=d;d=tmp;}
 if(dot(m.v[a].p-m.v[c].p,m.v[a].p-m.v[c].p)<=dot(m.v[b].p-m.v[d].p,m.v[b].p-m.v[d].p)){
  m.i.push(a);m.i.push(c);m.i.push(b);m.i.push(a);m.i.push(d);m.i.push(c);
 }else{m.i.push(a);m.i.push(d);m.i.push(b);m.i.push(b);m.i.push(d);m.i.push(c);}
}
struct Neighbors{int p[160];int n=0;void add(int v){for(int i=0;i<n;i++)if(p[i]==v)return;if(n<160)p[n++]=v;}};
static void prune(List<int>&adj,const Mesh&m,int v){int n=0;for(int j=0;j<adj.n;j++){int t=adj[j],at=t*3;if(m.i[at]!=0xffffffffu&&(m.i[at]==u32(v)||m.i[at+1]==u32(v)||m.i[at+2]==u32(v))){bool dup=false;for(int k=0;k<n;k++)if(adj[k]==t){dup=true;break;}if(!dup)adj[n++]=t;}}adj.n=n;}
static void neighbors(const List<int>&adj,const Mesh&m,int v,Neighbors&out){for(int j=0;j<adj.n;j++){int t=adj[j]*3;for(int k=0;k<3;k++)if(m.i[t+k]!=u32(v))out.add(int(m.i[t+k]));}}
static bool try_collapse(Mesh&m,int u,int v,List<int>*adj,float*weight,u8*alive){
 if(u==v||!alive[u]||!alive[v])return false;prune(adj[u],m,u);prune(adj[v],m,v);
 if(adj[u].n>70||adj[v].n>70||adj[u].n<3||adj[v].n<3)return false;
 Neighbors nu,nv;neighbors(adj[u],m,u,nu);neighbors(adj[v],m,v,nv);int common=0;for(int a=0;a<nu.n;a++)for(int b=0;b<nv.n;b++)if(nu.p[a]==nv.p[b])common++;
 if(common!=2)return false; // Interior manifold link condition; borders are never candidates.
 float w=weight[u]+weight[v];V3 target=(m.v[u].p*weight[u]+m.v[v].p*weight[v])/w;
 for(int side=0;side<2;side++){const List<int>&a=adj[side?v:u];for(int j=0;j<a.n;j++){
  int t=a[j]*3;u32 i0=m.i[t],i1=m.i[t+1],i2=m.i[t+2];bool hasu=i0==u32(u)||i1==u32(u)||i2==u32(u),hasv=i0==u32(v)||i1==u32(v)||i2==u32(v);if(hasu&&hasv)continue;
  V3 p0=m.v[i0].p,p1=m.v[i1].p,p2=m.v[i2].p,old=cross(p1-p0,p2-p0);
  if(i0==u32(u)||i0==u32(v))p0=target;if(i1==u32(u)||i1==u32(v))p1=target;if(i2==u32(u)||i2==u32(v))p2=target;
  V3 after=cross(p1-p0,p2-p0);float aa=dot(old,old),bb=dot(after,after),dd=dot(old,after);
  if(bb<1e-12f||dd<=0||dd*dd<0.3f*aa*bb)return false;
 }}
 m.v[u].p=target;m.v[u].n=normal(m.v[u].n*weight[u]+m.v[v].n*weight[v]);m.v[u].blend=(m.v[u].blend*weight[u]+m.v[v].blend*weight[v])/w;weight[u]=w;alive[v]=0;
 for(int j=0;j<adj[v].n;j++){
  int t=adj[v][j]*3;bool hasu=m.i[t]==u32(u)||m.i[t+1]==u32(u)||m.i[t+2]==u32(u);
  if(hasu){m.i[t]=m.i[t+1]=m.i[t+2]=0xffffffffu;continue;}
  for(int k=0;k<3;k++)if(m.i[t+k]==u32(v))m.i[t+k]=u;adj[u].push(t/3);
 }
 adj[v].clear();return true;
}
static void simplify(const World&w,Mesh&m,int ox,int oz,int size,int step,u32 epoch,bool shared_regions=false){
 if(step<=1||m.i.n<300)return;
 int nv=m.v.n;auto adj=(List<int>*)tr_alloc(size_t(nv)*sizeof(List<int>));auto alive=(u8*)tr_alloc(nv);auto weight=(float*)tr_alloc(size_t(nv)*4);auto group=(u32*)tr_alloc(size_t(nv)*4);
 if(!adj||!alive||!weight||!group){if(adj)tr_free(adj);if(alive)tr_free(alive);if(weight)tr_free(weight);if(group)tr_free(group);return;}
 zero_bytes(adj,size_t(nv)*sizeof(List<int>));
 for(int i=0;i<nv;i++){
  alive[i]=1;weight[i]=1;const Vertex&v=m.v[i];int x=v.cx-ox,z=v.cz-oz;
  // All patch-border representatives stay EXACTLY at their original world positions.
   bool pin=x<=0||z<=0||x>=size-2||z>=size-2;
   if(shared_regions){
    // Every potential 16m horizontal / 32m vertical ownership boundary keeps
    // the original representatives, independent of parent LOD and owner size.
    int bx=v.cx&15,bz=v.cz&15,by=v.cy&31;
    pin=pin||bx==0||bx>=14||bz==0||bz>=14||by==0||by>=30;
   }
  // Editing/caves are NOT a heightfield LOD. Protect their actual vertices at
  // every distance. This also prevents the old unconstrained collapse from
  // shrinking a tunnel mouth or changing an excavation into a different shape.
  bool edited=false;
  int px=v.cx>>4,pz=v.cz>>4;
  // A changed cell below ground must not lock its entire XZ column.
  // Inspect the 3D reconstruction support, not any historical page in a column.
  bool candidate=false;
  int py=imx(0,imn(16,v.cy>>4));u32 ymask=(1u<<py)|(py>0?(1u<<(py-1)):0u)|(py<16?(1u<<(py+1)):0u);
  for(int zz=imx(0,pz-1);zz<=imn(NP-1,pz+1)&&!candidate;zz++)
   for(int xx=imx(0,px-1);xx<=imn(NP-1,px+1);xx++)
    if(w.edit_columns[xx+NP*zz]&ymask){candidate=true;break;}
  // One neighboring 16m page in XYZ protects the complete field support,
  // including currently unchanged rim triangles. Unlike the old XZ-only test,
  // a deep edit cannot pin an unrelated mountain surface hundreds of metres up.
  edited=candidate;
  pin=pin||edited||v.n.y<.65f||v.p.y<w.height(v.p.x,v.p.z)-.6f;
  group[i]=pin?0xffffffffu:u32(x/step+(size/step+1)*(z/step+(size/step+1)*(v.cy/step)))+1;
 }
 for(int t=0;t<m.i.n/3;t++)for(int k=0;k<3;k++)adj[m.i[t*3+k]].push(t);
 for(int pass=0;pass<9;pass++){
  if(cancelled(w,epoch))break;
  int changed=0;for(int t=0;t<m.i.n;t+=3){if((t&255)==0&&cancelled(w,epoch))break;if(m.i[t]==0xffffffffu)continue;for(int k=0;k<3;k++){
   int a=m.i[t+k],b=m.i[t+(k+1)%3];if(a<0||b<0)break;
   if(group[a]==0xffffffffu||group[a]!=group[b]||ab(m.v[a].material-m.v[b].material)>.1f||dot(m.v[a].n,m.v[b].n)<.35f)continue;
   if(try_collapse(m,a,b,adj,weight,alive)){changed++;break;}
  }}if(changed==0)break;
 }
 List<u32> remap;remap.resize(nv);List<Vertex> vertices;
 for(int i=0;i<nv;i++)if(alive[i]){remap[i]=vertices.n;vertices.push(m.v[i]);}
 int at=0;for(int t=0;t<m.i.n;t+=3)if(m.i[t]!=0xffffffffu){m.i[at++]=remap[m.i[t]];m.i[at++]=remap[m.i[t+1]];m.i[at++]=remap[m.i[t+2]];}
 m.i.n=at;m.v.release();m.v=vertices;
 for(int i=0;i<nv;i++)adj[i].release();tr_free(adj);tr_free(alive);tr_free(weight);tr_free(group);remap.release();
}
struct Face {int axis,side,plane,u,v,mat;};
static bool face_less(const Face&a,const Face&b){if(a.axis!=b.axis)return a.axis<b.axis;if(a.side!=b.side)return a.side<b.side;if(a.plane!=b.plane)return a.plane<b.plane;if(a.v!=b.v)return a.v<b.v;return a.u<b.u;}
static void sort_faces(Face*p,int lo,int hi){while(lo<hi){Face pivot=p[(lo+hi)/2];int i=lo,j=hi;while(i<=j){while(face_less(p[i],pivot))i++;while(face_less(pivot,p[j]))j--;if(i<=j){Face tmp=p[i];p[i++]=p[j];p[j--]=tmp;}}if(j-lo<hi-i){if(lo<j)sort_faces(p,lo,j);lo=i;}else{if(i<hi)sort_faces(p,i,hi);hi=j;}}}
static void block_quad(Mesh&m,int axis,int side,float plane,float u,float v,float w,float h,int mat){
 V3 p[4];V3 n{};if(axis==0){p[0]={plane,v,u};p[1]={plane,v+h,u};p[2]={plane,v+h,u+w};p[3]={plane,v,u+w};n={float(side),0,0};}
 else if(axis==1){p[0]={u,plane,v};p[1]={u,plane,v+h};p[2]={u+w,plane,v+h};p[3]={u+w,plane,v};n={0,float(side),0};}
 else {p[0]={u,v,plane};p[1]={u+w,v,plane};p[2]={u+w,v+h,plane};p[3]={u,v+h,plane};n={0,0,float(side)};}
 u32 b=m.v.n;for(int i=0;i<4;i++){Vertex q;q.p=p[i];q.n=n;q.material=float(mat+4);m.v.push(q);}quad(m,b,b+1,b+2,b+3,side<0);
}
void add_blocks(const World&w,int ox,int oz,int size,Mesh&m,int y_begin,int y_end){
 List<Face> faces;static const int dx[6]={-1,1,0,0,0,0},dy[6]={0,0,-1,1,0,0},dz[6]={0,0,0,0,-1,1};
 for(int cz=oz/32;cz<imn(64,(oz+size+31)/32);cz++)for(int cx=ox/32;cx<imn(64,(ox+size+31)/32);cx++){
  const auto&column=w.block_columns[cx+64*cz];for(int i=0;i<column.n;i++){
  u32 key=column[i];int x,y,z;decode_block(key,x,y,z);if(x<ox||x>=ox+size||z<oz||z>=oz+size||y<y_begin||y>=y_end)continue;int material=w.blocks.get(key);
  for(int d=0;d<6;d++){
   int xx=x+dx[d],yy=y+dy[d],zz=z+dz[d];if(xx>=0&&xx<WORLD&&zz>=0&&zz<WORLD&&yy>=0&&yy<256&&w.blocks.get(block_key(xx,yy,zz))>=0)continue;
   int a=d/2,s=d%2?1:-1;Face f;f.axis=a;f.side=s;f.mat=material;
   f.plane=(a==0?x:(a==1?y:z))+(s>0);f.u=a==0?z:x;f.v=a==1?z:y;faces.push(f);
  }
 }}
 if(faces.n==0){faces.release();return;}sort_faces(faces.p,0,faces.n-1);
 for(int at=0;at<faces.n;){
  int end=at+1;while(end<faces.n&&faces[end].axis==faces[at].axis&&faces[end].side==faces[at].side&&faces[end].plane==faces[at].plane)end++;
  int u0=faces[at].u,u1=u0,v0=faces[at].v,v1=v0;for(int j=at;j<end;j++){u0=imn(u0,faces[j].u);u1=imx(u1,faces[j].u);v0=imn(v0,faces[j].v);v1=imx(v1,faces[j].v);}int width=u1-u0+1,height=v1-v0+1;
  List<u8> mask;mask.resize(width*height);for(int j=at;j<end;j++)mask[(faces[j].u-u0)+width*(faces[j].v-v0)]=u8(faces[j].mat);
  for(int v=0;v<height;v++)for(int u=0;u<width;u++){
   u8 mat=mask[u+width*v];if(!mat)continue;int rw=1;while(u+rw<width&&(u0+u+rw)/32==(u0+u)/32&&mask[u+rw+width*v]==mat)rw++;int rh=1;bool good=true;while(v+rh<height&&(v0+v+rh)/32==(v0+v)/32&&good){for(int k=0;k<rw;k++)if(mask[u+k+width*(v+rh)]!=mat){good=false;break;}if(good)rh++;}
   block_quad(m,faces[at].axis,faces[at].side,float(faces[at].plane),float(u0+u),float(v0+v),float(rw),float(rh),mat);
   for(int yy=0;yy<rh;yy++)for(int xx=0;xx<rw;xx++)mask[u+xx+width*(v+yy)]=0;
  }mask.release();at=end;
 }faces.release();
}
static void mark_y(u32*bits,int lo,int hi){lo=imx(0,lo);hi=imn(255,hi);for(int y=lo;y<=hi;y++)bits[y>>5]|=1u<<(y&31);}
struct CachedSample {i16 value;u8 material,valid;};
static bool extract_vertices(const World&w,int ox,int oz,int size,Mesh&m,u32 epoch,int y_begin=0,int y_end=WORLD_Y,const float*cached_heights=nullptr){
 const int hn=size+2;List<float> heights;
 if(!cached_heights){heights.resize(hn*hn);
 for(int z=-1;z<=size;z++){
  if(cancelled(w,epoch)){heights.release();return false;}
  for(int x=-1;x<=size;x++)heights[(x+1)+hn*(z+1)]=w.height(float(ox+x),float(oz+z));
 }
 }
 const float*height_values=cached_heights?cached_heights:heights.p;
 List<CachedSample> cache;const int plane_size=hn*257;cache.resize(plane_size*2);
 static const int edges[12][2]={{0,1},{2,3},{4,5},{6,7},{0,2},{1,3},{4,6},{5,7},{0,4},{1,5},{2,6},{3,7}};
 for(int z=-1;z<size;z++){
  if(cancelled(w,epoch))break;
  zero_bytes(cache.p+((z+1)&1)*plane_size,size_t(plane_size)*sizeof(CachedSample));
  for(int x=-1;x<size;x++){
  int gx=ox+x,gz=oz+z;if(gx<-1||gx>WORLD||gz<-1||gz>WORLD)continue;
  float h[4]={height_values[(x+1)+hn*(z+1)],height_values[(x+2)+hn*(z+1)],height_values[(x+1)+hn*(z+2)],height_values[(x+2)+hn*(z+2)]};
  float low=mn(mn(h[0],h[1]),mn(h[2],h[3]))-2,high=mx(mx(h[0],h[1]),mx(h[2],h[3]))+1;
  u32 ybits[8]={};mark_y(ybits,fl(low),fl(high)+1);
  bool side=gx<1||gz<1||gx>=WORLD-1||gz>=WORLD-1;if(side){low=0;mark_y(ybits,0,fl(high)+1);}
  for(int j=0;j<w.caves.n;j++){const Cave&c=w.caves[j];if(gx+1<mn(c.a.x,c.b.x)-c.r-2||gx>mx(c.a.x,c.b.x)+c.r+2||gz+1<mn(c.a.z,c.b.z)-c.r-2||gz>mx(c.a.z,c.b.z)+c.r+2)continue;mark_y(ybits,fl(mn(c.a.y,c.b.y)-c.r-2),fl(mx(c.a.y,c.b.y)+c.r+2)+1);low=mn(low,mn(c.a.y,c.b.y)-c.r-2);high=mx(high,mx(c.a.y,c.b.y)+c.r+2);}
  u32 mask=0;for(int zz=0;zz<2;zz++)for(int xx=0;xx<2;xx++){int px=(gx+xx)>>4,pz=(gz+zz)>>4;if(px>=0&&px<NP&&pz>=0&&pz<NP)mask|=w.edit_columns[px+NP*pz];}
  if(mask)for(int py=0;py<=16;py++)if(mask&(1u<<py)){mark_y(ybits,py*16-1,py*16+17);low=mn(low,float(py*16-1));high=mx(high,float(py*16+16));}
   int y0=imx(imx(0,y_begin-1),fl(low)),y1=imn(y_end-1,fl(high)+1);
  // Page indices for the four vertical sample columns are shared across all Y cells.
  int cached_py=-999,page_indices[4]={-1,-1,-1,-1};
  for(int y=y0;y<=y1;y++){
   if(!(ybits[y>>5]&(1u<<(y&31))))continue;
   float d[8];u8 mats[8];u32 signs=0;
   for(int k=0;k<8;k++){
    int xx=gx+(k&1),yy=y+((k>>1)&1),zz=gz+((k>>2)&1);int hc=(k&1)+2*((k>>2)&1);mats[k]=0;
    if(xx<0||xx>WORLD||zz<0||zz>WORLD||yy>WORLD_Y){d[k]=SDF_BAND;continue;}
    int cache_at=(x+1+(k&1))+hn*yy+((z+((k>>2)&1))&1)*plane_size;
    CachedSample& cached=cache[cache_at];
    if(cached.valid){d[k]=float(cached.value)/SDF_SCALE;mats[k]=cached.material;if(d[k]<0)signs|=1u<<k;continue;}
    int py=yy>>4;if(py!=cached_py){for(int c=0;c<4;c++){int sx=gx+(c&1),sz=gz+((c>>1)&1);page_indices[c]=sx<0||sz<0||sx>WORLD||sz>WORLD?-1:w.pages_by_key.get(page_key(sx>>4,py,sz>>4));}cached_py=py;}
    int pi=page_indices[hc];if(pi>=0){int at=(xx&15)+16*((zz&15)+16*(yy&15));d[k]=float(w.pages[pi].d[at])/SDF_SCALE;mats[k]=w.pages[pi].mat[at];}else d[k]=float(quant(w.base({float(xx),float(yy),float(zz)},h[hc])))/SDF_SCALE;
    cached.value=quant(d[k]);cached.material=mats[k];cached.valid=1;
    if(d[k]<0)signs|=1u<<k;
   }
   if(signs==0||signs==255)continue;
   V3 p{};int count=0;for(int e=0;e<12;e++){int a=edges[e][0],b=edges[e][1];if(((signs>>a)&1)==((signs>>b)&1))continue;float t=d[a]/(d[a]-d[b]);V3 va={float(a&1),float((a>>1)&1),float((a>>2)&1)},vb={float(b&1),float((b>>1)&1),float((b>>2)&1)};p=p+va+(vb-va)*t;count++;}
   if(!count)continue;p=p/float(count);
   if(w.surface_style==1){
    bool edited_cell=false;for(int k=0;k<8;k++)if(mats[k])edited_cell=true;
    if(edited_cell)for(int iteration=0;iteration<4;iteration++){
     float value=0;V3 grad{};
     for(int k=0;k<8;k++){
      float xx=k&1?p.x:1-p.x,yy=k&2?p.y:1-p.y,zz=k&4?p.z:1-p.z;
      value+=d[k]*xx*yy*zz;
      grad.x+=d[k]*(k&1?1.f:-1.f)*yy*zz;
      grad.y+=d[k]*(k&2?1.f:-1.f)*xx*zz;
      grad.z+=d[k]*(k&4?1.f:-1.f)*xx*yy;
     }
     float g2=dot(grad,grad);if(g2<1e-8f||ab(value)<.0005f)break;
     V3 delta=grad*(value/g2);float dl=length(delta);if(dl>.2f)delta=delta*(.2f/dl);
     p={clampf(p.x-delta.x,.001f,.999f),clampf(p.y-delta.y,.001f,.999f),clampf(p.z-delta.z,.001f,.999f)};
    }
   }
   Vertex v;v.p={gx+p.x,y+p.y,gz+p.z};v.n=gradient(d,p);v.cx=gx;v.cy=y;v.cz=gz;v.mask=signs;
   // Material classification does not affect the field or topology.
   float best=1e30f;for(int k=0;k<8;k++)if(mats[k]&&mats[k]<5&&ab(d[k])<best){best=ab(d[k]);v.material=float(mats[k]);} // Natural ore IDs are shaded separately from edit materials.
   m.v.push(v);
  }
 }}
 cache.release();
 if(cancelled(w,epoch)){heights.release();m.release();return false;}
 heights.release();return true;
}

static void connect_patch(int ox,int oz,int size,Mesh&m,int y_begin=0,int y_end=WORLD_Y){
 Map ids;
 for(int j=0;j<m.v.n;j++){const Vertex&v=m.v[j];ids.put(cell_key(v.cx-ox,v.cy,v.cz-oz,size),j);}
 int vn=m.v.n;
 for(int j=0;j<vn;j++){
   const Vertex&v=m.v[j];int x=v.cx-ox,y=v.cy,z=v.cz-oz;if(x<0||z<0||x>=size||z>=size||y<y_begin||y>=y_end)continue;u32 s=v.mask;
  for(int axis=0;axis<3;axis++){
   int other=axis==0?1:(axis==1?2:4);if((s&1)==((s>>other)&1))continue;int a,b,c,d;
   if(axis==0){if(y<1||z<0)continue;a=ids.get(cell_key(x,y-1,z-1,size));b=ids.get(cell_key(x,y,z-1,size));c=j;d=ids.get(cell_key(x,y-1,z,size));}
   else if(axis==1){a=ids.get(cell_key(x-1,y,z-1,size));b=ids.get(cell_key(x-1,y,z,size));c=j;d=ids.get(cell_key(x,y,z-1,size));}
   else{if(y<1)continue;a=ids.get(cell_key(x-1,y-1,z,size));b=ids.get(cell_key(x,y-1,z,size));c=j;d=ids.get(cell_key(x-1,y,z,size));}
   if(a<0||b<0||c<0||d<0)continue;quad(m,a,b,c,d,(s&1)==0);
  }
 }
 ids.release();
}

#include "geometry_regions.hpp"

bool build_patch(const World&w,int ox,int oz,int size,int step,Mesh&m,u32 expected_epoch,bool region_cache){
 double mark=w.profile_mesh?mesh_clock_ms():0;
 if(w.profile_mesh)zero_bytes(w.mesh_stage_ms,sizeof(w.mesh_stage_ms));
 const u32 epoch=expected_epoch==0xffffffffu?terrain_build_epoch(&w):expected_epoch;
 if(cancelled(w,epoch))return false;
 bool ok=region_cache?cached_vertices(w,ox,oz,size,m,epoch):extract_vertices(w,ox,oz,size,m,epoch);
 if(!ok){m.release();return false;}
 connect_patch(ox,oz,size,m);
 if(w.profile_mesh){double now=mesh_clock_ms();w.mesh_stage_ms[0]=float(now-mark);mark=now;}
 simplify(w,m,ox,oz,size,step,epoch);
 if(w.profile_mesh){double now=mesh_clock_ms();w.mesh_stage_ms[1]=float(now-mark);mark=now;}
 if(cancelled(w,epoch)){m.release();return false;}
 add_blocks(w,ox,oz,size,m);
 if(w.profile_mesh){double now=mesh_clock_ms();w.mesh_stage_ms[2]=float(now-mark);mark=now;}
 if(cancelled(w,epoch)){m.release();return false;}
 shade_mesh(w,m,epoch);
 if(w.profile_mesh)w.mesh_stage_ms[3]=float(mesh_clock_ms()-mark);
 if(cancelled(w,epoch)){m.release();return false;}
 return true;
}

bool build_owned_region(const World&w,int ox,int oz,int size,int step,int y_begin,int y_end,Mesh&m,u32 epoch){
 double mark=w.profile_mesh?mesh_clock_ms():0;
 if(w.profile_mesh)zero_bytes(w.mesh_stage_ms,sizeof(w.mesh_stage_ms));
 if(ox<0||oz<0||ox>=2048||oz>=2048||(size!=16&&size!=32&&size!=64)||
    ox%size||oz%size||(step!=1&&step!=2&&step!=4&&step!=8)||
    y_begin<0||y_end>WORLD_Y||y_begin>=y_end||y_begin%32||y_end-y_begin!=32)return false;
 const int hn=size+2;
 if(w.owned_height_x!=ox||w.owned_height_z!=oz||w.owned_height_size!=size||w.owned_height_seed!=w.seed||w.owned_heights.n!=hn*hn){
  w.owned_height_size=0;
  w.owned_heights.resize(hn*hn);
  if(tr_oom)return false;
  for(int z=-1;z<=size;z++){
   if(cancelled(w,epoch))return false;
   for(int x=-1;x<=size;x++)w.owned_heights[(x+1)+hn*(z+1)]=w.height(float(ox+x),float(oz+z));
  }
  w.owned_height_x=ox;w.owned_height_z=oz;w.owned_height_seed=w.seed;w.owned_height_size=size;
 }
 if(cancelled(w,epoch)||!extract_vertices(w,ox,oz,size,m,epoch,y_begin,y_end,w.owned_heights.p)){m.release();return false;}
 connect_patch(ox,oz,size,m,y_begin,y_end);
 if(w.profile_mesh){double now=mesh_clock_ms();w.mesh_stage_ms[0]=float(now-mark);mark=now;}
 simplify(w,m,ox,oz,size,step,epoch,true);
 if(w.profile_mesh){double now=mesh_clock_ms();w.mesh_stage_ms[1]=float(now-mark);mark=now;}
 if(cancelled(w,epoch)||tr_oom){m.release();return false;}
 add_blocks(w,ox,oz,size,m,y_begin,y_end);
 // Halo representatives with no owned face are inputs, not render vertices.
 // Do not perform lighting or transfer them to the engine.
 if(!tr_oom){
  List<u32> remap;remap.resize(m.v.n);
  if(tr_oom){remap.release();m.release();return false;}
  for(int i=0;i<remap.n;i++)remap[i]=0xffffffffu;
  for(int i=0;i<m.i.n;i++)remap[m.i[i]]=0;
  List<Vertex> used;
  for(int i=0;i<m.v.n;i++)if(remap[i]!=0xffffffffu){remap[i]=u32(used.n);used.push(m.v[i]);}
  if(!tr_oom){for(int i=0;i<m.i.n;i++)m.i[i]=remap[m.i[i]];m.v.release();m.v=used;}
  else used.release();
  remap.release();
 }
 if(w.profile_mesh){double now=mesh_clock_ms();w.mesh_stage_ms[2]=float(now-mark);mark=now;}
 if(!cancelled(w,epoch)&&!tr_oom)shade_mesh(w,m,epoch);
 if(w.profile_mesh)w.mesh_stage_ms[3]=float(mesh_clock_ms()-mark);
 if(cancelled(w,epoch)||tr_oom){m.release();return false;}
 return true;
}

// Cached material/occlusion build. No field sampling is done in the frame shader.
static float trilerp(const float*d,V3 p){float v=0;for(int k=0;k<8;k++)v+=d[k]*(k&1?p.x:1-p.x)*(k&2?p.y:1-p.y)*(k&4?p.z:1-p.z);return v;}
static float eased(float a,float b,float v){return smooth(clampf((v-a)/(b-a),0,1));}
static float cubic(float a,float b,float c,float d,float t){return ((a*t+b)*t+c)*t+d;}
static float segment_minimum(const float*d,V3 from,V3 to){
 // Restrict a trilinear cell to a ray segment: an exact cubic. Check endpoints
 // and derivative roots, rather than tunnelling through thin solid intervals.
 V3 v=to-from;float f0=trilerp(d,from),f1=trilerp(d,from+v/3.f),f2=trilerp(d,from+v*(2.f/3.f)),f3=trilerp(d,to);
 float a=4.5f*(f3-3*f2+3*f1-f0),b=4.5f*(f2-2*f1+f0)-a,c=f3-f0-a-b,result=mn(f0,f3);
 if(ab(a)<1e-6f){if(ab(b)>1e-6f){float t=-c/(2*b);if(t>0&&t<1)result=mn(result,cubic(a,b,c,f0,t));}}
 else {float disc=b*b-3*a*c;if(disc>=0){float q=root(disc);float t0=(-b-q)/(3*a),t1=(-b+q)/(3*a);if(t0>0&&t0<1)result=mn(result,cubic(a,b,c,f0,t0));if(t1>0&&t1<1)result=mn(result,cubic(a,b,c,f0,t1));}}
 return result;
}
static float exit_time(V3 p,V3 dir,int x,int y,int z,float size){
 float t=1e10f;float pos[3]={p.x,p.y,p.z},d[3]={dir.x,dir.y,dir.z},lo[3]={float(x),float(y),float(z)};
 for(int i=0;i<3;i++)if(ab(d[i])>1e-8f){float v=(lo[i]+(d[i]>0?size:0)-pos[i])/d[i];if(v>=-1e-5f)t=mn(t,mx(v,0));}
 return t;
}

// Revision-local worker-owned memoization of sampled fields, roofs and sky probes.
// Neighboring patches reuse it; any authoritative edit invalidates it. Soft size
// limits are checked at each patch/relight boundary. Nothing is persisted.
struct RoofCache {
 const World&w;Map &ids,&samples;List<float> &tops;
 explicit RoofCache(const World&world):w(world),ids(world.light_roofs),samples(world.light_samples),tops(world.light_tops){
  if(w.lighting_revision!=w.revision || samples.n>300000 || ids.n>65536 || w.light_probes.n>32768){
   ids.release();samples.release();tops.release();w.light_probe_ids.release();w.light_probes.release();
   w.lighting_revision=w.revision;
  }
 }
 float sample(int x,int y,int z){
  if(x<0||z<0||x>WORLD||z>WORLD||y<0||y>WORLD_Y)return SDF_BAND;
  u32 key=block_key(x,y,z);int v=samples.get(key);if(v>=0)return float(v-32768)/SDF_SCALE;
  i16 q=quant(w.sample(x,y,z));samples.put(key,int(q)+32768);return float(q)/SDF_SCALE;
 }
 float lattice(int x,int z){
  if(x<0||z<0||x>WORLD||z>WORLD)return 0;
  u32 key=u32(x+2001*z)+1;int id=ids.get(key);if(id>=0)return tops[id];
  float h=w.height(float(x),float(z));int upper=imn(255,fl(h)+2);
  u32 bits=w.edit_columns[(x>>4)+NP*(z>>4)];for(int py=0;py<=15;py++)if(bits&(1u<<py))upper=imx(upper,imn(255,py*16+16));
  float top=1,d_above=sample(x,upper,z);for(int y=upper-1;y>=1;y--){float d=sample(x,y,z);if(d<0){top=float(y)+d/(d-d_above);break;}d_above=d;}
  ids.put(key,tops.n);tops.push(top);return top;
 }
 float cube_top(int x,int z){
  if(x<0||z<0||x>=WORLD||z>=WORLD)return 0;
  float result=0;const auto&column=w.block_columns[(x>>5)+64*(z>>5)];
  for(int i=0;i<column.n;i++){int bx,by,bz;decode_block(column[i],bx,by,bz);if(bx==x&&bz==z)result=mx(result,float(by+1));}return result;
 }
 float upper_at(float px,float pz){
  int x=fl(px),z=fl(pz);if(x<0||z<0||x>=WORLD||z>=WORLD)return 0;
  return mx(cube_top(x,z),mx(mx(lattice(x,z),lattice(x+1,z)),mx(lattice(x,z+1),lattice(x+1,z+1))));
 }
 float top_at(float px,float pz){
  int x=fl(px),z=fl(pz);if(x<0||z<0||x>=WORLD||z>=WORLD)return 0;
  float fx=px-x,fz=pz-z;float weights[4]={(1-fx)*(1-fz),fx*(1-fz),(1-fx)*fz,fx*fz};
  float top=mx(mx(lattice(x,z),lattice(x+1,z)),mx(lattice(x,z+1),lattice(x+1,z+1)));
  int upper=imn(255,fl(top)+2);float above=4;
  for(int y=upper;y>=1;y--){float d=0;for(int k=0;k<4;k++)d+=weights[k]*sample(x+(k&1),y,z+((k>>1)&1));if(d<0)return mx(cube_top(x,z),float(y)+d/(d-above));above=d;}
  return cube_top(x,z);
 }
};
static int trace_visibility(const World&w,V3 origin,V3 direction,RoofCache*roof,int budget=1400){
 w.light_rays++;
 V3 dir=normal(direction);float t=0.001f;
 for(int iter=0;iter<budget;iter++){
  w.light_steps++;
  V3 p=origin+dir*t;if(p.x<0||p.x>=WORLD||p.z<0||p.z>=WORLD||p.y>=255)return false;if(p.y<1)return true;
  // After a cavity ray emerges outdoors, standard directional shadow maps
  // handle the remaining exterior occluders. This is a cavity-light gate,
  // not a replacement for all world-space shadows / global illumination.
  if(roof&&p.y>roof->upper_at(p.x,p.z)+.02f)return false;
  int x=fl(p.x),y=fl(p.y),z=fl(p.z);
  if(w.blocks.get(block_key(x,y,z))>=0)return true;
  if(roof && w.block_columns[(x>>5)+64*(z>>5)].n==0){
   bool edited=false;for(int k=0;k<8;k++)if(w.pages_by_key.get(page_key((x+(k&1))>>4,(y+((k>>1)&1))>>4,(z+((k>>2)&1))>>4))>=0){edited=true;break;}
   if(!edited){
    // Original cave capsules have an analytic distance in air. Use that only
    // until the next reconstruction-page boundary; edits retain cubic cell tests.
    float field=w.base(p,w.height(p.x,p.z));
    if(field<=.003f)return true;
    int px=(x>>4)*16,py=(y>>4)*16,pz=(z>>4)*16;
    float edge=exit_time(p,dir,x,y,z,1.f);
    if(p.x<px+15 && p.y<py+15 && p.z<pz+15)edge=exit_time(p,dir,px,py,pz,15.f);
    // Beneath the original height surface, positive air distance comes from
    // the union of the cave capsules (Lipschitz 1). Above it we already exit via roof.
    float advance=mn(field*.75f,edge);
    if(advance>1e-5f){t+=advance+(advance>=edge-1e-6f?.00005f:0.f);continue;}
   }
  }
  float span=exit_time(p,dir,x,y,z,1.f);if(span<1e-5f){t+=.0001f;continue;}
  float d[8],low=1e10f;for(int k=0;k<8;k++){d[k]=roof?roof->sample(x+(k&1),y+((k>>1)&1),z+((k>>2)&1)):w.sample(x+(k&1),y+((k>>1)&1),z+((k>>2)&1));low=mn(low,d[k]);}
  if(low<-.001f){V3 q={p.x-x,p.y-y,p.z-z};V3 end=q+dir*span;if(segment_minimum(d,q,end)<-.002f)return true;}
  t+=span+.00005f;
 }
 w.light_unresolved++;
 return 2; // Kept distinct from confirmed occlusion in diagnostics.
}
static bool trace_occluded(const World&w,V3 p,V3 d,RoofCache*roof){return trace_visibility(w,p,d,roof)!=0;}
int terrain_visibility(const World&w,V3 p,V3 d,int budget){return trace_visibility(w,p,d,nullptr,budget);}
bool terrain_occluded(const World&w,V3 origin,V3 direction){return terrain_visibility(w,origin,direction)!=0;}
static bool has_cover_candidates(const World&w,V3 p,float original_height){
 if(p.y<original_height-.30f)return true;
 int px=fl(p.x)>>4,pz=fl(p.z)>>4,py=imx(0,imn(16,fl(p.y)>>4));
 for(int zz=imx(0,pz-1);zz<=imn(NP-1,pz+1);zz++)for(int xx=imx(0,px-1);xx<=imn(NP-1,px+1);xx++)if(w.edit_columns[xx+NP*zz]>>py)return true;
 int cx=fl(p.x)>>5,cz=fl(p.z)>>5;
 for(int zz=imx(0,cz-1);zz<=imn(63,cz+1);zz++)for(int xx=imx(0,cx-1);xx<=imn(63,cx+1);xx++)if(w.block_columns[xx+64*zz].n)return true;
 return false;
}
static float owned_lattice_height(const World&w,int x,int z){
 int rx=x-w.owned_height_x+1,rz=z-w.owned_height_z+1,n=w.owned_height_size+2;
 if(w.owned_height_size>0&&w.owned_height_seed==w.seed&&w.owned_heights.n==n*n&&rx>=0&&rz>=0&&rx<n&&rz<n)return w.owned_heights[rx+n*rz];
 return w.height(float(x),float(z));
}
void shade_mesh(const World&w,Mesh&m,u32 expected_epoch){
 const u32 epoch=expected_epoch==0xffffffffu?terrain_build_epoch(&w):expected_epoch;
 if(cancelled(w,epoch))return;
 for(int i=0;i<m.v.n;i++){
  if((i&31)==0&&cancelled(w,epoch))return;
  Vertex&v=m.v[i];float h=w.height(v.p.x,v.p.z);
  v.ore=w.generator_id>=3&&v.material<5?geological_weight(v.p,h,u32(w.seed)):0;
  v.substrate=eased(.15f,.65f,h-v.p.y);v.blend={};v.asphalt=0;
  if(v.material<5){
   int x=fl(v.p.x),y=fl(v.p.y),z=fl(v.p.z);V3 f={v.p.x-x,v.p.y-y,v.p.z-z};float delta=0,total=0,asphalt=0,original[8];V3 influence{};
   for(int k=0;k<8;k++){
    int sx=x+(k&1),sy=y+((k>>1)&1),sz=z+((k>>2)&1);u8 mat=0;
    float original_sample=w.base({float(sx),float(sy),float(sz)},owned_lattice_height(w,sx,sz));
    float base=float(quant(original_sample))/SDF_SCALE;
    float current=original_sample;
    if(sx<0||sx>WORLD||sz<0||sz>WORLD||sy<0||sy>WORLD_Y)current=SDF_BAND;
    else {int pi=w.pages_by_key.get(page_key(sx>>4,sy>>4,sz>>4));if(pi>=0){int at=(sx&15)+16*((sz&15)+16*(sy&15));current=float(w.pages[pi].d[at])/SDF_SCALE;mat=w.pages[pi].mat[at];}}
    original[k]=base;
    float weight=(k&1?f.x:1-f.x)*(k&2?f.y:1-f.y)*(k&4?f.z:1-f.z);float difference=current-base;
    delta+=difference*weight;
    float amount=ab(difference)*weight;if(mat==1)influence.x+=amount;else if(mat==2)influence.y+=amount;else if(mat==3)influence.z+=amount;else if(mat==4)asphalt+=amount;
   }
   total=influence.x+influence.y+influence.z+asphalt;
   // Unchanged surface => ZERO paint, even in an allocated/previously edited page.
   // Blend continuously across the sub-metre reconstructed rim, not categorical UV thresholds.
   if(total>1e-6f){
    static const int edge[12][2]={{0,1},{2,3},{4,5},{6,7},{0,2},{1,3},{4,6},{5,7},{0,4},{1,5},{2,6},{3,7}};
    V3 original_vertex{};int crossings=0;
    for(int e=0;e<12;e++){int a=edge[e][0],b=edge[e][1];if((original[a]<0)==(original[b]<0))continue;float t=original[a]/(original[a]-original[b]);V3 pa={float(a&1),float((a>>1)&1),float((a>>2)&1)},pb={float(b&1),float((b>>1)&1),float((b>>2)&1)};original_vertex=original_vertex+pa+(pb-pa)*t;crossings++;}
    float amount=eased(.025f,.35f,ab(delta));
    if(crossings)amount=mn(amount,eased(.025f,.28f,length(f-original_vertex/float(crossings))));
    v.blend=influence*(amount/total);v.asphalt=asphalt*(amount/total);
   }
  }
 }
 if(!cancelled(w,epoch))shade_visibility(w,m,epoch);
}
// Project a representative from the cached mesh to the AIR side of the sampled
// field before testing visibility. Surface Nets representatives need not lie
// exactly on its trilinear zero set; a fixed .18 m offset can still be in rock.
static float interpolated_sample(RoofCache&roof,V3 p){
 int x=fl(p.x),y=fl(p.y),z=fl(p.z);float d[8];
 for(int k=0;k<8;k++)d[k]=roof.sample(x+(k&1),y+((k>>1)&1),z+((k>>2)&1));
 return trilerp(d,{p.x-x,p.y-y,p.z-z});
}
static V3 visibility_origin(RoofCache&roof,const Vertex&v){
 V3 p=v.p+v.n*.06f;
 if(v.material>=5.f)return p;
 for(int j=0;j<8;j++){
  float f=interpolated_sample(roof,p);if(f>.015f)break;
  float ahead=interpolated_sample(roof,p+v.n*.10f);
  float slope=mx(.10f,(ahead-f)*10.f);
  p=p+v.n*clampf((.02f-f)/slope,.015f,.20f);
 }
 return p;
}
// Nearby sky probes may be shared ONLY after verifying a connecting air
// segment in the same authoritative trilinear field. A thin separating wall
// therefore prevents irradiance from being reused on its opposite side.
static bool connected_air(const World&w,RoofCache&roof,V3 a,V3 b){
 float distance=length(b-a);if(distance<.015f)return true;
 V3 dir=(b-a)/distance;float t=0;
 for(int iter=0;iter<40&&t<distance;iter++){
  V3 p=a+dir*t;int x=fl(p.x),y=fl(p.y),z=fl(p.z);
  if(x<0||z<0||x>=WORLD||z>=WORLD||y<1||y>=255)return false;
  if(w.blocks.get(block_key(x,y,z))>=0)return false;
  float span=mn(distance-t,exit_time(p,dir,x,y,z,1.f));
  if(span<1e-6f){t+=.00001f;continue;}
  float d[8];for(int k=0;k<8;k++)d[k]=roof.sample(x+(k&1),y+((k>>1)&1),z+((k>>2)&1));
  V3 q={p.x-x,p.y-y,p.z-z};
  if(segment_minimum(d,q,q+dir*span)<.003f)return false;
  t+=span+.00001f;
 }
 return t>=distance;
}
void shade_visibility(const World&w,Mesh&m,u32 expected_epoch){
 const u32 epoch=expected_epoch==0xffffffffu?terrain_build_epoch(&w):expected_epoch;
 const V3 toward_sun={-0.3141378f,0.7431448f,0.5908073f};
 // A vertical roof test alone classifies the open side of an excavation as
 // sealed. Sample the upper hemisphere only where cover can actually exist.
 // This is diffuse sky visibility, NOT indirect multi-bounce GI.
 static const V3 sky_dirs[12]={
  {.80f,.60f,0},{-.80f,.60f,0},{0,.60f,.80f},{0,.60f,-.80f},
  {.9837f,.18f,0},{-.9837f,.18f,0},{0,.18f,.9837f},{0,.18f,-.9837f},
  {.6956f,.18f,.6956f},{-.6956f,.18f,.6956f},
  {.6956f,.18f,-.6956f},{-.6956f,.18f,-.6956f}};
 RoofCache roof(w);Map &probe_ids=w.light_probe_ids;List<SkyProbe>&probes=w.light_probes;
 for(int i=0;i<m.v.n;i++){
  if((i&7)==0&&cancelled(w,epoch))break;
  Vertex&v=m.v[i];float h=w.height(v.p.x,v.p.z);
  v.sky=1;v.sun=1;
  if(!has_cover_candidates(w,v.p,h))continue;
  V3 start=visibility_origin(roof,v);
  bool open_above=start.y>=roof.top_at(start.x,start.z)-.002f;
  // An unobstructed vertical column is the cheap exterior fast path. Shadow
  // maps resolve exterior sunlight; no stale baked mask multiplies it twice.
  if(open_above)continue;
  int nx=fl(clampf(start.x,0,1999.9f)*.5f),ny=fl(clampf(start.y,0,255.f)*.5f),nz=fl(clampf(start.z,0,1999.9f)*.5f);
  int axis=ab(v.n.x)>ab(v.n.y)?(ab(v.n.x)>ab(v.n.z)?0:2):(ab(v.n.y)>ab(v.n.z)?1:2);
  float component=axis==0?v.n.x:(axis==1?v.n.y:v.n.z);
  u32 key=u32(nx+1000*(nz+1000*ny))*6u+u32(axis*2+(component>0?1:0))+1u;
  int at=probe_ids.get(key);
  if(at<0){
   // World-aligned canonical probe, independent of which patch/LOD is built
   // first. A first-vertex cache would give mismatched light on shared borders.
   V3 pp={nx*2.f+1,ny*2.f+1,nz*2.f+1},axis_n={};
   if(axis==0)axis_n.x=component>0?1.f:-1.f;
   else if(axis==1)axis_n.y=component>0?1.f:-1.f;
   else axis_n.z=component>0?1.f:-1.f;
   bool air=false;
   for(int j=0;j<7;j++){
    int bx=fl(pp.x),by=fl(pp.y),bz=fl(pp.z);
    if(bx<0||bz<0||bx>=WORLD||bz>=WORLD||by<1||by>=255)break;
    if(interpolated_sample(roof,pp)>.015f&&w.blocks.get(block_key(bx,by,bz))<0){air=true;break;}
    pp=pp+axis_n*.25f;
   }
   float value=-1;
   if(air){
    if(pp.y>=roof.top_at(pp.x,pp.z)-.002f)value=1;
    else{
     value=0;for(int ray=0;ray<12;ray++)if(!trace_occluded(w,pp,sky_dirs[ray],&roof))value+=1.f/13.f;
    }
   }
   at=probes.n;probe_ids.put(key,at);probes.push({pp,axis_n,value});
  }
  bool reused=probes[at].sky>=0.f&&connected_air(w,roof,start,probes[at].p);
  if(reused){v.sky=probes[at].sky;w.light_probe_hits++;}
  else{
   float visible=0.f;
   for(int ray=0;ray<12;ray++){
    if(cancelled(w,epoch))break;
    if(!trace_occluded(w,start,sky_dirs[ray],&roof))visible+=1.f;
   }
   v.sky=visible/13.f;
  }
  // Keep directional shadowing per-vertex: a shared sky probe must not move
  // the edge of a small direct-sun shaft.
  v.sun=dot(v.n,toward_sun)>0.001f?(trace_occluded(w,start,toward_sun,&roof)?0.f:1.f):0.f;
 }
 // Revision-local memoization is retained for neighboring patches, not replayed edits.
}

void encode_mesh(const Mesh&m,int ox,int oz,int size,int step,Bytes&out){
 out.u(MESH_MAGIC);out.u(5);out.u(ox);out.u(oz);out.u(size);out.u(step);out.u(m.v.n);out.u(m.i.n);
 int face_count=size<=32&&step==1?m.i.n:0;out.u(face_count);
 // Planar channels make GDScript's PackedByteArray.to_float32_array conversion cheap.
 for(int i=0;i<m.v.n;i++)out.vec(m.v[i].p);
 for(int i=0;i<m.v.n;i++)out.vec(m.v[i].n);
 // Packet v3: UV carries cached sky/sun transmission; UV2 identifies exact
 // blocks/LOD only. COLOR is continuous material weights + geological exposure.
 for(int i=0;i<m.v.n;i++){out.f(m.v[i].sky);out.f(m.v[i].sun);}
 // Integer LOD step plus continuous asphalt weight in the fractional quarter.
 // Step is constant within a surface, so interpolation preserves both channels.
 for(int i=0;i<m.v.n;i++){out.f(m.v[i].material>=5?m.v[i].material:m.v[i].ore);out.f(float(step)+clampf(m.v[i].asphalt,0,1)*.25f);}
 for(int i=0;i<m.v.n;i++){out.vec(m.v[i].blend);out.f(m.v[i].substrate);}
 if(m.i.n)out.raw(m.i.p,m.i.n*4);
 for(int i=0;i<face_count;i++)out.vec(m.v[m.i[i]].p);
}
#include "experimental/density_ray.hpp"
void process_request(World&w,const u8*data,int n,Bytes&out){
 Reader r{data,n};u32 cmd=r.u();out.u(REPLY_MAGIC);out.u(cmd);out.u(0);
 if(!r.good){out.p[8]=1;return;}
 if(cmd==0){out.u(w.revision);out.u(w.edits);out.u(w.pages.n);out.u(w.blocks.n);out.u(u32(w.changed_samples));out.u(w.seed);}
 else if(cmd==1||cmd==20){
  int ox=int(r.u()),oz=int(r.u()),size=int(r.u()),step=int(r.u());
  u32 epoch=r.at+4<=r.n?r.u():terrain_build_epoch(&w);
  if(!r.good||ox<0||oz<0||ox>=2048||oz>=2048||(size!=16&&size!=32&&size!=64&&size!=128&&size!=256)||(step!=1&&step!=2&&step!=4&&step!=8)){out.p[8]=1;return;}
  Mesh m;
  if(!build_patch(w,ox,oz,size,step,m,epoch,cmd==20)){out.p[8]=4;return;}
  out.u(w.revision);encode_mesh(m,ox,oz,size,step,out);m.release();
 }
 else if(cmd==2){V3 a=r.vec(),b=r.vec();float radius=r.f();int shape=int(r.u()),add=int(r.u()),mat=int(r.u());if(!r.good||!(radius>=.5f&&radius<=64.f)||shape<0||shape>1||mat<0||mat>3||!(ab(a.x)<=10000&&ab(b.x)<=10000&&ab(a.y)<=10000&&ab(b.y)<=10000&&ab(a.z)<=10000&&ab(b.z)<=10000)){out.p[8]=1;return;}V3 lo,hi;int changes;u32 removed[16]{};bool ok=w.edit(a,b,radius,shape,add!=0,u8(mat),lo,hi,changes,1.f,0.f,0.f,removed);if(!ok)out.p[8]=2;out.u(w.revision);out.u(changes);out.u(w.pages.n);out.u(w.blocks.n);out.vec(lo);out.vec(hi);for(u32 count:removed)out.u(ok?count:0);}
 else if(cmd==28){
  V3 a=r.vec(),b=r.vec();float width=r.f(),depth=r.f(),clearance=n>=40?r.f():0;u32 material=n>=44?r.u():4;float shoulder=n==48?r.f():0;V3 axis={b.x-a.x,0,b.z-a.z};float distance=length(axis);
  if(!r.good||(n!=36&&n!=40&&n!=44&&n!=48)||material<1||material>4||!(shoulder>=0&&shoulder<=16)||!(clearance>=0&&clearance<=16&&mx(a.y,b.y)+clearance<=250&&width>=.5f&&width<=16.f&&depth>=1.f&&depth<=8.f&&distance>=1.f&&distance<=128.f)||
     !(a.x>=width+5&&a.x<=WORLD-width-5&&b.x>=width+5&&b.x<=WORLD-width-5&&a.z>=width+5&&a.z<=WORLD-width-5&&b.z>=width+5&&b.z<=WORLD-width-5&&a.y>=depth+4&&a.y<=250&&b.y>=depth+4&&b.y<=250&&ab(b.y-a.y)<=distance*.25f)){out.p[8]=1;return;}
  if(!(a.x>=width+shoulder+5&&a.x<=WORLD-width-shoulder-5&&b.x>=width+shoulder+5&&b.x<=WORLD-width-shoulder-5&&a.z>=width+shoulder+5&&a.z<=WORLD-width-shoulder-5&&b.z>=width+shoulder+5&&b.z<=WORLD-width-shoulder-5)){out.p[8]=1;return;}
  V3 lo,hi;int changes;bool ok=w.edit(a,b,width,2,true,u8(material),lo,hi,changes,depth,clearance,shoulder);
  if(!ok)out.p[8]=2;out.u(w.revision);out.u(changes);out.u(w.pages.n);out.u(w.blocks.n);out.vec(lo);out.vec(hi);
 }
 else if(cmd==3){
  int x=int(r.u()),y=int(r.u()),z=int(r.u()),material=int(r.u());
  if(!r.good||x<0||x>=WORLD||z<0||z>=WORLD||y<2||y>=255||material<0||material>3){out.p[8]=1;return;}
  u32 key=block_key(x,y,z);int old=w.blocks.get(key);
  if(material==0){
   if(old>=0){w.erase_block(key);w.revision++;w.edits++;}
   else{V3 c={x+.5f,y+.5f,z+.5f},lo,hi;int changes;if(!w.edit(c,c,.5f,1,false,1,lo,hi,changes)){out.p[8]=2;return;}}
  }else if(old!=material){if(!w.set_block(key,material)){out.p[8]=2;return;}w.revision++;w.edits++;}
  out.u(w.revision);out.u(w.blocks.n);
 }
 else if(cmd==4){w.serialize(out);}
 else if(cmd==5){if(!w.deserialize(data+4,n-4))out.p[8]=1;out.u(w.revision);out.u(w.pages.n);out.u(w.blocks.n);}
 else if(cmd==6){int seed=int(r.u());u32 generator=n==12?r.u():1;if(!r.good||(n!=8&&n!=12)||generator<1||generator>4){out.p[8]=1;return;}BuildControl *control=w.build_control;w.release();w=World{};w.build_control=control;w.init(seed,generator);}
 else if(cmd==7){V3 p=r.vec();if(!r.good||!(ab(p.x)<=10000&&ab(p.y)<=10000&&ab(p.z)<=10000)){out.p[8]=1;return;}out.f(w.height(p.x,p.z));out.f(w.sample(fl(p.x),fl(p.y),fl(p.z)));}
 else if(cmd==8){ // Deterministic construction proof; not a replay list.
  int bx=1472,bz=1440,by=int(w.height(float(bx),float(bz)))+1;
  for(int y=0;y<12;y++)for(int z=0;z<24;z++)for(int x=0;x<24;x++)if(y==0||y==11||x==0||x==23||z==0||z==23){if(z==0&&x>=10&&x<=13&&y<5)continue;w.set_block(block_key(bx+x,by+y,bz+z),y==11?3:1);}
  w.revision++;out.u(w.revision);out.vec({float(bx),float(by),float(bz)});
 }else if(cmd==10){
  Map columns;for(int z=0;z<NP;z++)for(int x=0;x<NP;x++)if(w.edit_columns[x+NP*z])columns.put(u32(x+NP*z)+1,1);
  for(int i=0;i<w.blocks.cap;i++)if(w.blocks.p[i].key&&w.blocks.p[i].key!=0xffffffffu){int x,y,z;decode_block(w.blocks.p[i].key,x,y,z);columns.put(u32((x>>4)+NP*(z>>4))+1,1);}
  out.u(columns.n);for(int i=0;i<columns.cap;i++)if(columns.p[i].key&&columns.p[i].key!=0xffffffffu)out.u(columns.p[i].key);columns.release();
 }else if(cmd==11){
  // Refresh illumination on EXISTING geometry, not a terrain rebuild. The main
  // thread supplies immutable positions/normals. No colliders or indices change.
  u32 epoch=r.u(),count=r.u();
  if(!r.good||count>2000000u||(i64(count)*24+12!=n && i64(count)*28+12!=n)){out.p[8]=1;return;}
  if(cancelled(w,epoch)){out.p[8]=4;return;}
  Mesh m;m.v.resize(int(count));
  for(u32 i=0;i<count;i++)m.v[i].p=r.vec();
  for(u32 i=0;i<count;i++)m.v[i].n=r.vec();
  if(i64(count)*28+12==n)for(u32 i=0;i<count;i++)m.v[i].material=r.f();
  shade_visibility(w,m,epoch);
  if(cancelled(w,epoch))out.p[8]=4;
  else {out.u(count);for(u32 i=0;i<count;i++){out.f(m.v[i].sky);out.f(m.v[i].sun);}}
  m.release();
 }else if(cmd==12){
  // Safe from the main thread during native meshing: atomic only, no World access.
  out.u(terrain_cancel_builds(&w));return;
 }else if(cmd==13){out.u(terrain_build_epoch(&w));return;}
 else if(cmd==14){int style=int(r.u());if(!r.good||style<0||style>1){out.p[8]=1;return;}if(w.surface_style!=style)release_geometry_cache(w);w.surface_style=style;out.u(style);}
 else if(cmd==15){out.u(u32(w.light_rays));out.u(u32(w.light_steps));out.u(u32(w.light_unresolved));out.u(u32(w.light_probe_hits));out.u(w.light_samples.n);out.u(w.light_probes.n);}
 else if(cmd==16){
  // No Godot-layout constants here: validated offsets come from RenderingServer.
  u32 count=r.u(),stride=r.u(),uv=r.u(),uv2=r.u(),color=r.u();
  bool overlaps=(uv<uv2+8&&uv2<uv+8)||(uv<color+4&&color<uv+8)||(uv2<color+4&&color<uv2+8);
  if(!r.good||count>2000000u||stride<20||stride>256||uv>stride-8||uv2>stride-8||color>stride-4||overlaps||i64(count)*32+24!=n){out.p[8]=1;return;}
  out.u(count);out.u(stride);int begin=out.n;out.resize(begin+int(count*stride));
  const u8*vis=data+24;const u8*tex=vis+count*8;const u8*rgba=tex+count*8;
  for(u32 i=0;i<count;i++){
   u8*p=out.p+begin+i*stride;copy_bytes(p+uv,vis+i*8,8);copy_bytes(p+uv2,tex+i*8,8);
   Reader channels{rgba+i*16,16};for(int k=0;k<4;k++)p[color+k]=u8(clampf(channels.f(),0,1)*255.f+.5f);
  }
 }
 else if(cmd==17){
  // Bounded natural-root support batch. Evaluate the same interpolated density
  // lattice as the terrain surface, never integer-rounded point probes.
  u32 count=r.u();
  if(!r.good||count==0||count>64||n!=8+int(count)*12){out.p[8]=1;return;}
  V3 points[64];
  for(u32 i=0;i<count;i++){
   points[i]=r.vec();V3 p=points[i];
   if(!r.good||!(p.x>=2&&p.x<1998&&p.z>=2&&p.z<1998&&ab(p.y)<=10000)){out.p[8]=1;return;}
  }
  auto density=[&](V3 p,bool *paved=nullptr){
   int x=fl(p.x),y=fl(p.y),z=fl(p.z);float dx=p.x-x,dy=p.y-y,dz=p.z-z,value=0;
   for(int k=0;k<8;k++){
    float weight=(k&1?dx:1-dx)*(k&2?dy:1-dy)*(k&4?dz:1-dz);
    if(weight<=0)continue;
    u8 material=0;float sample=w.sample(x+(k&1),y+((k>>1)&1),z+((k>>2)&1),paved?&material:nullptr);
    value+=sample*weight;
    if(paved&&sample<0&&material==4)*paved=true;
   }
   return value;
  };
  out.u(count);V3 normals[64];
  for(u32 i=0;i<count;i++){
   V3 p=points[i];int x=fl(p.x),z=fl(p.z);float dx=p.x-x,dz=p.z-z;
   float h00=w.height(float(x),float(z)),h10=w.height(float(x+1),float(z));
   float h01=w.height(float(x),float(z+1)),h11=w.height(float(x+1),float(z+1));
   p.y=(h00*(1-dx)+h10*dx)*(1-dz)+(h01*(1-dx)+h11*dx)*dz;
   V3 normal{};bool paved=false;
   if(density(p+V3{0,-.35f,0},&paved)<0&&!paved&&density(p+V3{0,.35f,0})>0){
    // Natural vegetation cannot root in asphalt. Inspect only contributing
    // solid support corners, not the whole owner cell or unrelated air paint.
    normal=::normal(V3{(h00-h10)*(1-dz)+(h01-h11)*dz,1,(h00-h01)*(1-dx)+(h10-h11)*dx});
   }
   out.vec(p);normals[i]=normal;
  }
  for(u32 i=0;i<count;i++)out.vec(normals[i]);
 }
 else if(cmd==18){
  u32 enabled=r.u();if(!r.good||n!=8||enabled>1){out.p[8]=1;return;}
  w.profile_mesh=enabled!=0;zero_bytes(w.mesh_stage_ms,sizeof(w.mesh_stage_ms));
 }else if(cmd==19){
  if(n!=4){out.p[8]=1;return;}
  for(float value:w.mesh_stage_ms)out.f(value);
 }
 else if(cmd==21){if(n!=4){out.p[8]=1;return;}geometry_cache_stats(w,out);}
 else if(cmd==22){u32 budget=r.u();if(!r.good||n!=8||!configure_geometry_cache(w,budget)){out.p[8]=1;return;}}
 else if(cmd==23||cmd==24){
  // Opt-in density interaction query. The typed bridge serializes world access.
  // Request: from, to, max_cells, expected build epoch. No implicit retry.
  V3 from=r.vec(),to=r.vec();u32 budget=r.u(),epoch=r.u();
  if(!r.good||n!=36||budget==0||budget>8192){out.p[8]=1;return;}
  struct QueryEpoch{const World*world;u32 expected;};QueryEpoch state{&w,epoch};
  terraforest::experimental::RayControl control;control.max_cells=budget;control.context=&state;
  control.cancel=[](void*p){auto&s=*static_cast<QueryEpoch*>(p);return terrain_build_epoch(s.world)!=s.expected;};
  if(control.cancel(control.context)){out.p[8]=4;return;}
  auto hit=terraforest::experimental::trace_world_density(w,from,to,control);
  using terraforest::experimental::RayStatus;
  if(hit.status==RayStatus::cancelled||control.cancel(control.context)){out.p[8]=4;return;}
  if(hit.status==RayStatus::invalid_input){out.p[8]=1;return;}
  // Reply payload: revision, result (0 hit, 1 miss, 2 work limit), cells,
  // fraction, position. The latter two are meaningful only for a hit.
  out.u(w.revision);out.u(hit.status==RayStatus::hit?0:(hit.status==RayStatus::miss?1:2));
  out.u(u32(hit.cells));out.f(float(hit.fraction));out.vec(hit.position);
  if(cmd==24)out.vec(hit.normal);
 }
 else if(cmd==25){
  if(n!=4){out.p[8]=1;return;}
  out.u(w.generator_id);out.u(u32(w.seed));out.u(w.caves.n);
  for(int i=0;i<w.caves.n;i++){out.vec(w.caves[i].a);out.vec(w.caves[i].b);out.f(w.caves[i].r);}
 }
 else if(cmd==26){
  V3 point=r.vec();if(!r.good||n!=16||!(point.x>=0&&point.x<=WORLD&&point.z>=0&&point.z<=WORLD&&point.y>=0&&point.y<WORLD_Y)){out.p[8]=1;return;}
  u8 material=0;float density=w.sample(fl(point.x),fl(point.y),fl(point.z),&material);
  out.u(material);out.f(density);out.f(w.generator_id>=3?geological_weight(point,w.height(point.x,point.z),u32(w.seed)):0);
 }
 else if(cmd==29||cmd==30){
  // Bounded read-only site probes. The worker owns the density field; never
  // sample it from the scene thread. Revision mismatch publishes no values.
  u32 revision=r.u(),count=r.u(),depth=cmd==30?r.u():0;
  if(!r.good||count<1||count>512||depth>8||n!=(cmd==30?16:12)+int(count)*12){out.p[8]=1;return;}
  V3 points[512];
  for(u32 i=0;i<count;i++){
   points[i]=r.vec();const V3 &p=points[i];
   if(!(p.x>=0&&p.x<WORLD&&p.z>=0&&p.z<WORLD&&p.y>=(depth?3.f:0.f)&&p.y<WORLD_Y)){out.p[8]=1;return;}
  }
  if(revision!=w.revision){out.p[8]=4;return;}
  out.u(w.revision);out.u(count);
  for(u32 i=0;i<count;i++){
   const V3 &p=points[i];float value=w.sample(fl(p.x),fl(p.y),fl(p.z));
   for(u32 down=1;down<=depth;down++)value=mx(value,w.sample(fl(p.x),int(mx(3.f,float(fl(p.y))-down)),fl(p.z)));
   out.f(value);
  }
 }
 else if(cmd==27){
  if(n!=4){out.p[8]=1;return;}
  out.u(w.basin_count);
  for(int i=0;i<w.basin_count;i++){
   const auto &b=w.basins[i];
   out.vec({b.x-28.f,float(fl(b.level))-12.f,b.z-28.f});
   out.u(56);out.u(16);out.u(56);out.f(1.f);out.f(b.level);
   out.vec({b.x,b.level-4.f,b.z});
  }
 }
 else out.p[8]=1;
 if(tr_oom)out.p[8]=3;
}
