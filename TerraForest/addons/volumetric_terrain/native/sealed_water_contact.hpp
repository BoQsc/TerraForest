// SPDX-License-Identifier: 0BSD
#pragma once
#include "core.h"

// Only used by the read-only contact packet on a sealed terrain revision.
// The owning TerrainFieldReader pins all borrowed arrays and page payloads.
// Each lane has its own signs, heights and geometry scratch.
class SealedWaterContact final {
    World view;
public:
    explicit SealedWaterContact(const World &src){
        view.pages_by_key=src.pages_by_key;view.pages=src.pages;
        view.blocks=src.blocks;view.block_columns=src.block_columns;
        view.edit_columns=src.edit_columns;view.caves=src.caves;
        view.build_control=src.build_control;view.surface_columns=src.surface_columns;
        view.contact_snapshot=true;view.contact_revision=src.contact_revision;
        view.contact_x0=src.contact_x0;view.contact_x1=src.contact_x1;
        view.contact_z0=src.contact_z0;view.contact_z1=src.contact_z1;
        view.seed=src.seed;view.revision=src.revision;view.generator_id=src.generator_id;
        view.surface_style=src.surface_style;view.cache_mesh_heights=src.cache_mesh_heights;
        view.indexed_caves=src.indexed_caves;view.basin_count=src.basin_count;
        view.site_count=src.site_count;view.regional_roads=src.regional_roads;
        copy_bytes(view.basins,src.basins,sizeof(view.basins));
        copy_bytes(view.basin_cells,src.basin_cells,sizeof(view.basin_cells));
        copy_bytes(view.cave_columns,src.cave_columns,sizeof(view.cave_columns));
        copy_bytes(view.sites,src.sites,sizeof(view.sites));
        copy_bytes(view.road_points,src.road_points,sizeof(view.road_points));
        copy_bytes(view.buildable_weights,src.buildable_weights,sizeof(view.buildable_weights));
    }
    SealedWaterContact(const SealedWaterContact &)=delete;
    SealedWaterContact &operator=(const SealedWaterContact &)=delete;
    ~SealedWaterContact(){
        view.pages_by_key={};view.pages={};view.blocks={};view.block_columns={};
        view.edit_columns=nullptr;view.caves={};
        view.release();
    }
    void read(const u8 *packet,int size,Bytes &out){
        view.contact_outside=false;
        process_request(view,packet,size,out);
        // The shared revision atlas owns canonical columns. Private columns
        // left by a cache miss can be released as soon as the packet is ready.
        release_geometry_cache(view);
    }
};
