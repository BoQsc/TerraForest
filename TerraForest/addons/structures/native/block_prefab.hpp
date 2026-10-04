#pragma once
#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <godot_cpp/variant/aabb.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <vector>

namespace terraforest {
using namespace godot;
struct PrefabCell { int32_t x,y,z,word; };
// Authoring asset; instantiated blocks remain ordinary world cells, not nodes.
class NativeBlockPrefab : public Resource {
    GDCLASS(NativeBlockPrefab,Resource)
    friend class NativeBlockWorld;
    std::vector<PrefabCell> cells;
    int64_t material_counts[4]{};
    std::vector<PrefabCell> foundation_columns;
    struct ClearanceColumn { int x,z,low,high; int64_t end; };
    std::vector<ClearanceColumn> clearance_columns;
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
    PackedInt64Array get_material_counts() const;
    AABB get_bounds() const { return bounds; }
    AABB placement_bounds(Vector3i origin,int quarter_turns) const;
    PackedVector3Array foundation_samples(Vector3i origin,int quarter_turns,int max_base_y) const;
    int64_t clearance_sample_count() const { return clearance_columns.empty()?0:clearance_columns.back().end; }
    PackedVector3Array clearance_samples(Vector3i origin,int quarter_turns,int64_t offset,int limit) const;
};
}
