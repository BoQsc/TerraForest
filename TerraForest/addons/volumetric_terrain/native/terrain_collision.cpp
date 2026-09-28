// SPDX-License-Identifier: 0BSD
#include "terrain_collision.hpp"
#include <godot_cpp/classes/concave_polygon_shape3d.hpp>
#include <godot_cpp/classes/os.hpp>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>

namespace terraforest {
using namespace godot;
static Dictionary failure(const char *message) {
    Dictionary out; out["ok"]=false; out["error"]=message; return out;
}
void NativeTerrainCollision::_bind_methods() {
    ClassDB::bind_method(D_METHOD("prepare","faces","triangles_per_piece"), &NativeTerrainCollision::prepare);
}
void NativeTerrainCollisionPiece::_bind_methods() {
    ClassDB::bind_method(D_METHOD("get_faces"), &NativeTerrainCollisionPiece::get_faces);
    ClassDB::bind_method(D_METHOD("get_token"), &NativeTerrainCollisionPiece::get_token);
    ClassDB::bind_method(D_METHOD("resolve","previous"), &NativeTerrainCollisionPiece::resolve);
}
Dictionary NativeTerrainCollision::prepare(const PackedVector3Array &faces, int64_t triangles_per_piece) const {
    const auto begin=Time::get_singleton()->get_ticks_usec();
    const int64_t face_count=faces.size();
    // Bounds limit transient memory and worst-case uninterrupted worker work.
    if(triangles_per_piece<256 || triangles_per_piece>1024 || face_count%3 || face_count>12000000LL)
        return failure("Invalid collision recipe size (256..1024 triangles/piece, at most 4000000 triangles).");
    const auto *vertices=faces.ptr();
    for(int64_t i=0;i<face_count;++i)
        if(!vertices[i].is_finite())return failure("Nonfinite collision vertex.");
    Array pieces;
    const int64_t stride=triangles_per_piece*3;
    for(int64_t at=0;at<face_count;at+=stride) {
        Ref<NativeTerrainCollisionPiece> piece; piece.instantiate();
        piece->faces_=faces.slice(at,MIN(at+stride,face_count));
        const auto bytes=piece->faces_.to_byte_array();
        const auto *raw=bytes.ptr();
        const int64_t byte_count=bytes.size();
        uint64_t hash=14695981039346656037ULL;
        for(int64_t i=0;i<byte_count;++i) { hash^=raw[i]; hash*=1099511628211ULL; }
        // Digest is only a bucket key. resolve() ALWAYS verifies exact faces.
        piece->token_="native-v1:"+String::num_uint64(hash,16);
        pieces.push_back(piece);
    }
    Dictionary out; out["ok"]=true; out["pieces"]=pieces;
    out["prepare_ms"]=double(Time::get_singleton()->get_ticks_usec()-begin)/1000.0;
    return out;
}
Dictionary NativeTerrainCollisionPiece::resolve(const Dictionary &previous) const {
    if(OS::get_singleton()->get_thread_caller_id()!=OS::get_singleton()->get_main_thread_id())
        return failure("Collision shape resolution requires the main thread.");
    if(faces_.is_empty() || token_.is_empty())return failure("Uninitialized collision recipe.");
    const auto begin=Time::get_singleton()->get_ticks_usec();
    Ref<ConcavePolygonShape3D> shape;
    const Variant candidate=previous.get(token_,Variant());
    if(candidate.get_type()==Variant::OBJECT)shape=candidate;
    const bool reused=shape.is_valid() && shape->is_backface_collision_enabled() && shape->get_faces()==faces_;
    const auto matched=Time::get_singleton()->get_ticks_usec();
    if(!reused) {
        shape.instantiate();
        shape->set_backface_collision_enabled(true);
        shape->set_faces(faces_);
    }
    Dictionary out; out["ok"]=true; out["shape"]=shape; out["reused"]=reused; out["token"]=token_;
    out["match_ms"]=double(matched-begin)/1000.0;
    out["cook_ms"]=double(Time::get_singleton()->get_ticks_usec()-matched)/1000.0;
    return out;
}
}
