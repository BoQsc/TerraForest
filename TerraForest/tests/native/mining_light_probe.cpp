#include <cstdio>
#include <cstdlib>
#include <cmath>
#include "../../addons/volumetric_terrain/native/core.cpp"

int main(int count, char **arguments) {
    if (count != 2) return 2;
    tr_alloc=malloc;tr_realloc=realloc;tr_free=free;
    FILE *input=fopen(arguments[1],"rb");
    if (!input) return 2;
    fseek(input,0,SEEK_END);int length=ftell(input);rewind(input);
    Bytes bytes;bytes.resize(length);
    fread(bytes.p,1,length,input);fclose(input);
    World world;world.init();
    if (!world.deserialize(bytes.p,bytes.n)) return 3;
    bytes.release();
    Mesh mesh;
    bool built=build_owned_region(world,976,1072,16,1,32,64,mesh,terrain_build_epoch(&world));
    printf("MESH ok=%d vertices=%d seed=%d generator=%u pages=%d\n",built,mesh.v.n,world.seed,world.generator_id,world.pages.n);
    RoofCache roof(world);
    for (int index=0;index<mesh.v.n;index++) {
        const Vertex &vertex=mesh.v[index];
        if (vertex.p.x<989 || vertex.p.x>995 || vertex.p.z<1079 || vertex.p.z>1085 || vertex.p.y<30 || vertex.p.y>37) continue;
        V3 start=visibility_origin(roof,vertex);
        int visible=0,unresolved=0;
        for (int ray=0;ray<256;ray++) {
            float height=(ray+.5f)/256.f;
            float azimuth=ray*2.39996323f;
            float radius=std::sqrt(1-height*height);
            int result=trace_visibility(world,start,{std::cos(azimuth)*radius,height,std::sin(azimuth)*radius},&roof);
            visible+=result==0;unresolved+=result==2;
        }
        printf("VERTEX %.5f %.5f %.5f sky %.5f field %.5f start %.5f %.5f %.5f field %.5f top %.5f dense %d unresolved %d normal %.3f %.3f %.3f\n",vertex.p.x,vertex.p.y,vertex.p.z,vertex.sky,interpolated_sample(roof,vertex.p),start.x,start.y,start.z,interpolated_sample(roof,start),roof.top_at(start.x,start.z),visible,unresolved,vertex.n.x,vertex.n.y,vertex.n.z);
    }
    mesh.release();world.release();
    return tr_oom?1:0;
}
