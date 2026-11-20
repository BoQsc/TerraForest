// SPDX-License-Identifier: 0BSD
#include "terrain_collision.hpp"
#include <godot_cpp/classes/concave_polygon_shape3d.hpp>
#include <godot_cpp/classes/os.hpp>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <algorithm>
#include <tuple>
#include <vector>

namespace terraforest {
using namespace godot;
static Dictionary failure(const char *message) {
    Dictionary out; out["ok"]=false; out["error"]=message; return out;
}
namespace {
struct Rectangle {
    int first, axis, winding;
    float plane, bottom, top, left, right;
    auto row() const { return std::tie(axis, winding, plane, bottom, top); }
};

// Accept only two same-winding triangles covering opposite halves of one
// axis-aligned rectangle. Each vertex must be an exact bounding-box corner.
bool rectangle_pair(const Vector3 *p, Rectangle &r) {
    Vector3 lo=p[0], hi=p[0];
    for(int i=1;i<6;++i) { lo=lo.min(p[i]); hi=hi.max(p[i]); }
    for(int axis=0;axis<3;++axis) {
        const int u=(axis+1)%3, v=(axis+2)%3;
        if(lo[axis]!=hi[axis] || lo[u]>=hi[u] || lo[v]>=hi[v])continue;
        int mask[2]={}, corner[6];
        for(int i=0;i<6;++i) {
            if((p[i][u]!=lo[u] && p[i][u]!=hi[u]) || (p[i][v]!=lo[v] && p[i][v]!=hi[v]))return false;
            corner[i]=(p[i][u]==hi[u]?1:0)+(p[i][v]==hi[v]?2:0);
            mask[i/3]|=1<<corner[i];
        }
        int shared=mask[0]&mask[1];
        if((mask[0]|mask[1])!=15 || (shared!=6 && shared!=9))return false;
        auto winding=[&](int i) {
            int a=corner[i], b=corner[i+1], c=corner[i+2];
            return ((b&1)-(a&1))*((c>>1)-(a>>1))-((c&1)-(a&1))*((b>>1)-(a>>1));
        };
        int orientation=winding(0);
        if(!orientation || orientation!=winding(3))return false;
        r.axis=axis; r.winding=orientation; r.plane=lo[axis];
        r.bottom=lo[v]; r.top=hi[v]; r.left=lo[u]; r.right=hi[u];
        return true;
    }
    return false;
}

PackedVector3Array merge_planar_faces(const PackedVector3Array &faces) {
    const int64_t count=faces.size();
    if(count<12 || count%3 || count>120000)return faces;
    const Vector3 *p=faces.ptr();
    for(int i=0;i<count;++i)if(!p[i].is_finite())return faces;
    std::vector<Rectangle> rects;
    for(int i=0;i+6<=count;) {
        Rectangle r{}; r.first=i;
        if(rectangle_pair(p+i,r)) { rects.push_back(r); i+=6; }
        else i+=3;
    }
    if(rects.size()<2)return faces;
    std::sort(rects.begin(),rects.end(),[](const Rectangle &a,const Rectangle &b) {
        if(a.row()!=b.row())return a.row()<b.row();
        return std::tie(a.left,a.first)<std::tie(b.left,b.first);
    });
    PackedVector3Array result=faces;
    std::vector<bool> omit(count/3);
    bool changed=false;
    for(size_t at=0;at<rects.size();) {
        const Rectangle &r=rects[at++];
        float right=r.right;
        while(at<rects.size() && rects[at].row()==r.row() && rects[at].left==right) {
            const auto &next=rects[at++];
            omit[next.first/3]=omit[next.first/3+1]=true;
            right=next.right;
        }
        if(right==r.right)continue;
        changed=true;
        const int axis=(r.axis+1)%3;
        for(int j=r.first;j<r.first+6;++j)
            if(p[j][axis]==r.right)result.ptrw()[j][axis]=right;
    }
    if(!changed)return faces;
    auto *out=result.ptrw();
    int used=0;
    for(int i=0;i<count;++i)if(!omit[i/3])out[used++]=out[i];
    result.resize(used);
    return result;
}
}
void NativeTerrainCollision::_bind_methods() {
    ClassDB::bind_static_method("NativeTerrainCollision",D_METHOD("merge_planar_faces","faces"),&merge_planar_faces);
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
