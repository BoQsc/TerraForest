#pragma once
#include "block_world.hpp"
#include <cmath>

namespace terraforest {
struct ModularPlane {Vector3 normal;double offset;};
struct ModularGeometry {
    std::vector<BlockVertex> vertices;
    std::vector<int32_t> indices;
    std::vector<std::vector<ModularPlane>> hulls;
};
inline Vector3 orient_block_vector(Vector3 value,int rotation) {
    switch(rotation/4) {
        case 1:value=Vector3(value.x,-value.z,value.y);break;
        case 2:value=Vector3(value.x,-value.y,-value.z);break;
        case 3:value=Vector3(value.x,value.z,-value.y);break;
        case 4:value=Vector3(-value.y,value.x,value.z);break;
        case 5:value=Vector3(value.y,-value.x,value.z);break;
    }
    for(int turn=0;turn<(rotation&3);++turn)value=Vector3(-value.z,value.y,value.x);
    return value;
}
inline Basis block_basis(int rotation) {
    return Basis(orient_block_vector(Vector3(1,0,0),rotation),orient_block_vector(Vector3(0,1,0),rotation),orient_block_vector(Vector3(0,0,1),rotation));
}
inline const ModularGeometry &modular_geometry(int shape) {
    static const std::array<ModularGeometry,6> catalogue=[] {
        std::array<ModularGeometry,6> result;
        auto triangle=[](ModularGeometry &mesh,Vector3 first,Vector3 second,Vector3 third,Vector3 smooth_first=Vector3(),Vector3 smooth_second=Vector3(),Vector3 smooth_third=Vector3()) {
            Vector3 normal=(second-first).cross(third-first).normalized();
            int base=int(mesh.vertices.size()),axis=normal.abs().max_axis_index();
            std::array<Vector3,3> points{first,second,third},normals{smooth_first,smooth_second,smooth_third};
            for(int index=0;index<3;++index) {
                Vector3 point=points[index],shade=normals[index].length_squared()>.5?normals[index]:normal;
                float horizontal=axis==0?point.z:point.x,vertical=axis==1?point.z:point.y;
                mesh.vertices.push_back({point.x,point.y,point.z,shade.x,shade.y,shade.z,horizontal,vertical,0});
            }
            mesh.indices.insert(mesh.indices.end(),{base,base+2,base+1});
        };
        auto prism=[&](ModularGeometry &mesh,const std::vector<Vector3> &polygon,bool draw=true) {
            std::vector<ModularPlane> hull{{Vector3(0,0,-1),0},{Vector3(0,0,1),1}};
            for(size_t index=0;index<polygon.size();++index) {
                Vector3 first=polygon[index],second=polygon[(index+1)%polygon.size()],depth(0,0,1);
                Vector3 normal=(second-first).cross(depth).normalized();
                hull.push_back({normal,normal.dot(first)});
                if(draw){triangle(mesh,first,second,second+depth);triangle(mesh,first,second+depth,first+depth);}
            }
            mesh.hulls.push_back(std::move(hull));
            if(draw)for(size_t index=1;index+1<polygon.size();++index) {
                triangle(mesh,polygon[0],polygon[index+1],polygon[index]);
                triangle(mesh,polygon[0]+Vector3(0,0,1),polygon[index]+Vector3(0,0,1),polygon[index+1]+Vector3(0,0,1));
            }
        };
        prism(result[0],{Vector3(0,0,0),Vector3(1,0,0),Vector3(1,.125,0),Vector3(0,.125,0)});
        auto &trim=result[1];
        prism(trim,{Vector3(0,0,0),Vector3(1,0,0),Vector3(1,.125,0),Vector3(0,.125,0)},false);
        prism(trim,{Vector3(0,.125,0),Vector3(.125,.125,0),Vector3(.125,1,0),Vector3(0,1,0)},false);
        const std::array<Vector3,6> outline{Vector3(0,0,0),Vector3(1,0,0),Vector3(1,.125,0),Vector3(.125,.125,0),Vector3(.125,1,0),Vector3(0,1,0)};
        for(size_t index=0;index<outline.size();++index) {
            Vector3 first=outline[index],second=outline[(index+1)%outline.size()],depth(0,0,1);
            triangle(trim,first,second,second+depth);triangle(trim,first,second+depth,first+depth);
        }
        for(auto face:std::array<std::array<int,3>,4>{{{0,1,2},{0,2,3},{0,3,4},{0,4,5}}}) {
            triangle(trim,outline[face[0]],outline[face[2]],outline[face[1]]);
            triangle(trim,outline[face[0]]+Vector3(0,0,1),outline[face[1]]+Vector3(0,0,1),outline[face[2]]+Vector3(0,0,1));
        }
        auto &arch=result[2];constexpr double half_pi=1.57079632679489661923;
        for(int segment=0;segment<12;++segment) {
            double first_angle=half_pi*segment/12,second_angle=half_pi*(segment+1)/12;
            Vector3 first(std::cos(first_angle),std::sin(first_angle),0),second(std::cos(second_angle),std::sin(second_angle),0);
            if(segment==0)first=Vector3(1,0,0);
            if(segment==11)second=Vector3(0,1,0);
            Vector3 inner_first=first*.875,inner_second=second*.875,depth(0,0,1);
            prism(arch,{inner_first,first,second,inner_second},false);
            triangle(arch,inner_first,second,first);triangle(arch,inner_first,inner_second,second);
            triangle(arch,inner_first+depth,first+depth,second+depth);triangle(arch,inner_first+depth,second+depth,inner_second+depth);
            triangle(arch,first,second,second+depth,first,second,second);triangle(arch,first,second+depth,first+depth,first,second,first);
            triangle(arch,inner_second,inner_first,inner_first+depth,-second,-first,-first);triangle(arch,inner_second,inner_first+depth,inner_second+depth,-second,-first,-second);
            if(segment==0){triangle(arch,inner_first,first,first+depth);triangle(arch,inner_first,first+depth,inner_first+depth);}
            if(segment==11){triangle(arch,second,inner_second,inner_second+depth);triangle(arch,second,inner_second+depth,second+depth);}
        }
        prism(result[3],{Vector3(0,0,0),Vector3(1,0,0),Vector3(.5,.5,0)});
        auto convex=[&](ModularGeometry &mesh,const std::vector<Vector3> &points,const std::vector<std::vector<int>> &faces) {
            Vector3 center;for(Vector3 point:points)center+=point;center/=float(points.size());
            std::vector<ModularPlane> hull;
            for(const auto &face:faces) {
                Vector3 first=points[face[0]],second=points[face[1]],third=points[face[2]];
                Vector3 normal=(second-first).cross(third-first).normalized();
                bool flip=normal.dot(center-first)>0;if(flip)normal=-normal;
                hull.push_back({normal,normal.dot(first)});
                for(size_t index=1;index+1<face.size();++index)
                    triangle(mesh,first,points[face[flip?index+1:index]],points[face[flip?index:index+1]]);
            }
            mesh.hulls.push_back(std::move(hull));
        };
        convex(result[4],{Vector3(0,0,0),Vector3(1,0,0),Vector3(1,0,1),Vector3(0,0,1),Vector3(1,1,1)},{{0,1,2,3},{0,1,4},{1,2,4},{2,3,4},{3,0,4}});
        convex(result[5],{Vector3(0,0,0),Vector3(1,0,0),Vector3(1,0,1),Vector3(0,0,1),Vector3(1,1,0),Vector3(1,1,1)},{{0,3,2,1},{1,2,5,4},{0,1,4},{3,5,2},{0,4,5,3}});
        ModularGeometry second_half;
        convex(second_half,{Vector3(0,0,0),Vector3(1,0,0),Vector3(1,0,1),Vector3(0,0,1),Vector3(0,1,1),Vector3(1,1,1)},{{0,1,2,3},{3,2,5,4},{0,4,3},{1,2,5},{0,1,5,4}});
        result[5].hulls.insert(result[5].hulls.end(),second_half.hulls.begin(),second_half.hulls.end());
        result[5].vertices.clear();result[5].indices.clear();
        const std::array<Vector3,7> inner{Vector3(0,0,0),Vector3(1,0,0),Vector3(1,0,1),Vector3(0,0,1),Vector3(1,1,0),Vector3(1,1,1),Vector3(0,1,1)};
        for(auto face:std::array<std::array<int,3>,10>{{{0,2,1},{0,3,2},{1,2,5},{1,5,4},{2,3,6},{2,6,5},{0,1,4},{0,6,3},{0,4,5},{0,5,6}}}) {
            Vector3 first=inner[face[0]],second=inner[face[1]],third=inner[face[2]];
            triangle(result[5],first,third,second);
        }
        return result;
    }();
    return catalogue[shape-9];
}
}
