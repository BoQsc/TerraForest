// SPDX-License-Identifier: 0BSD
#include "entity_activation.hpp"
#include <godot_cpp/classes/collision_shape3d.hpp>
#include <godot_cpp/classes/capsule_shape3d.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <algorithm>
#include <cmath>
#include <godot_cpp/classes/time.hpp>
using namespace godot;
namespace terraforest {
void NativeEntityActivation::_bind_methods(){
    ClassDB::bind_method(D_METHOD("set_profiling","enabled"),&NativeEntityActivation::set_profiling);
    ClassDB::bind_method(D_METHOD("set_orders","orders"),&NativeEntityActivation::set_orders);
    ClassDB::bind_method(D_METHOD("configure","store","capacity"),&NativeEntityActivation::configure);
    ClassDB::bind_method(D_METHOD("select","center","radius","candidate_budget"),&NativeEntityActivation::select,DEFVAL(4096));
    ClassDB::bind_method(D_METHOD("tick","targets","delta","ready"),&NativeEntityActivation::tick);
    ClassDB::bind_method(D_METHOD("settle","delta","readiness"),&NativeEntityActivation::settle);
    ClassDB::bind_method(D_METHOD("active_handles"),&NativeEntityActivation::active_handles);
}
bool NativeEntityActivation::configure(const Ref<NativeEntityStore> &store,int capacity){
    if(!is_inside_tree()||store.is_null()||!proxies_.empty()||capacity<1||capacity>64)return false;
    store_=store;proxies_.reserve(capacity);
    Ref<CapsuleShape3D> shape;shape.instantiate();shape->set_radius(0.35);shape->set_height(1.8);
    for(int i=0;i<capacity;++i){
        auto *body=memnew(NativeEntityActor);auto *collision=memnew(CollisionShape3D);
        collision->set_shape(shape);body->add_child(collision);body->set_collision_layer(0);body->set_collision_mask(0);
        body->set_floor_snap_length(0.25);add_child(body);proxies_.push_back({body,0});
    }
    return true;
}
void NativeEntityActivation::sleep_all(){
    active_.clear();for(auto &p:proxies_){p.handle=0;p.body->set_collision_layer(0);p.body->set_collision_mask(0);p.body->set_velocity(Vector3());}
}
Dictionary NativeEntityActivation::select(const Vector3 &center,double radius,int candidate_budget){
    Dictionary result;result["ok"]=false;result["active"]=0;
    if(store_.is_null()||!is_inside_tree())return result;
    result=store_->query_sphere_nearest(center,radius,int(proxies_.size()),candidate_budget);
    result["active"]=0;result["capacity"]=int(proxies_.size());
    // An incomplete candidate scan cannot certify which actors are nearest.
    if(!bool(result["ok"])||!bool(result["selection_complete"])){sleep_all();return result;}
    PackedInt64Array ids=result["ids"];
    // Keep incumbents unless a challenger is more than 2m closer. Unioning the
    // nearest K with at most K incumbents is sufficient for the biased top K.
    struct Candidate{int64_t handle,identity;double score;};
    std::vector<Candidate> candidates;candidates.reserve(ids.size()+active_.size());
    for(int64_t i=0;i<ids.size();++i){
        const double distance=store_->get_position(ids[i]).distance_to(center);
        candidates.push_back({ids[i],store_->persistent_id(ids[i]),distance-(active_.has(ids[i])?2.0:0.0)});
    }
    for(int64_t i=0;i<active_.size();++i){
        const int64_t handle=active_[i];if(ids.has(handle)||!store_->contains(handle))continue;
        const double distance=store_->get_position(handle).distance_to(center);
        if(distance<=radius)candidates.push_back({handle,store_->persistent_id(handle),distance-2.0});
    }
    std::sort(candidates.begin(),candidates.end(),[](const Candidate &a,const Candidate &b){return a.score<b.score||(a.score==b.score&&a.identity<b.identity);});
    ids.resize(std::min(candidates.size(),proxies_.size()));
    for(int64_t i=0;i<ids.size();++i)ids.set(i,candidates[i].handle);
    result["ids"]=ids;result["retention_margin_m"]=2.0;
    for(auto &p:proxies_)if(p.handle&& !ids.has(p.handle)){
        p.handle=0;p.body->set_collision_layer(0);p.body->set_collision_mask(0);p.body->set_velocity(Vector3());
    }
    for(int64_t i=0;i<ids.size();++i){
        auto found=std::find_if(proxies_.begin(),proxies_.end(),[&](const Proxy &p){return p.handle==ids[i];});
        if(found!=proxies_.end())continue;
        auto empty=std::find_if(proxies_.begin(),proxies_.end(),[](const Proxy &p){return p.handle==0;});
        if(empty==proxies_.end()||!empty->body->bind_entity(store_,ids[i])){sleep_all();result["ok"]=false;return result;}
        empty->handle=ids[i];empty->body->set_collision_layer(2);empty->body->set_collision_mask(1);
    }
    active_=ids;result["active"]=ids.size();return result;
}
bool NativeEntityActivation::tick(const PackedVector3Array &targets,double delta,const PackedByteArray &ready){
    if(store_.is_null()||!is_inside_tree()||targets.size()!=active_.size()||ready.size()!=active_.size()||!std::isfinite(delta)||delta<=0||delta>0.1)return false;
    for(int64_t i=0;i<active_.size();++i)if(!targets[i].is_finite()||ready[i]>1||!store_->contains(active_[i]))return false;
    for(int64_t i=0;i<active_.size();++i){
        auto p=std::find_if(proxies_.begin(),proxies_.end(),[&](const Proxy &p){return p.handle==active_[i];});
        if(p==proxies_.end())return false;
        p->body->tick(targets[i],delta,ready[i]!=0);
    }
    return true;
}
Dictionary NativeEntityActivation::settle(double delta,const Callable &readiness){
    Dictionary out;out["ok"]=false;out["visited"]=0;out["held"]=0;
    if(store_.is_null()||!is_inside_tree()||!readiness.is_valid()||!std::isfinite(delta)||delta<=0||delta>0.1)return out;
    int visited=0,held=0;uint64_t readiness_us=0,collision_us=0,transform_us=0,motion_us=0,store_us=0;
    for(auto &p:proxies_){
        if(!p.handle)continue;
        if(!store_->contains(p.handle)){sleep_all();return out;}
        const Vector3 position=store_->get_position(p.handle);
        // Include capsule, floor snap, current travel and next gravity increment.
        const real_t travel=real_t(std::max(double(p.body->get_velocity().length()),2.5)*delta+20*delta*delta+0.05);
        AABB bounds(position-Vector3(0.35,1.15,0.35),Vector3(0.7,2.05,0.7));bounds=bounds.grow(travel);
        const uint64_t begin=profiling_?Time::get_singleton()->get_ticks_usec():0;
        const Variant answer=readiness.call(bounds);
        const uint64_t ready_done=profiling_?Time::get_singleton()->get_ticks_usec():0;
        if(profiling_)readiness_us+=ready_done-begin;
        const bool ready=answer.get_type()==Variant::BOOL && bool(answer);
        const Vector3 target=orders_.is_valid()?orders_->target_for(store_->persistent_id(p.handle),position):position;
        p.body->profile_tick=profiling_;
        p.body->tick(target,delta,ready);
        transform_us+=p.body->transform_us;motion_us+=p.body->motion_us;store_us+=p.body->store_us;
        ++visited;if(!ready)++held;
        if(profiling_)collision_us+=Time::get_singleton()->get_ticks_usec()-ready_done;
    }
    if(profiling_){out["readiness_us"]=int64_t(readiness_us);out["collision_us"]=int64_t(collision_us);out["transform_us"]=int64_t(transform_us);out["motion_us"]=int64_t(motion_us);out["store_us"]=int64_t(store_us);}
    out["ok"]=true;out["visited"]=visited;out["held"]=held;return out;
}

}
