// SPDX-License-Identifier: 0BSD
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
namespace terraforest {
class NativePackMesh : public godot::RefCounted {
    GDCLASS(NativePackMesh,godot::RefCounted)
protected:
    static void _bind_methods(){godot::ClassDB::bind_method(godot::D_METHOD("merge","surfaces","tints","properties"),&NativePackMesh::merge);}
public:
    godot::Array merge(const godot::Array &surfaces,const godot::PackedColorArray &tints,const godot::PackedVector2Array &properties) const {
        using namespace godot;
        if(surfaces.is_empty()||surfaces.size()>512||tints.size()!=surfaces.size()||properties.size()!=surfaces.size())return {};
        int64_t vertices=0,indices=0;
        for(int s=0;s<surfaces.size();++s){
            Array a=surfaces[s];if(a.size()!=Mesh::ARRAY_MAX)return {};
            if(a[Mesh::ARRAY_VERTEX].get_type()!=Variant::PACKED_VECTOR3_ARRAY||a[Mesh::ARRAY_NORMAL].get_type()!=Variant::PACKED_VECTOR3_ARRAY||a[Mesh::ARRAY_TEX_UV].get_type()!=Variant::PACKED_VECTOR2_ARRAY)return {};
            PackedVector3Array v=a[Mesh::ARRAY_VERTEX],n=a[Mesh::ARRAY_NORMAL];PackedVector2Array uv=a[Mesh::ARRAY_TEX_UV];
            PackedInt32Array ix;if(a[Mesh::ARRAY_INDEX].get_type()!=Variant::NIL)ix=a[Mesh::ARRAY_INDEX];
            if(n.size()!=v.size()||uv.size()!=v.size())return {};
            for(int i=0;i<ix.size();++i)if(ix[i]<0||ix[i]>=v.size())return {};
            vertices+=v.size();indices+=ix.is_empty()?v.size():ix.size();
            if(vertices>2000000||indices>12000000)return {};
        }
        PackedVector3Array v,n;PackedVector2Array uv,pbr;PackedColorArray color;PackedInt32Array ix;
        v.resize(vertices);n.resize(vertices);uv.resize(vertices);pbr.resize(vertices);color.resize(vertices);ix.resize(indices);
        auto *vp=v.ptrw(),*np=n.ptrw();auto *up=uv.ptrw(),*pp=pbr.ptrw();auto *cp=color.ptrw();auto *ip=ix.ptrw();
        int offset=0,index=0;
        for(int s=0;s<surfaces.size();++s){
            Array a=surfaces[s];PackedVector3Array sv=a[Mesh::ARRAY_VERTEX],sn=a[Mesh::ARRAY_NORMAL];PackedVector2Array su=a[Mesh::ARRAY_TEX_UV];
            PackedInt32Array si;if(a[Mesh::ARRAY_INDEX].get_type()!=Variant::NIL)si=a[Mesh::ARRAY_INDEX];
            const auto tint=tints[s];const auto material=properties[s];
            for(int i=0;i<sv.size();++i){vp[offset+i]=sv[i];np[offset+i]=sn[i];up[offset+i]=su[i];pp[offset+i]=material;cp[offset+i]=tint;}
            const int count=si.is_empty()?sv.size():si.size();
            for(int i=0;i<count;++i)ip[index++]=offset+(si.is_empty()?i:si[i]);
            offset+=sv.size();
        }
        Array result;result.resize(Mesh::ARRAY_MAX);result[Mesh::ARRAY_VERTEX]=v;result[Mesh::ARRAY_NORMAL]=n;result[Mesh::ARRAY_TEX_UV]=uv;
        result[Mesh::ARRAY_TEX_UV2]=pbr;result[Mesh::ARRAY_COLOR]=color;result[Mesh::ARRAY_INDEX]=ix;return result;
    }
};
}
