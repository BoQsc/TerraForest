#include "static_batch.hpp"
#include <godot_cpp/classes/physics_server3d.hpp>
#include <godot_cpp/classes/world3d.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <algorithm>
#include <cmath>

namespace terraforest {
Transform3D NativeStaticBatch::placement_transform(const Placement &p) {
    return Transform3D(Basis(p[0],p[1],p[2],p[4],p[5],p[6],p[8],p[9],p[10]),Vector3(p[3],p[7],p[11]));
}
void NativeStaticBatch::release_proxy(int64_t id) {
    auto it=collision_bodies.find(id);if(it==collision_bodies.end())return;
    auto *server=PhysicsServer3D::get_singleton();
    body_ids.erase(it->second.body);
    server->free_rid(it->second.body);
    for(auto shape:it->second.shapes)server->free_rid(shape);
    collision_bodies.erase(it);proxy_evictions++;
}
void NativeStaticBatch::clear_proxies() {
    while(!collision_bodies.empty())release_proxy(collision_bodies.begin()->first);
    collision_pending.clear();proxy_candidates=0;
}
NativeStaticBatch::~NativeStaticBatch() {clear_proxies();}
void NativeStaticBatch::_notification(int what) {
    if(what==NOTIFICATION_TRANSFORM_CHANGED)emit_signal("exclusion_changed");
    if(what==NOTIFICATION_EXIT_TREE||what==NOTIFICATION_EXIT_WORLD) {clear_proxies();collision_dirty=true;}
    if(what==NOTIFICATION_ENTER_TREE||what==NOTIFICATION_ENTER_WORLD)collision_dirty=true;
    if(what==NOTIFICATION_EXIT_TREE&&render_streaming) {
        while(!batches.empty())release_batch(batches.begin()->first);
        render_pending.clear();render_dirty=true;
    }
    if(what==NOTIFICATION_ENTER_TREE)render_dirty=true;
}
bool NativeStaticBatch::configure_collision(const AABB &box,double radius,int64_t instance_limit,int64_t builds_per_tick) {
    TypedArray<AABB> boxes;boxes.push_back(box);
    return configure_compound_collision(boxes,radius,instance_limit,builds_per_tick,4096,64);
}
bool NativeStaticBatch::configure_compound_collision(const TypedArray<AABB> &boxes,double radius,int64_t instance_limit,int64_t builds_per_tick,int64_t shape_limit,int64_t shapes_per_tick) {
    if(boxes.is_empty()||boxes.size()>32||!std::isfinite(radius)||radius<0||radius>512||
       instance_limit<1||instance_limit>4096||builds_per_tick<1||builds_per_tick>64||
       shape_limit<boxes.size()||shape_limit>16384||shapes_per_tick<boxes.size()||shapes_per_tick>256)return false;
    std::vector<AABB> parts;AABB combined;
    for(int i=0;i<boxes.size();i++) {
        AABB box=boxes[i];
        if(!box.position.is_finite()||!box.size.is_finite()||box.size.x<=0||box.size.y<=0||box.size.z<=0||
       box.size.x>4096||box.size.y>4096||box.size.z>4096||
       std::abs(box.position.x)>4096||std::abs(box.position.y)>4096||std::abs(box.position.z)>4096)return false;
        combined=i?combined.merge(box):box;parts.push_back(box);
    }
    // Proxy geometry is application-owned asset metadata, not untrusted save data.
    clear_proxies();collision_bounds.clear();proxy_box=combined;proxy_parts=std::move(parts);proxy_radius=radius;
    proxy_shape_limit=int(shape_limit);proxy_shapes_per_tick=int(shapes_per_tick);
    proxy_limit=int(instance_limit);proxy_build_limit=int(builds_per_tick);collision_dirty=true;
    std::set<BlockKey> keys;for(auto &e:groups)keys.insert(e.first);refresh_collision_bounds(keys);
    set_physics_process(radius>0);emit_signal("exclusion_changed");return true;
}
void NativeStaticBatch::set_collision_focus(Vector3 p) {
    if(!p.is_finite())return;
    collision_focus=p;
    if(p.distance_squared_to(selection_focus)>=16)collision_dirty=true;
}
void NativeStaticBatch::invalidate_proxy(int64_t id) {release_proxy(id);collision_dirty=true;}
void NativeStaticBatch::refresh_collision_bounds(const std::set<BlockKey> &keys) {
    if(source_mesh.is_null())return;
    const AABB prototype=proxy_parts.empty()?source_mesh->get_aabb():proxy_box;
    const AABB visual=source_mesh->get_aabb();
    for(auto key:keys) {
        auto group=groups.find(key);collision_bounds.erase(key);
        render_bounds.erase(key);
        if(group==groups.end())continue;
        bool first=true;AABB box,render_box;
        for(auto id:group->second) {
            Transform3D transform=placement_transform(placements.at(id));
            AABB next=transform.xform(prototype),render_next=transform.xform(visual);
            render_box=first?render_next:render_box.merge(render_next);
            box=first?next:box.merge(next);first=false;
        }
        collision_bounds.emplace(key,box);
        render_bounds.emplace(key,render_box);
    }
    if(!keys.empty()) {collision_dirty=true;render_dirty=true;}
}
static double box_distance_squared(const AABB &box,const Vector3 &point) {
    Vector3 end=box.position+box.size;
    Vector3 nearest(std::clamp(point.x,box.position.x,end.x),std::clamp(point.y,box.position.y,end.y),std::clamp(point.z,box.position.z,end.z));
    return nearest.distance_squared_to(point);
}
void NativeStaticBatch::select_proxies() {
    collision_dirty=false;selection_focus=collision_focus;proxy_queries++;invalid_proxies=0;
    std::vector<std::pair<double,int64_t>> candidates;
    double range=(proxy_radius+4)*(proxy_radius+4);
    for(auto &group:collision_bounds)if(box_distance_squared(group.second,collision_focus)<=range) {
        for(auto id:groups.at(group.first)) {
            double distance=box_distance_squared(placement_transform(placements.at(id)).xform(proxy_box),collision_focus);
            if(distance<=range)candidates.emplace_back(distance,id);
        }
    }
    proxy_candidates=int(candidates.size());
    size_t count=std::min(candidates.size(),size_t(std::min(proxy_limit,proxy_shape_limit/int(proxy_parts.size()))));
    std::partial_sort(candidates.begin(),candidates.begin()+count,candidates.end());candidates.resize(count);
    std::set<int64_t> wanted;for(auto &e:candidates)wanted.insert(e.second);
    std::vector<int64_t> remove;for(auto &e:collision_bodies)if(!wanted.count(e.first))remove.push_back(e.first);
    for(auto id:remove)release_proxy(id);
    collision_pending.clear();
    // Reverse order allows constant-time pop_back with nearest-first publication.
    for(auto it=candidates.rbegin();it!=candidates.rend();++it)if(!collision_bodies.count(it->second))collision_pending.push_back(it->second);
}
void NativeStaticBatch::_physics_process(double) {
    if(proxy_radius<=0||!is_inside_tree())return;
    Transform3D current=get_global_transform();
    double determinant=current.basis.determinant();
    proxy_transform_valid=current.is_finite()&&std::isfinite(determinant)&&std::abs(determinant)>=1e-9;
    if(!proxy_transform_valid) {clear_proxies();collision_dirty=true;return;}
    if(current!=collision_transform) {clear_proxies();collision_transform=current;collision_dirty=true;}
    if(collision_dirty)select_proxies();
    auto *server=PhysicsServer3D::get_singleton();
    int build_limit=std::min(proxy_build_limit,proxy_shapes_per_tick/int(proxy_parts.size()));
    for(int i=0;i<build_limit&&!collision_pending.empty();i++) {
        int64_t id=collision_pending.back();collision_pending.pop_back();
        Transform3D world=current*placement_transform(placements.at(id));
        std::vector<PackedVector3Array> hulls;
        bool finite=world.origin.is_finite();
        for(const AABB &part:proxy_parts) {
            PackedVector3Array points;points.resize(8);
            for(int corner=0;corner<8;corner++) {
                Vector3 point=world.basis.xform(part.get_endpoint(corner));finite=finite&&point.is_finite();points.set(corner,point);
            }
            hulls.push_back(points);
        }
        if(!finite) {invalid_proxies++;continue;}
        RID body=server->body_create();server->body_set_mode(body,PhysicsServer3D::BODY_MODE_STATIC);
        std::vector<RID> shapes;
        for(auto &points:hulls) {
            RID shape=server->convex_polygon_shape_create();server->shape_set_data(shape,points);
            server->body_add_shape(body,shape);shapes.push_back(shape);
        }
        server->body_set_collision_layer(body,2);server->body_set_collision_mask(body,0);
        server->body_attach_object_instance_id(body,get_instance_id());
        server->body_set_state(body,PhysicsServer3D::BODY_STATE_TRANSFORM,Transform3D(Basis(),world.origin));
        server->body_set_space(body,get_world_3d()->get_space());
        collision_bodies.emplace(id,ProxyBody{body,std::move(shapes)});body_ids.emplace(body,id);proxy_builds++;
    }
}
int64_t NativeStaticBatch::placement_for_body(RID body) const {
    auto it=body_ids.find(body);return it==body_ids.end()?0:it->second;
}
Dictionary NativeStaticBatch::collision_stats() const {
    Dictionary d;d["enabled"]=proxy_radius>0;d["radius"]=proxy_radius;d["instance_limit"]=proxy_limit;d["builds_per_tick"]=proxy_build_limit;
    d["resident_bodies"]=int(collision_bodies.size());d["pending_bodies"]=int(collision_pending.size());d["candidate_bodies"]=proxy_candidates;
    int effective_limit=proxy_parts.empty()?proxy_limit:std::min(proxy_limit,proxy_shape_limit/int(proxy_parts.size()));
    d["budget_deferred"]=std::max(0,proxy_candidates-effective_limit);d["selection_pending"]=collision_dirty;d["transform_valid"]=proxy_transform_valid;
    d["parts_per_body"]=int(proxy_parts.size());d["resident_shapes"]=int(collision_bodies.size()*proxy_parts.size());
    d["shape_limit"]=proxy_shape_limit;d["shapes_per_tick"]=proxy_shapes_per_tick;
    d["invalid_proxies"]=invalid_proxies;
    d["body_builds"]=int64_t(proxy_builds);d["body_evictions"]=int64_t(proxy_evictions);d["selection_queries"]=int64_t(proxy_queries);return d;
}
}
