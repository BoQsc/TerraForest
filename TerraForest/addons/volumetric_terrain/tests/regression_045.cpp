// SPDX-License-Identifier: 0BSD
// Native behavior tests, not a claim about Godot FPS or electrical power.
#include "../native/core.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cmath>
#include <chrono>
#include <map>
#include <tuple>
static int checks=0,failures=0;
static void check(bool ok,const char*s){checks++;failures+=!ok;printf("%s %s\n",ok?"PASS":"FAIL",s);}
static double now(){return std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now().time_since_epoch()).count();}
static bool ok(const Bytes&r){return r.n>=12&&r.p[8]==0;}
static bool brush(World&w,V3 c,float radius,bool add){V3 lo,hi;int changed;return w.edit(c,c,radius,0,add,1,lo,hi,changed);}
static bool seam(const Mesh&a,const Mesh&b){std::map<std::tuple<int,int,int>,V3> q;for(int i=0;i<a.v.n;i++){auto v=a.v[i];q[{v.cx,v.cy,v.cz}]=v.p;}int shared=0;for(int i=0;i<b.v.n;i++){auto v=b.v[i];auto it=q.find({v.cx,v.cy,v.cz});if(it!=q.end()){shared++;if(memcmp(&v.p,&it->second,12))return false;}}return shared>10;}
static bool valid(const Mesh&m){for(int i=0;i<m.i.n;i++)if(m.i[i]>=u32(m.v.n))return false;for(int i=0;i<m.v.n;i++)if(!std::isfinite(m.v[i].p.x+m.v[i].p.y+m.v[i].p.z))return false;return m.i.n%3==0;}
static float signed_value(const World&w,V3 p){int x=fl(p.x),y=fl(p.y),z=fl(p.z);float f=0;for(int k=0;k<8;k++)f+=w.sample(x+(k&1),y+((k>>1)&1),z+((k>>2)&1))*(k&1?p.x-x:1-p.x+x)*(k&2?p.y-y:1-p.y+y)*(k&4?p.z-z:1-p.z+z);return f;}
int main(){tr_alloc=malloc;tr_realloc=realloc;tr_free=free;
 {World w;w.init();Bytes in,out;in.u(16);in.u(3);in.u(20);in.u(4);in.u(12);in.u(0);
 for(int i=0;i<3;i++){in.f(.1f*i);in.f(.5f+.1f*i);}for(int i=0;i<3;i++){in.f(float(i+5));in.f(1);}
 for(int i=0;i<3;i++){in.f(.2f*i);in.f(.4f);in.f(.6f);in.f(1);}
 process_request(w,in.p,in.n,out);check(ok(out)&&out.n==80,"engine-layout attribute pack produces only requested interleaved bytes");
 bool values=true;for(int i=0;i<3;i++){Reader r{out.p+20+i*20+4,16};values&=r.f()==.1f*i;values&=r.f()==.5f+.1f*i;values&=r.f()==float(i+5);values&=r.f()==1;values&=out.p[20+i*20+3]==255;}
 check(values,"UV visibility UV2 identity and material-alpha bytes retained");
 out.release();u32 overlap=4;memcpy(in.p+20,&overlap,4);process_request(w,in.p,in.n,out);check(!ok(out),"overlapping GPU offsets rejected instead of corrupting mesh");
 in.release();out.release();in.u(16);in.u(500);in.u(20);in.u(4);in.u(12);in.u(0);process_request(w,in.p,in.n,out);check(!ok(out),"truncated attribute packet rejected");in.release();out.release();
 int s=terrain_visibility(w,{985,61,985},{1,.001f,0},0);check(s==2&&w.light_unresolved==1,"exhausted ray is distinguishable from blocked and visible rays");
 check(terrain_visibility(w,{300,230,1300},{0,1,0},1400)==0,"sky ray still classified visible");w.release();}
 {World w;w.init();Mesh a,b;double t=now();build_patch(w,960,960,32,1,a);double cold=now()-t;int stored=w.light_samples.n;u64 hits=w.light_probe_hits;
 t=now();build_patch(w,960,960,32,1,b);double warm=now()-t;
 bool equal=a.v.n==b.v.n;for(int i=0;i<a.v.n&&equal;i++)equal=a.v[i].sky==b.v[i].sky&&a.v[i].sun==b.v[i].sun;
 printf("LIGHT_CACHE cold %.3f ms / repeat %.3f ms / samples %d / unresolved %llu\n",cold,warm,stored,(unsigned long long)w.light_unresolved);
 check(equal,"cached patch visibility equals cold output byte-for-byte");check(w.light_probe_hits>hits&&stored>0,"neighbor/repeated patch uses revision-local probes");
 V3 c{985,61,985};check(brush(w,c,6,true),"actual change invalidates derived light cache");check(w.lighting_revision==-1,"cache marked invalid immediately after field edit");
 Mesh changed;build_patch(w,976,976,16,1,changed);check(w.lighting_revision==w.revision,"lighting cache rebuilt at current field revision");
 Bytes before,after;w.serialize(before);w.light_samples.release();w.light_roofs.release();w.light_tops.release();w.light_probes.release();w.light_probe_ids.release();w.lighting_revision=-1;w.serialize(after);
 check(before.n==after.n&&memcmp(before.p,after.p,before.n)==0,"derived cache never changes saved world bytes");
 before.release();after.release();a.release();b.release();changed.release();w.release();}
 {World w;w.init();V3 c{320,140,1312};check(brush(w,c,8,true),"isolated floating sphere fixture created");Mesh rough,smooth;build_patch(w,304,1296,32,1,rough);w.surface_style=1;build_patch(w,304,1296,32,1,smooth);
 check(valid(smooth)&&rough.i.n==smooth.i.n&&rough.v.n==smooth.v.n,"fitted style keeps cell topology and valid finite geometry");
 double e0=0,e1=0;float radial=0;int count=0;for(int i=0;i<smooth.v.n;i++){auto&a=rough.v[i];auto&b=smooth.v[i];if(a.material<=0)continue;count++;e0+=ab(signed_value(w,a.p));e1+=ab(signed_value(w,b.p));radial=mx(radial,ab(length(b.p-c)-8.f));}
 printf("FITTED mean field residual %.6f -> %.6f; vertex radial error %.4fm (%d vertices)\n",e0/mx(count,1),e1/mx(count,1),radial,count);
 check(count>500&&e1<e0*.25,"fitting reduces sampled-field surface residual");
 check(radial<.12f,"isolated radius-eight fitted vertices within 0.12m of analytic sphere");
 Mesh left,right;build_patch(w,304,1296,16,1,left);build_patch(w,320,1296,16,1,right);check(seam(left,right),"fitted mode preserves identical neighboring patch boundary positions");
 Bytes snapshot;w.serialize(snapshot);World back;back.init();back.deserialize(snapshot.p,snapshot.n);check(back.surface_style==0&&back.pages.n==w.pages.n,"optional reconstruction mode does not alter save format or field pages");
 left.release();right.release();snapshot.release();rough.release();smooth.release();back.release();w.release();}
 {World a,b;a.init();b.init();V3 deep{1480,20,1460};check(brush(b,deep,4,false),"deep local-edit fixture accepted");Mesh baseline,edited;build_patch(a,1472,1440,64,8,baseline);build_patch(b,1472,1440,64,8,edited);
 int top_a=0,top_b=0;for(int i=0;i<baseline.i.n;i+=3)if(baseline.v[baseline.i[i]].p.y>80)top_a++;for(int i=0;i<edited.i.n;i+=3)if(edited.v[edited.i[i]].p.y>80)top_b++;
 printf("LOD remote surface triangles before=%d after deep edit=%d\n",top_a,top_b);check(top_a==top_b,"deep edit no longer pins unrelated high surface in same XZ columns");baseline.release();edited.release();a.release();b.release();}
 check(!tr_oom,"no native allocation failure");printf("RELEASE_045_RESULT %d checks / %d failures\n",checks,failures);return failures?1:0;}
