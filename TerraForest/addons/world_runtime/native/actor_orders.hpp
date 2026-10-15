// SPDX-License-Identifier: 0BSD
#pragma once
#include "entity_store.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <map>
#include <cmath>
#include <utility>
namespace terraforest {
class NativeActorOrders : public godot::RefCounted {
    GDCLASS(NativeActorOrders,godot::RefCounted)
    godot::Ref<NativeEntityStore> store_;
    struct Order {godot::Vector3 target,other;bool patrol=false;};
    std::map<int64_t,Order> targets_;
protected:
    static void _bind_methods(){
        using namespace godot;
        ClassDB::bind_method(D_METHOD("configure","store"),&NativeActorOrders::configure);
        ClassDB::bind_method(D_METHOD("set_target","identity","target"),&NativeActorOrders::set_target);
        ClassDB::bind_method(D_METHOD("set_patrol","identity","target"),&NativeActorOrders::set_patrol);
        ClassDB::bind_method(D_METHOD("clear_target","identity"),&NativeActorOrders::clear_target);
        ClassDB::bind_method(D_METHOD("get_target","identity"),&NativeActorOrders::get_target);
        ClassDB::bind_method(D_METHOD("capture_storage_snapshot"),&NativeActorOrders::capture_storage_snapshot);
        ClassDB::bind_method(D_METHOD("validate_snapshot","data"),&NativeActorOrders::validate_snapshot);
        ClassDB::bind_method(D_METHOD("restore_storage_snapshot","data"),&NativeActorOrders::restore_storage_snapshot);
    }
public:
    bool configure(const godot::Ref<NativeEntityStore> &store){if(store.is_null()||store_.is_valid())return false;store_=store;return true;}
    bool owns(const godot::Ref<NativeEntityStore> &store)const{return store_==store;}
    bool set_target(int64_t identity,const godot::Vector3 &target){
        if(store_.is_null()||!store_->resolve_identity(identity)||!target.is_finite())return false;
        if(!targets_.count(identity)&&targets_.size()>=262144)return false;
        targets_[identity]={target,{},false};return true;
    }
    bool set_patrol(int64_t identity,const godot::Vector3 &target){
        if(store_.is_null()||!target.is_finite())return false;
        const int64_t handle=store_->resolve_identity(identity);if(!handle)return false;
        const auto start=store_->get_position(handle);const auto distance=start.distance_to(target);
        if(distance<1||distance>16||(!targets_.count(identity)&&targets_.size()>=262144))return false;
        targets_[identity]={target,start,true};return true;
    }
    // Called only after a ready active body reaches its routed destination.
    bool advance_if_arrived(int64_t identity,const godot::Vector3 &position){
        auto found=targets_.find(identity);if(found==targets_.end()||!found->second.patrol)return false;
        auto &order=found->second;auto offset=position-order.target;
        if(std::abs(offset.y)>.3)return false;offset.y=0;
        if(offset.length_squared()>.09)return false;
        std::swap(order.target,order.other);return true;
    }
    bool clear_target(int64_t identity){return targets_.erase(identity)!=0;}
    godot::Vector3 target_for(int64_t identity,const godot::Vector3 &fallback)const{
        auto found=targets_.find(identity);return found==targets_.end()?fallback:found->second.target;
    }
    godot::Dictionary get_target(int64_t identity)const{
        godot::Dictionary out;auto found=targets_.find(identity);out["present"]=found!=targets_.end();
        if(found!=targets_.end()){out["target"]=found->second.target;out["patrol"]=found->second.patrol;if(found->second.patrol)out["other"]=found->second.other;}return out;
    }
    godot::PackedByteArray capture_storage_snapshot()const{
        bool patrol=false;for(const auto &entry:targets_)patrol=patrol||entry.second.patrol;
        const int stride=patrol?64:32;
        godot::PackedByteArray data;data.resize(16+int64_t(targets_.size())*stride);data.fill(0);
        data.encode_u32(0,0x314f4154);data.encode_u32(4,patrol?2:1);data.encode_u32(8,uint32_t(targets_.size()));
        int64_t offset=16;for(const auto &entry:targets_){data.encode_s64(offset,entry.first);
            for(int axis=0;axis<3;++axis)data.encode_double(offset+8+axis*8,entry.second.target[axis]);
            if(patrol){for(int axis=0;axis<3;++axis)data.encode_double(offset+32+axis*8,entry.second.other[axis]);data.encode_u32(offset+56,entry.second.patrol?1:0);}
            offset+=stride;
        }return data;
    }
    bool validate_snapshot(const godot::PackedByteArray &data)const{
        if(data.size()<16||data.decode_u32(0)!=0x314f4154||data.decode_u32(12)!=0)return false;
        const auto version=data.decode_u32(4);if(version!=1&&version!=2)return false;
        const int stride=version==2?64:32;
        const uint32_t count=data.decode_u32(8);if(count>262144||data.size()!=16+int64_t(count)*stride)return false;
        int64_t previous=0;for(uint32_t i=0;i<count;++i){const int64_t offset=16+int64_t(i)*stride,id=data.decode_s64(offset);
            if(id<=previous)return false;previous=id;
            godot::Vector3 target;for(int axis=0;axis<3;++axis)target[axis]=data.decode_double(offset+8+axis*8);
            if(!target.is_finite())return false;
            if(version==2){
                const auto mode=data.decode_u32(offset+56);if(mode>1||data.decode_u32(offset+60)!=0)return false;
                godot::Vector3 other;for(int axis=0;axis<3;++axis)other[axis]=data.decode_double(offset+32+axis*8);
                if(!other.is_finite()||(!mode&&other!=godot::Vector3()))return false;
                const auto distance=target.distance_to(other);if(mode&&(distance<1||distance>16))return false;
            }
        }return true;
    }
    bool restore_storage_snapshot(const godot::PackedByteArray &data){
        if(store_.is_null()||!validate_snapshot(data))return false;
        const int stride=data.decode_u32(4)==2?64:32;
        std::map<int64_t,Order> staged;
        for(uint32_t i=0;i<data.decode_u32(8);++i){int64_t offset=16+int64_t(i)*stride,id=data.decode_s64(offset);
            if(!store_->resolve_identity(id))return false;
            Order order;for(int axis=0;axis<3;++axis)order.target[axis]=data.decode_double(offset+8+axis*8);
            if(stride==64){for(int axis=0;axis<3;++axis)order.other[axis]=data.decode_double(offset+32+axis*8);order.patrol=data.decode_u32(offset+56)==1;}
            staged[id]=order;
        }
        targets_.swap(staged);return true;
    }
};
}
