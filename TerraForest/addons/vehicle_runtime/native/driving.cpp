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
Vector3 forward(RigidBody3D *body,Vector3 up){
    Vector3 value=body->get_global_transform().basis.get_column(2).slide(up);
    return value.length_squared()<.0001?Vector3(0,0,1):value.normalized();
}
}
void NativeDrivingPolicy::_bind_methods(){
    ClassDB::bind_method(D_METHOD("reset"),&NativeDrivingPolicy::reset);
    ClassDB::bind_method(D_METHOD("steering","input","speed","delta"),&NativeDrivingPolicy::steering);
    ClassDB::bind_method(D_METHOD("speed","previous","throttle","reverse_brake","parked","boost","delta"),&NativeDrivingPolicy::speed);
    ClassDB::bind_method(D_METHOD("apply_grounded","body","up","speed"),&NativeDrivingPolicy::apply_grounded);
    ClassDB::bind_method(D_METHOD("apply_free","body","up","throttle","reverse_brake","handbrake","parked","supported"),&NativeDrivingPolicy::apply_free);
    ClassDB::bind_method(D_METHOD("stabilize","body","up","supported","loaded_wheels"),&NativeDrivingPolicy::stabilize);
}
void NativeDrivingPolicy::reset(){fraction_=angle_=sign_=0;cap_=26*radians;}
double NativeDrivingPolicy::apply_grounded(RigidBody3D *body,Vector3 up,double speed) const {
    if(!body||!body->is_inside_tree()||!up.is_finite()||up.length_squared()<.0001||!std::isfinite(speed))return 0;
    up.normalize();Vector3 f=forward(body,up),side=up.cross(f);
    side=side.length_squared()<.0001?Vector3(1,0,0):side.normalized();
    double yaw=std::clamp(speed*std::tan(angle_)/2.726,-85*radians,85*radians);
    Vector3 linear=body->get_linear_velocity(),angular=body->get_angular_velocity();
    body->set_linear_velocity(f*real_t(speed)+side*real_t(yaw*1.2581)+up*linear.dot(up));
    body->set_angular_velocity(angular-up*angular.dot(up)+up*real_t(yaw));
    return yaw;
}
void NativeDrivingPolicy::apply_free(RigidBody3D *body,Vector3 up,double throttle,double reverse_brake,bool handbrake,bool parked,bool supported) const {
    if(!supported||!body||!body->is_inside_tree()||!up.is_finite()||up.length_squared()<.0001||!std::isfinite(throttle)||!std::isfinite(reverse_brake))return;
    up.normalize();Vector3 f=forward(body,up),v=body->get_linear_velocity();double longitudinal=v.dot(f);
    if(parked){if(v.length()>.1)body->apply_central_force(-v.normalized()*22000);return;}
    if(throttle>0&&reverse_brake>0){if(v.length()>.1)body->apply_central_force(-v.normalized()*22000);}
    else if(throttle>0){if(longitudinal<60)body->apply_central_force(f*real_t(12000*throttle));}
    else if(reverse_brake>0){
        if(longitudinal>1)body->apply_central_force(-f*real_t(22000*reverse_brake));
        else if(longitudinal>-15)body->apply_central_force(-f*real_t(7000*reverse_brake));
    }
    if(handbrake){v.y=0;if(v.length()>.1)body->apply_central_force(-v.normalized()*9500);}
}
double NativeDrivingPolicy::stabilize(RigidBody3D *body,Vector3 up,bool supported,int loaded_wheels) const {
    if(!body||!body->is_inside_tree()||!up.is_finite()||up.length_squared()<.0001)return 0;
    up.normalize();double roll=0;
    if(supported){
        auto basis=body->get_global_transform().basis;Vector3 side=basis.get_column(0).normalized(),f=basis.get_column(2).normalized(),angular=body->get_angular_velocity();
        double re=std::clamp(double(side.dot(up)),-1.0,1.0),pe=std::clamp(double(f.dot(up)),-1.0,1.0);
        roll=std::asin(re)/radians;
        double rt=std::clamp(-re*5200-angular.dot(f)*2500,-5200.0,5200.0);
        double pt=std::clamp(pe*1100-angular.dot(side)*1300,-2300.0,2300.0);
        body->apply_torque((f*real_t(rt)+side*real_t(pt)).slide(up));
    }
    Vector3 v=body->get_linear_velocity();v.y=0;double planar=v.length();
    if(loaded_wheels>=3&&planar>3)body->apply_central_force(Vector3(0,real_t(-std::min(planar*planar*.55,1450.0)),0));
    return roll;
}
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
