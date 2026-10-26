#include "../../addons/volumetric_terrain/native/core.h"
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>

static double milliseconds(){return std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now().time_since_epoch()).count();}

int main(int count,char **arguments){
    if(count!=5)return 2;
    tr_alloc=malloc;tr_realloc=realloc;tr_free=free;
    FILE *input=fopen(arguments[1],"rb");
    if(!input)return 2;
    fseek(input,0,SEEK_END);long length=ftell(input);rewind(input);
    if(length<=0||length>0x7fffffff){fclose(input);return 2;}
    Bytes bytes;bytes.resize(int(length));
    if(tr_oom||fread(bytes.p,1,length,input)!=size_t(length)){fclose(input);bytes.release();return 2;}
    fclose(input);
    V3 focus={float(atof(arguments[2])),float(atof(arguments[3])),float(atof(arguments[4]))};
    int origin_x=fl((focus.x-4)/16)*16,origin_z=fl((focus.z-4)/16)*16;
    int failures=0;
    for(int trial=0;trial<3;trial++){
        World world;world.init();
        if(!world.deserialize(bytes.p,bytes.n)){world.release();bytes.release();return 3;}
        Mesh cold,warm;
        double started=milliseconds();
        bool built=build_patch(world,origin_x,origin_z,32,1,cold);
        double cold_ms=milliseconds()-started;
        u64 rays=world.light_rays;
        started=milliseconds();
        built&=build_patch(world,origin_x,origin_z,32,1,warm);
        double warm_ms=milliseconds()-started;
        bool equal=cold.v.n==warm.v.n&&cold.i.n==warm.i.n;
        for(int index=0;index<cold.v.n&&equal;index++)equal=std::memcmp(&cold.v[index],&warm.v[index],sizeof(Vertex))==0;
        failures+=!built||!equal||tr_oom;
        printf("SAVED_LIGHT trial=%d cold_ms=%.3f warm_ms=%.3f cold_rays=%llu warm_rays=%llu vertices=%d exact=%d\n",trial,cold_ms,warm_ms,(unsigned long long)rays,(unsigned long long)(world.light_rays-rays),cold.v.n,equal);
        cold.release();warm.release();world.release();
    }
    bytes.release();
    printf("SAVED_LIGHT_RESULT failures=%d\n",failures);
    return failures?1:0;
}
