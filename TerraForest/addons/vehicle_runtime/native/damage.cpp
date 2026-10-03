// SPDX-License-Identifier: 0BSD
#include "damage.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <cmath>
using namespace godot;
namespace terraforest {
void NativeVehicleDamage::_bind_methods(){
    ClassDB::bind_method(D_METHOD("dent","source","transform","point","direction","radius","depth"),&NativeVehicleDamage::dent);
}
Ref<ArrayMesh> NativeVehicleDamage::dent(const Ref<Mesh> &source,Transform3D transform,Vector3 point,Vector3 direction,double radius,double depth) const {
    Ref<ArrayMesh> array_source=source;
    if(array_source.is_null())return {};
    if(source.is_null()||source->get_surface_count()==0||!transform.is_finite()||!point.is_finite()||!direction.is_finite()||!std::isfinite(radius)||radius<=0||!std::isfinite(depth)||depth<=0||std::abs(transform.basis.determinant())<1e-12)return {};
    // Conservative world bounds: no surface readback/allocation for distant impacts.
    if(!transform.xform(source->get_aabb()).grow(real_t(radius)).has_point(point))return {};
    Transform3D inverse=transform.affine_inverse();
    TypedArray<Array> surfaces;
    bool changed=false;
    for(int s=0;s<source->get_surface_count();++s){
        Array arrays=source->surface_get_arrays(s);
        if(arrays.size()!=Mesh::ARRAY_MAX)return {};
        PackedVector3Array vertices=arrays[Mesh::ARRAY_VERTEX];
        bool surface_changed=false;
        // Packed arrays detach on first write; unchanged channels remain shared.
        for(int64_t i=0;i<vertices.size();++i){
            Vector3 world=transform.xform(vertices[i]);
            double distance=world.distance_to(point);
            if(distance>=radius)continue;
            double t=1-distance/radius,falloff=t*t*(3-2*t);
            vertices.set(i,inverse.xform(world+direction*real_t(depth*falloff)));
            surface_changed=true;
        }
        if(surface_changed){arrays[Mesh::ARRAY_VERTEX]=vertices;changed=true;}
        surfaces.push_back(arrays);
    }
    if(!changed)return {};
    Ref<ArrayMesh> output;output.instantiate();
    for(int s=0;s<source->get_surface_count();++s){
        output->add_surface_from_arrays(array_source->surface_get_primitive_type(s),surfaces[s]);
        output->surface_set_material(s,source->surface_get_material(s));
    }
    return output;
}
}
