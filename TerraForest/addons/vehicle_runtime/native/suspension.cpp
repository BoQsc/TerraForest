// SPDX-License-Identifier: 0BSD
#include "suspension.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <algorithm>
#include <cmath>
using namespace godot;
namespace terraforest {
void NativeVehicleSuspension::_bind_methods(){
    ClassDB::bind_method(D_METHOD("configure_gravity","acceleration"),&NativeVehicleSuspension::configure_gravity);
    ClassDB::bind_method(D_METHOD("sample_and_apply","body","rays"),&NativeVehicleSuspension::sample_and_apply);
}
bool NativeVehicleSuspension::configure_gravity(double acceleration){
    if(!std::isfinite(acceleration)||acceleration<=0||acceleration>100)return false;
    spring_scale=acceleration/9.8;damping_scale=std::sqrt(spring_scale);return true;
}
PackedFloat32Array NativeVehicleSuspension::sample_and_apply(RigidBody3D *body,const TypedArray<RayCast3D> &rays) const {
    PackedFloat32Array result;
    if(!body||!body->is_inside_tree()||rays.size()!=4)return result;
    RayCast3D *wheel[4];
    for(int i=0;i<4;i++){wheel[i]=Object::cast_to<RayCast3D>(rays[i]);if(!wheel[i]||!wheel[i]->is_inside_tree())return result;}
    result.resize(40);float *data=result.ptrw();
    Vector3 center=body->get_global_transform().xform(body->get_center_of_mass());
    for(int i=0;i<4;i++){
        auto *ray=wheel[i];ray->force_raycast_update();
        Vector3 down=-ray->get_global_transform().basis.get_column(1).normalized();
        Vector3 point=ray->get_global_position()+down*.906,normal(0,1,0);
        double length=.44,force=0;bool contact=ray->is_colliding(),loaded=false;
        if(contact){
            point=ray->get_collision_point();normal=ray->get_collision_normal();
            normal=normal.length_squared()<.0001?Vector3(0,1,0):normal.normalized();
            length=std::clamp(double((point-ray->get_global_position()).dot(down))-.466,.16,.44);
            double compression=.30-length;loaded=compression>.006;
            Vector3 velocity=body->get_linear_velocity()+body->get_angular_velocity().cross(point-center);
            double normal_speed=velocity.dot(normal);
            force=std::clamp(std::max(compression,0.0)*45000*spring_scale-normal_speed*(normal_speed<0?6200:7600)*damping_scale,0.0,12000.0*spring_scale);
            body->apply_force(normal*real_t(force),point-body->get_global_position());
        }
        float *row=data+i*10;row[0]=contact?1:0;row[1]=loaded?1:0;row[2]=float(length);row[3]=float(force);
        for(int axis=0;axis<3;axis++){row[4+axis]=point[axis];row[7+axis]=normal[axis];}
    }
    return result;
}
}
