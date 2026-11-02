// SPDX-License-Identifier: 0BSD
#include "zombie_hit_reaction.hpp"
#include <godot_cpp/classes/skeleton3d.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <algorithm>
#include <cmath>
using namespace godot;
namespace terraforest {
void NativeZombieHitReaction::_bind_methods(){
    ClassDB::bind_method(D_METHOD("configure","parts"),&NativeZombieHitReaction::configure);
    ClassDB::bind_method(D_METHOD("hit","part","point","impulse","damage"),&NativeZombieHitReaction::hit);
    ClassDB::bind_method(D_METHOD("clear"),&NativeZombieHitReaction::clear);
    ClassDB::bind_method(D_METHOD("statistics"),&NativeZombieHitReaction::statistics);
}
bool NativeZombieHitReaction::configure(const Dictionary &parts){
    auto skeleton=get_skeleton();if(!skeleton||parts.size()!=14||configured)return false;
    std::array<Joint,14> next;const auto keys=parts.keys();
    for(int index=0;index<14;++index){
        if(keys[index].get_type()!=Variant::STRING||parts[keys[index]].get_type()!=Variant::DICTIONARY)return false;
        const Dictionary spec=parts[keys[index]];
        if(!spec.has("bone")||spec["bone"].get_type()!=Variant::STRING)return false;
        next[index].bone=skeleton->find_bone(spec["bone"]);next[index].part=keys[index];
        if(next[index].bone<0)return false;
    }
    joints=next;configured=true;clear();return true;
}
void NativeZombieHitReaction::clear(){
    for(auto &joint:joints){joint.angle=Vector3();joint.velocity=Vector3();}
    set_active(false);
}
void NativeZombieHitReaction::impulse(Joint &joint,Vector3 point,Vector3 force,double strength){
    auto skeleton=get_skeleton();const Transform3D pose=skeleton->get_global_transform()*skeleton->get_bone_global_pose(joint.bone);
    Vector3 axis=(point-pose.origin).limit_length(.6).cross(force);
    if(axis.length_squared()<.001)axis=Vector3(0,1,0).cross(force)*.2;
    axis=pose.basis.orthonormalized().inverse().xform(axis);
    joint.velocity=(joint.velocity+axis*strength).limit_length(8);
}
bool NativeZombieHitReaction::hit(const String &part,Vector3 point,Vector3 force,double damage){
    if(!configured||!get_skeleton()||!point.is_finite()||!force.is_finite()||!std::isfinite(damage)||damage<=0||force.length_squared()<.0001)return false;
    const auto found=std::find_if(joints.begin(),joints.end(),[&part](const Joint &joint){return joint.part==part;});
    if(found==joints.end())return false;
    force=force.limit_length(4);const double strength=std::clamp(damage/20.0,.5,2.5)*5;
    impulse(*found,point,force,strength);
    if(part!="torso")for(auto &joint:joints)if(joint.part=="torso")impulse(joint,point,force,strength*.3);
    set_active(true);return true;
}
void NativeZombieHitReaction::_process_modification_with_delta(double delta){
    auto skeleton=get_skeleton();if(!configured||!skeleton||!std::isfinite(delta)||delta<0)return;
    const double step=std::min(delta,.25),decay=std::exp(-8*step),frequency=std::sqrt(192.0);
    const double cosine=std::cos(frequency*step),sine=std::sin(frequency*step);
    bool moving=false;
    for(auto &joint:joints){
        const Vector3 initial=joint.angle,velocity=joint.velocity;
        joint.angle=(initial*cosine+(velocity+initial*8)*(sine/frequency))*decay;
        joint.velocity=(velocity*cosine-(velocity*8+initial*256)*(sine/frequency))*decay;
        joint.angle=joint.angle.limit_length(.48);
        if(joint.angle.length_squared()+joint.velocity.length_squared()<.000001){joint.angle=Vector3();joint.velocity=Vector3();continue;}
        moving=true;const double angle=joint.angle.length();
        if(angle>.000001)skeleton->set_bone_pose_rotation(joint.bone,(skeleton->get_bone_pose_rotation(joint.bone)*Quaternion(joint.angle/angle,angle)).normalized());
    }
    if(!moving)set_active(false);
}
Dictionary NativeZombieHitReaction::statistics()const{
    Dictionary result;double angle=0,energy=0;
    for(const auto &joint:joints){angle=std::max(angle,double(joint.angle.length()));energy+=joint.angle.length_squared()+joint.velocity.length_squared();}
    result["configured"]=configured;result["active"]=is_active();result["maximum_angle"]=angle;result["energy"]=energy;result["joints"]=14;return result;
}
}
