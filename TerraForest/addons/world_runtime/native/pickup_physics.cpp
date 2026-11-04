// SPDX-License-Identifier: 0BSD
#include "pickup_physics.hpp"
#include <godot_cpp/classes/physics_server3d.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/aabb.hpp>
#include <cmath>
#include <cstring>
#include <set>
namespace terraforest {
using namespace godot;
void NativePickupPhysics::_bind_methods(){
    ClassDB::bind_method(D_METHOD("configure","space","exclude","transform"),&NativePickupPhysics::configure);
    ClassDB::bind_method(D_METHOD("bind_store","batch","store"),&NativePickupPhysics::bind_store);
    ClassDB::bind_method(D_METHOD("set_layout","batch","half_extents","offset"),&NativePickupPhysics::set_layout);
    ClassDB::bind_method(D_METHOD("can_launch"),&NativePickupPhysics::can_launch);
    ClassDB::bind_method(D_METHOD("launch","batch","handle","velocity"),&NativePickupPhysics::launch);
    ClassDB::bind_method(D_METHOD("forget","batch","identity"),&NativePickupPhysics::forget);
    ClassDB::bind_method(D_METHOD("reset"),&NativePickupPhysics::reset);
    ClassDB::bind_method(D_METHOD("step","delta","run","ready"),&NativePickupPhysics::step);
    ClassDB::bind_method(D_METHOD("statistics"),&NativePickupPhysics::statistics);
    ClassDB::bind_method(D_METHOD("capture_storage_snapshot"),&NativePickupPhysics::capture_storage_snapshot);
    ClassDB::bind_method(D_METHOD("validate_snapshot","bytes"),&NativePickupPhysics::validate_snapshot);
    ClassDB::bind_method(D_METHOD("restore_storage_snapshot","bytes"),&NativePickupPhysics::restore_storage_snapshot);
}
NativePickupPhysics::~NativePickupPhysics(){
    reset();auto *server=PhysicsServer3D::get_singleton();
    if(server){if(shape.is_valid())server->free_rid(shape);for(const auto &entry:layouts)if(entry.second.shape.is_valid())server->free_rid(entry.second.shape);}
}
NativePickupPhysics::Layout NativePickupPhysics::layout_for(int batch)const{
    auto found=layouts.find(batch);return found==layouts.end()?Layout():found->second;
}
bool NativePickupPhysics::set_layout(int batch,const Vector3 &half,const Vector3 &offset){
    if(!stores.count(batch)||!half.is_finite()||!offset.is_finite()||half.x<.01||half.y<.01||half.z<.01||half.x>16||half.y>16||half.z>16)return false;
    const Layout old=layout_for(batch);if(old.half==half&&old.offset==offset)return true;
    auto *server=PhysicsServer3D::get_singleton();Layout next;next.half=half;next.offset=offset;
    next.shape=server->box_shape_create();if(!next.shape.is_valid())return false;
    server->shape_set_data(next.shape,half);
    for(auto &motion:records)if(motion.identity&&motion.batch==batch&&motion.body.is_valid()){
        auto store=stores.at(batch);
        if(!motion.suspended){
            Transform3D pose=server->body_get_state(motion.body,PhysicsServer3D::BODY_STATE_TRANSFORM);
            store->set_position(motion.handle,world.affine_inverse().xform(pose.origin)-old.offset);
            Vector3 velocity=server->body_get_state(motion.body,PhysicsServer3D::BODY_STATE_LINEAR_VELOCITY);
            motion.sleeping=server->body_get_state(motion.body,PhysicsServer3D::BODY_STATE_SLEEPING);
            motion.velocity=motion.sleeping?Vector3():velocity.limit_length(64);store->set_velocity(motion.handle,motion.velocity);
        }
        server->body_set_mode(motion.body,PhysicsServer3D::BODY_MODE_STATIC);motion.suspended=true;
        motion.sleeping=false; // A resized body must recheck contacts when resumed.
        server->body_set_shape(motion.body,0,next.shape);
        server->body_set_state(motion.body,PhysicsServer3D::BODY_STATE_TRANSFORM,Transform3D(Basis(),world.xform(store->get_position(motion.handle)+offset)));
    }
    layouts[batch]=next;if(old.shape.is_valid())server->free_rid(old.shape);return true;
}
bool NativePickupPhysics::configure(RID physics_space,RID exclude,const Transform3D &transform){
    if(space.is_valid()||!physics_space.is_valid()||!transform.is_finite()||std::abs(transform.basis.determinant())<.001)return false;
    space=physics_space;excluded=exclude;world=transform;
    auto *server=PhysicsServer3D::get_singleton();shape=server->box_shape_create();
    server->shape_set_data(shape,Vector3(.17,.17,.17));return shape.is_valid();
}
bool NativePickupPhysics::bind_store(int batch,const Ref<NativeEntityStore> &store){
    if(batch<0||store.is_null()||stores.count(batch))return false;
    stores.emplace(batch,store);return true;
}
void NativePickupPhysics::release(Motion &motion){
    if(motion.body.is_valid()&&PhysicsServer3D::get_singleton())PhysicsServer3D::get_singleton()->free_rid(motion.body);
    motion=Motion();
}
void NativePickupPhysics::reset(){for(auto &motion:records)release(motion);}
int NativePickupPhysics::available()const{
    for(int i=0;i<LIMIT;++i)if(!records[i].identity)return i;
    // Resting pickups retain their position; retire a sleeping proxy if full.
    for(int i=0;i<LIMIT;++i)if(records[i].sleeping)return i;
    return -1;
}
bool NativePickupPhysics::can_launch()const{return space.is_valid()&&available()>=0;}
bool NativePickupPhysics::create_body(Motion &motion){
    auto found=stores.find(motion.batch);if(found==stores.end()||!space.is_valid())return false;
    auto store=found->second;motion.handle=store->resolve_identity(motion.identity);
    if(!motion.handle)return false;
    auto *server=PhysicsServer3D::get_singleton();motion.body=server->body_create();
    if(!motion.body.is_valid())return false;
    server->body_set_mode(motion.body,PhysicsServer3D::BODY_MODE_STATIC);
    const Layout layout=layout_for(motion.batch);
    server->body_add_shape(motion.body,layout.shape.is_valid()?layout.shape:shape);
    server->body_set_collision_layer(motion.body,1u<<21);
    server->body_set_collision_mask(motion.body,7|(1u<<21));
    server->body_set_param(motion.body,PhysicsServer3D::BODY_PARAM_MASS,.25);
    server->body_set_param(motion.body,PhysicsServer3D::BODY_PARAM_BOUNCE,.22);
    server->body_set_param(motion.body,PhysicsServer3D::BODY_PARAM_FRICTION,.8);
    server->body_set_param(motion.body,PhysicsServer3D::BODY_PARAM_LINEAR_DAMP,.4);
    server->body_set_enable_continuous_collision_detection(motion.body,true);
    if(excluded.is_valid())server->body_add_collision_exception(motion.body,excluded);
    server->body_set_state(motion.body,PhysicsServer3D::BODY_STATE_TRANSFORM,Transform3D(Basis(),world.xform(store->get_position(motion.handle)+layout.offset)));
    server->body_set_space(motion.body,space);motion.suspended=true;return true;
}
bool NativePickupPhysics::launch(int batch,int64_t handle,const Vector3 &velocity){
    auto found=stores.find(batch);int slot=available();
    if(slot<0||!space.is_valid()||found==stores.end()||!found->second->contains(handle)||!velocity.is_finite()||velocity.length()>64)return false;
    const int64_t identity=found->second->persistent_id(handle);
    for(const auto &record:records)if(record.identity==identity&&record.batch==batch)return false;
    Motion next;next.batch=batch;next.identity=identity;next.velocity=velocity;
    if(!create_body(next))return false;
    release(records[slot]);records[slot]=next;found->second->set_velocity(handle,velocity);return true;
}
void NativePickupPhysics::forget(int batch,int64_t identity){
    for(auto &motion:records)if(motion.identity==identity&&motion.batch==batch){release(motion);return;}
}
Dictionary NativePickupPhysics::step(double delta,bool run,const Callable &ready){
    Dictionary out;out["ok"]=false;out["changed"]=false;
    if(!std::isfinite(delta)||delta<=0||delta>.1||!ready.is_valid())return out;
    auto *server=PhysicsServer3D::get_singleton();bool changed=false;int simulated=0,suspended=0;
    for(auto &motion:records){
        if(!motion.identity)continue;
        auto store=stores.at(motion.batch);
        const Layout layout=layout_for(motion.batch);
        if(!store->resolve_identity(motion.identity)){release(motion);changed=true;continue;}
        if(!motion.body.is_valid()&&!create_body(motion)){release(motion);changed=true;continue;}
        Vector3 position=store->get_position(motion.handle);
        if(!motion.suspended){
            Transform3D pose=server->body_get_state(motion.body,PhysicsServer3D::BODY_STATE_TRANSFORM);
            Vector3 next=world.affine_inverse().xform(pose.origin)-layout.offset;
            Vector3 velocity=server->body_get_state(motion.body,PhysicsServer3D::BODY_STATE_LINEAR_VELOCITY);
            bool sleeping=server->body_get_state(motion.body,PhysicsServer3D::BODY_STATE_SLEEPING);
            if(next.is_finite()&&velocity.is_finite()){
                if(velocity.length_squared()>4096)server->body_set_state(motion.body,PhysicsServer3D::BODY_STATE_LINEAR_VELOCITY,velocity.limit_length(64));
                velocity=velocity.limit_length(64);
                changed=changed||position.distance_squared_to(next)>1e-10||motion.velocity!=velocity||motion.sleeping!=sleeping;
                position=next;motion.velocity=sleeping?Vector3():velocity;motion.sleeping=sleeping;
                store->set_position(motion.handle,position);store->set_velocity(motion.handle,motion.velocity);
            }
        }
        Vector3 origin=world.xform(position+layout.offset);
        Vector3 end=origin+motion.velocity*real_t(delta)+Vector3(0,-20*delta*delta,0);
        const Vector3 extent=layout.half+Vector3(.23,.23,.23);
        AABB bounds(origin.min(end)-extent,origin.max(end)-origin.min(end)+extent*2);
        bool allowed=run&&bool(ready.call(bounds));
        if(!allowed){
            if(!motion.suspended)server->body_set_mode(motion.body,PhysicsServer3D::BODY_MODE_STATIC);
            motion.suspended=true;++suspended;continue;
        }
        if(motion.suspended){
            server->body_set_mode(motion.body,PhysicsServer3D::BODY_MODE_RIGID_LINEAR);
            server->body_set_state(motion.body,PhysicsServer3D::BODY_STATE_LINEAR_VELOCITY,motion.velocity);
            server->body_set_state(motion.body,PhysicsServer3D::BODY_STATE_SLEEPING,motion.sleeping);
            motion.suspended=false;
        }
        ++simulated;
    }
    out["ok"]=true;out["changed"]=changed;out["simulated"]=simulated;out["suspended"]=suspended;return out;
}
Dictionary NativePickupPhysics::statistics()const{
    Dictionary out;int active=0,sleeping=0,suspended=0;
    for(const auto &motion:records)if(motion.identity){++active;sleeping+=motion.sleeping;suspended+=motion.suspended;}
    out["capacity"]=LIMIT;out["active"]=active;out["sleeping"]=sleeping;out["suspended"]=suspended;out["configured"]=space.is_valid();return out;
}
PackedByteArray NativePickupPhysics::capture_storage_snapshot()const{
    int count=0;for(const auto &motion:records)count+=motion.identity>0;
    PackedByteArray bytes;bytes.resize(16+count*32);std::memcpy(bytes.ptrw(),"TFDP\1\0\0\0",8);bytes.encode_u64(8,count);
    int at=16;for(const auto &motion:records)if(motion.identity){
        bytes.encode_u32(at,motion.batch);bytes.encode_u32(at+4,motion.sleeping?1:0);bytes.encode_u64(at+8,motion.identity);
        bytes.encode_float(at+16,motion.velocity.x);bytes.encode_float(at+20,motion.velocity.y);bytes.encode_float(at+24,motion.velocity.z);bytes.encode_u32(at+28,0);at+=32;
    }
    return bytes;
}
bool NativePickupPhysics::validate_snapshot(const PackedByteArray &bytes)const{
    if(bytes.size()<16||std::memcmp(bytes.ptr(),"TFDP\1\0\0\0",8))return false;
    uint64_t count=bytes.decode_u64(8);if(count>LIMIT||bytes.size()!=int64_t(16+count*32))return false;
    std::set<std::pair<int,int64_t>> seen;
    for(int64_t at=16;at<bytes.size();at+=32){
        int batch=bytes.decode_u32(at);int64_t identity=bytes.decode_u64(at+8);
        Vector3 velocity(bytes.decode_float(at+16),bytes.decode_float(at+20),bytes.decode_float(at+24));
        if(!stores.count(batch)||identity<=0||bytes.decode_u32(at+4)>1||bytes.decode_u32(at+28)||!velocity.is_finite()||velocity.length()>64.001||(bytes.decode_u32(at+4)&&velocity!=Vector3())||!seen.emplace(batch,identity).second)return false;
    }
    return true;
}
bool NativePickupPhysics::restore_storage_snapshot(const PackedByteArray &bytes){
    if(!validate_snapshot(bytes))return false;
    reset();int index=0;for(int64_t at=16;at<bytes.size();at+=32){
        auto &motion=records[index++];motion.batch=bytes.decode_u32(at);motion.identity=bytes.decode_u64(at+8);motion.sleeping=bytes.decode_u32(at+4)==1;
        motion.velocity=Vector3(bytes.decode_float(at+16),bytes.decode_float(at+20),bytes.decode_float(at+24));
    }
    return true;
}
}
