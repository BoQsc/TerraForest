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
        godot::ClassDB::bind_method(godot::D_METHOD("render_biomes","pixels","seed","profile","origin","width","size"),&NativeWorldRecipe::render_biomes,DEFVAL(godot::Vector2i()),DEFVAL(256),DEFVAL(256));
    }
public:
    godot::PackedByteArray encode(const godot::Dictionary &options) const {
        godot::PackedByteArray bytes;
        const char *names[]={"biome","settlements","districts","network","trails","road_grid","material_veins"};
        if(options.size()<5||options.size()>7)return bytes;
        const int count=options.size();
        bytes.resize(8+count*4);bytes.fill(0);bytes.encode_u32(0,0x31504352);bytes.encode_u32(4,count==5?1:2);
        for(int index=0;index<count;++index){
            if(!options.has(names[index])||options[names[index]].get_type()!=godot::Variant::INT)return {};
            const int64_t value=options[names[index]];
            if(value<0||value>4)return {};
            bytes.encode_u32(8+index*4,uint32_t(value));
        }
        if(count==6&&bytes.decode_u32(28)>=2)bytes.encode_u32(4,bytes.decode_u32(28)+1);
        if(count==7)bytes.encode_u32(4,5);
        if(count==7&&(bytes.decode_u32(16)>2||bytes.decode_u32(20)>1))bytes.encode_u32(4,6);
        return validate_snapshot(bytes)?bytes:godot::PackedByteArray();
    }
    bool validate_snapshot(const godot::PackedByteArray &bytes) const {
        if(bytes.is_empty())return true;
        if((bytes.size()!=28&&bytes.size()!=32&&bytes.size()!=36)||bytes.decode_u32(0)!=0x31504352)return false;
        if(bytes.size()==28&&bytes.decode_u32(4)!=1)return false;
        if(bytes.size()==32&&(bytes.decode_u32(28)>3||bytes.decode_u32(4)!=(bytes.decode_u32(28)>=2?bytes.decode_u32(28)+1:2)))return false;
        if(bytes.size()==36&&((bytes.decode_u32(4)!=5&&bytes.decode_u32(4)!=6)||bytes.decode_u32(28)>3||bytes.decode_u32(32)>1))return false;
        const auto settlements=bytes.decode_u32(12),districts=bytes.decode_u32(16);
        const bool expanded=bytes.decode_u32(4)==6;
        return bytes.decode_u32(8)<=2&&settlements>=1&&settlements<=3&&districts>=1&&districts<=(expanded?3u:2u)
            &&settlements*districts<=(expanded?9u:6u)&&bytes.decode_u32(20)<=(expanded?2u:1u)&&bytes.decode_u32(24)<=2;
    }
    godot::Dictionary decode(const godot::PackedByteArray &bytes) const {
        godot::Dictionary result;
        if(bytes.is_empty()||!validate_snapshot(bytes))return result;
        const char *names[]={"biome","settlements","districts","network","trails"};
        for(int index=0;index<5;++index)result[names[index]]=int(bytes.decode_u32(8+index*4));
        if(bytes.size()>=32)result["road_grid"]=int(bytes.decode_u32(28));
        if(bytes.size()==36)result["material_veins"]=int(bytes.decode_u32(32));
        return result;
    }
    godot::PackedByteArray capture_snapshot() const {return state;}
    bool restore_snapshot(const godot::PackedByteArray &bytes) {
        if(!validate_snapshot(bytes))return false;
        state=bytes;return true;
    }
    godot::PackedByteArray render_biomes(const godot::PackedByteArray &pixels,int64_t seed,int profile,godot::Vector2i origin=godot::Vector2i(),int width=256,int size=256) const {
        if(size<64||size>1024||width<1||width>size||pixels.is_empty()||pixels.size()%(width*4)||pixels.size()>size*size*4||origin.x<0||origin.y<0||origin.x+width>size||origin.y+pixels.size()/(width*4)>size||seed<0||seed>0x7fffffff||profile<0||profile>2)return {};
        auto result=pixels.duplicate();auto *data=result.ptrw();
        for(int row=0;row<pixels.size()/(width*4);++row)for(int column=0;column<width;++column){
            const int offset=(row*width+column)*4;
            if(data[offset+1]<=data[offset]*1.09||data[offset+1]<=data[offset+2]*1.18)continue;
            const double woodland=biome_woodland((origin.x+column+.5)*2000.0/size,(origin.y+row+.5)*2000.0/size,uint32_t(seed),profile);
            const double factors[3]={1.04-.53*woodland,1.02-.39*woodland,.94-.35*woodland};
            for(int channel=0;channel<3;++channel)data[offset+channel]=uint8_t(std::clamp(data[offset+channel]*factors[channel],0.0,255.0));
        }
        return result;
    }
};
}
