// SPDX-License-Identifier: 0BSD
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <vector>
namespace terraforest {
// Worker-owned hydrostatic hierarchy, not a velocity/pressure field simulator.
// Geometry supplies cumulative storage profiles and verified spill connections.
class NativeWaterSettling : public godot::RefCounted {
    GDCLASS(NativeWaterSettling,godot::RefCounted)
    struct Node {
        int parent=-1,left=-1,right=-1,entry=-1,merge=0;
        int64_t capacity=0,base=0,local=0,total=0;
        std::vector<int64_t> profile;
    };
    struct Frame {int target,node;int64_t remaining;};
    std::vector<Node> nodes;
    std::vector<int64_t> heights;
    std::vector<Frame> frames;
    int leaves=0,root=-1,source=-1,mode=0,root_count=0;
    std::vector<int> leaf_roots;
    int64_t total_ml=0;
    bool configure_impl(const godot::PackedInt64Array &,const godot::Array &,const godot::PackedInt32Array &,bool);
    int64_t requested=0,pending=0,moved=0,events=0;
    static constexpr int64_t maximum=9007199254740991LL;
    int active_node(int leaf,int stop) const;
    void change(int node,int64_t amount);
    void return_frame(int64_t remainder);
protected:
    static void _bind_methods();
public:
    bool configure(const godot::PackedInt64Array &levels,const godot::Array &profiles,const godot::PackedInt32Array &merges);
    bool configure_forest(const godot::PackedInt64Array &levels,const godot::Array &profiles,const godot::PackedInt32Array &merges);
    bool begin_add(int64_t leaf,int64_t amount_ml);
    bool begin_remove(int64_t leaf,int64_t amount_ml);
    godot::Dictionary advance(int64_t event_budget);
    godot::Dictionary statistics() const;
    godot::Dictionary inspect(int64_t leaf) const;
};
}
