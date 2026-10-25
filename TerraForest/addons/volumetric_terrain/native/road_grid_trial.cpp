#include "road_profile.hpp"
#include <algorithm>
#include <array>
#include <cmath>
#include <vector>

namespace terraforest {
using namespace godot;
namespace {
using Cubic=std::array<double,4>;
double height(const Cubic &curve,double position){return ((curve[0]*position+curve[1])*position+curve[2])*position+curve[3];}
double slope(const Cubic &curve,double position){return (3*curve[0]*position+2*curve[1])*position+curve[2];}
double smooth(double value){value=std::clamp(value,0.,1.);return value*value*(3-2*value);}
double smooth_derivative(double value){return value>0&&value<1?6*value*(1-value):0;}
double maximum_height(const Cubic &curve){
 double maximum=std::max(std::abs(height(curve,0)),std::abs(height(curve,1)));
 auto inspect=[&](double position){if(position>0&&position<1)maximum=std::max(maximum,std::abs(height(curve,position)));};
 double discriminant=4*curve[1]*curve[1]-12*curve[0]*curve[2];
 if(std::abs(curve[0])>1e-14&&discriminant>=0){
  for(double sign:{-1.,1.})inspect((-2*curve[1]+sign*std::sqrt(discriminant))/(6*curve[0]));
 }else if(std::abs(curve[1])>1e-14)inspect(-curve[2]/(2*curve[1]));
 return maximum;
}
double maximum_slope(const Cubic &curve){
 double maximum=std::max(std::abs(slope(curve,0)),std::abs(slope(curve,1)));
 if(std::abs(curve[0])>1e-14){double position=-curve[1]/(3*curve[0]);if(position>0&&position<1)maximum=std::max(maximum,std::abs(slope(curve,position)));}
 return maximum;
}
Cubic interval(const Cubic &curve,double start,double span){
 return {curve[0]*span*span*span,(3*curve[0]*start+curve[1])*span*span,slope(curve,start)*span,height(curve,start)};
}
Dictionary invalid(){Dictionary result;result["ok"]=false;result["reason"]="Invalid road-grid trial profile";return result;}
}
Dictionary NativeRoadProfile::grid_trial(const PackedFloat64Array &coefficients,double spacing) const {
 if(coefficients.is_empty()||coefficients.size()%4||coefficients.size()>256||!std::isfinite(spacing)||spacing<1||spacing>256)return invalid();
 int count=coefficients.size()/4;
 std::vector<Cubic> original(count);
 double original_grade=0;
 for(int section=0;section<count;++section){
  for(int component=0;component<4;++component){double value=coefficients[section*4+component];if(!std::isfinite(value)||std::abs(value)>4096)return invalid();original[section][component]=value;}
  original_grade=std::max(original_grade,maximum_slope(original[section])/spacing);
  if(section>0&&(std::abs(height(original[section-1],1)-height(original[section],0))>1e-4||std::abs(slope(original[section-1],1)-slope(original[section],0))>1e-3))return invalid();
 }
 int subdivisions=std::min({64/count,std::max(1,int(std::floor(spacing))),std::max(1,int(std::ceil(spacing/1.5)))});
 double step=spacing/subdivisions,length=spacing*count;
 double taper=std::min(6.,length*.25);
 auto evaluate=[&](int section,double position){
  double base=height(original[section],position),derivative=slope(original[section],position)/spacing;
  double phase=(base-std::floor(base)-.25)*2;
  double shifted=std::floor(base)+smooth(phase),shift_derivative=2*smooth_derivative(phase);
  double distance=(section+position)*spacing;
  double near=distance/taper,far=(length-distance)/taper;
  double blend=smooth(near)*smooth(far);
  double blend_derivative=(smooth_derivative(near)*smooth(far)-smooth(near)*smooth_derivative(far))/taper;
  return std::array<double,2>{base+blend*(shifted-base),derivative+blend*(shift_derivative-1)*derivative+blend_derivative*(shifted-base)};
 };
 std::vector<Cubic> baseline,proposal;
 for(int section=0;section<count;++section)for(int part=0;part<subdivisions;++part){
  double start=double(part)/subdivisions,finish=double(part+1)/subdivisions;
  auto first=evaluate(section,start),last=evaluate(section,finish);
  double delta=last[0]-first[0],first_slope=first[1]*step,last_slope=last[1]*step;
  proposal.push_back({-2*delta+first_slope+last_slope,3*delta-2*first_slope-last_slope,first_slope,first[0]});
  baseline.push_back(interval(original[section],start,1./subdivisions));
 }
 auto metrics=[&](double weight){
  std::array<double,2> maximum{};
  for(size_t section=0;section<baseline.size();++section){
   Cubic blended{},difference{};
   for(int component=0;component<4;++component){difference[component]=(proposal[section][component]-baseline[section][component])*weight;blended[component]=baseline[section][component]+difference[component];}
   maximum[0]=std::max(maximum[0],maximum_slope(blended)/step);
   maximum[1]=std::max(maximum[1],maximum_height(difference));
  }
  return maximum;
 };
 double weight=0;
 if(original_grade<=.16&&step<=4){
  double low=0,high=1;
  for(int iteration=0;iteration<32;++iteration){double candidate=(low+high)*.5;auto limits=metrics(candidate);if(limits[0]<=.16&&limits[1]<=.30)low=candidate;else high=candidate;}
  weight=low;
 }
 PackedFloat64Array result_coefficients;
 if(weight<.01){weight=0;subdivisions=1;result_coefficients=coefficients;}
 else for(size_t section=0;section<baseline.size();++section)for(int component=0;component<4;++component)result_coefficients.push_back(baseline[section][component]+weight*(proposal[section][component]-baseline[section][component]));
 auto limits=metrics(weight);
 Dictionary result;result["ok"]=true;result["coefficients"]=result_coefficients;result["subdivisions"]=subdivisions;result["weight"]=weight;result["max_grade"]=limits[0];result["max_shift"]=limits[1];result["version"]=1;return result;
}
}
