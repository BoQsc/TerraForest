#pragma once
#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <godot_cpp/variant/aabb.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <vector>

namespace terraforest {
using namespace godot;
struct PrefabCell { int32_t x,y,z,word; };
// Authoring asset; instantiated blocks remain ordinary world cells, not nodes.
class NativeBlockPrefab : public Resource {
    GDCLASS(NativeBlockPrefab,Resource)
    friend class NativePrefabPlacement;
    friend class NativeBlockWorld;
    std::vector<PrefabCell> cells;
    int64_t material_counts[4]{};
    std::vector<PrefabCell> foundation_columns;
    struct ClearanceColumn { int x,z,low,high; int64_t end; };
    std::vector<ClearanceColumn> clearance_columns;
    mutable std::vector<Vector3> terrain_surface_probes;
    mutable uint64_t terrain_surface_revision=uint64_t(-1);
    mutable int terrain_surface_band=-1;
    mutable bool terrain_surface_overflow=false;
    void cache_terrain_surfaces(int surface_band) const;
    AABB bounds, attachment_envelope;
    uint64_t definition_revision=0;
    Array model_attachments;
    bool configure_impl(const PackedInt32Array &records,bool notify);
protected:
    static void _bind_methods();
public:
    Dictionary plan_paving(const Array &roads,const Array &access) const;
    bool configure_model_attachments(const Array &attachments);
    void set_model_attachments(const Array &attachments);
    Array get_model_attachments() const;
    bool configure(const PackedInt32Array &records);
    bool compose(const Array &sources,const PackedInt32Array &placements);
    bool compose_frontage(const Array &sources,int64_t lots_per_side,int64_t street_width,int64_t gap,int64_t seed);
    bool compose_settlement(const Array &sources,int64_t lots_per_side,int64_t street_width,int64_t gap,int64_t seed,int64_t streets);
    Dictionary layout_counts(const Array &sources,int64_t lots_per_side,int64_t seed,int64_t streets) const;
    void set_records(const PackedInt32Array &records);
    PackedInt32Array get_records() const;
    Dictionary survey_surface() const;
    Dictionary interior_light_sites() const;
    int get_cell_count() const { return int(cells.size()); }
    PackedInt64Array get_material_counts() const;
    bool configure_attachment_envelope(AABB box);
    void set_attachment_envelope(AABB box);
    AABB get_attachment_envelope() const { return attachment_envelope; }
    AABB get_bounds() const { return attachment_envelope.size==Vector3()?bounds:bounds.merge(attachment_envelope); }
    AABB placement_bounds(Vector3i origin,int quarter_turns) const;
    PackedVector3Array foundation_samples(Vector3i origin,int quarter_turns,int max_base_y) const;
    int64_t clearance_sample_count() const { return clearance_columns.empty()?0:clearance_columns.back().end; }
    PackedVector3Array clearance_samples(Vector3i origin,int quarter_turns,int64_t offset,int limit,int surface_band=0) const;
    int64_t terrain_surface_sample_count(int surface_band=0) const;
    PackedVector3Array terrain_surface_samples(Vector3i origin,int quarter_turns,int64_t offset,int limit,int surface_band=0) const;
    Dictionary terrain_surface_clearance(Vector3i origin,int quarter_turns,int surface_band=0) const;
};
}
