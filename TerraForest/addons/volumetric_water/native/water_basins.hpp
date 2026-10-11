// SPDX-License-Identifier: 0BSD
#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <vector>
namespace terraforest {
// Worker-owned, resumable regional merge forest. No fluid quantity is stored here.
class NativeWaterBasins : public godot::RefCounted {
    GDCLASS(NativeWaterBasins,godot::RefCounted)
    friend class NativeWaterProfiles;
    struct Event { int height,type,a,b; };
    struct Draft { int left=-1,right=-1,height=0,entry=-1,rep=-1,depth=0; };
    static bool later(const Event &a,const Event &b);
    godot::PackedInt32Array ids,floors,edges,owners,leaf_floors,merges,roots,ports;
    std::vector<Event> heap;
    std::vector<int> parent,sizes,basin,owner,activated,remap;
    std::vector<Draft> drafts;
    int status=-1,phase=0,cursor=0,level=0,leaf_count=0,merge_count=0,root_count=0,port_count=0,max_depth=0;
    bool has_level=false;
    int64_t events=0;
    godot::String error;
    int find(int node);
    int locate(int id) const;
    void fail(const char *reason);
    void unit();
protected:
    static void _bind_methods();
public:
    bool begin(const godot::Dictionary &graph);
    godot::Dictionary advance(int64_t work_budget);
    godot::Dictionary statistics() const;
    godot::Dictionary hierarchy() const;
};
}
