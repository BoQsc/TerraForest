// SPDX-License-Identifier: 0BSD
#include "road_profile.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <array>
#include <vector>
#include <cmath>
#include <algorithm>
namespace terraforest {
using namespace godot;
void NativeRoadProfile::_bind_methods(){ClassDB::bind_method(D_METHOD("fit","samples","max_grade","max_curvature","max_cut","max_fill"),&NativeRoadProfile::fit);}
namespace {
using Weights=std::array<double,65>;
struct Term{int i;double a;};
struct Constraint{std::vector<Term> terms;double lo,hi,norm=0;};
Dictionary failure(const char* reason){Dictionary d;d["ok"]=false;d["reason"]=reason;return d;}
void tangent(Weights &w,int i,int n,double amount,double h){
 // Flat entrance; one-sided exit; centered interior slopes. All are linear.
 if(i==0)return;
 if(i==n-1){w[i]+=amount/h;w[i-1]-=amount/h;}
 else {w[i+1]+=amount/(2*h);w[i-1]-=amount/(2*h);}
}
Weights basis(int i,int n,double h,double t,int derivative){
 Weights w{};double a,b,c,d;
 if(derivative==0){a=2*t*t*t-3*t*t+1;b=t*t*t-2*t*t+t;c=-2*t*t*t+3*t*t;d=t*t*t-t*t;}
 else if(derivative==1){a=(6*t*t-6*t)/h;b=3*t*t-4*t+1;c=(-6*t*t+6*t)/h;d=3*t*t-2*t;}
 else {a=(12*t-6)/(h*h);b=(6*t-4)/h;c=(-12*t+6)/(h*h);d=(6*t-2)/h;}
 w[i]=a;w[i+1]=c;tangent(w,i,n,b*(derivative==0?h:1),h);tangent(w,i+1,n,d*(derivative==0?h:1),h);return w;
}
double eval(const Weights&w,const std::vector<double>&y){double v=0;for(size_t i=0;i<y.size();++i)v+=w[i]*y[i];return v;}
}
Dictionary NativeRoadProfile::fit(const PackedVector3Array &samples,double grade,double curvature,double cut,double fill) const {
 int n=samples.size();
 if(n<3||n>65||!std::isfinite(grade)||!std::isfinite(curvature)||!std::isfinite(cut)||!std::isfinite(fill)||grade<=0||grade>.25||curvature<=0||curvature>.1||cut<0||cut>16||fill<0||fill>8)return failure("invalid_limits");
 Vector3 axis=samples[1]-samples[0];axis.y=0;double h=axis.length();
 if(!std::isfinite(h)||h<4||h>32)return failure("invalid_spacing");axis/=h;
 std::vector<double> y(n);
 for(int i=0;i<n;++i){auto p=samples[i];Vector3 expected=samples[0]+axis*real_t(i*h);expected.y=p.y;
  if(!p.is_finite()||p.y<8||p.y>230||p.distance_to(expected)>.01)return failure("requires_uniform_straight_samples");y[i]=p.y;}
 std::vector<Constraint> constraints;
 auto add=[&](const Weights&w,double lo,double hi){Constraint c;c.lo=lo;c.hi=hi;for(int i=0;i<n;++i)if(std::abs(w[i])>1e-15){c.terms.push_back({i,w[i]});c.norm+=w[i]*w[i];}if(c.norm>0)constraints.push_back(c);};
 Weights anchor{};anchor[0]=1;add(anchor,y[0],y[0]);
 for(int i=0;i<n-1;++i)for(int j=0;j<=8;++j){double t=j/8.0,ground=samples[i].y*(1-t)+samples[i+1].y*t;
  add(basis(i,n,h,t,0),ground-cut,ground+fill);
  // Reserve margin for derivative extrema between collocation points.
  // Analytic validation below still enforces the caller's full limits.
  add(basis(i,n,h,t,1),-grade*.999,grade*.999);
  if(j==0||j==8)add(basis(i,n,h,t,2),-curvature,curvature);
 }
 int iterations=0;double residual=0;
 for(;iterations<2048;++iterations){residual=0;
  for(const auto&c:constraints){double value=0;for(auto term:c.terms)value+=term.a*y[term.i];double error=value-std::clamp(value,c.lo,c.hi);residual=std::max(residual,std::abs(error));if(error!=0)for(auto term:c.terms)y[term.i]-=error*term.a/c.norm;}
  if(residual<1e-7)break;
 }
 // Analytic extrema validation: finite sample constraints alone cannot certify
 // an entire cubic. Fail without exposing a partial profile when not certified.
 double max_grade=0,max_curve=0,max_cut=0,max_fill=0;
 PackedFloat64Array coefficients;
 for(int i=0;i<n-1;++i){double d=y[i],c=eval(basis(i,n,h,0,1),y)*h,b=eval(basis(i,n,h,0,2),y)*h*h/2,a=y[i+1]-d-c-b;
  coefficients.push_back(a);coefficients.push_back(b);coefficients.push_back(c);coefficients.push_back(d);
  auto inspect=[&](double t){double value=((a*t+b)*t+c)*t+d,ground=samples[i].y*(1-t)+samples[i+1].y*t;max_cut=std::max(max_cut,ground-value);max_fill=std::max(max_fill,value-ground);max_grade=std::max(max_grade,std::abs((3*a*t*t+2*b*t+c)/h));max_curve=std::max(max_curve,std::abs((6*a*t+2*b)/(h*h)));};
  inspect(0);inspect(1);if(std::abs(a)>1e-14){double t=-b/(3*a);if(t>0&&t<1)inspect(t);}
  double linear=c-(samples[i+1].y-samples[i].y),disc=4*b*b-12*a*linear;
  if(std::abs(a)>1e-14&&disc>=0){for(double sign:{-1.0,1.0}){double t=(-2*b+sign*std::sqrt(disc))/(6*a);if(t>0&&t<1)inspect(t);}}
  else if(std::abs(b)>1e-14){double t=-linear/(2*b);if(t>0&&t<1)inspect(t);}
 }
 if(std::abs(y[0]-samples[0].y)>1e-5||max_grade>grade+1e-6||max_curve>curvature+1e-6||max_cut>cut+1e-5||max_fill>fill+1e-5){auto failed=failure("no_certified_profile_within_iteration_budget");failed["max_grade"]=max_grade;failed["max_curvature"]=max_curve;failed["max_cut"]=max_cut;failed["max_fill"]=max_fill;failed["residual"]=residual;return failed;}
 Dictionary result;result["ok"]=true;result["coefficients"]=coefficients;result["spacing"]=h;result["iterations"]=iterations;result["max_grade"]=max_grade;result["max_curvature"]=max_curve;result["max_cut"]=max_cut;result["max_fill"]=max_fill;return result;
}
}
