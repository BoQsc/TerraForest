// SPDX-License-Identifier: 0BSD
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <vector>
#include <cstdint>
namespace terraforest {
// Bounded session-local intent. Physics, navigation and contact keep their owners.
class NativeZombieAwareness : public godot::RefCounted {
    GDCLASS(NativeZombieAwareness,godot::RefCounted)
    enum State { IDLE, WANDER, CHASE, INVESTIGATE, SEARCH };
    struct Agent {
        int64_t id=0;uint32_t random=1;State state=IDLE;
        godot::Vector3 home,goal,last_seen;
        double remaining=1,unseen=0,blocked=0,ignore=0;
        bool visible=false;int revision=0;
    };
    std::vector<Agent> agents_;
    int capacity_=0;uint32_t seed_=1;
    Agent *find(int64_t id);
    static double random(Agent &agent);
    static void rest(Agent &agent);
    static void roam(Agent &agent,const godot::Vector3 &feet,bool search);
    static godot::Dictionary describe(const Agent &agent);
protected:
    static void _bind_methods();
public:
    bool configure(int capacity,int64_t seed);
    bool add_agent(int64_t id,const godot::Vector3 &feet);
    void remove_agent(int64_t id);
    void clear();
    bool wants_sight(int64_t id,const godot::Vector3 &feet,const godot::Vector3 &forward,const godot::Vector3 &player);
    void observe(int64_t id,const godot::Vector3 &player,bool visible);
    void provoke(int64_t id,const godot::Vector3 &player);
    bool hear(int64_t id,const godot::Vector3 &feet,const godot::Vector3 &source,double radius);
    bool accept_roam(int64_t id,const godot::Vector3 &supported);
    godot::Dictionary advance(int64_t id,const godot::Vector3 &feet,double delta,bool active,const godot::String &route_state);
    godot::Dictionary status(int64_t id);
};
}
