// SPDX-License-Identifier: 0BSD
// Port of the user's Vehicle Driving Test steering and longitudinal policy.
#include "driving.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <algorithm>
#include <cmath>
using namespace godot;
namespace terraforest {
namespace {
constexpr double radians=0.017453292519943295;
double toward(double a,double b,double step){return a+std::clamp(b-a,-step,step);}
double sign(double x){return x>0?1:(x<0?-1:0);}
bool zero(double x){return std::abs(x)<0.00001;}
}
void NativeDrivingPolicy::_bind_methods(){
    ClassDB::bind_method(D_METHOD("reset"),&NativeDrivingPolicy::reset);
    ClassDB::bind_method(D_METHOD("steering","input","speed","delta"),&NativeDrivingPolicy::steering);
    ClassDB::bind_method(D_METHOD("speed","previous","throttle","reverse_brake","parked","boost","delta"),&NativeDrivingPolicy::speed);
}
void NativeDrivingPolicy::reset(){fraction_=angle_=sign_=0;cap_=26*radians;}
Vector3 NativeDrivingPolicy::steering(double input,double speed,double delta){
    if(!std::isfinite(input)||!std::isfinite(speed)||!std::isfinite(delta)||delta<=0||delta>0.1)return Vector3(angle_,cap_,fraction_);
    input=std::clamp(input,-1.0,1.0);speed=std::abs(speed);
    double instantaneous=speed<1?26*radians:std::min(26*radians,std::atan(13*2.726/std::max(speed*speed,1.0)));
    double input_sign=sign(input);
    if(zero(input)){sign_=0;cap_=instantaneous;}
    else if(zero(sign_)||input_sign!=sign_){sign_=input_sign;cap_=instantaneous;}
    else if(instantaneous<cap_)cap_=instantaneous;
    else cap_=toward(cap_,instantaneous,9*radians*delta);
    double rate=zero(input)?5.25:(!zero(fraction_)&&sign(fraction_)!=input_sign?5.0:4.25);
    fraction_=toward(fraction_,input,rate*delta);
    angle_=toward(angle_,fraction_*cap_,120*radians*delta);
    if(std::abs(angle_)<0.00005)angle_=0;
    return Vector3(angle_,cap_,fraction_);
}
Vector2 NativeDrivingPolicy::speed(double previous,double throttle,double reverse_brake,bool parked,double boost,double delta) const {
    if(!std::isfinite(previous)||!std::isfinite(throttle)||!std::isfinite(reverse_brake)||!std::isfinite(boost)||!std::isfinite(delta)||delta<=0||delta>0.1)return Vector2(std::isfinite(previous)?previous:0,0);
    boost=std::clamp(boost,0.0,1.0);double v=previous,acceleration=0,limit=55+17*boost;
    if(parked)return Vector2(toward(v,0,18*delta),0);
    if(throttle>0&&reverse_brake>0)return Vector2(toward(v,0,14*delta),0);
    if(throttle>0){
        if(v<-.4)v=toward(v,0,14*delta);
        else {
            double ratio=std::clamp(std::max(v,0.0)/std::max(limit,.001),0.0,1.0);
            acceleration=(8.8+(1.7-8.8)*ratio)*(1-ratio)*(1+.42*boost);
            double lateral=v*v*std::abs(std::tan(angle_)/2.726);
            acceleration=std::min(acceleration,std::sqrt(std::max(13.5*13.5-lateral*lateral,0.0)));
            v=std::min(v+acceleration*delta,limit);
        }
    } else if(reverse_brake>0){
        if(v>.4)v=toward(v,0,14*delta);
        else {double ratio=std::clamp(std::abs(v)/15,0.0,1.0);acceleration=-5.8*(1-ratio);v=std::max(v+acceleration*delta,-15.0);}
    } else v=toward(v,0,1.45*delta);
    return Vector2(v,acceleration);
}
}
