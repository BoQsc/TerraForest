// SPDX-License-Identifier: 0BSD
#include "../native/core.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cmath>
#include <chrono>
#include <map>
#include <set>
#include <tuple>
#include <vector>
#include <algorithm>
static int checks=0,failed=0;
static void check(bool v,const char*message){checks++;printf("%s %s\n",v?"PASS":"FAIL",message);if(!v)failed++;}
static double now(){return std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now().time_since_epoch()).count();}
static unsigned hash(const World&w){unsigned h=2166136261u;for(int p=0;p<w.pages.n;p++)for(int j=0;j<4096;j++){h^=(unsigned short)w.pages[p].d[j];h*=16777619u;}return h;}
using Key=std::tuple<int,int,int>;
static bool seam(const Mesh&a,const Mesh&b){std::map<Key,V3> points;for(int i=0;i<a.v.n;i++)points[{a.v[i].cx,a.v[i].cy,a.v[i].cz}]=a.v[i].p;int count=0;for(int i=0;i<b.v.n;i++){const Vertex&v=b.v[i];auto it=points.find({v.cx,v.cy,v.cz});if(it!=points.end()){if(std::memcmp(&it->second,&v.p,sizeof(V3)))return false;count++;}}return count>20;}
static bool valid(const Mesh&m){for(int i=0;i<m.i.n;i++)if(m.i[i]>=unsigned(m.v.n))return false;for(int i=0;i<m.v.n;i++){V3 p=m.v[i].p,n=m.v[i].n;if(!std::isfinite(p.x+p.y+p.z+n.x+n.y+n.z))return false;}return m.i.n%3==0;}
static float winding(const Mesh&m){int good=0,total=0;for(int i=0;i<m.i.n;i+=3){const Vertex&a=m.v[m.i[i]],&b=m.v[m.i[i+1]],&c=m.v[m.i[i+2]];V3 cr=cross(b.p-a.p,c.p-a.p);if(dot(cr,cr)<1e-12)continue;total++;if(dot(cr,a.n+b.n+c.n)<=0)good++;}return total?float(good)/total:1;}
static void place(World&w,int x,int y,int z,int material=1){Bytes req,out;req.u(3);req.u(x);req.u(y);req.u(z);req.u(material);process_request(w,req.p,req.n,out);check(out.n>=12&&out.p[8]==0,"exact block command accepted");req.release();out.release();}
int main(){tr_alloc=malloc;tr_realloc=realloc;tr_free=free;World w;w.init();
 check(w.sample(1000,0,1000)>0,"bedrock exterior is positive");
 check(w.sample(985,61,985)>0,"procedural underground chamber is air");
 Mesh near,fine,coarse;double a=now();build_patch(w,960,1280,32,1,near);double near_ms=now()-a;
 a=now();build_patch(w,992,1280,32,1,fine);double neighbor_ms=now()-a;
 check(valid(near)&&valid(fine),"native mesh packets have finite vertices / valid indices");
 check(seam(near,fine),"two adjacent fine patches have bit-identical border vertices");
 printf("INFO clockwise-normal alignment %.5f\n",winding(near));check(winding(near)>.999f,"fine surface winding matches outward normals");
 a=now();build_patch(w,1024,1280,256,8,coarse);double root_ms=now()-a;Mesh adjacent;build_patch(w,992,1280,32,1,adjacent);
 check(seam(adjacent,coarse),"32 m fine / 256 m simplified LOD border matches exactly");
 check(valid(coarse)&&winding(coarse)>.995f,"simplified LOD indices / normals / orientation");
 printf("CPU initial fine %.3f ms (%d triangles), neighbor %.3f ms; coarse %.3f ms (%d triangles)\n",near_ms,near.i.n/3,neighbor_ms,root_ms,coarse.i.n/3);
 V3 p={1024,w.height(1024,1300)-1,1300},lo,hi;int changes;check(w.edit(p,p,4,0,false,1,lo,hi,changes),"sphere excavation across native page / mesh border");unsigned state=hash(w);int pages=w.pages.n;std::vector<double> times;
 for(int i=0;i<1000;i++){a=now();bool ok=w.edit(p,p,4,0,false,1,lo,hi,changes);times.push_back(now()-a);if(!ok||changes)failed++;}
 check(state==hash(w)&&pages==w.pages.n,"1000 identical edits are idempotent; page count and field unchanged");
 near.release();fine.release();coarse.release();adjacent.release();build_patch(w,992,1280,32,1,near);build_patch(w,1024,1280,256,8,coarse);
 check(seam(near,coarse),"edited mixed-LOD border uses identical field and vertices");
 check(valid(near)&&valid(coarse),"edited sphere meshes have valid indices / finite vertices");
 Bytes save;w.serialize(save);World restored;restored.init();check(restored.deserialize(save.p,save.n),"world snapshot reload accepted");check(hash(restored)==hash(w)&&restored.pages.n==w.pages.n,"snapshot preserves every stored SDF sample");
 save.p[save.n/2]^=1;unsigned before=hash(restored);check(!restored.deserialize(save.p,save.n)&&hash(restored)==before,"corrupted snapshot rejected without replacing world");save.p[save.n/2]^=1;
 Bytes encoded;encode_mesh(near,992,1280,32,1,encoded);Reader r{encoded.p,encoded.n};check(r.u()==MESH_MAGIC&&r.u()==5,"versioned native mesh codec header");
 r.at=24;unsigned nv=r.u(),ni=r.u(),nf=r.u();check(nf==ni&&encoded.n==36+int(nv)*56+int(ni)*4+int(nf)*12,"collision packet includes same full-resolution triangles");
 bool same=true;const u8*positions=encoded.p+36;const u8*indices=positions+nv*56;const u8*faces=indices+ni*4;
 for(unsigned i=0;i<ni;i++){unsigned vi;std::memcpy(&vi,indices+i*4,4);if(std::memcmp(positions+vi*12,faces+i*12,12))same=false;}check(same,"render and collision triangle positions match byte-for-byte");
 World blocks;blocks.init();for(int z=160;z<164;z++)for(int y=180;y<183;y++)for(int x=160;x<165;x++)blocks.set_block(1+unsigned(x|(z<<11)|(y<<22)),1);
 Mesh bm;build_patch(blocks,160,160,32,1,bm);int bt=0;for(int i=0;i<bm.i.n;i+=3)if(bm.v[bm.i[i]].material>=5)bt++;
 check(bt==12,"60 exact adjacent cubes greedy-mesh to six exterior quads");check(winding(bm)>.999f,"greedy construction face winding is correct");
 // 120 changes spread locally, not a single no-op stress case.
 std::vector<double> edit_times,mesh_times;for(int i=0;i<120;i++){V3 q={980.f+float(i%12)*.65f,w.height(984,1310)-2-float(i/12)*.45f,1310.f};a=now();w.edit(q,q,3.5f,0,false,1,lo,hi,changes);edit_times.push_back(now()-a);Mesh m;a=now();build_patch(w,960,1280,32,1,m);mesh_times.push_back(now()-a);if(!valid(m))failed++;m.release();}
 std::sort(times.begin(),times.end());std::sort(edit_times.begin(),edit_times.end());std::sort(mesh_times.begin(),mesh_times.end());
 printf("CPU repeated idempotent edits median %.3f p95 %.3f ms\n",times[500],times[950]);
 printf("CPU 120 changed edits median %.3f p95 %.3f ms; remesh median %.3f p95 %.3f ms; final pages %d\n",edit_times[60],edit_times[114],mesh_times[60],mesh_times[114],w.pages.n);
 Bytes request, response, reload;request.u(4);process_request(w,request.p,request.n,response);reload.u(5);reload.raw(response.p+12,response.n-12);Bytes loaded;process_request(restored,reload.p,reload.n,loaded);
 check(loaded.n>=12&&loaded.p[8]==0,"framed protocol save/load checksum excludes transport header");request.release();response.release();reload.release();loaded.release();
 Mesh cave;a=now();build_patch(w,960,960,32,1,cave);double cave_ms=now()-a;check(valid(cave)&&winding(cave)>.98f,"underground fine mesh validity and orientation");printf("CPU cave mesh %.3f ms (%d triangles), winding %.5f\n",cave_ms,cave.i.n/3,winding(cave));cave.release();
 Mesh coarse_cave;build_patch(w,960,960,64,2,coarse_cave);check(valid(coarse_cave),"underground simplified mesh validity");coarse_cave.release();

 for(int z=100;z<200;z++)for(int x=100;x<200;x++)for(int y=160;y<170;y++)w.set_block(1+unsigned(x|(z<<11)|(y<<22)),1);
 Mesh isolated;a=now();build_patch(w,960,1280,32,1,isolated);double isolated_ms=now()-a;
 check(w.blocks.n==100000&&valid(isolated),"100000 distant cubes remain outside local mesh candidates");printf("CPU local edited patch with 100000 remote cubes %.3f ms (%d triangles)\n",isolated_ms,isolated.i.n/3);isolated.release();
 Map churn;for(int i=0;i<100000;i++){u32 key=u32(i)+1;churn.put(key,1);churn.erase(key);}check(churn.n==0&&churn.cap==64,"100000 insert/delete cycles do not grow tombstone storage");churn.release();
 check(!tr_oom,"native allocator did not signal allocation failure");
 near.release();fine.release();coarse.release();adjacent.release();bm.release();save.release();encoded.release();restored.release();blocks.release();w.release();
 printf("RESULT %d checks; %d failures\n",checks,failed);return failed?1:0;
}
