// SPDX-License-Identifier: 0BSD
// CPU presentation skinning. Source packets are immutable and prepared at admission.
#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <vector>
#include <cmath>
using namespace godot;
namespace terraforest {
Array bake_zombie_surface(const Array &source, const Array &morphs,
        const PackedFloat64Array &amounts, bool relative,
        const TypedArray<Transform3D> &transforms, const Transform3D &unskinned) {
    if (source.size()!=Mesh::ARRAY_MAX || !unskinned.is_finite()) return {};
    Array result=source.duplicate();
    PackedVector3Array vertices=source[Mesh::ARRAY_VERTEX];
    const PackedVector3Array base_vertices=vertices;
    PackedVector3Array normals=source[Mesh::ARRAY_NORMAL].get_type()==Variant::NIL?PackedVector3Array():PackedVector3Array(source[Mesh::ARRAY_NORMAL]);
    const PackedVector3Array base_normals=normals;
    PackedFloat32Array tangents=source[Mesh::ARRAY_TANGENT].get_type()==Variant::NIL?PackedFloat32Array():PackedFloat32Array(source[Mesh::ARRAY_TANGENT]);
    const PackedInt32Array bones=source[Mesh::ARRAY_BONES].get_type()==Variant::NIL?PackedInt32Array():PackedInt32Array(source[Mesh::ARRAY_BONES]);
    const PackedFloat32Array weights=source[Mesh::ARRAY_WEIGHTS].get_type()==Variant::NIL?PackedFloat32Array():PackedFloat32Array(source[Mesh::ARRAY_WEIGHTS]);
    const int count=vertices.size(), influences=count?bones.size()/count:0;
    if (bones.size()!=count*influences || weights.size()!=bones.size()) return {};
    std::vector<Transform3D> binds;binds.reserve(transforms.size());
    for (int i=0;i<transforms.size();i++) { Transform3D transform=transforms[i]; if(!transform.is_finite())return {};binds.push_back(transform); }
    auto *points=vertices.ptrw();auto *directions=normals.ptrw();auto *tangent_data=tangents.ptrw();
    const auto *original=base_vertices.ptr();const auto *original_normals=base_normals.ptr();
    const bool has_normals=normals.size()==count, has_tangents=tangents.size()==count*4;
    for (int morph=0;morph<morphs.size() && morph<amounts.size();morph++) {
        const double amount=amounts[morph];if(!std::isfinite(amount)||std::abs(amount)<1e-6)continue;
        const Array arrays=morphs[morph];if(arrays.size()<Mesh::ARRAY_MAX)continue;
        const PackedVector3Array positions=arrays[Mesh::ARRAY_VERTEX].get_type()==Variant::NIL?PackedVector3Array():PackedVector3Array(arrays[Mesh::ARRAY_VERTEX]);
        const PackedVector3Array normals_delta=arrays[Mesh::ARRAY_NORMAL].get_type()==Variant::NIL?PackedVector3Array():PackedVector3Array(arrays[Mesh::ARRAY_NORMAL]);
        const auto *delta=positions.ptr();const auto *normal_delta=normals_delta.ptr();
        for(int vertex=0;vertex<count;vertex++) {
            if(positions.size()==count)points[vertex]+=(relative?delta[vertex]:delta[vertex]-original[vertex])*amount;
            if(has_normals&&normals_delta.size()==count)directions[vertex]+=(relative?normal_delta[vertex]:normal_delta[vertex]-original_normals[vertex])*amount;
        }
    }
    const auto *bone_ids=bones.ptr();const auto *bone_weights=weights.ptr();
    for(int vertex=0;vertex<count;vertex++) {
        Vector3 position,normal,tangent;double total=0;
        const Vector3 initial_normal=has_normals?directions[vertex]:Vector3(0,1,0);
        const Vector3 initial_tangent=has_tangents?Vector3(tangent_data[vertex*4],tangent_data[vertex*4+1],tangent_data[vertex*4+2]):Vector3(1,0,0);
        for(int influence=0;influence<influences;influence++) {
            const int slot=vertex*influences+influence,bind=bone_ids[slot];const double weight=bone_weights[slot];
            if(weight<=0 || bind<0 || bind>=int(binds.size()))continue;
            position+=binds[bind].xform(points[vertex])*weight;
            normal+=binds[bind].basis.xform(initial_normal)*weight;
            tangent+=binds[bind].basis.xform(initial_tangent)*weight;total+=weight;
        }
        if(total<=1e-5) {
            position=unskinned.xform(points[vertex]);normal=unskinned.basis.xform(initial_normal);tangent=unskinned.basis.xform(initial_tangent);
        } else position/=total;
        points[vertex]=position;
        if(has_normals)directions[vertex]=normal.normalized();
        if(has_tangents) { tangent.normalize();tangent_data[vertex*4]=tangent.x;tangent_data[vertex*4+1]=tangent.y;tangent_data[vertex*4+2]=tangent.z; }
    }
    result[Mesh::ARRAY_VERTEX]=vertices;
    result[Mesh::ARRAY_NORMAL]=normals.is_empty()?Variant():Variant(normals);
    result[Mesh::ARRAY_TANGENT]=tangents.is_empty()?Variant():Variant(tangents);
    result[Mesh::ARRAY_BONES]=Variant();result[Mesh::ARRAY_WEIGHTS]=Variant();return result;
}
}
