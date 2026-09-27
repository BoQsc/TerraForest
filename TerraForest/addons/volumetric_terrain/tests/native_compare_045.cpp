#include "../native/core.h"
#include <chrono>
#include <cstdlib>
#include <cstdio>
static double now(){return std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now().time_since_epoch()).count();}
int main(){tr_alloc=malloc;tr_realloc=realloc;tr_free=free;World w;w.init();double t=now();Mesh m;build_patch(w,960,960,32,1,m);printf("cold_cave %.3f\n",now()-t);m.release();t=now();build_patch(w,960,960,32,1,m);printf("warm_cave %.3f\n",now()-t);m.release();V3 c{330,w.height(330,1320)+8,1320},lo,hi;int changes;w.edit(c,c,10,0,true,1,lo,hi,changes);w.edit(c,c,7.5,0,false,1,lo,hi,changes);t=now();build_patch(w,320,1312,16,1,m);printf("player_sphere %.3f\n",now()-t);m.release();t=now();build_patch(w,336,1312,16,1,m);printf("neighbor_sphere %.3f\n",now()-t);m.release();w.release();}