// SPDX-License-Identifier: 0BSD
#pragma once
#include "water_solid_clip.hpp"
#include <array>
#include <cstdint>

namespace terraforest {
// Immutable, edit-time-prepared occupancy. Queries never clip polygons or
// allocate. Heights are metres internally; volume is cubic metres.
class WaterSolidProfile {
public:
    using C=WaterSolidClip;
    struct Segment {double low,high;std::array<double,4> polynomial;};
    struct Hull {std::vector<C::Plane> planes;};
    static constexpr size_t MAX_KNOTS=128,MAX_VERTICES=32768;
private:
    std::vector<Segment> curve;
    std::vector<Hull> hulls;
    double full=0,low=0,high=0;
public:
    bool prepare(const C::Pieces &pieces){
        if(pieces.size()>C::MAX_PIECES)return false;
        WaterSolidProfile staged;std::vector<double> knots;size_t vertices=0;
        for(const auto &piece:pieces){
            if(piece.faces.size()>C::MAX_FACES)return false;
            C::Point center;size_t count=0;
            for(const auto &face:piece.faces)for(auto p:face){
                if(++vertices>MAX_VERTICES||!std::isfinite(p.x)||!std::isfinite(p.y)||!std::isfinite(p.z)||
                    p.x< -1e-8||p.x>.5+1e-8||p.y< -1e-8||p.y>.5+1e-8||p.z< -1e-8||p.z>.5+1e-8)return false;
                knots.push_back(std::clamp(p.y,0.0,.5));center=center+p;++count;
            }
            if(!count)continue;center=center*(1.0/count);Hull hull;
            for(const auto &face:piece.faces){
                if(face.size()<3)continue;C::Point n;
                for(size_t i=1;i+1<face.size();++i){n=(face[i]-face[0]).cross(face[i+1]-face[0]);if(n.dot(n)>1e-24)break;}
                double length=std::sqrt(n.dot(n));if(length<1e-12)continue;n=n*(1/length);
                double offset=n.dot(face[0]);if(n.dot(center)>offset){n=n*(-1);offset=-offset;}
                hull.planes.push_back({n,offset});
            }
            if(!hull.planes.empty())staged.hulls.push_back(std::move(hull));
        }
        if(knots.empty()){*this=std::move(staged);return true;}
        std::sort(knots.begin(),knots.end());
        knots.erase(std::unique(knots.begin(),knots.end(),[](double a,double b){return b-a<1e-9;}),knots.end());
        if(knots.size()>MAX_KNOTS)return false;
        staged.low=knots.front();staged.high=knots.back();staged.full=C::volume(pieces);
        if(!std::isfinite(staged.full)||staged.full>.125+1e-9)return false;
        auto at=[&](double y,double &v){C::Pieces cut;if(!C::below(pieces,y,cut))return false;v=C::volume(cut);return std::isfinite(v);};
        // Polyhedral volume below a moving plane is cubic between vertex
        // heights. Fit in normalized local t to avoid large-coordinate loss.
        for(size_t i=1;i<knots.size();++i){
            double a=knots[i-1],b=knots[i],v[4];
            for(int j=0;j<4;++j)if(!at(a+(b-a)*(j/3.0),v[j]))return false;
            double d1=v[1]-v[0],d2=v[2]-v[0],d3=v[3]-v[0];
            staged.curve.push_back({a,b,{v[0],9*d1-4.5*d2+d3,-22.5*d1+18*d2-4.5*d3,13.5*d1-13.5*d2+4.5*d3}});
        }
        *this=std::move(staged);return true;
    }
    double volume(double y)const{
        if(y<=low)return 0;if(y>=high)return full;
        auto it=std::lower_bound(curve.begin(),curve.end(),y,[](const Segment &s,double value){return s.high<value;});
        if(it==curve.end())return full;double t=(y-it->low)/(it->high-it->low);const auto &c=it->polynomial;
        return std::clamp(((c[3]*t+c[2])*t+c[1])*t+c[0],0.0,full);
    }
    double head(double amount)const{
        if(amount<=0)return low;if(amount>=full)return high;
        double a=low,b=high;for(int i=0;i<28;++i){double m=(a+b)*.5;if(volume(m)<amount)a=m;else b=m;}return (a+b)*.5;
    }
    double capacity()const{return full;}
    double minimum()const{return low;}
    double maximum()const{return high;}
    // Merge vertical intervals before querying the field. Taking the minimum
    // of convex-piece distances alone leaves zero-valued artificial seams on
    // the internal triangulation and can split a continuous water surface.
    using Intervals=std::array<std::array<double,2>,C::MAX_PIECES>;
    size_t vertical_intervals(double x,double z,double head,Intervals &out)const{
        size_t count=0;
        for(const auto &h:hulls){double a=0,b=std::min(.5,head);bool valid=true;
            for(auto plane:h.planes){double room=plane.offset-plane.normal.x*x-plane.normal.z*z;
                if(std::abs(plane.normal.y)<1e-12){if(room< -1e-9){valid=false;break;}}
                else if(plane.normal.y>0)b=std::min(b,room/plane.normal.y);else a=std::max(a,room/plane.normal.y);}
            if(valid&&b>a+1e-10)out[count++]={a,b};
        }
        std::sort(out.begin(),out.begin()+count);size_t merged=0;
        for(size_t i=0;i<count;++i){double a=out[i][0],b=out[i][1];
            while(i+1<count&&out[i+1][0]<=b+1e-9)b=std::max(b,out[++i][1]);
            out[merged++]={a,b};}
        return merged;
    }
    // Negative inside water; same vertical-distance convention as terrain
    // contacts, retaining every interval instead of joining through an object.
    double distance(C::Point p,double head)const{
        Intervals spans;size_t count=vertical_intervals(std::clamp(p.x,0.0,.5),std::clamp(p.z,0.0,.5),head,spans);
        double nearest=1e30,horizontal=std::max(std::abs(p.x-.25)-.25,std::abs(p.z-.25)-.25);
        for(size_t i=0;i<count;++i)nearest=std::min(nearest,std::max({horizontal,spans[i][0]-p.y,p.y-spans[i][1]}));
        if(!count){
            // A column fully occupied by a post still needs a finite outside
            // value for interpolation; infinity would pull vertices to edges.
            for(const auto &h:hulls){double d=p.y-head;for(auto plane:h.planes)d=std::max(d,plane.normal.dot(p)-plane.offset);nearest=std::min(nearest,d);}
        }
        return std::min(nearest,.25);
    }
    bool interval(C::Point p,double head,double &bottom,double &top)const{
        Intervals spans;size_t count=vertical_intervals(p.x,p.z,head,spans);
        for(size_t i=0;i<count;++i)if(p.y>=spans[i][0]-1e-9&&p.y<=spans[i][1]+1e-9){bottom=spans[i][0];top=spans[i][1];return true;}
        return false;
    }
    size_t bytes()const{size_t n=sizeof(*this)+curve.capacity()*sizeof(Segment)+hulls.capacity()*sizeof(Hull);for(const auto &h:hulls)n+=h.planes.capacity()*sizeof(C::Plane);return n;}
};
}
