// SPDX-License-Identifier: 0BSD
#pragma once
#include "water_cell_profile.hpp"

namespace terraforest {
// Boundary representation of the occupied cut cells. Unlike sampling an SDF,
// clipping preserves a wet wedge even when it is thinner than the mesh lattice.
// Interior faces are polygon differences against the neighbouring occupied
// volumes, so this is one union boundary rather than overlapping cell boxes.
struct WaterBoundary {
    using C=WaterSolidClip;
    using P=C::Point;
    using F=C::Face;
    // Smaller than the minimum nonzero triangle on the shared 2^-22 m grid.
    // A larger pre-projection cutoff removes a representable cap and leaves
    // three unmatched perimeter edges. Quantized zero-area faces are discarded
    // exactly by triangulation instead.
    static constexpr double MIN_AREA=1e-16;
    static double length(P p){return std::sqrt(p.dot(p));}
    static bool occupied(const WaterCellProfile &shape,double head,C::Pieces &out){
        if(shape.solid)return shape.solid->occupied_pieces(head*.001,out);
        if(!shape.contact&&shape.minimum()==shape.maximum()){
            const double bottom=std::max(0.0,shape.minimum())*.001;
            const double top=std::min(head,shape.ceiling)*.001;
            if(top>bottom)out.push_back(C::box({0,bottom,0},{.5,top,.5}));
            return true;
        }
        return shape.solid_remainder(head,{},out);
    }
    static F clip(const F &face,C::Plane plane){
        F out;
        for(size_t i=0;i<face.size();++i){
            auto a=face[i],b=face[(i+1)%face.size()];
            double da=plane.normal.dot(a)-plane.offset,db=plane.normal.dot(b)-plane.offset;
            if(std::abs(da)<1e-11)da=0;if(std::abs(db)<1e-11)db=0;
            if(da<=0)C::append_unique(out,a);
            if((da<0&&db>0)||(da>0&&db<0))C::append_unique(out,C::intersection(a,b,da,db));
        }
        return out;
    }
    static double area(const F &face){
        P cross;for(size_t i=1;i+1<face.size();++i)cross=cross+(face[i]-face[0]).cross(face[i+1]-face[0]);
        return length(cross)*.5;
    }
    // Keep every shared perimeter vertex, including collinear subdivisions.
    template<class Emit> static bool triangulate(F polygon,Emit emit){
        P normal;for(size_t i=1;i+1<polygon.size();++i)normal=normal+(polygon[i]-polygon[0]).cross(polygon[i+1]-polygon[0]);
        if(normal.dot(normal)==0)return true;
        while(polygon.size()>3){
            bool cut=false;
            for(size_t i=0;i<polygon.size();++i){
                size_t previous=(i+polygon.size()-1)%polygon.size(),next=(i+1)%polygon.size();
                auto a=polygon[previous],b=polygon[i],c=polygon[next];
                if((b-a).cross(c-a).dot(normal)<=0)continue;
                auto d=c-a;double norm=d.dot(d);bool crosses_vertex=false;
                for(size_t j=0;j<polygon.size();++j)if(j!=previous&&j!=i&&j!=next){
                    auto v=polygon[j];double t=(v-a).dot(d)/norm;
                    if(t>=0&&t<=1){auto error=(v-a).cross(d);crosses_vertex|=error.dot(error)==0;}
                    crosses_vertex|=(b-a).cross(v-a).dot(normal)>=0&&(c-b).cross(v-b).dot(normal)>=0&&(a-c).cross(v-c).dot(normal)>=0;
                }
                if(crosses_vertex)continue;
                emit(a,b,c);polygon.erase(polygon.begin()+i);cut=true;break;
            }
            if(!cut)return false;
        }
        if(polygon.size()==3)emit(polygon[0],polygon[1],polygon[2]);
        return true;
    }
    // Subtract only a volume that exists across this oriented face. Coincident
    // exterior faces of adjacent fragments must not erase each other.
    static bool subtract(std::vector<F> &faces,const C::Polyhedron &other,P translation,C::Plane boundary){
        bool across=false;
        for(const auto &face:other.faces)for(auto p:face)
            across|=boundary.normal.dot(p+translation)-boundary.offset>1e-9;
        if(!across)return true;
        std::vector<F> result;
        for(auto inside:faces){
            for(auto plane:other.planes){
                double scale=length(plane.normal);if(scale<=0)continue;
                plane.normal=plane.normal*(1/scale);plane.offset/=scale;
                plane.offset+=plane.normal.dot(translation);
                double maximum=-1e30,minimum=1e30;
                for(auto p:inside){double d=plane.normal.dot(p)-plane.offset;maximum=std::max(maximum,d);minimum=std::min(minimum,d);}
                if(maximum<=1e-11)continue;
                if(minimum>=-1e-11){result.push_back(std::move(inside));break;}
                auto outside=clip(inside,{plane.normal*(-1),-plane.offset});
                if(area(outside)>MIN_AREA)result.push_back(std::move(outside));
                inside=clip(inside,plane);
                if(area(inside)<=MIN_AREA)break;
            }
            if(result.size()>4096)return false;
        }
        faces=std::move(result);return true;
    }
};
}
