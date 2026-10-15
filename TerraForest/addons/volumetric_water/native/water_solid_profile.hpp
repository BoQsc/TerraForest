// SPDX-License-Identifier: 0BSD
#pragma once
#include "water_face_clip.hpp"
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
    std::array<std::vector<std::vector<WaterFaceClip::Point>>,6> faces;
    bool prepare_faces(){
        size_t total=0;
        for(auto &face:faces)face.clear();
        for(int axis=0;axis<3;++axis)for(int side=0;side<2;++side)for(const auto &h:hulls){
            auto polygon=WaterFaceClip::square();
            for(auto plane:h.planes){if(!WaterFaceClip::project(polygon,plane,axis,side))return false;if(polygon.count<3)break;}
            if(polygon.count<3||WaterFaceClip::area(polygon)<=1e-12)continue;
            total+=polygon.count;if(total>MAX_VERTICES)return false;
            faces[axis*2+side].emplace_back(polygon.points.begin(),polygon.points.begin()+polygon.count);
        }
        return true;
    }
public:
    bool prepare(const C::Pieces &pieces){
        if(pieces.size()>C::MAX_PIECES)return false;
        WaterSolidProfile staged;std::vector<double> knots;size_t vertices=0;
        // Roundoff can leave almost-flat fragments with fewer than four
        // independent faces. Their total possible volume is below .001 ml per
        // cell; do not cache unbounded pseudo-hulls from these fragments.
        C::Pieces stable;for(const auto &piece:pieces)if(C::volume(piece)>1e-12)stable.push_back(piece);
        for(const auto &piece:stable){
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
            if(hull.planes.size()<4)return false;staged.hulls.push_back(std::move(hull));
        }
        if(knots.empty()){*this=std::move(staged);return true;}
        std::sort(knots.begin(),knots.end());
        knots.erase(std::unique(knots.begin(),knots.end(),[](double a,double b){return b-a<1e-9;}),knots.end());
        if(knots.size()>MAX_KNOTS)return false;
        staged.low=knots.front();staged.high=knots.back();staged.full=C::volume(stable);
        if(!std::isfinite(staged.full)||staged.full>.125+1e-9)return false;
        auto fit=[](double a,double b,const double *v){
            double d1=v[1]-v[0],d2=v[2]-v[0],d3=v[3]-v[0];
            return Segment{a,b,{v[0],9*d1-4.5*d2+d3,-22.5*d1+18*d2-4.5*d3,13.5*d1-13.5*d2+4.5*d3}};
        };
        // Each convex fragment is cubic between its own vertex heights. Fit
        // it once there, rather than clipping it at every other fragment's
        // heights too. Combining these curves preserves the same cell knots.
        struct PieceCurve {double bottom,top,full;std::vector<Segment> segments;};
        std::vector<PieceCurve> curves;curves.reserve(stable.size());
        for(const auto &piece:stable){
            std::vector<double> heights;
            for(const auto &face:piece.faces)for(auto p:face)heights.push_back(std::clamp(p.y,0.0,.5));
            std::sort(heights.begin(),heights.end());
            heights.erase(std::unique(heights.begin(),heights.end(),[](double a,double b){return b-a<1e-9;}),heights.end());
            if(heights.size()<2||heights.size()>MAX_KNOTS)return false;
            PieceCurve curve{heights.front(),heights.back(),C::volume(piece),{}};
            double previous=0;
            for(size_t i=1;i<heights.size();++i){double a=heights[i-1],b=heights[i],v[4]={previous,0,0,0};
                for(int j=1;j<4;++j){double y=a+(b-a)*(j/3.0);
                    if(y>=curve.top){v[j]=curve.full;continue;}
                    C::Polyhedron cut;if(!C::clip(piece,{{0,1,0},y},cut))return false;
                    v[j]=C::volume(cut);if(!std::isfinite(v[j]))return false;}
                curve.segments.push_back(fit(a,b,v));previous=v[3];
            }
            curves.push_back(std::move(curve));
        }
        auto at=[&](double y){double v=0;
            for(const auto &piece:curves){
                if(y<=piece.bottom)continue;if(y>=piece.top){v+=piece.full;continue;}
                auto it=std::lower_bound(piece.segments.begin(),piece.segments.end(),y,[](const Segment &s,double value){return s.high<value;});
                if(it==piece.segments.end()){v+=piece.full;continue;}
                double t=(y-it->low)/(it->high-it->low);const auto &c=it->polynomial;
                v+=std::clamp(((c[3]*t+c[2])*t+c[1])*t+c[0],0.0,piece.full);
            }
            return v;
        };
        for(size_t i=1;i<knots.size();++i){
            double a=knots[i-1],b=knots[i],v[4];
            for(int j=0;j<4;++j){v[j]=at(a+(b-a)*(j/3.0));if(!std::isfinite(v[j]))return false;}
            staged.curve.push_back(fit(a,b,v));
        }
        if(!staged.prepare_faces())return false;*this=std::move(staged);return true;
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
    template<class Emit> bool visit_face(int axis,int side,double head,Emit emit)const{
        for(const auto &points:faces[axis*2+side]){WaterFaceClip::Polygon p;p.count=points.size();std::copy(points.begin(),points.end(),p.points.begin());
            if(!WaterFaceClip::wet(p,axis,side,head))continue;
            if(p.count>=3&&WaterFaceClip::area(p)>1e-12&&emit(p))return true;}
        return false;
    }
    size_t encoded_size()const{size_t n=5+curve.size()*6;for(const auto &h:hulls)n+=1+h.planes.size()*4;return n;}
    std::vector<double> encode()const{
        std::vector<double> out{full,low,high,double(curve.size()),double(hulls.size())};
        for(const auto &s:curve){out.push_back(s.low);out.push_back(s.high);for(auto c:s.polynomial)out.push_back(c);}
        for(const auto &h:hulls){out.push_back(double(h.planes.size()));for(auto p:h.planes){out.push_back(p.normal.x);out.push_back(p.normal.y);out.push_back(p.normal.z);out.push_back(p.offset);}}
        return out;
    }
    bool decode(const std::vector<double> &data){
        if(data.size()<5||data.size()>131072)return false;
        for(double v:data)if(!std::isfinite(v))return false;
        auto integer=[](double v,size_t max){return v>=0&&v<=max&&v==std::floor(v);};
        if(!integer(data[3],MAX_KNOTS)||!integer(data[4],C::MAX_PIECES)||data[0]<0||data[0]>.125+1e-9||data[1]<0||data[2]>.5||data[1]>data[2])return false;
        WaterSolidProfile staged;staged.full=data[0];staged.low=data[1];staged.high=data[2];size_t at=5;
        double previous_y=staged.low,previous_v=0;
        for(size_t i=0;i<size_t(data[3]);++i){
            if(at+6>data.size())return false;
            Segment seg{data[at],data[at+1],{data[at+2],data[at+3],data[at+4],data[at+5]}};at+=6;
            if(std::abs(seg.low-previous_y)>1e-9||seg.high<=seg.low||seg.high>staged.high+1e-9||std::abs(seg.polynomial[0]-previous_v)>1e-9)return false;
            auto c=seg.polynomial;for(auto value:c)if(std::abs(value)>4)return false;
            auto derivative=[&](double t){return c[1]+2*c[2]*t+3*c[3]*t*t;};
            if(derivative(0)<-1e-9||derivative(1)<-1e-9)return false;
            if(std::abs(c[3])>1e-15){double t=-c[2]/(3*c[3]);if(t>0&&t<1&&derivative(t)<-1e-9)return false;}
            previous_y=seg.high;previous_v=c[0]+c[1]+c[2]+c[3];
            if(previous_v< -1e-9||previous_v>staged.full+1e-9)return false;staged.curve.push_back(seg);
        }
        if(std::abs(previous_y-staged.high)>1e-9||std::abs(previous_v-staged.full)>1e-9)return false;
        size_t plane_total=0;
        for(size_t i=0;i<size_t(data[4]);++i){
            if(at>=data.size()||!integer(data[at],C::MAX_FACES))return false;size_t count=size_t(data[at++]);
            if(count<4||at+4*count>data.size()||(plane_total+=count)>MAX_VERTICES)return false;Hull hull;
            for(size_t j=0;j<count;++j){C::Plane p{{data[at],data[at+1],data[at+2]},data[at+3]};at+=4;
                if(std::abs(p.normal.dot(p.normal)-1)>1e-6||std::abs(p.offset)>2)return false;hull.planes.push_back(p);}
            staged.hulls.push_back(std::move(hull));
        }
        if(at!=data.size()||(staged.full>0&&(staged.curve.empty()||staged.hulls.empty())))return false;
        if(!staged.prepare_faces())return false;*this=std::move(staged);return true;
    }
    size_t bytes()const{size_t n=sizeof(*this)+curve.capacity()*sizeof(Segment)+hulls.capacity()*sizeof(Hull);for(const auto &h:hulls)n+=h.planes.capacity()*sizeof(C::Plane);for(const auto &face:faces){n+=face.capacity()*sizeof(std::vector<WaterFaceClip::Point>);for(const auto &p:face)n+=p.capacity()*sizeof(WaterFaceClip::Point);}return n;}
};
}
