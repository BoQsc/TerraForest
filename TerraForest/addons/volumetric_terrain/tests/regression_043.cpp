// SPDX-License-Identifier: 0BSD
// Actual native regression tests. Standard C++ library only; not a GPU/Godot test.
#include "../native/core.h"
#include <cstdlib>
#include <cstdio>
#include <chrono>
#include <thread>
#include <atomic>
#include <cstring>
#include <algorithm>
#include <vector>
static std::atomic<long> live{0};
static void* allocate(size_t n){void*p=std::malloc(n);if(p)live++;return p;}
static void* reallocate(void*p,size_t n){void*q=std::realloc(p,n);if(q&&!p)live++;return q;}
static void deallocate(void*p){if(p){live--;std::free(p);}}
static int checks=0,failures=0;
static void check(bool good,const char*message){checks++;if(!good)failures++;std::printf("%s %s\n",good?"PASS":"FAIL",message);}
static auto now(){return std::chrono::steady_clock::now();}
static double ms(std::chrono::steady_clock::time_point start){return std::chrono::duration<double,std::milli>(now()-start).count();}
static bool reply_ok(const Bytes&b){return b.n>=12&&b.p[8]==0;}
static bool same(V3 a,V3 b){return std::memcmp(&a,&b,sizeof(V3))==0;}
static void put_command(Bytes&b,u32 cmd){b.clear();b.u(cmd);}
static void request(World&w,Bytes&cmd,Bytes&out){out.clear();process_request(w,cmd.p,cmd.n,out);}
int main(){
 tr_alloc=allocate;tr_realloc=reallocate;tr_free=deallocate;
 {
 World w;w.init();V3 center{984,w.height(984,1308)-1.f,1308},lo,hi;int changes=0;
 w.edit(center,center,4,0,false,1,lo,hi,changes);
 Mesh parent,child;check(build_patch(w,960,1280,32,1,parent),"32m baseline patch builds");
 check(build_patch(w,976,1296,16,1,child),"16m fine patch builds on same 1m lattice");
 int matched=0,wrong=0;
 for(int i=0;i<child.v.n;i++)for(int j=0;j<parent.v.n;j++)if(child.v[i].cx==parent.v[j].cx&&child.v[i].cy==parent.v[j].cy&&child.v[i].cz==parent.v[j].cz){matched++;if(!same(child.v[i].p,parent.v[j].p)||!same(child.v[i].n,parent.v[j].n))wrong++;break;}
 check(matched>100&&wrong==0,"overlapping 16m and 32m cell representatives/normals match exactly");
 Bytes encoded;encode_mesh(child,976,1296,16,1,encoded);Reader packet{encoded.p,encoded.n};for(int k=0;k<6;k++)packet.u();u32 nv=packet.u(),ni=packet.u(),nf=packet.u();
 check(nf==ni&&ni>0,"16m patch contains exact full render collision triangles");
 bool identical=true;int face_at=36+nv*56+ni*4;
 for(u32 i=0;i<ni;i++){V3 point;copy_bytes(&point,encoded.p+face_at+i*12,12);if(!same(point,child.v[child.i[i]].p))identical=false;}
 check(identical,"16m collision packet is byte-identical to render triangles");
 encoded.release();child.release();parent.release();
 // A lighting refresh must not build geometry or invent collider triangles.
 Mesh cave;build_patch(w,960,960,32,1,cave);
 Bytes cmd,out;put_command(cmd,11);cmd.u(terrain_build_epoch());cmd.u(cave.v.n);
 for(int i=0;i<cave.v.n;i++)cmd.vec(cave.v[i].p);for(int i=0;i<cave.v.n;i++)cmd.vec(cave.v[i].n);
 request(w,cmd,out);check(reply_ok(out)&&out.n==16+cave.v.n*8,"visibility-only protocol has bounded UV-only output");
 bool lighting_match=reply_ok(out);Reader light{out.p,out.n};for(int k=0;k<4;k++)light.u();
 for(int i=0;i<cave.v.n&&lighting_match;i++){float sky=light.f(),sun=light.f();if(sky!=cave.v[i].sky||sun!=cave.v[i].sun)lighting_match=false;}
 check(lighting_match,"visibility-only output matches old complete rebuild lighting bit-for-bit");
 int revision=w.revision,pages=w.pages.n,edits=w.edits;request(w,cmd,out);
 check(w.revision==revision&&w.pages.n==pages&&w.edits==edits,"lighting refresh does not mutate terrain state");
 cmd.n-=1;request(w,cmd,out);check(!reply_ok(out),"truncated visibility packets rejected");cave.release();
 // Stale-token jobs must skip all work without a fake success mesh.
 u32 old_epoch=terrain_build_epoch();terrain_cancel_builds();Mesh stale;
 check(!build_patch(w,768,768,256,8,stale,old_epoch)&&stale.v.n==0&&stale.i.n==0,"stale queued mesh generation is rejected immediately");
 put_command(cmd,1);cmd.u(768);cmd.u(768);cmd.u(256);cmd.u(8);cmd.u(old_epoch);request(w,cmd,out);
 check(out.n==12&&out.p[8]==4,"cancelled builds return explicit status 4, never an incomplete mesh");
 // A running native build cooperatively yields to an interactive request.
 double worst_cancel=0;bool all_cancelled=true;
 for(int trial=0;trial<8;trial++){
  Mesh m;u32 epoch=terrain_build_epoch();std::atomic<bool> started{false};bool result=true;
  std::thread worker([&]{started=true;result=build_patch(w,768,768,256,8,m,epoch);});
  while(!started.load())std::this_thread::yield();std::this_thread::sleep_for(std::chrono::milliseconds(2+trial*2));
  auto start=now();terrain_cancel_builds();worker.join();worst_cancel=std::max(worst_cancel,ms(start));
  if(result||m.v.n||m.i.n)all_cancelled=false;m.release();
 }
 check(all_cancelled,"running coarse builds cancel cleanly in eight timings");
 check(worst_cancel<250.0,"cooperative cancellation joins within 250ms test ceiling on this CPU");
 std::printf("CPU cancellation worst %.3f ms (not input-to-display latency)\n",worst_cancel);
 check(w.revision==revision&&w.pages.n==pages&&w.edits==edits,"cancellation never mutates world/save state");
 // Fine vs original work, measured on the same state and position.
 std::vector<double> small,old;
 for(int trial=0;trial<20;trial++){
  V3 c=center;c.x+=float(trial%5)*.13f;w.edit(c,c,1.f,0,(trial&1)!=0,1,lo,hi,changes);
  Mesh a,b;auto time=now();build_patch(w,976,1296,16,1,a);small.push_back(ms(time));time=now();build_patch(w,960,1280,32,1,b);old.push_back(ms(time));a.release();b.release();
 }
 std::sort(small.begin(),small.end());std::sort(old.begin(),old.end());
 std::printf("CPU 16m build median %.3f p95 %.3f ms; 32m same-area build median %.3f p95 %.3f ms\n",small[10],small[18],old[10],old[18]);
 // Read-only token command: lets a restarted backend synchronize without changing World.
 put_command(cmd,13);request(w,cmd,out);Reader token{out.p,out.n};for(int i=0;i<3;i++)token.u();check(reply_ok(out)&&token.u()==terrain_build_epoch(),"backend can read cancellation epoch after restart");
 cmd.release();out.release();w.release();
 }
 check(live.load()==0,"all tested native allocations freed, including cancellation paths");
 check(!tr_oom,"no allocation failure in regression workload");
 std::printf("RESULT %d checks; %d failures\n",checks,failures);return failures?1:0;
}
