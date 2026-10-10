// SPDX-License-Identifier: 0BSD
#pragma once
#include "entity_store.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <map>
namespace terraforest {
class NativeActorOrders : public godot::RefCounted {
    GDCLASS(NativeActorOrders,godot::RefCounted)
    godot::Ref<NativeEntityStore> store_;
    std::map<int64_t,godot::Vector3> targets_;
protected:
    static void _bind_methods(){
        using namespace godot;
        ClassDB::bind_method(D_METHOD("configure","store"),&NativeActorOrders::configure);
        ClassDB::bind_method(D_METHOD("set_target","identity","target"),&NativeActorOrders::set_target);
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
        targets_[identity]=target;return true;
    }
    bool clear_target(int64_t identity){return targets_.erase(identity)!=0;}
    godot::Vector3 target_for(int64_t identity,const godot::Vector3 &fallback)const{
        auto found=targets_.find(identity);return found==targets_.end()?fallback:found->second;
    }
    godot::Dictionary get_target(int64_t identity)const{
        godot::Dictionary out;auto found=targets_.find(identity);out["present"]=found!=targets_.end();
        if(found!=targets_.end())out["target"]=found->second;return out;
    }
    godot::PackedByteArray capture_storage_snapshot()const{
        godot::PackedByteArray data;data.resize(16+int64_t(targets_.size())*32);data.fill(0);
        data.encode_u32(0,0x314f4154);data.encode_u32(4,1);data.encode_u32(8,uint32_t(targets_.size()));
        int64_t offset=16;for(const auto &entry:targets_){data.encode_s64(offset,entry.first);
            for(int axis=0;axis<3;++axis)data.encode_double(offset+8+axis*8,entry.second[axis]);offset+=32;}
        return data;
    }
    bool validate_snapshot(const godot::PackedByteArray &data)const{
        if(data.size()<16||data.decode_u32(0)!=0x314f4154||data.decode_u32(4)!=1||data.decode_u32(12)!=0)return false;
        const uint32_t count=data.decode_u32(8);if(count>262144||data.size()!=16+int64_t(count)*32)return false;
        int64_t previous=0;for(uint32_t i=0;i<count;++i){const int64_t offset=16+int64_t(i)*32,id=data.decode_s64(offset);
            if(id<=previous)return false;previous=id;
            godot::Vector3 target;for(int axis=0;axis<3;++axis)target[axis]=data.decode_double(offset+8+axis*8);
            if(!target.is_finite())return false;
        }return true;
    }
    bool restore_storage_snapshot(const godot::PackedByteArray &data){
        if(store_.is_null()||!validate_snapshot(data))return false;
        std::map<int64_t,godot::Vector3> staged;
        for(uint32_t i=0;i<data.decode_u32(8);++i){int64_t offset=16+int64_t(i)*32,id=data.decode_s64(offset);
            if(!store_->resolve_identity(id))return false;
            godot::Vector3 target;for(int axis=0;axis<3;++axis)target[axis]=data.decode_double(offset+8+axis*8);staged[id]=target;
        }
        targets_.swap(staged);return true;
    }
};
}
