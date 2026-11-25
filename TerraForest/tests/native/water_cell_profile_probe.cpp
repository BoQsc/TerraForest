// SPDX-License-Identifier: 0BSD
#include "../../addons/volumetric_water/native/water_cell_profile.hpp"
#include "../../addons/volumetric_water/native/water_volume_query.hpp"
#include "../../addons/volumetric_water/native/water_terrain_contacts.hpp"
#include "../../addons/volumetric_water/native/water_storage_groups.hpp"
#include "../../addons/volumetric_water/native/water_edit_stencil.hpp"
#include "../../addons/volumetric_water/native/water_level_section.hpp"
#include <atomic>
#include <cstdio>
#include <cstdlib>
using terraforest::WaterCellProfile;
static void require(bool ok,const char *name){std::printf("%s %s\n",ok?"PASS":"FAIL",name);if(!ok)std::exit(1);}
static void check_graded_shoreline() {
    using namespace terraforest;
    using T=WaterCellProfile::Triangle;
    using P=WaterCellProfile::Point;
    // The terrain diagonal runs from (1,0) to (0,1). The water diagonal
    // runs from (0,0) to (1,1). Each pair of triangles can intersect.
    const P a{0,0,-70}, b{1,0,690}, c{0,1,175}, d{1,1,-23};
    WaterCellProfile::Bed terrain{{T{a,b,c},T{b,d,c}}};
    WaterCellProfile shape;
    shape.contact=&terrain;
    for (const std::array<double,4> head : {
            std::array<double,4>{-.12,.66,.34,.18}, {0,.5,0,.5},
            {.41,.13,.025,.47}, {.05,.05,.05,.05}, {.5,.5,.5,.5}}) {
        std::vector<WaterSolidClip::Face> faces;
        bool planes_match=true;
        water_cap_sections(shape,head,[&](auto face,auto plane){
            for (const auto &v:face)
                planes_match &= std::abs(plane.normal.dot(v)-plane.offset)<1e-12;
            faces.push_back(std::move(face));
        });
        for (int j=0;j<43;++j) for (int i=0;i<43;++i) {
            const double x=(i+.317)/43., z=(j+.689)/43.;
            const double floor=(x+z<1
                ? a.y*(1-x-z)+b.y*x+c.y*z
                : b.y*(1-z)+d.y*(x+z-1)+c.y*(1-x))*.001;
            const double level=head[0]+(x>=z
                ? (head[1]-head[0])*x+(head[3]-head[1])*z
                : (head[3]-head[2])*x+(head[2]-head[0])*z);
            bool covered=false;
            for (const auto &face:faces) {
                bool positive=false,negative=false;
                for (size_t k=0;k<face.size();++k) {
                    const auto &v=face[k], &w=face[(k+1)%face.size()];
                    const double cross=(w.x-v.x)*(z*.5-v.z)-(w.z-v.z)*(x*.5-v.x);
                    positive |= cross>1e-12;
                    negative |= cross< -1e-12;
                }
                covered |= !(positive&&negative);
            }
            const bool expected=level>0 && level<.5 && level>floor;
            planes_match &= covered==expected;
        }
        require(planes_match,"projected shoreline polygons match independent vertical rays through crossing terrain and water triangles");
    }
}
static void check_storage_groups(){
    using namespace terraforest;
    struct Room {uint64_t before=0,after=0,capacity=0;double fraction=0;};
    constexpr int widths[]={128,96,64};
    const auto base=[](int i){return i<128?0.:(i<224?.75:1.25);};
    const auto volume=[&](int i,double head){return 250000.*std::clamp(head-base(i),0.,4.-base(i));};
    std::vector<WaterSpillEdge> edges;
    for(int i=1;i<288;++i)
        edges.push_back({i-1,i,i==128?2.25:(i==224?3.:base(i)+1.e-9)});
    const auto curve=[&](int i){
        WaterColumnCurve c;c.bottom=base(i);c.terms[0]=base(i);return c;
    };
    std::atomic<bool> cancel{false};
    for(int source:{0,128,224})for(uint64_t delivered:{1u,125000u,17834937u,123456789u}){
        std::vector<Room> reference(288);uint64_t left=delivered;
        for(int i=0;i<288;++i)reference[i].capacity=uint64_t(volume(i,4.));
        for(int n=0;n<288&&left;++n){
            auto &r=reference[(source+n)%288];r.before=std::min(left,r.capacity);left-=r.before;
        }
        auto grouped=reference,repeat=reference;auto links=edges;
        uint64_t quantity=delivered;int64_t exchange=0;const char *reason=nullptr;
        auto cap=[&](int i){return reference[i].capacity;};
        auto integral=[&](int i,double h){return uint64_t(std::floor(volume(i,h)));};
        require(distribute_basin_water(reference,links,-1,4.,quantity,exchange,volume,cap,integral,cancel,
                [](int){},reason,56),"reference spill hierarchy accepts the connected three-pool fixture");
        size_t groups=0;
        require(settle_storage_groups(grouped,edges,4.,delivered,curve,volume,cancel,groups)&&groups==3&&
                settle_storage_groups(repeat,edges,4.,delivered,curve,volume,cancel,groups),
                "dry-floor contraction preserves both perched outlets");
        uint64_t total=0;int first=0;
        for(int width:widths){
            uint64_t oracle=0,actual=0;bool equal=true;
            for(int i=first;i<first+width;++i){
                const uint64_t a=grouped[i].after,b=reference[i].after;
                equal&=(a>b?a-b:b-a)<=1&&a<=cap(i)&&a==repeat[i].after;actual+=a;oracle+=b;
            }
            require(equal&&((actual>oracle?actual-oracle:oracle-actual)<=uint64_t(width))&&
                    ((oracle==0)==(actual==0)),"grouped room depths agree within one ml and dry basins remain dry");
            total+=actual;first+=width;
        }
        require(total==delivered,"grouped settlement returns every millilitre");
    }
}
static void check_edit_stencil(){
    using namespace terraforest;
    WaterEditStencil stencil;
    require(stencil.begin({0,0,0},{13,12,10}),"allocate the bounded water-contact receipt extent");
    const uint32_t records[][4]={{0,2,0,2},{9,11,15,23},{48,32,32,65536},{30,43,28,131072}};
    for(auto &r:records){
        uint32_t address=r[0]|(r[2]<<11)|(r[1]<<22);uint8_t bytes[8];
        for(int i=0;i<4;++i){bytes[i]=uint8_t(address>>(8*i));bytes[4+i]=uint8_t(r[3]>>(8*i));}
        require(stencil.records(bytes,8),"decode a real lattice run, first page, or constructed block");
    }
    stencil.seal();bool equal=true;
    for(int z=0;z<=10;++z)for(int y=0;y<=12;++y)for(int x=0;x<=13;++x){
        bool touches=false;
        for(auto &r:records){
            const bool page=r[3]==65536,block=r[3]==131072;
            const int dx=page?15:0,y0=int(r[1])-int(page),y1=page?int(r[1])+17:(block?int(r[1]):int(r[3]));
            touches|=int(r[0])<=x*4+8&&int(r[0])+dx>=x*4-4&&int(r[2])<=z*4+8&&
                    int(r[2])+dx>=z*4-4&&y0<=y*4+8&&y1>=y*4-4;
        }
        equal&=stencil.changed({x,y,z})==touches;
    }
    require(equal&&stencil.changed({14,1,1}),"every captured brick agrees with independent stencil intersection; outside stays dirty");
}
int main(){
    check_graded_shoreline();
    check_edit_stencil();
    check_storage_groups();
    WaterCellProfile ramp;ramp.floor={0,500,0,500};
    require(ramp.capacity()==62500,"sloped half-cell capacity is 62.5 litres");
    require(std::abs(ramp.volume(250)-15625)<1e-6,"quarter-height wedge integrates to 15.625 litres");
    for(uint64_t ml:{1u,10u,1000u,10000u,62500u})require(std::abs(ramp.volume(ramp.head(ml))-ml)<0.02,"head inversion conserves sub-litre and full-cell quantities");
    auto shape=ramp.footprint(250);
    require(std::abs(shape.area-0.5)<1e-8&&std::abs(shape.x-0.25)<1e-8&&std::abs(shape.z-0.5)<1e-8,"wetted centroid excludes the dry half of the slope");
    WaterCellProfile bank_a,bank_b;
    bank_a.floor={0,0,500,500};
    bank_b.floor={500,500,0,0};
    require(!WaterCellProfile::connected(bank_a,250,bank_b,250,1),
        "opposing slopes touching at one point keep basins separate");
    require(WaterCellProfile::connected(bank_a,251,bank_b,251,1) &&
            WaterCellProfile::connected(bank_b,251,bank_a,251,2),
        "a shared opening above the sill connects both directions");
    WaterCellProfile air;
    require(!WaterCellProfile::connected(air,499,air,100,5) &&
            WaterCellProfile::connected(air,500,air,100,5),
        "stacked water connects only when the lower interval reaches the interface");
    WaterCellProfile flat;flat.floor.fill(275);
    require(flat.capacity()==56250&&flat.head(10000)==315,"flat cells retain their exact constant-area behavior");
    float wall[8]={-1,-1,-1,-1,1,1,1,1};
    auto closed=WaterCellProfile::make(wall,true,500,500);
    require(!closed.cut&&closed.capacity()==0,"ambiguous walls retain conservative closure");
    float slope[8]={0,-1,1,1,0,-1,1,1};
    auto cut=WaterCellProfile::make(slope,true,250,500);
    require(cut.cut&&cut.capacity()==93750&&!cut.open_bottom,"cached floor crossings recover partial capacity without opening solid bottom");
    float crossing_top[8]={-0.4f,-0.6f,0.1f,-0.1f,-0.4f,-0.6f,0.1f,-0.1f};
    auto partial=WaterCellProfile::make(crossing_top,true,500,500);
    require(partial.cut&&std::abs(double(partial.capacity())-6250)<2,"floor crossing the cell top retains its partial air wedge");
    WaterCellProfile film;film.floor={0,30,0,30};
    require(film.surface(film.head(1000),0,0)==film.surface(film.head(1000),1,0),"static top stays horizontal above a sloping floor");
    for(uint64_t ml:{1u,100u,1000u,6000u})require(std::abs(partial.volume(partial.head(ml))-ml)<0.03,"static partial-top inversion conserves volume");
    float crossing_bottom[8]={0.1f,-0.1f,0.6f,0.4f,0.1f,-0.1f,0.6f,0.4f};
    auto bottom_cut=WaterCellProfile::make(crossing_bottom,true,100,500);
    require(bottom_cut.cut&&bottom_cut.open_bottom&&std::abs(double(bottom_cut.capacity())-118750)<2,"partial bottom clips the interpolated floor instead of inventing a ramp");
    require(bottom_cut.bottom(0.25,0.5)==0&&std::abs(bottom_cut.bottom(0.75,0.5)-50)<0.001,"partial bottom retains a finite open face and real uphill terrain");
    for(uint64_t ml:{1u,100u,1000u,50000u,118000u})require(std::abs(bottom_cut.volume(bottom_cut.head(ml))-ml)<0.03,"static partial-bottom surface preserves volume within the cell");
    for(auto shape:{partial,bottom_cut}){
        double h=490,reference=0;constexpr int samples=400;
        for(int z=0;z<samples;++z)for(int x=0;x<samples;++x){double u=(x+0.5)/samples,v=(z+0.5)/samples;
            reference+=std::max(0.0,shape.surface(h,u,v)-shape.bottom(u,v))*250/(samples*samples);}
        require(std::abs(reference-shape.volume(h))<1.0,"clipped static volume agrees with independent dense area quadrature within one millilitre");
    }
    float zero_density[8]={};auto unknown=WaterCellProfile::make(zero_density,true,500,500);
    require(unknown.capacity()==0,"zero-density ambiguity does not invent fully open space");
    auto fractional=film;fractional.floor[0]+=0.123;
 require(fractional.head(fractional.capacity())==500,"integer-capacity saturation reaches the top despite sub-millilitre rounding");
 auto adjacent=film;for(double &y:adjacent.floor)y+=30;
    require(WaterCellProfile::face_overlap(film,film.head(10000),adjacent,adjacent.head(10000),0,1),"sufficient static volumes meet across a shared sloping floor face");
    auto barrier=adjacent;barrier.floor.fill(500);
    require(!WaterCellProfile::face_overlap(film,film.head(1000),barrier,500,0,1),"coherence never bridges a solid face");
    auto lower=partial;
    auto upper=bottom_cut;
    require(WaterCellProfile::vertical_overlap(lower,504,upper,4),"static volumes connect through a narrow partial vertical opening");
    require(!WaterCellProfile::vertical_overlap(lower,504,upper,-10),"a dry vertical gap stays disconnected");
    uint32_t random=1703;int queries=0,passages=0;bool parity=true,face_parity=true,integrals=true,stored=true;
    for(int trial=0;trial<256;++trial){
        WaterCellProfile shape;
        for(double &height:shape.floor){random=random*1664525u+1013904223u;height=(int(random%900001)-200000)*.001;}
        shape.ceiling=100+(trial%401);
        WaterCellProfile::Bed bed;
        auto &contacts=bed.triangles;
        if(trial%2){
            // Real terrain contacts may contain many floor fragments, not
            // merely the four corner heights used by legacy cell fixtures.
            for(int z=0;z<4;++z)for(int x=0;x<4;++x){
                auto point=[&](int u,int v){return WaterCellProfile::Point{u*.25,v*.25,shape.floor[0]+u*17.25-v*11.125};};
                contacts.push_back({point(x,z),point(x+1,z),point(x+1,z+1)});
                contacts.push_back({point(x,z),point(x+1,z+1),point(x,z+1)});
            }
            shape.contact=&bed;
        }
        // Compare the compiled sill to the independent interval intersection
        // on both axes and orientations, including touching and clipped faces.
        for(int axis:{0,2})for(int side:{0,1}){
            const double threshold=WaterCellProfile::floor_spill_height(shape,bank_a,axis,side);
            for(double head:{.1,350.,500.,threshold-1e-6,threshold,threshold+1e-6,threshold+1e-4}){
                if(head<=0)continue;
                double sill;
                const bool connected=WaterCellProfile::floor_passage(shape,head,bank_a,head+.5,axis,side,sill);
                face_parity&=sill==threshold&&connected==WaterCellProfile::face_overlap(shape,head,bank_a,head+.5,axis,side);
                ++passages;
            }
        }
        terraforest::WaterVolumeQuery cached(shape);
        terraforest::TerrainWaterContacts brick;
        WaterCellProfile resident=shape;
        if(!contacts.empty()){
            brick.add(317,contacts);brick.seal();brick.attach(resident,317);
            resident.ceiling=shape.ceiling;
            stored&=resident.contact->storage&&brick.floor(316)==nullptr&&resident.capacity()==shape.capacity();
        }
        parity&=cached.capacity()==shape.capacity();
        auto clipped_volume=[&](double h){
            double ml=0;
            shape.polygons(h,[&](double a,WaterCellProfile::Point p,WaterCellProfile::Point q,WaterCellProfile::Point r){
                ml+=a*(h-(p.y+q.y+r.y)/3.)*250.;
            });
            return ml;
        };
        for(int step=0;step<=32;++step){double h=-10+step*17.123;
            const double reference=h<=0?0:clipped_volume(std::min(h,shape.ceiling))-clipped_volume(0);
            integrals&=std::abs(shape.volume(h)-reference)<1e-6;
            stored&=resident.volume(h)==shape.volume(h);
            parity&=cached.volume(h)==shape.volume(h);++queries;
            uint64_t ml=shape.capacity()*step/32;
            parity&=cached.head(ml)==shape.head(ml);++queries;}
    }
    require(parity,"cached floor moments preserve exact volumes and inverse heads across clipped slopes");
    require(integrals,"analytic storage agrees with independent polygon clipping to one millionth of a millilitre");
    require(stored,"sparse resident beds retain the exact capacities and volumes of their source triangles");
    require(face_parity,"shared sill thresholds preserve contact, direction and ceiling in the interval oracle");
    std::printf("WATER_SPILL_FACE exact_queries=%d\n",passages);
    std::printf("WATER_VOLUME_QUERY exact_queries=%d\n",queries);
    std::puts("WATER_CELL_PROFILE failures=0");
}
