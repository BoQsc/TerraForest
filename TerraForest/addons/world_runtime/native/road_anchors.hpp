// SPDX-License-Identifier: 0BSD
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/array.hpp>
#include <cmath>
namespace terraforest {
class NativeRoadAnchors : public godot::RefCounted {
    GDCLASS(NativeRoadAnchors, godot::RefCounted)
    static bool valid(const godot::PackedVector3Array &ends, double width) {
        if (ends.size()!=2 || !std::isfinite(width) || width<4 || width>64) return false;
        for (int i=0;i<2;++i) {
            const auto p=ends[i];
            if (!p.is_finite() || p.x<0 || p.x>2000 || p.z<0 || p.z>2000 || p.y<0 || p.y>250) return false;
        }
        return ends[0].distance_to(ends[1])>=1;
    }
protected:
    static void _bind_methods() {
        godot::ClassDB::bind_method(godot::D_METHOD("encode","ends","width"), &NativeRoadAnchors::encode);
        godot::ClassDB::bind_method(godot::D_METHOD("encode_collection","records","selected"), &NativeRoadAnchors::encode_collection);
        godot::ClassDB::bind_method(godot::D_METHOD("decode","data"), &NativeRoadAnchors::decode);
        godot::ClassDB::bind_method(godot::D_METHOD("validate_snapshot","data"), &NativeRoadAnchors::validate_snapshot);
    }
public:
    godot::PackedByteArray encode_collection(const godot::PackedByteArray &records,int selected) const {
        godot::PackedByteArray out;
        const int count=records.size()/64;
        if(count<1 || count>256 || records.size()!=count*64 || selected<0 || selected>=count) return out;
        for(int i=0;i<count;++i) {
            auto record=records.slice(i*64,(i+1)*64);
            if(record.decode_u32(4)!=1 || !validate_snapshot(record)) return out;
        }
        out.resize(16);out.encode_u32(0,0x31415254);out.encode_u32(4,2);
        out.encode_u32(8,count);out.encode_u32(12,selected);out.append_array(records);return out;
    }
    godot::PackedByteArray encode(const godot::PackedVector3Array &ends,double width) const {
        godot::PackedByteArray out;
        if (!valid(ends,width)) return out;
        out.resize(64);out.fill(0);out.encode_u32(0,0x31415254);out.encode_u32(4,1);
        for(int i=0;i<2;++i) for(int axis=0;axis<3;++axis) out.encode_double(8+(i*3+axis)*8,ends[i][axis]);
        out.encode_double(56,width);return out;
    }
    godot::Dictionary decode(const godot::PackedByteArray &data) const {
        godot::Dictionary result;result["ok"]=false;
        if(data.is_empty()) { result["ok"]=true;result["present"]=false;result["streets"]=godot::Array();result["selected"]=-1;return result; }
        if(data.size()>=16 && data.decode_u32(0)==0x31415254 && data.decode_u32(4)==2) {
            const uint32_t count=data.decode_u32(8),selected=data.decode_u32(12);
            if(count<1 || count>256 || selected>=count || data.size()!=16+count*64) return result;
            godot::Array streets;
            for(uint32_t i=0;i<count;++i) {
                auto record=data.slice(16+i*64,16+(i+1)*64);
                if(record.decode_u32(4)!=1) return result;
                auto street=decode(record);
                if(!bool(street["ok"])) return result;
                godot::Dictionary item;item["ends"]=street["ends"];item["width"]=street["width"];streets.append(item);
            }
            result["ok"]=true;result["present"]=true;result["streets"]=streets;result["selected"]=selected;return result;
        }
        if(data.size()!=64 || data.decode_u32(0)!=0x31415254 || data.decode_u32(4)!=1) return result;
        godot::PackedVector3Array ends;ends.resize(2);
        for(int i=0;i<2;++i) {
            godot::Vector3 p;
            for(int axis=0;axis<3;++axis) {
                double value=data.decode_double(8+(i*3+axis)*8);
                if(!std::isfinite(value) || value<0 || value>(axis==1 ? 250 : 2000)) return result;
                p[axis]=value;
            }
            ends.set(i,p);
        }
        double width=data.decode_double(56);
        if(!valid(ends,width)) return result;
        result["ok"]=true;result["present"]=true;result["ends"]=ends;result["width"]=width;
        godot::Dictionary item;item["ends"]=ends;item["width"]=width;
        godot::Array streets;streets.append(item);result["streets"]=streets;result["selected"]=0;return result;
    }
    bool validate_snapshot(const godot::PackedByteArray &data) const { return bool(decode(data)["ok"]); }
};
}
