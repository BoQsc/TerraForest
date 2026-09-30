#include "experimental/density_ray.hpp"
#include <cstdio>
#include <cmath>
using namespace terraforest::experimental;
int main(){
 int id=0;
 for(double scale:{1e-9,1.,1e9})for(double offset:{1e-4,1e-8,1e-12,1e-14,1e-16,0.,-1e-16,-1e-14,-1e-12,-1e-8,-1e-4}){
  double c[4]={(.25+offset)*scale,-scale,scale,0};
  // Independent quadratic oracle in extended precision, using the actual
  // rounded double coefficients passed to the candidate (not ideal inputs).
  long double a=c[2],b=c[1],d=c[0],disc=b*b-4*a*d;
  bool expected=disc>=0;long double first=expected?(-b-std::sqrt(disc))/(2*a):-1;
  double root=-1;bool found=first_cubic_root(c,root);
  bool pass=found==expected&&(!found||std::abs(root-double(first))<1e-9);
  printf("{\"id\":%d,\"scale\":%.17g,\"offset\":%.17g,\"expected_hit\":%s,\"hit\":%s,\"expected_fraction\":%.17g,\"fraction\":%.17g,\"passed\":%s}\n",id++,scale,offset,expected?"true":"false",found?"true":"false",double(first),root,pass?"true":"false");
 }
 auto cubic_case=[&](double*c){
  double root=-1;bool found=first_cubic_root(c,root);
  printf("{\"id\":%d,\"kind\":\"cubic\",\"coefficients\":[%.17g,%.17g,%.17g,%.17g],\"hit\":%s,\"fraction\":%.17g}\n",id++,c[0],c[1],c[2],c[3],found?"true":"false",root);
 };
 for(double scale:{1e-9,1.,1e9})for(double offset:{1e-4,1e-8,1e-12,1e-14,1e-16,0.,-1e-16,-1e-14,-1e-12,-1e-8,-1e-4}){
  double c[4]={(.0625+.25*offset)*scale,offset*scale,-.75*scale,scale};cubic_case(c);
 }
 double rational_tangent[4]={2,-11,12,9};cubic_case(rational_tangent);
 return 0;
}
