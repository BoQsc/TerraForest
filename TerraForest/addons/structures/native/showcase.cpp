#include "block_world.hpp"
namespace terraforest {
void NativeBlockWorld::create_showcase() {
    // Deterministic example authoring operation, not part of the frame loop.
    std::map<BlockKey,int> blocks;
    auto put=[&](int x,int y,int z,int shape,int mat,int rotation=0){blocks[{x,y,z}]=shape?shape+(rotation<<3)+(mat<<5):0;};
    auto box=[&](int x0,int y0,int z0,int x1,int y1,int z1,int shape,int mat){
        for(int z=z0;z<=z1;z++)for(int y=y0;y<=y1;y++)for(int x=x0;x<=x1;x++)put(x,y,z,shape,mat);
    };
    box(-20,-1,-12,54,-1,38,1,2);
    // Walk-in brick house with real openings, wood floors and a stepped gable roof.
    box(-9,0,-5,7,0,9,1,1);
    for(int y=1;y<=6;y++)for(int x=-9;x<=7;x++)for(int z=-5;z<=9;z++) {
        if(x!=-9&&x!=7&&z!=-5&&z!=9)continue;
        bool door=z==-5&&x>=-2&&x<=0&&y<=3;
        bool window=y>=2&&y<=4&&((z==-5&&(x>=-7&&x<=-5||x>=3&&x<=5))||(x==7&&z>=0&&z<=3)||(x==-9&&z>=0&&z<=3));
        if(!door&&!window)put(x,y,z,1,0);
    }
    for(int z=-6;z<=10;z++)for(int x=-10;x<=8;x++) {
        int rise=std::min(x+10,8-x);
        put(x,7+rise,z,x==-1?2:4,3,x<-1?3:1);
        if((z==-5||z==9)&&x>=-9&&x<=7)
            for(int y=7;y<7+rise;y++)put(x,y,z,1,0);
    }
    // Front porch, squared columns, slab canopy, external four-step stairs.
    box(-5,0,-9,3,0,-6,1,1);
    for(int x:{-5,3})for(int y=1;y<=4;y++)put(x,y,-9,5,1);
    box(-5,5,-9,3,5,-6,2,1);
    for(int x=-2;x<=0;x++)put(x,0,-10,3,2);
    // Office tower: repeated structural bays, hollow floors, open window bands.
    for(int floor=0;floor<12;floor++) {
        int base=floor*4;
        for(int z=6;z<=21;z++)for(int x=20;x<=35;x++)
            if(floor==0||x<22||x>23||z<8||z>11)put(x,base,z,1,2);
        for(int y=base+1;y<=base+3;y++) {
            for(int x=20;x<=35;x++)for(int z=6;z<=21;z++)
                if(((z==6||z==21)&&(x-20)%5==0)||((x==20||x==35)&&(z-6)%5==0))put(x,y,z,1,2);
        }
        // Solid service core, plus a visible staircase with one metre rise per cell.
        box(26,base+1,12,28,base+3,14,1,3);
        for(int step=0;step<4;step++)for(int x=22;x<24;x++)put(x,base+step+1,8+step,3,1);
    }
    box(20,48,6,35,48,21,1,3);
    // Shape library clearly separated from terrain, arranged on individual plinths.
    for(int shape=1;shape<=5;shape++) {
        int x=-14+(shape-1)*4;box(x,0,19,x+2,0,21,1,2);
        put(x+1,1,20,shape,(shape-1)%4,shape==4?1:0);
    }
    // Retaining wall, narrow posts and a ramp up to a raised platform.
    box(42,0,0,51,2,10,1,2);
    for(int x=43;x<=49;x++)for(int z=-3;z<0;z++) {
        put(x,z+3,z,4,2);for(int y=0;y<z+3;y++)put(x,y,z,1,2);
    }
    PackedInt32Array records;records.resize(blocks.size()*4);int i=0;
    for(auto &e:blocks){records.set(i++,e.first.x);records.set(i++,e.first.y);records.set(i++,e.first.z);records.set(i++,e.second);}
    set_cells(records);
}
}
