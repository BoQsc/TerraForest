#pragma once
#include "biome_field.hpp"
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
namespace terraforest {
class NativeWorldRecipe : public godot::RefCounted {
    GDCLASS(NativeWorldRecipe,godot::RefCounted)
    godot::PackedByteArray state;
protected:
    static void _bind_methods() {
        godot::ClassDB::bind_method(godot::D_METHOD("encode","options"),&NativeWorldRecipe::encode);
        godot::ClassDB::bind_method(godot::D_METHOD("decode","data"),&NativeWorldRecipe::decode);
        godot::ClassDB::bind_method(godot::D_METHOD("validate_snapshot","data"),&NativeWorldRecipe::validate_snapshot);
        godot::ClassDB::bind_method(godot::D_METHOD("capture_snapshot"),&NativeWorldRecipe::capture_snapshot);
        godot::ClassDB::bind_method(godot::D_METHOD("restore_snapshot","data"),&NativeWorldRecipe::restore_snapshot);
        godot::ClassDB::bind_method(godot::D_METHOD("render_biomes","pixels","seed","profile"),&NativeWorldRecipe::render_biomes);
    }
public:
    godot::PackedByteArray encode(const godot::Dictionary &options) const {
        godot::PackedByteArray bytes;
        const char *names[]={"biome","settlements","districts","network","trails","road_grid"};
        if(options.size()!=5&&options.size()!=6)return bytes;
        const int count=options.size();
        bytes.resize(8+count*4);bytes.fill(0);bytes.encode_u32(0,0x31504352);bytes.encode_u32(4,count==5?1:2);
        for(int index=0;index<count;++index){
            if(!options.has(names[index])||options[names[index]].get_type()!=godot::Variant::INT)return {};
            const int64_t value=options[names[index]];
            if(value<0||value>4)return {};
            bytes.encode_u32(8+index*4,uint32_t(value));
        }
        if(count==6&&bytes.decode_u32(28)>=2)bytes.encode_u32(4,bytes.decode_u32(28)+1);
        return validate_snapshot(bytes)?bytes:godot::PackedByteArray();
    }
    bool validate_snapshot(const godot::PackedByteArray &bytes) const {
        if(bytes.is_empty())return true;
        if((bytes.size()!=28&&bytes.size()!=32)||bytes.decode_u32(0)!=0x31504352)return false;
        if(bytes.size()==28&&bytes.decode_u32(4)!=1)return false;
        if(bytes.size()==32&&(bytes.decode_u32(28)>3||bytes.decode_u32(4)!=(bytes.decode_u32(28)>=2?bytes.decode_u32(28)+1:2)))return false;
        const auto settlements=bytes.decode_u32(12),districts=bytes.decode_u32(16);
        return bytes.decode_u32(8)<=2&&settlements>=1&&settlements<=3&&districts>=1&&districts<=2
            &&settlements*districts<=6&&bytes.decode_u32(20)<=1&&bytes.decode_u32(24)<=2;
    }
    godot::Dictionary decode(const godot::PackedByteArray &bytes) const {
        godot::Dictionary result;
        if(bytes.is_empty()||!validate_snapshot(bytes))return result;
        const char *names[]={"biome","settlements","districts","network","trails"};
        for(int index=0;index<5;++index)result[names[index]]=int(bytes.decode_u32(8+index*4));
        if(bytes.size()==32)result["road_grid"]=int(bytes.decode_u32(28));
        return result;
    }
    godot::PackedByteArray capture_snapshot() const {return state;}
    bool restore_snapshot(const godot::PackedByteArray &bytes) {
        if(!validate_snapshot(bytes))return false;
        state=bytes;return true;
    }
    godot::PackedByteArray render_biomes(const godot::PackedByteArray &pixels,int64_t seed,int profile) const {
        if(pixels.size()!=256*256*4||seed<0||seed>0x7fffffff||profile<0||profile>2)return {};
        auto result=pixels.duplicate();auto *data=result.ptrw();
        for(int row=0;row<256;++row)for(int column=0;column<256;++column){
            const int offset=(row*256+column)*4;
            const double woodland=biome_woodland(column*2000.0/255,row*2000.0/255,uint32_t(seed),profile);
            const double strength=.18+.20*woodland;
            const double shade=(data[offset]+data[offset+1]+data[offset+2])/400.0+.45;
            const double colors[3]={100-48*woodland,120-22*woodland,68+9*woodland};
            for(int channel=0;channel<3;++channel)data[offset+channel]=uint8_t(std::clamp(data[offset+channel]*(1-strength)+colors[channel]*shade*strength,0.0,255.0));
        }
        return result;
    }
};
}
