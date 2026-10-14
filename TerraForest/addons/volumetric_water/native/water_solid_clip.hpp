// SPDX-License-Identifier: 0BSD
#pragma once
#include <algorithm>
#include <cmath>
#include <vector>

namespace terraforest {
// Edit-time convex clipping in cell-local metres. No scene or renderer access.
// A solid is an intersection of half-spaces; stairs are four disjoint solids.
// Remaining convex pieces can represent air on both sides of an overhang.
struct WaterSolidClip {
    struct Point {
        double x=0,y=0,z=0;
        Point operator+(Point b)const{return {x+b.x,y+b.y,z+b.z};}
        Point operator-(Point b)const{return {x-b.x,y-b.y,z-b.z};}
        Point operator*(double s)const{return {x*s,y*s,z*s};}
        double dot(Point b)const{return x*b.x+y*b.y+z*b.z;}
        Point cross(Point b)const{return {y*b.z-z*b.y,z*b.x-x*b.z,x*b.y-y*b.x};}
    };
    struct Plane {Point normal;double offset=0;}; // normal.dot(point) <= offset
    using Face=std::vector<Point>;
    struct Polyhedron {std::vector<Face> faces;};
    using Pieces=std::vector<Polyhedron>;
    static constexpr size_t MAX_FACES=256,MAX_PIECES=512,MAX_PLANES=128;
    static constexpr double EPS=1e-10;
    static bool valid(Plane p){return std::isfinite(p.offset)&&std::isfinite(p.normal.x)&&std::isfinite(p.normal.y)&&std::isfinite(p.normal.z)&&p.normal.dot(p.normal)>1e-20;}
    static Polyhedron box(Point lo,Point hi){
        Point a{lo.x,lo.y,lo.z},b{hi.x,lo.y,lo.z},c{hi.x,lo.y,hi.z},d{lo.x,lo.y,hi.z};
        Point e{lo.x,hi.y,lo.z},f{hi.x,hi.y,lo.z},g{hi.x,hi.y,hi.z},h{lo.x,hi.y,hi.z};
        return {{{a,b,c,d},{e,h,g,f},{a,e,f,b},{d,c,g,h},{a,d,h,e},{b,f,g,c}}};
    }
    static void append_unique(Face &points,Point p){for(auto q:points)if((p-q).dot(p-q)<EPS*EPS)return;points.push_back(p);}
    // Outputs are replaced only on success, including an empty intersection.
    static bool clip(const Polyhedron &source,Plane plane,Polyhedron &out){
        if(!valid(plane)||source.faces.size()>MAX_FACES)return false;
        Polyhedron result;Face cap;
        for(const auto &face:source.faces){
            if(face.size()>MAX_FACES)return false;
            Face polygon;
            for(size_t i=0;i<face.size();++i){
                Point a=face[i],b=face[(i+1)%face.size()];
                double da=plane.normal.dot(a)-plane.offset,db=plane.normal.dot(b)-plane.offset;
                bool ia=da<=EPS,ib=db<=EPS;
                if(ia)append_unique(polygon,a);
                if(ia!=ib){
                    // Intersect the true plane, not an epsilon-shifted boundary.
                    double t=std::clamp(da/(da-db),0.0,1.0);Point p=a+(b-a)*t;
                    append_unique(polygon,p);append_unique(cap,p);
                }
            }
            if(polygon.size()>=3)result.faces.push_back(std::move(polygon));
        }
        if(cap.size()>=3){
            Point center;for(auto p:cap)center=center+p;center=center*(1.0/cap.size());
            Point n=plane.normal,axis=std::abs(n.x)<std::abs(n.y)?Point{1,0,0}:Point{0,1,0};
            Point u=n.cross(axis),v=n.cross(u);
            u=u*(1/std::sqrt(u.dot(u)));v=v*(1/std::sqrt(v.dot(v)));
            std::sort(cap.begin(),cap.end(),[&](Point a,Point b){a=a-center;b=b-center;return std::atan2(a.dot(v),a.dot(u))<std::atan2(b.dot(v),b.dot(u));});
            result.faces.push_back(std::move(cap));
        }
        if(result.faces.size()>MAX_FACES)return false;
        out=std::move(result);return true;
    }
    static double volume(const Polyhedron &poly){
        Point center;size_t count=0;
        for(const auto &face:poly.faces)for(auto p:face){center=center+p;++count;}
        if(!count)return 0;center=center*(1.0/count);
        double result=0;
        for(const auto &face:poly.faces)for(size_t i=1;i+1<face.size();++i)
            result+=std::abs((face[0]-center).dot((face[i]-center).cross(face[i+1]-center)))/6;
        return result;
    }
    static double volume(const Pieces &pieces){double v=0;for(const auto &p:pieces)v+=volume(p);return v;}
    // Successive outside fragments are disjoint. Only the final intersection
    // is discarded; therefore repeated/overlapping solids cannot double-delete.
    static bool subtract(const Pieces &source,const std::vector<Plane> &solid,Pieces &out){
        if(source.size()>MAX_PIECES||solid.empty()||solid.size()>MAX_PLANES)return false;
        for(auto plane:solid)if(!valid(plane))return false;
        Pieces result;
        for(const auto &piece:source){
            Polyhedron inside=piece;
            for(auto plane:solid){
                Polyhedron outside,next;
                if(!clip(inside,{plane.normal*(-1),-plane.offset},outside)||!clip(inside,plane,next))return false;
                if(volume(outside)>1e-15){
                    if(result.size()==MAX_PIECES)return false;
                    result.push_back(std::move(outside));
                }
                inside=std::move(next);
                if(volume(inside)<=1e-15)break;
            }
        }
        out=std::move(result);return true;
    }
    static bool below(const Pieces &source,double head,Pieces &out){
        if(!std::isfinite(head)||source.size()>MAX_PIECES)return false;
        Pieces result;
        for(const auto &p:source){Polyhedron clipped;if(!clip(p,{{0,1,0},head},clipped))return false;
            if(volume(clipped)>1e-15)result.push_back(std::move(clipped));}
        out=std::move(result);return true;
    }
};
}
