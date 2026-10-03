// SPDX-License-Identifier: 0BSD
#include "accessories.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <algorithm>
#include <cmath>
using namespace godot;
namespace terraforest {
void NativeVehicleAccessories::_bind_methods(){
    ClassDB::bind_method(D_METHOD("configure","nodes","profiles"),&NativeVehicleAccessories::configure);
    ClassDB::bind_method(D_METHOD("reset","velocity","angular"),&NativeVehicleAccessories::reset);
    ClassDB::bind_method(D_METHOD("step","basis","velocity","angular","delta","enabled","strength"),&NativeVehicleAccessories::step);
}
bool NativeVehicleAccessories::configure(TypedArray<Node3D> nodes,PackedFloat32Array profiles){
    if(nodes.size()!=profiles.size()||nodes.size()>256)return false;
    std::vector<Mount> staged;staged.reserve(nodes.size());
    for(int i=0;i<nodes.size();++i){
        Node3D *node=Object::cast_to<Node3D>(nodes[i]);double profile=profiles[i];
        if(!node||!std::isfinite(profile)||profile<0)return false;
        double softness=std::clamp(profile,0.0,1.0),pk=62-28*softness,rk=56-28*softness;
        staged.push_back({node->get_instance_id(),node->get_transform(),{},{},{},{},profile,pk,1.75*std::sqrt(pk),rk,1.70*std::sqrt(rk)});
    }
    mounts.swap(staged);initialized=false;disabled=false;return true;
}
void NativeVehicleAccessories::reset(Vector3 velocity,Vector3 angular){
    for(auto &m:mounts){
        auto *node=Object::cast_to<Node3D>(ObjectDB::get_instance(m.id));
        if(node)node->set_transform(m.base);
        m.p=m.pv=m.r=m.rv=Vector3();
    }
    previous_v=velocity;previous_w=angular;initialized=true;
}
void NativeVehicleAccessories::step(Basis basis,Vector3 velocity,Vector3 angular,double delta,bool enabled,double strength){
    if(!basis.is_finite()||std::abs(basis.determinant())<1e-12||!velocity.is_finite()||!angular.is_finite()||!std::isfinite(delta)||delta<=0||delta>.1||!std::isfinite(strength)||strength<0)return;
    if(!enabled){if(!disabled)reset(velocity,angular);disabled=true;previous_v=velocity;previous_w=angular;return;}
    disabled=false;
    if(!initialized){reset(velocity,angular);return;}
    double dt=std::max(delta,.0001);Basis inverse=basis.inverse();
    Vector3 a=inverse.xform((velocity-previous_v)/real_t(dt)),w=inverse.xform((angular-previous_w)/real_t(dt));
    previous_v=velocity;previous_w=angular;
    a=a.clamp(Vector3(-18,-24,-18),Vector3(18,24,18));w=w.clamp(Vector3(-8,-8,-8),Vector3(8,8,8));
    for(auto &m:mounts){
        auto *node=Object::cast_to<Node3D>(ObjectDB::get_instance(m.id));if(!node)continue;
        real_t profile=real_t(m.profile*strength);
        Vector3 tp=Vector3(-a.x*.0017,-a.y*.00065,-a.z*.0016)*profile;
        tp=tp.clamp(Vector3(-.032,-.014,-.030)*profile,Vector3(.032,.014,.030)*profile);
        Vector3 tr=Vector3(a.z*.0028,-w.y*.010,-a.x*.0030)*profile;
        tr=tr.clamp(Vector3(-.075,-.055,-.080)*profile,Vector3(.075,.055,.080)*profile);
        m.pv+=((tp-m.p)*real_t(m.pk)-m.pv*real_t(m.pd))*real_t(dt);m.p+=m.pv*real_t(dt);
        m.rv+=((tr-m.r)*real_t(m.rk)-m.rv*real_t(m.rd))*real_t(dt);m.r+=m.rv*real_t(dt);
        node->set_transform(Transform3D(Basis::from_euler(m.r)*m.base.basis,m.base.origin+m.p));
    }
}
}
