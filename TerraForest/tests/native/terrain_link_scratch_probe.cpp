// SPDX-License-Identifier: 0BSD
#include "core.h"
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <string>

int main(int argc,char**argv){
 if(argc!=2)return 2;
 tr_alloc=std::malloc;tr_realloc=std::realloc;tr_free=std::free;
 int number=0;
 const int generators[]={1,9,19,19},seeds[]={1703,42,0,1703};
 for(int fixture=0;fixture<4;fixture++){
  World w;w.init(seeds[fixture],generators[fixture]);w.profile_mesh=true;
  for(int state=0;state<3;state++){
   if(state){V3 a={1311.5f,w.height(1311.5f,1311.5f)-.4f,1311.5f},b=a;b.y-=8;
    V3 lo,hi;int changes=0;
    if(!w.edit(a,b,3,0,state==2,1,lo,hi,changes)||!changes||tr_oom)return 3;
   }
   for(int size:{16,32,64,128,256}){
    Bytes command,response;command.u(1);command.u(1280);command.u(1280);command.u(size);command.u(imx(1,size/32));
    auto began=std::chrono::steady_clock::now();process_request(w,command.p,command.n,response);
    double ms=std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-began).count();
    if(response.n<48||response.p[8]||tr_oom)return 4;
    std::string path=std::string(argv[1])+"/"+std::to_string(number)+".mesh";
    FILE*f=fopen(path.c_str(),"wb");if(!f)return 5;
    bool saved=fwrite(response.p,1,response.n,f)==size_t(response.n);saved=fclose(f)==0&&saved;if(!saved)return 6;
    printf("{\"case\":%d,\"generator\":%d,\"seed\":%d,\"state\":%d,\"size\":%d,\"bytes\":%d,\"ms\":%.5f,\"simplify_ms\":%.5f}\n",number++,generators[fixture],seeds[fixture],state,size,response.n,ms,w.mesh_stage_ms[1]);
    command.release();response.release();
   }
  }
  w.release();
 }
 return number==60?0:7;
}
