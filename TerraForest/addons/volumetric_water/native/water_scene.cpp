// SPDX-License-Identifier: 0BSD
#include "water_scene.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/classes/mesh_instance3d.hpp>
#include <godot_cpp/classes/time.hpp>
using namespace godot;
namespace terraforest {
void NativeWaterScene::_bind_methods(){
    ClassDB::bind_method(D_METHOD("begin_publish","network","material"),&NativeWaterScene::begin_publish);
    ClassDB::bind_method(D_METHOD("advance","work_budget"),&NativeWaterScene::advance);
    ClassDB::bind_method(D_METHOD("refresh"),&NativeWaterScene::refresh);
    ClassDB::bind_method(D_METHOD("probe","point"),&NativeWaterScene::probe);
    ClassDB::bind_method(D_METHOD("depth_at","point"),&NativeWaterScene::depth_at);
    ClassDB::bind_method(D_METHOD("statistics"),&NativeWaterScene::statistics);
}
bool NativeWaterScene::identity() const{return get_transform()==Transform3D()&&(!is_inside_tree()||get_global_transform()==Transform3D());}
bool NativeWaterScene::valid(const Ref<NativeWaterNetwork> &n,uint64_t revision) const{return identity()&&n.is_valid()&&n->status==1&&n->current()&&n->water_revision==revision;}
bool NativeWaterScene::begin_publish(const Ref<NativeWaterNetwork> &water,const Ref<Material> &water_material){
    if(status==0||retiring||water.is_null()||water_material.is_null()||!valid(water,water->water_revision)||bool(water->solver->statistics()["busy"]))return false;
    pending=water;pending_revision=water->water_revision;material=water_material;piece=0;staged_regions=0;
    staging=memnew(Node3D);staging->set_name("FiniteWaterStaging");staging->set_visible(false);add_child(staging);
    status=0;set_process(true);return true;
}
void NativeWaterScene::refresh(){if(shown)shown->set_visible(valid(active,active_revision));}
void NativeWaterScene::cancel(){
    status=-2;surface.unref();pending.unref();material.unref();
    if(staging){retiring=staging;staging=nullptr;}
}
Dictionary NativeWaterScene::advance(int64_t budget){
    int64_t work=0;
    if(budget<1||budget>2048){Dictionary out=statistics();out["ok"]=false;out["work_units"]=0;return out;}
    refresh();
    // At most one regional mesh retirement per call; no bulk group queue_free.
    if(retiring){
        if(retiring->get_child_count()){auto child=retiring->get_child(0);retiring->remove_child(child);child->queue_free();}
        else{remove_child(retiring);retiring->queue_free();retiring=nullptr;}
        ++work;++work_total;
    }else if(status==0){
        if(!valid(pending,pending_revision))cancel();
        const uint64_t start=Time::get_singleton()->get_ticks_usec();
        while(status==0&&work<budget){
            ++work;++work_total;
            if(piece==int(pending->pieces.size())){
                if(shown){shown->set_visible(false);retiring=shown;}
                active=pending;active_revision=pending_revision;pending.unref();
                shown=staging;staging=nullptr;shown->set_name("FiniteWaterActive");shown->set_visible(true);
                published_regions=staged_regions;material.unref();status=1;++publications;break;
            }
            if(surface.is_null()){
                surface.instantiate();if(!surface->begin(pending,pending->pieces[piece].coordinate)){cancel();break;}
            }else if(surface->status==0){surface->unit();++surface->work_total;}
            else if(surface->status!=1){cancel();break;}
            else{
                const Array arrays=surface->surface_arrays();
                if(arrays.size()!=Mesh::ARRAY_MAX){cancel();break;}
                const PackedVector3Array vertices=arrays[Mesh::ARRAY_VERTEX];
                if(!vertices.is_empty()){
                    Ref<ArrayMesh> mesh;mesh.instantiate();mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES,arrays);
                    auto instance=memnew(MeshInstance3D);instance->set_mesh(mesh);instance->set_material_override(material);
                    instance->set_cast_shadows_setting(GeometryInstance3D::SHADOW_CASTING_SETTING_OFF);
                    staging->add_child(instance);
                }
                ++piece;++staged_regions;surface.unref();
                // A GPU resource upload is indivisible; never upload two in one slice.
                break;
            }
            if(work%16==0&&Time::get_singleton()->get_ticks_usec()-start>=2000)break;
        }
    }
    Dictionary out=statistics();out["ok"]=status>=0;out["work_units"]=work;return out;
}
void NativeWaterScene::_process(double){refresh();if(status==0||retiring)advance(128);}
Dictionary NativeWaterScene::probe(const Vector3 &point){
    refresh();if(valid(active,active_revision))return active->probe(point);
    Dictionary out;out["ok"]=false;out["wet"]=false;return out;
}
double NativeWaterScene::depth_at(const Vector3 &point){const Dictionary result=probe(point);return double(result.get("depth_m",0.0));}
Dictionary NativeWaterScene::statistics() const {
    Dictionary out;out["status"]=status;out["ready"]=valid(active,active_revision);out["publications"]=publications;
    out["regions"]=published_regions;out["staged_regions"]=staged_regions;out["retiring"]=retiring!=nullptr;out["work_units_total"]=work_total;
    return out;
}
}
