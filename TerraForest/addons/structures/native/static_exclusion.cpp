#include "static_batch.hpp"
#include "exclusion_queries.hpp"
#include <cmath>

namespace terraforest {
PackedByteArray NativeStaticBatch::overlap_mask(const TypedArray<Transform3D> &transforms,const AABB &bounds) const {
    return overlap_mask_impl(transforms,bounds,true);
}
PackedByteArray NativeStaticBatch::overlap_mask_impl(const TypedArray<Transform3D> &transforms,const AABB &bounds,bool include_unloaded) const {
    PackedByteArray result;
    ExclusionQueries prepared;
    if(!prepared.configure(transforms,bounds)||!prepared.in_frame(is_inside_tree()?get_global_transform():get_transform()))return result;
    result.resize(transforms.size());result.fill(0);
    accumulate_overlap(prepared.boxes,prepared.combined,include_unloaded,result);
    return result;
}
void NativeStaticBatch::accumulate_overlap(const std::vector<AABB> &queries,const AABB &combined,bool include_unloaded,PackedByteArray &result,uint64_t *visited) const {
    if(queries.empty()||source_mesh.is_null())return;
    auto *output=result.ptrw();
    // Unknown placement details must not make vegetation regrow through models.
    // Retain conservative group bounds until exact records return.
    const auto overlaps_unloaded=[&](const auto &self,const ModelBoundsIndex::Node *node,const AABB &query)->bool {
        if(!node||!node->bounds.intersects(query))return false;
        return (node->box.intersects(query)&&unloaded_regions.at(node->key).count)||
            self(self,node->left.get(),query)||self(self,node->right.get(),query);
    };
    if(include_unloaded)for(size_t index=0;index<queries.size();++index)
        if(!output[index]&&overlaps_unloaded(overlaps_unloaded,unloaded_bounds.root(),queries[index]))output[index]=1;
    const AABB fallback=proxy_parts.empty()?source_mesh->get_aabb():AABB();
    // Test group bounds once per batch before traversing nearby authored records.
    // This index is independent of physics residency and retains compound gaps.
    const auto visit=[&](const auto &self,const ModelBoundsIndex::Node *node)->void {
        if(!node)return;
        if(visited)++*visited;
        if(!node->bounds.intersects(combined))return;
        if(node->box.intersects(combined)) {
            std::vector<int> candidates;
            for(size_t i=0;i<queries.size();i++)if(!output[i]&&node->box.intersects(queries[i]))candidates.push_back(int(i));
            if(!candidates.empty())for(auto id:groups.at(node->key)) {
                Transform3D placement=placement_transform(placements.at(id));
                int count=proxy_parts.empty()?1:int(proxy_parts.size());
                for(int part=0;part<count;part++) {
                    AABB solid=placement.xform(proxy_parts.empty()?fallback:proxy_parts[part]);
                    for(size_t i=0;i<candidates.size();) {
                        if(solid.intersects(queries[candidates[i]])) {
                            output[candidates[i]]=1;candidates[i]=candidates.back();candidates.pop_back();
                        } else ++i;
                    }
                    if(candidates.empty())break;
                }
                if(candidates.empty())break;
            }
        }
        self(self,node->left.get());self(self,node->right.get());
    };
    visit(visit,collision_index.root());
}
}
