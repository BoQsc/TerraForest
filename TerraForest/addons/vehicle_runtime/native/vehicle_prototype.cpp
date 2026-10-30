// SPDX-License-Identifier: 0BSD
#include "vehicle_prototype.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/classes/standard_material3d.hpp>
#include <godot_cpp/classes/rendering_server.hpp>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <algorithm>
#include <cmath>
#include <map>
#include <set>
#include <vector>
using namespace godot;
namespace terraforest {
namespace {
constexpr int MAX_VERTICES=131072,MAX_INDICES=786432,MAX_SURFACES=64,MAX_LODS=128;
constexpr int64_t MAX_BYTES=32*1024*1024;
struct Surface {Array arrays;Transform3D transform;std::map<float,PackedInt32Array> levels;int offset=0,count=0;};
struct Group {Ref<Material> material;uint64_t channels=0;std::vector<Surface> surfaces;int vertices=0;};
Dictionary failure(const char *reason){Dictionary result;result["ok"]=false;result["reason"]=reason;return result;}
bool compatible(const Ref<Material> &material){
    if(material.is_null())return true;
    Ref<StandardMaterial3D> standard=material;
    if(standard.is_null()||standard->get_next_pass().is_valid()||standard->get_transparency()!=BaseMaterial3D::TRANSPARENCY_DISABLED||standard->get_billboard_mode()!=BaseMaterial3D::BILLBOARD_DISABLED||standard->is_grow_enabled()||standard->get_distance_fade()!=BaseMaterial3D::DISTANCE_FADE_DISABLED)return false;
    for(auto flag:{BaseMaterial3D::FLAG_FIXED_SIZE,BaseMaterial3D::FLAG_UV1_USE_TRIPLANAR,BaseMaterial3D::FLAG_UV2_USE_TRIPLANAR,BaseMaterial3D::FLAG_PARTICLE_TRAILS_MODE,BaseMaterial3D::FLAG_USE_Z_CLIP_SCALE,BaseMaterial3D::FLAG_USE_FOV_OVERRIDE})if(standard->get_flag(flag))return false;
    return true;
}
bool valid_indices(const PackedInt32Array &indices,int vertices){
    if(indices.is_empty()||indices.size()%3)return false;
    for(auto index:indices)if(index<0||index>=vertices)return false;
    return true;
}
void append_indices(PackedInt32Array &target,const PackedInt32Array &source,int offset){
    const int start=target.size(),count=source.size();target.resize(start+count);int32_t *data=target.ptrw()+start;const int32_t *input=source.ptr();
    for(int index=0;index<count;++index)data[index]=input[index]+offset;
}
}
void NativeVehiclePrototype::_bind_methods(){ClassDB::bind_method(D_METHOD("bake","parts"),&NativeVehiclePrototype::bake);}
Dictionary NativeVehiclePrototype::bake(const Array &parts) const {
    const uint64_t began=Time::get_singleton()->get_ticks_usec();
    if(parts.size()<2||parts.size()>64)return failure("part_count");
    std::vector<Group> groups;int total_vertices=0,total_indices=0,total_surfaces=0,source_lods=0;
    int64_t read_bytes=0;
    for(int part_index=0;part_index<parts.size();++part_index){
        if(parts[part_index].get_type()!=Variant::DICTIONARY)return failure("part_type");
        Dictionary part=parts[part_index];Variant source=part.get("mesh",Variant()),pose=part.get("transform",Variant()),override=part.get("material",Variant());
        if(source.get_type()!=Variant::OBJECT||pose.get_type()!=Variant::TRANSFORM3D)return failure("part_fields");
        Ref<ArrayMesh> mesh=source;Transform3D transform=pose;Ref<Material> material_override;
        if(mesh.is_null()||mesh->get_blend_shape_count()!=0||!transform.is_finite()||!transform.basis.is_conformal()||transform.basis.determinant()<=.000001)return failure("mesh_or_transform");
        if(override.get_type()!=Variant::NIL){
            if(override.get_type()!=Variant::OBJECT)return failure("material_type");
            Object *object=override;if(object&&!Object::cast_to<Material>(object))return failure("material_type");material_override=override;
        }
        for(int surface_index=0;surface_index<mesh->get_surface_count();++surface_index){
            if(++total_surfaces>MAX_SURFACES)return failure("surface_budget");
            const int count=mesh->surface_get_array_len(surface_index),indices=mesh->surface_get_array_index_len(surface_index);
            total_vertices+=count;total_indices+=indices;
            if(count<1||count>65535||indices<3||total_vertices>MAX_VERTICES||total_indices>MAX_INDICES)return failure("geometry_budget");
            const uint64_t channels=uint64_t(mesh->surface_get_format(surface_index))&((1<<Mesh::ARRAY_MAX)-1);
            constexpr uint64_t supported=Mesh::ARRAY_FORMAT_VERTEX|Mesh::ARRAY_FORMAT_NORMAL|Mesh::ARRAY_FORMAT_TANGENT|Mesh::ARRAY_FORMAT_COLOR|Mesh::ARRAY_FORMAT_TEX_UV|Mesh::ARRAY_FORMAT_TEX_UV2|Mesh::ARRAY_FORMAT_INDEX;
            if((channels&~supported)||!(channels&Mesh::ARRAY_FORMAT_VERTEX)||mesh->surface_get_primitive_type(surface_index)!=Mesh::PRIMITIVE_TRIANGLES)return failure("vertex_format");
            Ref<Material> material=material_override.is_valid()?material_override:mesh->surface_get_material(surface_index);
            if(!compatible(material))return failure("material_semantics");
            int group_index=0;
            for(;group_index<int(groups.size());++group_index)if(groups[group_index].material==material&&groups[group_index].channels==channels)break;
            if(group_index==int(groups.size())){Group group;group.material=material;group.channels=channels;groups.push_back(std::move(group));}
            auto &group=groups[group_index];Surface surface;surface.transform=transform;surface.offset=group.vertices;surface.count=count;
            surface.arrays=mesh->surface_get_arrays(surface_index);
            if(surface.arrays.size()!=Mesh::ARRAY_MAX||surface.arrays[Mesh::ARRAY_VERTEX].get_type()!=Variant::PACKED_VECTOR3_ARRAY||surface.arrays[Mesh::ARRAY_INDEX].get_type()!=Variant::PACKED_INT32_ARRAY)return failure("vertex_arrays");
            const PackedInt32Array base=surface.arrays[Mesh::ARRAY_INDEX];if(!valid_indices(base,count))return failure("indices");
            surface.levels[0]=base;read_bytes+=count*80+indices*4;
            Dictionary raw=RenderingServer::get_singleton()->mesh_get_surface(mesh->get_rid(),surface_index);
            Array lods=raw.get("lods",Array());if(lods.size()>32)return failure("lod_count");
            for(int level=0;level<lods.size();++level){
                if(lods[level].get_type()!=Variant::DICTIONARY)return failure("lod_fields");
                Dictionary lod=lods[level];Variant edge=lod.get("edge_length",Variant()),data=lod.get("index_data",Variant());
                if(edge.get_type()!=Variant::FLOAT||data.get_type()!=Variant::PACKED_BYTE_ARRAY)return failure("lod_fields");
                const float error=float(edge);PackedByteArray bytes=data;
                read_bytes+=bytes.size();if(read_bytes>MAX_BYTES||bytes.size()%6||bytes.is_empty()||!std::isfinite(error)||error<=0)return failure("lod_budget_or_error");
                const int decoded_count=bytes.size()/2;PackedInt32Array decoded;decoded.resize(decoded_count);int32_t *destination=decoded.ptrw();const uint8_t *input=bytes.ptr();
                for(int index=0;index<decoded_count;++index)destination[index]=input[index*2]|(int32_t(input[index*2+1])<<8);
                if(!valid_indices(decoded,count))return failure("lod_indices");
                surface.levels[error]=decoded;++source_lods;
            }
            group.vertices+=count;group.surfaces.push_back(std::move(surface));
        }
    }
    const uint64_t read_us=Time::get_singleton()->get_ticks_usec()-began;
    if(groups.empty()||groups.size()>=size_t(parts.size()))return failure("no_draw_reduction");
    Array result_parts;int64_t payload_bytes=0;int baked_lods=0;
    uint64_t upload_us=0;
    for(auto &group:groups){
        Array arrays;arrays.resize(Mesh::ARRAY_MAX);
        PackedVector3Array vertices,normals;PackedVector2Array uv,uv2;PackedColorArray colors;PackedFloat32Array tangents;PackedInt32Array indices;
        vertices.resize(group.vertices);
        if(group.channels&Mesh::ARRAY_FORMAT_NORMAL)normals.resize(group.vertices);
        if(group.channels&Mesh::ARRAY_FORMAT_TANGENT)tangents.resize(group.vertices*4);
        if(group.channels&Mesh::ARRAY_FORMAT_COLOR)colors.resize(group.vertices);
        if(group.channels&Mesh::ARRAY_FORMAT_TEX_UV)uv.resize(group.vertices);
        if(group.channels&Mesh::ARRAY_FORMAT_TEX_UV2)uv2.resize(group.vertices);
        Vector3 *vertex_data=vertices.ptrw(),*normal_data=normals.ptrw();Vector2 *uv_data=uv.ptrw(),*uv2_data=uv2.ptrw();Color *color_data=colors.ptrw();float *tangent_data=tangents.ptrw();
        std::set<float> thresholds;
        for(const auto &surface:group.surfaces){
            PackedVector3Array source_vertices=surface.arrays[Mesh::ARRAY_VERTEX];
            if(source_vertices.size()!=surface.count)return failure("vertices");
            PackedVector3Array source_normals;PackedFloat32Array source_tangents;PackedColorArray source_colors;PackedVector2Array source_uv,source_uv2;
            if(!normals.is_empty())source_normals=surface.arrays[Mesh::ARRAY_NORMAL];if(!tangents.is_empty())source_tangents=surface.arrays[Mesh::ARRAY_TANGENT];
            if(!colors.is_empty())source_colors=surface.arrays[Mesh::ARRAY_COLOR];if(!uv.is_empty())source_uv=surface.arrays[Mesh::ARRAY_TEX_UV];if(!uv2.is_empty())source_uv2=surface.arrays[Mesh::ARRAY_TEX_UV2];
            const int count=source_vertices.size();const int offset=surface.offset;const Basis normal_basis=surface.transform.basis.inverse().transposed();
            if((!normals.is_empty()&&source_normals.size()!=count)||(!tangents.is_empty()&&source_tangents.size()!=count*4)||(!colors.is_empty()&&source_colors.size()!=count)||(!uv.is_empty()&&source_uv.size()!=count)||(!uv2.is_empty()&&source_uv2.size()!=count))return failure("attribute_lengths");
            const Vector3 *source_vertex_data=source_vertices.ptr(),*source_normal_data=source_normals.ptr();const Vector2 *source_uv_data=source_uv.ptr(),*source_uv2_data=source_uv2.ptr();const Color *source_color_data=source_colors.ptr();const float *source_tangent_data=source_tangents.ptr();
            for(int vertex=0;vertex<count;++vertex){
                if(!source_vertex_data[vertex].is_finite())return failure("nonfinite_vertex");
                vertex_data[offset+vertex]=surface.transform.xform(source_vertex_data[vertex]);
                if(normal_data){
                    if(!source_normal_data[vertex].is_finite()||source_normal_data[vertex].length_squared()<.000001)return failure("normal");
                    normal_data[offset+vertex]=normal_basis.xform(source_normal_data[vertex]).normalized();
                }
                if(tangent_data){
                    Vector3 tangent=surface.transform.basis.xform(Vector3(source_tangent_data[vertex*4],source_tangent_data[vertex*4+1],source_tangent_data[vertex*4+2])).normalized();
                    if(!tangent.is_finite()||tangent.length_squared()<.000001||!std::isfinite(source_tangent_data[vertex*4+3]))return failure("tangent");
                    for(int axis=0;axis<3;++axis)tangent_data[(offset+vertex)*4+axis]=tangent[axis];tangent_data[(offset+vertex)*4+3]=source_tangent_data[vertex*4+3];
                }
                if(color_data)color_data[offset+vertex]=source_color_data[vertex];
                if(uv_data){if(!source_uv_data[vertex].is_finite())return failure("uv");uv_data[offset+vertex]=source_uv_data[vertex];}
                if(uv2_data){if(!source_uv2_data[vertex].is_finite())return failure("uv2");uv2_data[offset+vertex]=source_uv2_data[vertex];}
            }
            append_indices(indices,surface.levels.begin()->second,offset);
            for(const auto &level:surface.levels)if(level.first>0)thresholds.insert(level.first);
        }
        arrays[Mesh::ARRAY_VERTEX]=vertices;arrays[Mesh::ARRAY_INDEX]=indices;
        if(!normals.is_empty())arrays[Mesh::ARRAY_NORMAL]=normals;if(!tangents.is_empty())arrays[Mesh::ARRAY_TANGENT]=tangents;
        if(!colors.is_empty())arrays[Mesh::ARRAY_COLOR]=colors;if(!uv.is_empty())arrays[Mesh::ARRAY_TEX_UV]=uv;if(!uv2.is_empty())arrays[Mesh::ARRAY_TEX_UV2]=uv2;
        payload_bytes+=group.vertices*80+indices.size()*4;
        if(thresholds.size()>MAX_LODS)return failure("merged_lod_budget");
        Dictionary lods;
        for(float error:thresholds){
            PackedInt32Array combined;
            for(const auto &surface:group.surfaces){auto found=surface.levels.upper_bound(error);--found;append_indices(combined,found->second,surface.offset);}
            payload_bytes+=combined.size()*4;if(payload_bytes>MAX_BYTES)return failure("output_budget");
            lods[error]=combined;++baked_lods;
        }
        const uint64_t upload_began=Time::get_singleton()->get_ticks_usec();
        Ref<ArrayMesh> mesh;mesh.instantiate();mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES,arrays,Array(),lods);mesh->surface_set_material(0,group.material);
        upload_us+=Time::get_singleton()->get_ticks_usec()-upload_began;
        Dictionary row;row["mesh"]=mesh;row["transform"]=Transform3D();row["material"]=group.material;result_parts.push_back(row);
    }
    Dictionary result;result["ok"]=true;result["parts"]=result_parts;result["source_parts"]=parts.size();result["source_lods"]=source_lods;result["baked_lods"]=baked_lods;result["payload_bytes"]=payload_bytes;result["read_us"]=int64_t(read_us);result["upload_us"]=int64_t(upload_us);result["bake_us"]=int64_t(Time::get_singleton()->get_ticks_usec()-began);return result;
}
}
