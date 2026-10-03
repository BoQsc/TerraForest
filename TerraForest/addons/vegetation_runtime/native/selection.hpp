// SPDX-License-Identifier: 0BSD
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <queue>
#include <unordered_map>
namespace terraforest {
class NativeVegetationSelection : public godot::RefCounted {
 GDCLASS(NativeVegetationSelection,godot::RefCounted)
 struct Event { double distance; int64_t id,token; bool operator<(const Event &b)const{return distance>b.distance;} };
 std::priority_queue<Event> events;
 std::unordered_map<int64_t,Event> live;
 double travel=0;
 int64_t serial=0;
 void schedule(int64_t id,double slack);
protected: static void _bind_methods();
public:
 void clear();
 void erase(int64_t id);
 void select(godot::Object *renderer,godot::Vector3 eye,double projection,double time,bool instant);
 godot::Dictionary queue_stats() const;
};
}
