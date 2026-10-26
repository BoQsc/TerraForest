#include <cstdio>
#include <cstdlib>
#include <cstring>
#include "../../addons/volumetric_terrain/native/core.cpp"

static int failures=0;
static void check(bool passed,const char *label){printf("%s %s\n",passed?"PASS":"FAIL",label);failures+=!passed;}

static V3 old_origin(RoofCache &roof,const Vertex &vertex){
    V3 point=vertex.p+vertex.n*.06f;
    for(int step=0;step<8;step++){
        float value=interpolated_sample(roof,point);
        if(value>.015f)break;
        float ahead=interpolated_sample(roof,point+vertex.n*.1f);
        point=point+vertex.n*clampf((.02f-value)/mx(.1f,(ahead-value)*10),.015f,.2f);
    }
    return point;
}

static bool brush(World &world,V3 point,float radius,int shape,bool add){
    V3 minimum,maximum;int changes=0;
    return world.edit(point,point,radius,shape,add,1,minimum,maximum,changes);
}

int main(){
    tr_alloc=malloc;tr_realloc=realloc;tr_free=free;
    World world;world.init(1703,5);
    check(brush(world,{320,29,320},6,1,true),"solid excavation fixture");
    for(int across=318;across<=322;across++)for(int along=318;along<=322;along++){
        int bottom=31+(across*17+along*13)%3;
        for(int height=bottom;height<=36;height++)brush(world,{float(across),float(height),float(along)},1,0,false);
    }
    for(int across=318;across<=322;across++)for(int along=318;along<=322;along++)for(int height=31;height<=36;height++){
        if(world.sample(across,height,along)<0)continue;
        Page *page=world.ensure(across>>4,height>>4,along>>4);
        page->d[(across&15)+16*((along&15)+16*(height&15))]=0;
    }
    Mesh mesh;
    check(build_patch(world,304,304,32,1,mesh),"native exact-zero excavation mesh");
    RoofCache roof(world);
    int old_inside=0,repaired=0,zero_starts=0,zero_drift=0;
    for(int index=0;index<mesh.v.n;index++){
        const Vertex &vertex=mesh.v[index];
        if(vertex.p.x<317||vertex.p.x>323||vertex.p.z<317||vertex.p.z>323||vertex.p.y<30||vertex.p.y>35)continue;
        V3 before=old_origin(roof,vertex),after=visibility_origin(roof,vertex);
        if(interpolated_sample(roof,before)<-.002f){old_inside++;repaired+=interpolated_sample(roof,after)>=-.002f;
            if(interpolated_sample(roof,after)<-.002f)printf("REMAIN %.5f %.5f %.5f start %.5f %.5f %.5f value %.6f\n",vertex.p.x,vertex.p.y,vertex.p.z,after.x,after.y,after.z,interpolated_sample(roof,after));}
        V3 initial=vertex.p+vertex.n*.06f;
        if(interpolated_sample(roof,initial)==0.f){zero_starts++;zero_drift+=length(after-initial)>.0001f;}
    }
    printf("MINING_PROBES old_inside=%d repaired=%d zero_starts=%d zero_drift=%d\n",old_inside,repaired,zero_starts,zero_drift);
    check(old_inside>0&&repaired==old_inside,"previously buried lighting probes stay in excavated air");
    check(zero_starts>0&&zero_drift==0,"exact-zero mined air stops projection immediately");
    check(connected_air(world,roof,{319,34,319},{321,34,321}),"zero-density cleared cells can reuse connected sky probes");
    check(!connected_air(world,roof,{313,30,320},{327,30,320}),"solid wall forbids cross-wall light reuse");
    Bytes before,after;world.serialize(before);
    Mesh repeat;build_patch(world,304,304,32,1,repeat);world.serialize(after);
    bool equal=repeat.v.n==mesh.v.n&&repeat.i.n==mesh.i.n;
    for(int index=0;index<mesh.v.n&&equal;index++)equal=std::memcmp(&mesh.v[index],&repeat.v[index],sizeof(Vertex))==0;
    check(equal,"cold and warm lighting builds are deterministic");
    check(before.n==after.n&&std::memcmp(before.p,after.p,before.n)==0,"lighting never changes saved density");
    before.release();after.release();repeat.release();mesh.release();world.release();
    printf("MINING_LIGHT_REGRESSION failures=%d\n",failures);
    return failures?1:0;
}
