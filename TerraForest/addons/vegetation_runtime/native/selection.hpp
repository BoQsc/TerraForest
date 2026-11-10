// SPDX-License-Identifier: 0BSD
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <vector>
#include <queue>
#include <unordered_map>
namespace terraforest {
class NativeVegetationSelection : public godot::RefCounted {
 GDCLASS(NativeVegetationSelection,godot::RefCounted)
 struct Event { double distance; int64_t id,token; bool operator<(const Event &b)const{return distance>b.distance;} };
 std::priority_queue<Event> events;
 std::unordered_map<int64_t,Event> live;
 std::vector<godot::Transform3D> shadow_roots;
 // Main-thread forest membership, separate from LOD decision certificates and
 // from the immutable per-job rasterization snapshot.
 std::vector<godot::Transform3D> canopy_roots;
 std::vector<int64_t> canopy_ids;
 std::unordered_map<int64_t,size_t> canopy_slots;
 godot::Vector3 shadow_origin,shadow_sun;
 double shadow_span=0;int shadow_resolution=0;
 double travel=0;
 int64_t serial=0;
 void schedule(int64_t id,double slack);
protected: static void _bind_methods();
public:
 godot::PackedByteArray shadow_mask(godot::Object *renderer,godot::Vector3 origin,double span,int resolution,godot::Vector3 sun);
 bool prepare_shadow_mask(godot::Object *renderer,godot::Vector3 origin,double span,int resolution,godot::Vector3 sun);
 bool upsert_shadow_root(int64_t id,const godot::Transform3D &transform);
 void remove_shadow_root(int64_t id);
 bool prepare_shadow_snapshot(godot::Object *source,godot::Vector3 origin,double span,int resolution,godot::Vector3 sun);
 godot::PackedByteArray build_shadow_mask() const;
 void clear();
 void erase(int64_t id);
 void flush(godot::Object *renderer);
 void select(godot::Object *renderer,godot::Vector3 eye,double projection,double time,bool instant);
 godot::Dictionary queue_stats() const;
};
}
