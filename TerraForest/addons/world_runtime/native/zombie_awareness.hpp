// SPDX-License-Identifier: 0BSD
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <vector>
#include <cstdint>
namespace terraforest {
// Bounded session-local intent. Physics, navigation and contact keep their owners.
class NativeZombieAwareness : public godot::RefCounted {
    GDCLASS(NativeZombieAwareness,godot::RefCounted)
    enum State { IDLE, WANDER, CHASE, INVESTIGATE, SEARCH, SUSPICIOUS, SLEEPING, WAKING };
    struct Profile {
        godot::String name="legacy";
        double sight=32,tracking=44,near_sense=5,notice=0,pursuit=30,forget=18,search=6,ignore=10;
        double roam_min=4,roam_max=9,idle_min=1.5,idle_max=4,hearing=1,walk_speed=.72,chase_multiplier=1.2,wake=3;
        double close_notice=.2,sleep_notice=.4,sleep_range=2.5,wake_speed=1.65,provoked_speed=1.8,sleeper_speed=2.2;
        double sight_grace=.75;
    };
    struct Agent {
        int64_t id=0;uint32_t random=1;State state=IDLE;
        godot::Vector3 home,goal,last_seen;
        double remaining=1,unseen=0,blocked=0,ignore=0,confidence=0,interest=0,wake_elapsed=0,sound_cooldown=0;
        bool visible=false,provoked=false,ambusher=false,close_visible=false;int revision=0,sleep_pose=0;
        Profile profile;
    };
    std::vector<Agent> agents_;
    int capacity_=0;uint32_t seed_=1;
    Agent *find(int64_t id);
    static double random(Agent &agent);
    static void rest(Agent &agent);
    static void roam(Agent &agent,const godot::Vector3 &feet,bool search);
    static void wake(Agent &agent,const godot::Vector3 &source,bool provoked);
    static godot::Dictionary describe(const Agent &agent);
protected:
    static void _bind_methods();
public:
    bool configure(int capacity,int64_t seed);
    bool add_agent(int64_t id,const godot::Vector3 &feet);
    bool set_profile(int64_t id,const godot::Dictionary &profile);
    bool set_sleeping(int64_t id,int pose);
    bool finish_waking(int64_t id);
    godot::PackedByteArray capture_sleep(int64_t id);
    bool restore_sleep(int64_t id,const godot::PackedByteArray &bytes);
    void remove_agent(int64_t id);
    void clear();
    bool wants_sight(int64_t id,const godot::Vector3 &feet,const godot::Vector3 &forward,const godot::Vector3 &player);
    void observe(int64_t id,const godot::Vector3 &player,bool visible,double distance=-1);
    void provoke(int64_t id,const godot::Vector3 &player);
    bool hear(int64_t id,const godot::Vector3 &feet,const godot::Vector3 &source,double radius);
    bool accept_roam(int64_t id,const godot::Vector3 &supported);
    godot::Dictionary advance(int64_t id,const godot::Vector3 &feet,double delta,bool active,const godot::String &route_state);
    godot::Dictionary status(int64_t id);
};
}
