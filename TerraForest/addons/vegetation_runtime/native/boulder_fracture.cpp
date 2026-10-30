// SPDX-License-Identifier: 0BSD
#include "boulder_fracture.hpp"
#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/classes/surface_tool.hpp>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/classes/world3d.hpp>
#include <godot_cpp/classes/physics_direct_space_state3d.hpp>
#include <godot_cpp/classes/physics_ray_query_parameters3d.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <algorithm>
#include <cmath>
#include <set>
namespace terraforest {
using namespace godot;
namespace {
struct Vertex {Vector3 p,n;Vector2 uv;Color color;};
using Face=std::vector<Vertex>;
using Fragment=std::vector<Face>;
double clock_seconds(){return Time::get_singleton()->get_ticks_msec()/1000.;}
Vertex mix_vertex(const Vertex &a,const Vertex &b,double t){return {a.p.lerp(b.p,t),a.n.lerp(b.n,t).normalized(),a.uv.lerp(b.uv,t),a.color.lerp(b.color,t)};}
AABB fragment_bounds(const Fragment &faces){AABB box(faces.front().front().p,Vector3());for(const auto &face:faces)for(const auto &v:face)box.expand_to(v.p);return box;}
// Preserve face polygons until the final mesh bake. Re-triangulating a cap
// between cuts creates artificial internal edges and tiny sliver fragments.
Fragment clip(const Fragment &source,Vector3 normal,double distance,bool positive){
    Fragment result;std::vector<Vector3> edge;
    for(const auto &face:source){
        Face polygon;
        for(size_t j=0;j<face.size();++j){const auto &a=face[j],&b=face[(j+1)%face.size()];double da=normal.dot(a.p)-distance,db=normal.dot(b.p)-distance;
            bool inside=positive?da>=0:da<=0,other=positive?db>=0:db<=0;
            if(inside)polygon.push_back(a);
            if(inside!=other){auto v=mix_vertex(a,b,da/(da-db));bool duplicate=false;
                // Adjacent triangles must use the exact same cut vertex as
                // the closing cap, including after successive bisections.
                for(const auto &p:edge)if(p.distance_squared_to(v.p)<1e-12){v.p=p;duplicate=true;break;}
                if(!duplicate)edge.push_back(v.p);polygon.push_back(v);
            }
        }
        if(polygon.size()>=3)result.push_back(std::move(polygon));
    }
    if(edge.size()>=3){
        Vector3 centre;for(auto p:edge)centre+=p;centre/=edge.size();Vector3 outward=positive?-normal:normal;
        Vector3 u=outward.cross(std::abs(outward.y)<.9?Vector3(0,1,0):Vector3(1,0,0)).normalized(),v=outward.cross(u);
        std::sort(edge.begin(),edge.end(),[&](Vector3 a,Vector3 b){a-=centre;b-=centre;return std::atan2(a.dot(v),a.dot(u))<std::atan2(b.dot(v),b.dot(u));});
        Face cap;for(auto p:edge)cap.push_back({p,outward,Vector2(p.dot(u)*2+.5,p.dot(v)*2+.5),Color(.78,.78,.78,1)});
        result.push_back(std::move(cap));
    }
    return result;
}
double roll_angle(Vector3 centre,int stage){return (stage==1?.10:stage==2?.20:.40)*(.8+.4*std::clamp(std::abs(centre.x)*2.+std::abs(centre.z),0.,1.));}
struct PiecePose {Vector3 pivot;double support;};
PiecePose resting_pose(const Fragment &fragment,int stage){
    auto box=fragment_bounds(fragment);Vector3 centre=box.get_center();
    Vector3 direction(centre.x,0,centre.z);direction=direction.normalized();
    Vector3 axis(direction.z,0,-direction.x),pivot(centre.x,box.position.y,centre.z);
    Basis roll(axis,roll_angle(centre,stage));double lowest=1e10;
    for(const auto &face:fragment)for(const auto &v:face)lowest=std::min(lowest,double((pivot+roll.xform(v.p-pivot)).y));
    return {pivot,(stage==3?-.125:box.position.y)-lowest};
}
Ref<ArrayMesh> combined_mesh(const std::vector<Fragment> &fragments,int stage,const std::vector<Fragment> &parents){
    Ref<SurfaceTool> builder;builder.instantiate();builder->begin(Mesh::PRIMITIVE_TRIANGLES);
    builder->set_custom_format(0,SurfaceTool::CUSTOM_RGBA_FLOAT);
    for(size_t piece=0;piece<fragments.size();++piece){const auto &fragment=fragments[piece];auto box=fragment_bounds(fragment);Vector3 centre=box.get_center();
        auto pose=resting_pose(fragment,stage);auto parent=stage>1?resting_pose(parents[piece/2],stage-1):PiecePose{Vector3(),0};
        // Keep each chunk's volume: rotate about its own lower edge, never
        // collapse all piece centres onto a shared horizontal layer.
        double support=pose.support/.5+.5;
        auto emit=[&](const Vertex &v){builder->set_normal(v.n);builder->set_uv(v.uv);builder->set_uv2(Vector2(centre.x,centre.z));
            // Children start in their parent's settled pose, without snapping
            // the already fractured boulder back together at the next break.
            builder->set_custom(0,Color(parent.pivot.x,parent.pivot.y,parent.pivot.z,parent.support));
            // Pivot, identity and precomputed support correction for the GPU.
            builder->set_color(Color(v.color.r,box.position.y/.4f+.5f,centre.y/.4f+.5f,support));builder->add_vertex(v.p);};
        for(const auto &face:fragment){
            if(face.size()==3){for(const auto &v:face)emit(v);continue;}
            Vertex middle;middle.color=Color(0,0,0,0);
            for(const auto &v:face){middle.p+=v.p;middle.n+=v.n;middle.uv+=v.uv;middle.color+=v.color;}
            middle.p/=face.size();middle.n=middle.n.normalized();middle.uv/=face.size();middle.color/=face.size();
            for(size_t j=0;j<face.size();++j){emit(middle);emit(face[j]);emit(face[(j+1)%face.size()]);}
        }
    }
    builder->generate_tangents();return builder->commit();
}
}
void NativeBoulderFracture::_bind_methods(){
    ClassDB::bind_method(D_METHOD("configure","mesh","material","durability"),&NativeBoulderFracture::configure);
    ClassDB::bind_method(D_METHOD("configure_horizon","distant"),&NativeBoulderFracture::configure_horizon);
    ClassDB::bind_method(D_METHOD("upsert_rows","ids","transforms"),&NativeBoulderFracture::upsert_rows);
    ClassDB::bind_method(D_METHOD("sync_damage","id","hit_from"),&NativeBoulderFracture::sync_damage,DEFVAL(Vector3()));
    ClassDB::bind_method(D_METHOD("finish","id"),&NativeBoulderFracture::finish);
    ClassDB::bind_method(D_METHOD("remove_rows","ids"),&NativeBoulderFracture::remove_rows);
    ClassDB::bind_method(D_METHOD("clear"),&NativeBoulderFracture::clear);
    ClassDB::bind_method(D_METHOD("advance","eye"),&NativeBoulderFracture::advance);
    ClassDB::bind_method(D_METHOD("advance_view","eye","projection_scale"),&NativeBoulderFracture::advance_view);
    ClassDB::bind_method(D_METHOD("statistics"),&NativeBoulderFracture::statistics);
    ClassDB::bind_method(D_METHOD("stage","id"),&NativeBoulderFracture::stage);
    ClassDB::bind_method(D_METHOD("stage_mesh","stage"),&NativeBoulderFracture::stage_mesh);
}
static bool build_fractures(const Ref<Mesh> &source,std::array<Ref<Mesh>,4> &meshes,int &triangles){
    if(source.is_null()||source->get_surface_count()!=1)return false;
    Array arrays=source->surface_get_arrays(0);PackedVector3Array vertices=arrays[Mesh::ARRAY_VERTEX],normals=arrays[Mesh::ARRAY_NORMAL];
    PackedVector2Array uv=arrays[Mesh::ARRAY_TEX_UV];PackedColorArray colors=arrays[Mesh::ARRAY_COLOR];PackedInt32Array indices=arrays[Mesh::ARRAY_INDEX];
    if(indices.is_empty())for(int i=0;i<vertices.size();++i)indices.append(i);
    if(indices.size()%3||normals.size()!=vertices.size()||uv.size()!=vertices.size())return false;
    Fragment whole;for(int i=0;i<indices.size();i+=3){Face face;for(int j=0;j<3;++j){int index=indices[i+j];if(index<0||index>=vertices.size())return false;face.push_back({vertices[index],normals[index],uv[index],colors.size()==vertices.size()?colors[index]:Color(1,1,1)});}whole.push_back(std::move(face));}
    if(whole.empty()||indices.size()>30000)return false;
    meshes[0]=source;std::vector<Fragment> pieces{whole};
    for(int depth=1;depth<=3;++depth){std::vector<Fragment> next;
        for(size_t i=0;i<pieces.size();++i){auto box=fragment_bounds(pieces[i]);Vector3 normal;normal[box.size.x>=box.size.z?0:2]=1;
            // Upright irregular cracks create solid chunks, not stacked plates.
            Vector3 twist=Vector3(.16f*std::sin(double(i)*17+depth),.045f*std::cos(double(i)*13+depth),.16f*std::sin(double(i)*7-depth));normal=(normal+twist).normalized();
            double plane=normal.dot(box.get_center());auto a=clip(pieces[i],normal,plane,true),b=clip(pieces[i],normal,plane,false);
            if(a.empty()||b.empty())return false;next.push_back(std::move(a));next.push_back(std::move(b));
        }
        meshes[depth]=combined_mesh(next,depth,pieces);pieces=std::move(next);if(meshes[depth].is_null())return false;
        PackedVector3Array cached_vertices=meshes[depth]->surface_get_arrays(0)[Mesh::ARRAY_VERTEX];triangles+=cached_vertices.size()/3;
    }
    return true;
}
bool NativeBoulderFracture::configure(const Ref<Mesh> &source,const Ref<ShaderMaterial> &appearance,const Ref<RefCounted> &damage){
    if(material.is_valid()||appearance.is_null()||(damage.is_valid()&&!damage->has_method("damage")))return false;
    std::array<Ref<Mesh>,4> meshes;int triangles=0;
    if(!build_fractures(source,meshes,triangles))return false;
    material=appearance;durability=damage;cache_triangles=triangles;
    for(int index=0;index<4;++index){auto &group=groups[index];group.mesh=meshes[index];group.appearance=material;
        group.instances.instantiate();group.instances->set_transform_format(MultiMesh::TRANSFORM_3D);group.instances->set_use_custom_data(true);group.instances->set_mesh(group.mesh);group.instances->set_instance_count(capacity);group.instances->set_visible_instance_count(0);
        group.node=memnew(MultiMeshInstance3D);group.node->set_multimesh(group.instances);group.node->set_material_override(group.appearance);add_child(group.node);}
    return true;
}
bool NativeBoulderFracture::configure_horizon(const Ref<Mesh> &distant){
    if(material.is_null()||horizon||!rocks.empty())return false;
    std::array<Ref<Mesh>,4> meshes;int triangles=0;
    if(!build_fractures(distant,meshes,triangles))return false;
    capacity=4096;group_count=8;horizon=true;cache_triangles+=triangles;
    for(int index=0;index<8;++index){auto &group=groups[index];
        group.appearance=material->duplicate();
        group.appearance->set_shader_parameter("horizon_tier",index/4);
        if(index>=4){group.mesh=meshes[index-4];group.instances.instantiate();group.instances->set_transform_format(MultiMesh::TRANSFORM_3D);group.instances->set_use_custom_data(true);group.instances->set_mesh(group.mesh);
            group.node=memnew(MultiMeshInstance3D);group.node->set_multimesh(group.instances);group.node->set_cast_shadows_setting(GeometryInstance3D::SHADOW_CASTING_SETTING_OFF);add_child(group.node);}
        group.instances->set_instance_count(capacity);group.instances->set_visible_instance_count(0);group.node->set_material_override(group.appearance);
    }
    return true;
}
int NativeBoulderFracture::damage_stage(int64_t id)const{if(durability.is_null())return 0;int damage=durability->call("damage",String("cover:")+String::num_int64(id),240);return std::clamp(damage/80,0,2);}
void NativeBoulderFracture::bounds(int stage){auto &g=groups[stage];AABB box;bool first=true;
    for(auto id:g.ids){const auto &r=rocks.at(id);AABB local=stage%4>0?AABB(Vector3(-.45,-.55,-.4),Vector3(.9,.8,.8)):g.mesh->get_aabb();AABB world=r.pose.xform(local);box=first?world:box.merge(world);first=false;}
    if(!first)g.instances->set_custom_aabb(box);
}
Color NativeBoulderFracture::custom(const Rock &r){return Color(r.began,r.stage+r.impact*.4f+(r.tap?.5f:0),r.slope.x,r.slope.y);}
void NativeBoulderFracture::attach_tier(int64_t id,int tier){auto &rock=rocks.at(id);auto &group=groups[rock.stage+4*tier];
    rock.slots[tier]=int(group.ids.size());group.ids.push_back(id);
    group.instances->set_instance_transform(rock.slots[tier],rock.pose);group.instances->set_instance_custom_data(rock.slots[tier],custom(rock));group.dirty=true;
}
void NativeBoulderFracture::detach_tier(int64_t id,int tier){auto &rock=rocks.at(id);const int slot=rock.slots[tier];if(slot<0)return;
    auto &group=groups[rock.stage+4*tier];const int64_t tail=group.ids.back();group.ids[slot]=tail;group.ids.pop_back();rock.slots[tier]=-1;
    if(tail!=id){auto &moved=rocks.at(tail);moved.slots[tier]=slot;group.instances->set_instance_transform(slot,moved.pose);group.instances->set_instance_custom_data(slot,custom(moved));}
    group.dirty=true;
}
void NativeBoulderFracture::select_tiers(int64_t id){auto &rock=rocks.at(id);
    const float scale=std::max({rock.pose.basis.get_column(0).length(),rock.pose.basis.get_column(1).length(),rock.pose.basis.get_column(2).length()})/12.f;
    const float distance=view_eye.distance_to(rock.pose.origin)/std::max(.001f,scale*projection);
    const bool selected[2]={!horizon||distance<104.f,horizon&&distance>=72.f};
    for(int tier=0;tier<2;++tier){if(selected[tier]&&rock.slots[tier]<0)attach_tier(id,tier);else if(!selected[tier])detach_tier(id,tier);}
}
void NativeBoulderFracture::attach(int64_t id){select_tiers(id);}
void NativeBoulderFracture::detach(int64_t id){detach_tier(id,0);detach_tier(id,1);}
void NativeBoulderFracture::flush(){
    for(int index=0;index<group_count;++index)if(groups[index].dirty){groups[index].instances->set_visible_instance_count(groups[index].ids.size());bounds(index);groups[index].dirty=false;}
}
bool NativeBoulderFracture::upsert_rows(const PackedInt64Array &ids,const PackedFloat32Array &values){
    if(material.is_null()||values.size()!=ids.size()*12||ids.size()>capacity)return false;
    std::set<int64_t> unique;int added=0;
    for(int i=0;i<ids.size();++i){if(ids[i]<=0||!unique.insert(ids[i]).second)return false;if(!rocks.count(ids[i]))++added;
        const float *p=values.ptr()+i*12;Transform3D t(Basis(p[0],p[1],p[2],p[4],p[5],p[6],p[8],p[9],p[10]),Vector3(p[3],p[7],p[11]));if(!t.is_finite()||std::abs(t.basis.determinant())<1e-8)return false;}
    if(rocks.size()+added>size_t(capacity))return false;
    for(int i=0;i<ids.size();++i){auto id=ids[i];const float *p=values.ptr()+i*12;Transform3D t(Basis(p[0],p[1],p[2],p[4],p[5],p[6],p[8],p[9],p[10]),Vector3(p[3],p[7],p[11]));int stage=damage_stage(id);
        auto at=rocks.find(id);if(at!=rocks.end()&&at->second.pose==t&&at->second.stage==stage)continue;
        if(at!=rocks.end())detach(id);Rock rock;rock.pose=t;rock.stage=stage;rock.began=clock_seconds()-1.;rocks[id]=rock;attach(id);}
    flush();return true;
}
bool NativeBoulderFracture::sync_damage(int64_t id,Vector3 hit_from){auto at=rocks.find(id);if(at==rocks.end()||at->second.stage==3||!hit_from.is_finite())return false;
    auto &r=at->second;Vector3 local=r.pose.affine_inverse().xform(hit_from);double angle=std::atan2(local.z,local.x);if(angle<0)angle+=6.283185307;
    r.impact=angle/6.283185307;r.began=clock_seconds();int stage=damage_stage(id);r.tap=stage==r.stage;
    if(r.tap){for(int tier=0;tier<2;++tier)if(r.slots[tier]>=0)groups[r.stage+tier*4].instances->set_instance_custom_data(r.slots[tier],custom(r));return true;}
    detach(id);r.stage=stage;attach(id);flush();return true;
}
bool NativeBoulderFracture::finish(int64_t id){auto at=rocks.find(id);if(at==rocks.end()||at->second.stage==3)return false;
    detach(id);auto &r=at->second;r.stage=3;r.began=clock_seconds();r.tap=false;
    if(is_inside_tree()){auto ray=PhysicsRayQueryParameters3D::create(r.pose.origin+Vector3(0,2,0),r.pose.origin-Vector3(0,24,0),1);Dictionary hit=get_world_3d()->get_direct_space_state()->intersect_ray(ray);
        if(!hit.is_empty()){Vector3 n=r.pose.basis.transposed().xform(Vector3(hit["normal"]));if(std::abs(n.y)>.01)r.slope=Vector2(-n.x/n.y,-n.z/n.y);}}
    attach(id);flush();return true;
}
void NativeBoulderFracture::remove_rows(const PackedInt64Array &ids){for(auto id:ids){auto at=rocks.find(id);if(at!=rocks.end()&&at->second.stage!=3){detach(id);rocks.erase(at);}}flush();}
void NativeBoulderFracture::clear(){rocks.clear();for(auto &g:groups){g.ids.clear();if(g.instances.is_valid())g.instances->set_visible_instance_count(0);}}
void NativeBoulderFracture::advance_view(Vector3 eye,double projection_scale){
    if(!std::isfinite(projection_scale)||projection_scale<.1||projection_scale>32)return;
    if(projection!=float(projection_scale)){projection=float(projection_scale);view_valid=false;}advance(eye);
}
void NativeBoulderFracture::advance(Vector3 eye){if(material.is_null()||!eye.is_finite())return;double now=clock_seconds();
    const bool view_changed=!view_valid||view_eye!=eye;view_eye=eye;view_valid=true;
    for(int index=0;index<group_count;++index){auto appearance=groups[index].appearance;appearance->set_shader_parameter("cover_clock",now);appearance->set_shader_parameter("cover_eye",eye);appearance->set_shader_parameter("horizon_projection",projection);}
    for(auto it=rocks.begin();it!=rocks.end();){if(it->second.stage==3&&now-it->second.began>=2.6){auto id=it->first;++it;detach(id);rocks.erase(id);}else{if(horizon&&view_changed)select_tiers(it->first);++it;}}
    flush();
}
int64_t NativeBoulderFracture::stage(int64_t id)const{auto at=rocks.find(id);return at==rocks.end()?-1:at->second.stage;}
Ref<Mesh> NativeBoulderFracture::stage_mesh(int64_t stage)const{return stage>=0&&stage<group_count?groups[stage].mesh:Ref<Mesh>();}
Dictionary NativeBoulderFracture::statistics()const{Dictionary out;int near=0,far=0;for(int index=0;index<4;++index){near+=groups[index].ids.size();far+=groups[index+4].ids.size();}out["roots"]=int64_t(rocks.size());out["draw_groups"]=group_count;out["near"]=near;out["far"]=far;out["cached_triangles"]=cache_triangles;out["capacity"]=capacity;out["horizon"]=horizon;return out;}
}
