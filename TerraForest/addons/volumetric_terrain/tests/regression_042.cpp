// SPDX-License-Identifier: 0BSD
// Independent regression tests for v0.4.2. Standard C++ only; no Godot runtime.
#include "../native/core.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cmath>
#include <map>
#include <tuple>
#include <chrono>
static int count=0, failures=0;
static void check(bool ok,const char*name){count++;std::printf("%s %s\n",ok?"PASS":"FAIL",name);if(!ok)failures++;}
using Key=std::tuple<int,int,int>;
static float total(const Vertex&v){return v.blend.x+v.blend.y+v.blend.z;}
static Key key(const Vertex&v){return {v.cx,v.cy,v.cz};}
static u32 block(int x,int y,int z){return 1+u32(x|(z<<11)|(y<<22));}
static bool near(V3 a,V3 b,float eps=1e-5f){return length(a-b)<=eps;}
static bool metadata(const Mesh&m){for(int i=0;i<m.v.n;i++){auto&v=m.v[i];if(!std::isfinite(v.sky+v.sun+v.substrate+total(v)))return false;if(v.sky<0||v.sky>1||v.sun<0||v.sun>1||v.substrate<0||v.substrate>1||v.blend.x<0||v.blend.y<0||v.blend.z<0||total(v)>1.00001f)return false;}return true;}
static void sphere(World&w,V3 c,float radius,bool add){V3 lo,hi;int changed;check(w.edit(c,c,radius,0,add,1,lo,hi,changed),add?"test sphere addition accepted":"test sphere excavation accepted");}
static void probe(World&w,Mesh&m,V3 p,V3 n={0,1,0}){m.v.n=0;Vertex v{};v.p=p;v.n=n;v.cx=fl(p.x);v.cy=fl(p.y);v.cz=fl(p.z);m.v.push(v);shade_mesh(w,m);}
int main(){tr_alloc=malloc;tr_realloc=realloc;tr_free=free;World w;w.init();
 // Reproduce the reported small sphere and quantify unchanged-surface paint.
 Mesh original,edited;build_patch(w,192,1120,32,1,original);
 std::map<Key,V3> old;for(int i=0;i<original.v.n;i++)old[key(original.v[i])]=original.v[i].p;
 V3 c={214.6f,w.height(214.6f,1132.1f)+1.2f,1132.1f};sphere(w,c,3.8f,true);build_patch(w,192,1120,32,1,edited);
 int unpainted=0,wrong=0,actual_paint=0,unchanged_outside=0,moved_outside=0;
 for(int i=0;i<edited.v.n;i++){const Vertex&v=edited.v[i];auto it=old.find(key(v));if(total(v)>.1f)actual_paint++;if(it!=old.end()&&near(v.p,it->second,1e-6f)){unpainted++;if(total(v)>1e-5f)wrong++;}if(length(v.p-c)>3.8f+1.75f){if(it==old.end()||!near(v.p,it->second,.001f))moved_outside++;else unchanged_outside++;}}
 printf("MATERIAL unchanged=%d wrongly painted=%d strongly painted=%d unchanged outside brush+cell=%d moved outside=%d\n",unpainted,wrong,actual_paint,unchanged_outside,moved_outside);
 check(unpainted>500&&wrong==0,"sphere does not paint ANY geometrically unchanged surface vertex");
 check(actual_paint>30,"new sphere surface retains selected material instead of globally disabling paint");
 check(unchanged_outside>500&&moved_outside==0,"terrain outside sphere plus reconstruction cell remains geometrically unchanged");
 check(metadata(edited),"continuous material weights and cached light channels stay finite and normalized");
 Bytes packet;encode_mesh(edited,192,1120,32,1,packet);Reader pr{packet.p,packet.n};check(pr.u()==MESH_MAGIC&&pr.u()==5,"new planar packet is v4 (older baked lighting rejected)");
 original.release();edited.release();packet.release();w.release();
 // Legacy snapshots can contain material bytes on density-identical samples.
 World legacy;legacy.init();for(int z=70;z<=72;z++)for(int x=12;x<=14;x++)for(int y=1;y<=5;y++){Page*p=legacy.ensure(x,y,z);if(p)std::memset(p->mat,1,PAGE_SAMPLES);}
 Mesh lm;build_patch(legacy,192,1120,32,1,lm);float max_weight=0;for(int i=0;i<lm.v.n;i++)max_weight=mx(max_weight,total(lm.v[i]));check(max_weight==0,"legacy page material labels alone cannot stain unchanged terrain");
 Bytes save;legacy.serialize(save);World restored;restored.init();check(restored.deserialize(save.p,save.n),"v1 world snapshot remains readable after mesh codec change");Mesh loaded;build_patch(restored,192,1120,32,1,loaded);bool same=lm.v.n==loaded.v.n&&lm.i.n==loaded.i.n;for(int i=0;same&&i<lm.v.n;i++)same=near(lm.v[i].p,loaded.v[i].p)&&near(lm.v[i].blend,loaded.v[i].blend);check(same,"save/reload reproduces corrected appearance without erasing player edits");
 lm.release();loaded.release();save.release();legacy.release();restored.release();
 // Coarse exterior vertices must not become self-occluded by their own simplification.
 World outside;outside.init();for(int size: {32,64,128,256}){Mesh m;build_patch(outside,256,1280,size,size/32,m);bool clear=true;for(int i=0;i<m.v.n;i++)if(m.v[i].p.y>5&&m.v[i].sky<.5f)clear=false;check(clear,"open outdoor LOD has no false sealed-cave sky suppression");m.release();}
 // Shared collars must carry the same material AND light, not just geometry.
 V3 at={1024,outside.height(1024,1300)-2,1300};sphere(outside,at,4,false);Mesh fine,coarse;build_patch(outside,992,1280,32,1,fine);build_patch(outside,1024,1280,256,8,coarse);std::map<Key,Vertex> vertices;for(int i=0;i<fine.v.n;i++)vertices[key(fine.v[i])]=fine.v[i];int shared=0;bool matches=true;for(int i=0;i<coarse.v.n;i++){const auto&v=coarse.v[i];auto found=vertices.find(key(v));if(found==vertices.end())continue;shared++;const auto&a=found->second;if(!near(a.p,v.p)||!near(a.blend,v.blend)||a.sky!=v.sky||a.sun!=v.sun||a.substrate!=v.substrate)matches=false;}
 check(shared>20&&matches,"edited fine/coarse collar geometry, material and light match");fine.release();coarse.release();outside.release();
 // Closed cave: no sun and no uniform ambient, independent of camera.
 World cave;cave.init();V3 center={330,35,1320};center.y=cave.height(center.x,center.z)-14;sphere(cave,center,6,false);
 Mesh pv;V3 floor={center.x,center.y-6,center.z};probe(cave,pv,floor);check(pv.v[0].sky==0&&pv.v[0].sun==0,"sealed edited chamber floor has zero sky and sun transmission");
 check(terrain_occluded(cave,floor+V3{0,.2f,0},{0,1,0}),"voxel/cubic reference tracer detects the intact cave roof");
 probe(cave,pv,floor);float sky=pv.v[0].sky,sun=pv.v[0].sun;probe(cave,pv,floor);check(pv.v[0].sky==sky&&pv.v[0].sun==sun,"lighting bake has no camera-dependent input or history");
 // Vertical excavation connects the chamber to sky, leaving the floor intact.
 V3 a={center.x,center.y,center.z},b={center.x,cave.height(center.x,center.z)+3,center.z},lo,hi;int changes=0;check(cave.edit(a,b,2.5f,0,false,1,lo,hi,changes),"roof-opening shaft accepted");probe(cave,pv,floor);check(pv.v[0].sky==1,"opening a roof updates floor sky transmission (no stale bake cache)");
 check(!terrain_occluded(cave,floor+V3{0,.2f,0},{0,1,0}),"reference tracer passes through open shaft to sky");
 // Adding a 1 m exact roof must also block ambient and direct sun from below.
 int fy=fl(floor.y+8);for(int z=fl(center.z)-3;z<=fl(center.z)+3;z++)for(int x=fl(center.x)-3;x<=fl(center.x)+3;x++)cave.set_block(block(x,fy,z),1);
 probe(cave,pv,floor);check(pv.v[0].sky==0,"exact-cube roof blocks cached sky above smooth excavated floor");check(terrain_occluded(cave,floor+V3{0,.2f,0},{0,1,0}),"exact-cube roof blocks reference lighting ray");
 for(int z=fl(center.z)-3;z<=fl(center.z)+3;z++)for(int x=fl(center.x)-3;x<=fl(center.x)+3;x++)cave.erase_block(block(x,fy,z));probe(cave,pv,floor);check(pv.v[0].sky==1,"removing exact-cube roof restores sky transmission");pv.release();cave.release();
 // Natural chamber, no edits: an actual mesh contains properly dark underground surfaces.
 World natural;natural.init();Mesh chamber;build_patch(natural,960,960,32,1,chamber);int interior=0,bad=0;for(int i=0;i<chamber.v.n;i++){const auto&v=chamber.v[i];if(v.p.y>10&&v.p.y<90&&v.p.x>970&&v.p.x<992&&v.p.z>970&&v.p.z<992){interior++;if(v.sky!=0||v.sun!=0)bad++;}}
 printf("LIGHT natural interior=%d unexpected lit vertices=%d\n",interior,bad);check(interior>100&&bad==0,"natural chamber mesh is dark beneath its intact roof");check(metadata(chamber),"natural cave packet metadata is finite / normalized");chamber.release();natural.release();check(!tr_oom,"all material / roof / visibility temporary caches release cleanly");printf("REGRESSION_RESULT %d checks / %d failures\n",count,failures);return failures?1:0;}
