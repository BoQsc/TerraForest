// SPDX-License-Identifier: 0BSD
#include "block_world.hpp"
#include <godot_cpp/classes/collision_shape3d.hpp>
#include <godot_cpp/classes/concave_polygon_shape3d.hpp>
#include <godot_cpp/classes/time.hpp>
#include <algorithm>
#include <cmath>

namespace terraforest {
bool NativeBlockWorld::is_collision_region_ready(const AABB &world_bounds) const {
    if(!world_bounds.position.is_finite()||!world_bounds.size.is_finite()||
       world_bounds.size.x<=0||world_bounds.size.y<=0||world_bounds.size.z<=0)return false;
    const Transform3D frame=is_inside_tree()?get_global_transform():get_transform();
    if(!frame.is_finite()||std::abs(frame.basis.determinant())<1e-12)return false;
    const AABB local=frame.affine_inverse().xform(world_bounds);
    if(!local.position.is_finite()||!local.get_end().is_finite())return false;
    if(unavailable_region(local))return false;
    for(const auto &entry:chunks) {
        const auto &key=entry.first;
        const AABB chunk_bounds(Vector3(key.x*16,key.y*16,key.z*16),Vector3(16,16,16));
        if(!local.intersects(chunk_bounds))continue;
        const AABB overlap=local.intersection(chunk_bounds);
        const Vector3 lo=overlap.position-chunk_bounds.position,hi=overlap.get_end()-chunk_bounds.position;
        const int x0=std::max(0,int(std::floor(lo.x))),x1=std::min(15,int(std::ceil(hi.x))-1);
        const int y0=std::max(0,int(std::floor(lo.y))),y1=std::min(15,int(std::ceil(hi.y))-1);
        const int z0=std::max(0,int(std::floor(lo.z))),z1=std::min(15,int(std::ceil(hi.z))-1);
        if(x0>x1||y0>y1||z0>z1)continue;
        const uint16_t mask=uint16_t(((1u<<(y1+1))-1)&~((1u<<y0)-1));
        bool occupied=false;
        for(int z=z0;z<=z1&&!occupied;++z)for(int x=x0;x<=x1;++x)
            if(entry.second.columns[x+16*z]&mask) {occupied=true;break;}
        if(!occupied)continue;
        if(!collisions||!settled.count(key)||dirty.count(key)||tickets.count(key))return false;
        const auto visual=visuals.find(key);
        if(visual!=visuals.end()&&!visual->second.collision_ready)return false;
        // Settled fully enclosed cells emit no surfaces and need no body.
        if(visual==visuals.end()&&budget_blocked.count(key))return false;
    }
    return true;
}
bool NativeBlockWorld::collision_near(BlockKey key) const {
    return collisions&&distance_to_focus(key)<=(collision_radius+14)*(collision_radius+14);
}
void NativeBlockWorld::retire_collision(BlockVisual &visual) {
    if(!visual.body)return;
    visual.body->set_collision_layer(0);
    visual.body->set_collision_mask(0);
    retired_collision.push_back(visual.body);
    visual.body=nullptr;visual.collision_at=0;visual.collision_ready=false;
}
bool NativeBlockWorld::update_collisions() {
    const auto begin=Time::get_singleton()->get_ticks_usec();
    ++collision_ticks;
    BlockVisual *candidate=nullptr;BlockKey candidate_key;
    double best=1e300;
    for(auto &entry:visuals) {
        if(!collision_near(entry.first)) {retire_collision(entry.second);continue;}
        auto &visual=entry.second;
        if(!visual.collision_ready) {
            double distance=distance_to_focus(entry.first);
            if(distance<best) {candidate=&visual;candidate_key=entry.first;best=distance;}
        }
    }
    // Drain before admitting replacements: repeated edits/travel cannot grow a
    // second unbounded population of retired and newly created shapes.
    int released=0;
    while(!retired_collision.empty()&&released<COLLISION_RETIRE_PER_TICK) {
        auto *body=retired_collision.front();
        if(body->get_child_count()) {
            memdelete(body->get_child(body->get_child_count()-1));
            ++released;++collision_pieces_retired;
        } else {
            memdelete(body);retired_collision.pop_front();++released;
        }
    }
    const auto retired_at=Time::get_singleton()->get_ticks_usec();
    collision_retire_max_ms=std::max(collision_retire_max_ms,double(retired_at-begin)/1000.0);
    if(candidate&&retired_collision.empty()) {
        auto &visual=*candidate;
        if(!visual.body) {
            visual.body=memnew(StaticBody3D);
            visual.body->set_position(Vector3(candidate_key.x*16,candidate_key.y*16,candidate_key.z*16));
            visual.body->set_collision_layer(0);visual.body->set_collision_mask(0);
            add_child(visual.body);
        }
        const int end=std::min(int(visual.collision_indices.size()),visual.collision_at+COLLISION_PIECE_TRIANGLES*3);
        PackedVector3Array faces;faces.resize(end-visual.collision_at);
        auto *destination=faces.ptrw();
        const auto *positions=visual.collision_vertices.ptr();
        const auto *indices=visual.collision_indices.ptr();
        for(int i=visual.collision_at;i<end;++i)destination[i-visual.collision_at]=positions[indices[i]];
        const auto cook_begin=Time::get_singleton()->get_ticks_usec();
        Ref<ConcavePolygonShape3D> shape;shape.instantiate();shape->set_faces(faces);
        const auto attach_begin=Time::get_singleton()->get_ticks_usec();
        collision_cook_max_ms=std::max(collision_cook_max_ms,double(attach_begin-cook_begin)/1000.0);
        auto *node=memnew(CollisionShape3D);node->set_shape(shape);visual.body->add_child(node);
        const auto activate_begin=Time::get_singleton()->get_ticks_usec();
        collision_attach_max_ms=std::max(collision_attach_max_ms,double(activate_begin-attach_begin)/1000.0);
        visual.collision_at=end;++collision_pieces_built;
        if(end==visual.collision_indices.size()) {
            // Partial geometry never advertises a completed traversable chunk.
            visual.collision_ready=true;visual.body->set_collision_layer(2);
            collision_activate_max_ms=std::max(collision_activate_max_ms,double(Time::get_singleton()->get_ticks_usec()-activate_begin)/1000.0);
        }
    }
    collision_last_ms=double(Time::get_singleton()->get_ticks_usec()-begin)/1000.0;
    collision_max_ms=std::max(collision_max_ms,collision_last_ms);
    if(!retired_collision.empty())return true;
    for(const auto &entry:visuals)if(collision_near(entry.first)&&!entry.second.collision_ready)return true;
    return false;
}
Dictionary NativeBlockWorld::collision_stats() const {
    int ready=0,pending=0,missing=0,shapes=0,retired_shapes=0;
    uint64_t retained=0;
    for(const auto &entry:visuals) {
        const auto &v=entry.second;
        retained+=v.collision_vertices.size()*sizeof(Vector3)+v.collision_indices.size()*sizeof(int32_t);
        if(v.body)shapes+=v.body->get_child_count();
        if(collision_near(entry.first)) {
            if(v.collision_ready)++ready;else ++pending;
        }
    }
    for(const auto &entry:chunks)if(collision_near(entry.first)) {
        // A settled empty surface has no triangles to collide with. Dirty or
        // budget-deferred authored geometry is never reported as ready.
        if(!settled.count(entry.first)||dirty.count(entry.first)||tickets.count(entry.first))++missing;
    }
    for(auto *body:retired_collision)retired_shapes+=body->get_child_count();
    Dictionary result;
    result["enabled"]=collisions;result["ready"]=collisions&&!pending&&!missing;
    result["ready_chunks"]=ready;result["pending_chunks"]=pending;result["unresolved_mesh_chunks"]=missing;
    result["live_pieces"]=shapes;result["retired_pieces"]=retired_shapes;result["retired_bodies"]=int(retired_collision.size());
    result["source_payload_bytes"]=int64_t(retained);
    result["triangles_per_piece"]=COLLISION_PIECE_TRIANGLES;result["pieces_per_tick"]=1;
    result["retire_operations_per_tick"]=COLLISION_RETIRE_PER_TICK;
    result["ticks"]=int64_t(collision_ticks);result["pieces_built"]=int64_t(collision_pieces_built);
    result["pieces_retired"]=int64_t(collision_pieces_retired);
    result["last_tick_ms"]=collision_last_ms;result["max_tick_ms"]=collision_max_ms;
    result["cook_max_ms"]=collision_cook_max_ms;result["attach_max_ms"]=collision_attach_max_ms;
    result["activate_max_ms"]=collision_activate_max_ms;result["retire_max_ms"]=collision_retire_max_ms;
    return result;
}
}
