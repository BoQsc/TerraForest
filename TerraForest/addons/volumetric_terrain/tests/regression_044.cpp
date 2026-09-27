// SPDX-License-Identifier: 0BSD
// Real native tests: diffuse openings, detail-locked LOD and continuous local edits.
// No Godot, GPU, game-frame or electrical power performance claim.
#include "../native/core.h"
#include <cstdlib>
#include <cstdio>
#include <cmath>
#include <cstring>
#include <map>
#include <tuple>
#include <set>
#include <chrono>
#include <algorithm>
#include <vector>
static int checks=0,failures=0;
static void check(bool ok,const char* label){checks++;failures+=!ok;printf("%s %s\n",ok?"PASS":"FAIL",label);}
static double now(){return std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now().time_since_epoch()).count();}
static bool brush(World&w,V3 a,V3 b,float r,bool add){V3 lo,hi;int changes=0;return w.edit(a,b,r,0,add,1,lo,hi,changes);}
static Vertex probe(World&w,V3 p,V3 n){Mesh m;Vertex v{};v.p=p;v.n=n;v.cx=fl(p.x);v.cy=fl(p.y);v.cz=fl(p.z);m.v.push(v);shade_mesh(w,m);v=m.v[0];m.release();return v;}
using Key=std::tuple<int,int,int>;
static Key key(const Vertex&v){return {v.cx,v.cy,v.cz};}
static bool same(V3 a,V3 b){return std::memcmp(&a,&b,12)==0;}
int main(){tr_alloc=malloc;tr_realloc=realloc;tr_free=free;
 {
 World w;w.init();float h=w.height(330,1320);V3 c{330,h+8,1320};
 check(brush(w,c,c,10,true),"build above-ground sphere");
 // Hollow sphere, then a horizontal opening: vertical roof remains intact.
 check(brush(w,c,c,7.5f,false),"hollow sphere remains a sealed chamber");
 V3 floor=c+V3{0,-7.5f,0};Vertex sealed=probe(w,floor,{0,1,0});
 printf("LIGHT closed sky %.4f sun %.4f\n",sealed.sky,sealed.sun);
 check(sealed.sky==0&&sealed.sun==0,"closed hollow sphere is not given uniform daylight");
 V3 mouth=c+V3{16,2,0};check(brush(w,c+V3{2,0,0},mouth,6,false),"create side opening without removing complete overhead roof");
 Vertex opened=probe(w,floor,{0,1,0});
 bool roof=terrain_occluded(w,floor+V3{0,.2f,0},{0,1,0});
 printf("LIGHT side-open sky %.4f sun %.4f vertical_roof %d\n",opened.sky,opened.sun,roof);
 check(roof,"side-open test still has a real roof directly overhead");
 check(opened.sky>0&&opened.sky<1,"open-sided excavation receives diffuse sky while under a roof");
 check(opened.sky>=0&&opened.sky<=1&&opened.sun>=0&&opened.sun<=1,"light channels stay normalized");
 Vertex again=probe(w,floor,{0,1,0});check(again.sky==opened.sky&&again.sun==opened.sun,"sky lighting is deterministic, independent of camera history");
 w.release();
 }
 {
 World w;w.init();V3 c{984,w.height(984,1310)-3,1310};check(brush(w,c,c,7,false),"LOD comparison excavation accepted");
 Mesh fine,coarse;check(build_patch(w,960,1280,64,1,fine),"reference finest surface builds");
 check(build_patch(w,960,1280,64,8,coarse),"coarse-requested patch builds with protected edits");
 std::map<Key,Vertex> vertices;for(int i=0;i<coarse.v.n;i++)vertices[key(coarse.v[i])]=coarse.v[i];
 int protected_count=0,missing=0,changed=0;
 for(int i=0;i<fine.v.n;i++){const auto&v=fine.v[i];if(length(v.p-c)>12)continue;protected_count++;auto it=vertices.find(key(v));if(it==vertices.end()){missing++;continue;}const auto&o=it->second;if(!same(v.p,o.p)||!same(v.n,o.n)||v.sky!=o.sky||v.sun!=o.sun)changed++;}
 printf("LOD protected_vertices=%d missing=%d changed=%d triangles fine=%d coarse=%d\n",protected_count,missing,changed,fine.i.n/3,coarse.i.n/3);
 check(protected_count>100&&missing==0&&changed==0,"edited surface positions normals and light preserved at coarse LOD");
 using Triangle=std::tuple<Key,Key,Key>;std::set<Triangle> triangles;
 for(int i=0;i<coarse.i.n;i+=3){Key k[3]={key(coarse.v[coarse.i[i]]),key(coarse.v[coarse.i[i+1]]),key(coarse.v[coarse.i[i+2]])};std::sort(k,k+3);triangles.insert({k[0],k[1],k[2]});}
 int kept=0,lost=0;for(int i=0;i<fine.i.n;i+=3){auto&a=fine.v[fine.i[i]],&b=fine.v[fine.i[i+1]],&d=fine.v[fine.i[i+2]];if(length(a.p-c)>10||length(b.p-c)>10||length(d.p-c)>10)continue;kept++;Key k[3]={key(a),key(b),key(d)};std::sort(k,k+3);if(!triangles.count({k[0],k[1],k[2]}))lost++;}
 check(kept>100&&lost==0,"all excavation triangles survive coarse request without hole shrinking");
 Bytes packet;encode_mesh(coarse,960,1280,64,8,packet);Reader r{packet.p,packet.n};r.u();check(r.u()==5,"new mesh caches explicitly use version 5");packet.release();fine.release();coarse.release();
 // Native edit history bounded by final pages; rendering work doesn't replay strokes.
 std::vector<double> edits,builds;int before=w.pages.n;int changes=0;V3 lo,hi;
 for(int k=0;k<48;k++){V3 a=c+V3{float(k%8)*.25f,0,float(k%3)*.12f};V3 b=a+V3{.35f,0,0};double t=now();bool ok=w.edit(a,b,2,0,k%2==1,1,lo,hi,changes);edits.push_back(now()-t);if(!ok){check(false,"continuous swept update accepted");break;}Mesh m;t=now();if(!build_patch(w,976,1296,16,1,m))check(false,"continuous fine rebuild accepted");builds.push_back(now()-t);m.release();}
 std::sort(edits.begin(),edits.end());std::sort(builds.begin(),builds.end());
 printf("CPU 48 changing swept edits: edit p95 %.3f ms; single 16m build p95 %.3f ms; pages %d -> %d\n",edits[45],builds[45],before,w.pages.n);
 check(edits.size()==48&&builds.size()==48,"48 actually changing swept edits and local rebuilds finish");
 check(w.pages.n<=before+8,"same-region stroke does not append history-dependent field storage");
 Bytes saved;w.serialize(saved);World back;back.init();check(back.deserialize(saved.p,saved.n),"existing v1 world format roundtrips after new light/LOD caches");check(back.pages.n==w.pages.n&&back.edits==w.edits,"save/load retains edited page count and edit revision");saved.release();back.release();w.release();
 }
 check(!tr_oom,"no native allocation failure");printf("RELEASE_044_RESULT %d checks / %d failures\n",checks,failures);return failures?1:0;
}
