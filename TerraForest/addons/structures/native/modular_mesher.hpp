#pragma once
#include "block_shapes.hpp"
#include <algorithm>

namespace terraforest {
inline void append_modular_shape(BlockBake &output,Vector3 origin,int word) {
    const auto &geometry=modular_geometry(block_shape(word));
    int base=int(output.vertices.size()),rotation=block_rotation(word);
    for(auto vertex:geometry.vertices) {
        Vector3 point=origin+Vector3(.5,.5,.5)+orient_block_vector(Vector3(vertex.x,vertex.y,vertex.z)-Vector3(.5,.5,.5),rotation);
        Vector3 normal=orient_block_vector(Vector3(vertex.nx,vertex.ny,vertex.nz),rotation);
        output.vertices.push_back({point.x,point.y,point.z,normal.x,normal.y,normal.z,vertex.u,vertex.v,float(block_material(word))});
    }
    for(int index:geometry.indices)output.indices.push_back(base+index);
}
inline BlockVertex interpolate_block_vertex(const BlockVertex &first,const BlockVertex &second,float fraction) {
    return {first.x+(second.x-first.x)*fraction,first.y+(second.y-first.y)*fraction,first.z+(second.z-first.z)*fraction,
        first.nx+(second.nx-first.nx)*fraction,first.ny+(second.ny-first.ny)*fraction,first.nz+(second.nz-first.nz)*fraction,
        first.u+(second.u-first.u)*fraction,first.v+(second.v-first.v)*fraction,first.material};
}
inline void split_block_polygon(const std::vector<BlockVertex> &polygon,Vector3 normal,double offset,std::vector<BlockVertex> &inside,std::vector<BlockVertex> &outside) {
    auto distance=[&](const BlockVertex &vertex){return double(normal.x)*vertex.x+double(normal.y)*vertex.y+double(normal.z)*vertex.z-offset;};
    for(size_t index=0;index<polygon.size();++index) {
        const auto &first=polygon[index],&second=polygon[(index+1)%polygon.size()];
        double first_distance=distance(first),second_distance=distance(second);
        bool first_inside=first_distance<=1e-7,second_inside=second_distance<=1e-7;
        (first_inside?inside:outside).push_back(first);
        if(first_inside!=second_inside) {
            auto intersection=interpolate_block_vertex(first,second,float(std::clamp(first_distance/(first_distance-second_distance),0.,1.)));
            inside.push_back(intersection);outside.push_back(intersection);
        }
    }
}
inline void clip_modular_boundaries(BlockBake &output,const std::array<uint16_t,5832> &halo,size_t legacy_indices) {
    std::vector<BlockVertex> vertices=std::move(output.vertices);std::vector<int32_t> indices;
    indices.reserve(output.indices.size());
    for(size_t triangle=0;triangle<output.indices.size();triangle+=3) {
        std::vector<BlockVertex> polygon;
        for(size_t corner=0;corner<3;++corner)polygon.push_back(vertices[output.indices[triangle+corner]]);
        Vector3 first(polygon[0].x,polygon[0].y,polygon[0].z),second(polygon[1].x,polygon[1].y,polygon[1].z),third(polygon[2].x,polygon[2].y,polygon[2].z);
        Vector3 normal=(third-first).cross(second-first).normalized();
        int axis=normal.abs().max_axis_index();double boundary=std::round(first[axis]);
        bool cell_face=std::abs(normal[axis])>.99999&&std::abs(first[axis]-boundary)<1e-6&&std::abs(second[axis]-boundary)<1e-6&&std::abs(third[axis]-boundary)<1e-6;
        if(!cell_face){indices.insert(indices.end(),output.indices.begin()+triangle,output.indices.begin()+triangle+3);continue;}
        bool processed=false;
        std::vector<std::vector<BlockVertex>> fragments{std::move(polygon)};
        if(cell_face) {
            int horizontal=(axis+1)%3,vertical=(axis+2)%3;
            Vector3 low=first.min(second).min(third),high=first.max(second).max(third);
            for(int row=int(std::floor(low[vertical]+1e-6));row<int(std::ceil(high[vertical]-1e-6))&&!fragments.empty();++row)
                for(int column=int(std::floor(low[horizontal]+1e-6));column<int(std::ceil(high[horizontal]-1e-6))&&!fragments.empty();++column) {
                    Vector3i neighbor;neighbor[axis]=int(boundary)-(normal[axis]<0?1:0);neighbor[horizontal]=column;neighbor[vertical]=row;
                    if(neighbor.x<-1||neighbor.y<-1||neighbor.z<-1||neighbor.x>16||neighbor.y>16||neighbor.z>16)continue;
                    int word=halo[neighbor.x+1+18*(neighbor.y+1+18*(neighbor.z+1))];
                    if(!word||(triangle<legacy_indices&&!extended_block(word)))continue;
                    processed=true;
                    std::vector<std::vector<ModularPlane>> hulls;std::vector<ModularPlane> hull;
                    Vector3 center(.5,.5,.5),translation(neighbor);int rotation=block_rotation(word);
                    visit_shape_hulls(block_shape(word),[&](){hull.clear();},[&](Vector3 side,double offset){
                        Vector3 rotated=orient_block_vector(side,rotation);
                        hull.push_back({rotated,offset+rotated.dot(center+translation)-side.dot(center)});
                    },[&](){hulls.push_back(hull);});
                    for(const auto &component:hulls) {
                        std::vector<std::vector<BlockVertex>> remainder;
                        for(auto &fragment:fragments) {
                            auto candidate=std::move(fragment);
                            for(const auto &side:component) {
                                std::vector<BlockVertex> inside,outside;
                                split_block_polygon(candidate,side.normal,side.offset,inside,outside);
                                if(outside.size()>=3)remainder.push_back(std::move(outside));
                                candidate=std::move(inside);if(candidate.size()<3)break;
                            }
                        }
                        fragments=std::move(remainder);if(fragments.empty())break;
                    }
                }
        }
        if(!processed){indices.insert(indices.end(),output.indices.begin()+triangle,output.indices.begin()+triangle+3);continue;}
        for(const auto &fragment:fragments)for(size_t corner=1;corner+1<fragment.size();++corner) {
            const auto &first_vertex=fragment[0],&second_vertex=fragment[corner],&third_vertex=fragment[corner+1];
            Vector3 edge_a(second_vertex.x-first_vertex.x,second_vertex.y-first_vertex.y,second_vertex.z-first_vertex.z),edge_b(third_vertex.x-first_vertex.x,third_vertex.y-first_vertex.y,third_vertex.z-first_vertex.z);
            if(edge_a.cross(edge_b).length_squared()<1e-16)continue;
            int base=int(vertices.size());vertices.insert(vertices.end(),{first_vertex,second_vertex,third_vertex});indices.insert(indices.end(),{base,base+1,base+2});
        }
    }
    std::vector<int32_t> remap(vertices.size(),-1);
    output.vertices.reserve(vertices.size());
    for(auto &index:indices){if(remap[index]<0){remap[index]=int(output.vertices.size());output.vertices.push_back(vertices[index]);}index=remap[index];}
    output.indices=std::move(indices);
}
}
