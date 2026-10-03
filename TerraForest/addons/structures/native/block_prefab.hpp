#pragma once
#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/aabb.hpp>
#include <godot_cpp/variant/array.hpp>
#include <vector>

namespace terraforest {
using namespace godot;
struct PrefabCell { int32_t x,y,z,word; };
// Authoring asset; instantiated blocks remain ordinary world cells, not nodes.
class NativeBlockPrefab : public Resource {
    GDCLASS(NativeBlockPrefab,Resource)
    friend class NativeBlockWorld;
    std::vector<PrefabCell> cells;
    AABB bounds;
protected:
    static void _bind_methods();
public:
    bool configure(const PackedInt32Array &records);
    bool compose(const Array &sources,const PackedInt32Array &placements);
    bool compose_frontage(const Array &sources,int64_t lots_per_side,int64_t street_width,int64_t gap,int64_t seed);
    void set_records(const PackedInt32Array &records);
    PackedInt32Array get_records() const;
    int get_cell_count() const { return int(cells.size()); }
    AABB get_bounds() const { return bounds; }
    AABB placement_bounds(Vector3i origin,int quarter_turns) const;
};
}
