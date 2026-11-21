// SPDX-License-Identifier: 0BSD
#include "regional_water.hpp"
#include "water_level_section.hpp"
#include <map>

using namespace godot;
namespace terraforest {
// Intersect the free surface with the terrain triangles directly when the
// occupied volumes and their reconstruction halo prove one hydrostatic head.
// Disconnected dry cavities, non-level surfaces and structural contacts use
// the general convex union. Both paths retain exact per-cell ownership.
bool NativeRegionalWater::build_level_surface(Key key,const std::array<const Region*,27> &halo,SurfaceMesh &out) const{
    const auto *owner=halo[13];
    if(!owner||!owner->valid)return false;
    const Vector3i base=position(key)*8;
    double level=-1;
    if(owner->ocean_state&&surrounding_ocean)level=40;
    else for(int i=0;i<512;++i){
        const auto amount=owner->water[i];
        if(amount==0||amount>=125000)continue;
        auto shape=profile(*owner,i);
        if(!shape.is_full_air())continue;
        level=(base.y+(i/8)%8)*.5+amount/250000.;
        break;
    }
    if(level<0)return false;
    auto at=[&](int x,int y,int z){
        return halo[((x+8)>>3)+3*(((y+8)>>3)+3*((z+8)>>3))];
    };
    // A free cap can be reconstructed from neighbouring columns up to two
    // cells above/below. A wholly full cell has no interior free surface.
    for(int z=-2;z<10;++z)for(int y=-4;y<12;++y){
        double depth=(level-(base.y+y)*.5)*1000.;
        for(int x=-2;x<10;++x){
            auto p=base+Vector3i(x,y,z);
            if(!in_domain(p))return false;
            auto *r=at(x,y,z);
            if(!r){
                if(depth>0&&(!surrounding_ocean||level!=40||std::min({p.x,p.z,3999-p.x,3999-p.z})>=280))return false;
                continue;
            }
            if(!r->valid)return false;
            const int i=index(p);const uint64_t amount=r->water[i];
            if(depth<=0){if(amount)return false;continue;}
            if(r->floor[i]==r->ceiling[i]){if(amount)return false;continue;}
            if(depth>=500&&amount==125000)continue;
            const auto shape=profile(*r,i);
            if(depth>=500){
                if(amount!=shape.capacity())return false;
            }else{
                const double occupied=shape.volume(depth);
                if(!amount){if(occupied>1e-7)return false;continue;}
                if(amount==shape.capacity()&&depth>=shape.ceiling)continue;
                // Bound the difference below half a vertex-grid interval.
                if(std::abs(shape.head(amount)-depth)>.0001)return false;
            }
        }
    }
    const int top=int(std::ceil(level*2.))-1,y=top-base.y;
    if(y<0||y>=8){out.faces["level_section"]=true;return true;}
    const double depth=(level-top*.5)*1000.;
    constexpr double grid=4194304.;
    const float height=float(std::round((level-base.y*.5)*grid)/grid);
    std::vector<Vector3> vertices;
    std::vector<int32_t> indices;
    std::vector<uint16_t> owners;
    std::map<std::pair<int32_t,int32_t>,int> vertex_ids;
    auto vertex=[&](int x,int z,WaterFaceClip::Point p){
        auto position=std::make_pair(int32_t(std::llround((x*.5+p.x)*grid)),int32_t(std::llround((z*.5+p.y)*grid)));
        auto [it,fresh]=vertex_ids.emplace(position,int(vertices.size()));
        if(fresh)vertices.emplace_back(position.first/grid,height,position.second/grid);
        return it->second;
    };
    for(int z=0;z<8;++z)for(int x=0;x<8;++x){
        int i=x+8*y+64*z;
        if(!owner->water[i])continue;
        const auto bed=profile(*owner,i);
        if(bed.solid||bed.ceiling!=500)return false;
        WaterCellProfile over;
        if(depth==500){
            const auto *r=at(x,y+1,z);
            if(r){
                const int above=index(base+Vector3i(x,y+1,z));
                if(r->floor[above]==r->ceiling[above])continue;
                over=profile(*r,above);if(over.solid)return false;
            }
        }
        auto emit=[&](const WaterFaceClip::Polygon &poly){
            if(poly.count<3)return;
            const int a=vertex(x,z,poly[0]);int b=vertex(x,z,poly[1]);
            for(size_t j=2;j<poly.count;++j){
                const int c=vertex(x,z,poly[j]);
                const auto ab=vertices[b]-vertices[a],ac=vertices[c]-vertices[a];
                if(ac.cross(ab).y>0){indices.insert(indices.end(),{a,b,c});owners.push_back(i);}
                b=c;
            }
        };
        bed.floor_triangles([&](const WaterCellProfile::Triangle &floor){
            auto polygon=water_floor_section(floor,depth,false);
            if(polygon.count<3)return;
            if(depth<500||over.is_full_air()){emit(polygon);return;}
            over.floor_triangles([&](const WaterCellProfile::Triangle &roof){
                auto open=water_floor_section(roof,0,true);
                if(open.count<3||WaterFaceClip::area(open)<=1e-16)return;
                auto free=polygon;
                if(WaterFaceClip::intersect(free,open))emit(free);
            });
        });
    }
    if(!indices.empty()){
        out.render_vertices.resize(vertices.size());std::copy(vertices.begin(),vertices.end(),out.render_vertices.ptrw());
        out.render_indices.resize(indices.size());std::copy(indices.begin(),indices.end(),out.render_indices.ptrw());
        out.query_vertices=out.render_vertices;out.query_indices=out.render_indices;
        out.render_uv.resize(vertices.size());auto *uv=out.render_uv.ptrw();
        for(size_t i=0;i<vertices.size();++i)uv[i]={base.x*.5f+vertices[i].x,base.z*.5f+vertices[i].z};
        out.render_normals.resize(vertices.size());out.render_normals.fill({0,1,0});
        out.render_colors.resize(vertices.size());out.render_colors.fill({1,1,1,1});
        out.owners=std::move(owners);
    }
    out.faces["top"]=out.faces["triangles"]=int64_t(out.owners.size());
    out.faces["level_section"]=true;
    return true;
}
}
