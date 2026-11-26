// SPDX-License-Identifier: 0BSD
#include "water_render_pages.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <chrono>
#include <algorithm>
#include <cmath>
using namespace godot;
namespace terraforest {
void NativeWaterRenderPages::_bind_methods() {
    ClassDB::bind_method(D_METHOD("configure","pages"),&NativeWaterRenderPages::configure);
    ClassDB::bind_method(D_METHOD("prepare"),&NativeWaterRenderPages::prepare);
    ClassDB::bind_method(D_METHOD("result"),&NativeWaterRenderPages::result);
    ClassDB::bind_method(D_METHOD("statistics"),&NativeWaterRenderPages::statistics);
}
bool NativeWaterRenderPages::configure(const Array &input) {
    if(configured||input.is_empty()||input.size()>16)return false;
    std::vector<std::vector<Owner>> next;int64_t total=0,nv=0,ni=0;
    for(int p=0;p<input.size();++p) {
        if(input[p].get_type()!=Variant::ARRAY)return false;
        Array members=input[p];if(members.size()<2||members.size()>64)return false;
        std::vector<Owner> page;int64_t page_bytes=0;
        for(int i=0;i<members.size();++i) {
            if(members[i].get_type()!=Variant::DICTIONARY)return false;
            Dictionary record=members[i];
            if(record.get("arrays",Variant()).get_type()!=Variant::ARRAY||record.get("offset",Variant()).get_type()!=Variant::VECTOR3)return false;
            Array a=record["arrays"];Owner owner;owner.offset=record["offset"];
            if(a.size()!=Mesh::ARRAY_MAX||!owner.offset.is_finite()||owner.offset.x<0||owner.offset.y<0||owner.offset.z<0||owner.offset.x>12||owner.offset.y>12||owner.offset.z>12)return false;
            for(int j=0;j<a.size();++j)if(j!=Mesh::ARRAY_VERTEX&&j!=Mesh::ARRAY_NORMAL&&j!=Mesh::ARRAY_TEX_UV&&j!=Mesh::ARRAY_COLOR&&j!=Mesh::ARRAY_INDEX&&a[j].get_type()!=Variant::NIL)return false;
            if(a[Mesh::ARRAY_VERTEX].get_type()!=Variant::PACKED_VECTOR3_ARRAY||a[Mesh::ARRAY_NORMAL].get_type()!=Variant::PACKED_VECTOR3_ARRAY||
               a[Mesh::ARRAY_TEX_UV].get_type()!=Variant::PACKED_VECTOR2_ARRAY||a[Mesh::ARRAY_COLOR].get_type()!=Variant::PACKED_COLOR_ARRAY||
               a[Mesh::ARRAY_INDEX].get_type()!=Variant::PACKED_INT32_ARRAY)return false;
            owner.vertices=a[Mesh::ARRAY_VERTEX];owner.normals=a[Mesh::ARRAY_NORMAL];owner.uv=a[Mesh::ARRAY_TEX_UV];owner.colors=a[Mesh::ARRAY_COLOR];owner.indices=a[Mesh::ARRAY_INDEX];
            const int64_t count=owner.vertices.size();
            if(!count||count!=owner.normals.size()||count!=owner.uv.size()||count!=owner.colors.size()||owner.indices.is_empty()||owner.indices.size()%3)return false;
            page_bytes+=count*48+owner.indices.size()*4;
            if(page_bytes>512*1024)return false;
            nv+=count;ni+=owner.indices.size();page.push_back(std::move(owner));
        }
        total+=page_bytes;if(total>4*1024*1024)return false;next.push_back(std::move(page));
    }
    pages=std::move(next);bytes=total;vertices=nv;indices=ni;configured=true;return true;
}
void NativeWaterRenderPages::prepare() {
    if(!configured||prepared)return;prepared=true;
    const auto began=std::chrono::steady_clock::now();
    for(const auto &page:pages) {
        int nv=0,ni=0;for(const auto &owner:page){nv+=owner.vertices.size();ni+=owner.indices.size();}
        PackedVector3Array v,n;PackedVector2Array uv;PackedColorArray c;PackedInt32Array ix;
        v.resize(nv);n.resize(nv);uv.resize(nv);c.resize(nv);ix.resize(ni);
        auto *vp=v.ptrw(),*np=n.ptrw();auto *up=uv.ptrw();auto *cp=c.ptrw();auto *ip=ix.ptrw();
        int at=0,ia=0;bool valid=true;
        for(const auto &owner:page) {
            const int count=owner.vertices.size();
            for(int j=0;j<count;++j){vp[at+j]=owner.vertices[j]+owner.offset;valid&=vp[at+j].is_finite()&&owner.normals[j].is_finite()&&owner.uv[j].is_finite()&&std::isfinite(owner.colors[j].r)&&std::isfinite(owner.colors[j].g)&&std::isfinite(owner.colors[j].b)&&std::isfinite(owner.colors[j].a);}
            std::copy_n(owner.normals.ptr(),count,np+at);std::copy_n(owner.uv.ptr(),count,up+at);std::copy_n(owner.colors.ptr(),count,cp+at);
            for(int j=0;j<owner.indices.size();++j){const int index=owner.indices[j];valid&=index>=0&&index<count;ip[ia++]=(index>=0&&index<count)?at+index:0;}
            at+=count;
        }
        Ref<ArrayMesh> mesh;
        if(valid){Array a;a.resize(Mesh::ARRAY_MAX);a[Mesh::ARRAY_VERTEX]=v;a[Mesh::ARRAY_NORMAL]=n;a[Mesh::ARRAY_TEX_UV]=uv;a[Mesh::ARRAY_COLOR]=c;a[Mesh::ARRAY_INDEX]=ix;
            mesh.instantiate();mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES,a);if(mesh->get_surface_count()!=1)mesh.unref();}
        meshes.append(mesh);
    }
    pages.clear();
    worker_us=std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now()-began).count();
}
Dictionary NativeWaterRenderPages::statistics() const {
    Dictionary out;out["input_bytes"]=bytes;out["vertices"]=vertices;out["indices"]=indices;out["worker_us"]=worker_us;out["pages"]=meshes.size();return out;
}
}
