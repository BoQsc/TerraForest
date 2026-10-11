// SPDX-License-Identifier: 0BSD
// Standalone analytic oracle for successive old-density, height, new-density clips.
#include "../addons/volumetric_water/native/water_clip.hpp"
#include <algorithm>
#include <cstdio>
using namespace terraforest::water_clip;
constexpr int tets[6][4]={{0,1,3,7},{0,1,5,7},{0,2,3,7},{0,2,6,7},{0,4,5,7},{0,4,6,7}};
double measure(double cut,double height,double other,double ceiling,bool oblique=false){
    double result=0;
    for(auto &ids:tets){
        Tet input;for(int k=0;k<4;++k){int c=ids[k];double x=c&1,y=(c>>1)&1,z=(c>>2)&1;
            input[k]={x,y,z,x-cut,oblique?x+y+z-other:z-other};}
        std::array<Tet,3> a,b,c,d;
        int na=clip(input,a,true,0);
        for(int i=0;i<na;++i){int nb=clip(a[i],b,false,height);
            for(int j=0;j<nb;++j){int nc=clip_field(b[j],c,2,0);
                for(int k=0;k<nc;++k){int nd=clip(c[k],d,false,ceiling);
                    for(int l=0;l<nd;++l)result+=volume(d[l]);}}}
    }return result;
}
int main(){
    int checks=0,failures=0;double largest=0;
    auto check=[&](double actual,double expected){++checks;double error=std::abs(actual-expected);largest=std::max(largest,error);if(error>1e-12)++failures;};
    const double positions[]={-.2,0,.13,.5,.89,1,1.2};
    for(double x:positions)for(double y:positions)for(double z:positions)for(double ceiling:positions)
        check(measure(x,y,z,ceiling),(1-std::clamp(x,0.,1.))*std::clamp(std::min(y,ceiling),0.,1.)*(1-std::clamp(z,0.,1.)));
    // Analytic CDF of the sum of three independent uniform coordinates.
    for(int i=0;i<=60;++i){double t=i/20.;auto cube=[](double x){x=std::max(x,0.);return x*x*x;};
        double cdf=(cube(t)-3*cube(t-1)+3*cube(t-2)-cube(t-3))/6;
        check(measure(-1,2,t,2,true),1-cdf);}
    std::printf("WATER_CLIP_INTERSECTION checks=%d failures=%d max_error=%.17g\n",checks,failures,largest);
    return failures?1:0;
}
