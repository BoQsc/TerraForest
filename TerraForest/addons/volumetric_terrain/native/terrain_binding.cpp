// SPDX-License-Identifier: 0BSD
#include "core.h"
#include "resident_surface_columns.hpp"
#include "sealed_water_contact.hpp"
#include "survey_map.hpp"
#include "terrain_planner.hpp"
#include "road_profile.hpp"
#include "material_deposits.hpp"
#include "exploration_sites.hpp"
#include "terrain_collision.hpp"
#include "terrain_region_store.hpp"
#include "terrain_capture.hpp"
#include "terrain_field_patch.hpp"
#include "terrain_cube_patch.hpp"
#include "terrain_residency.hpp"
#include "generation_bake_progress.hpp"
#include "geometry_content_key.hpp"
#include "experimental/snapshot_worker.hpp"
#include "experimental/godot_surface_mesh.hpp"
#include "experimental/mesh_partition.hpp"
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/dir_access.hpp>
#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/classes/worker_thread_pool.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <optional>
#include <algorithm>
#include <cstdlib>
#include <atomic>
#include <mutex>
#include <chrono>
#include <memory>
#include <map>

namespace terraforest {
godot::PackedByteArray render_generation_map(const godot::PackedByteArray &,const godot::Array &,const godot::Array &,const godot::PackedByteArray &);
godot::Dictionary plan_regional_route(const World &,godot::Vector3,godot::Vector3,const godot::Array &);
godot::Dictionary fit_generated_road_network(const World &,const godot::Array &,const godot::Array &,bool);
godot::Dictionary plan_region_network(const World &,const godot::Array &,const godot::Array &,int,int,int64_t,const godot::Array &,double);
godot::Dictionary plan_settlement_lots(const World &,godot::Vector3,const godot::Array &,const godot::Array &,bool);
godot::Dictionary plan_street_network(const World &,const godot::Array &,const godot::PackedVector3Array &);
godot::Dictionary normalize_generated_roads(const World &,const godot::Array &,const godot::Array &);
godot::Dictionary fit_generated_lakes(const World &,const godot::Array &);
godot::Dictionary survey_generated_lake_surfaces(const World &,const godot::Array &);
godot::Dictionary plan_lake_crossings(const World &,bool);
godot::Dictionary plan_land_footbridges(const World &,const godot::Array &,const godot::Array &,int64_t);
class TerrainCore;
// Only this read-only interface owns a shareable field. The mutable TerrainCore
// returned by the legacy snapshot API always has independent page storage.
class TerrainFieldReader : public godot::RefCounted {
    GDCLASS(TerrainFieldReader,godot::RefCounted)
    friend class TerrainCore;
    godot::Ref<godot::RefCounted> field_;
    struct ContactLane {std::mutex mutex;std::unique_ptr<SealedWaterContact> view;};
    mutable std::array<ContactLane,3> contact_lanes_;
    mutable std::atomic<uint64_t> lane_packets_{0};
    mutable std::mutex extrusion_mutex_;
    mutable std::map<std::array<i16,66>,uint32_t> extrusion_ids_;
protected:
    static void _bind_methods();
public:
    godot::PackedByteArray execute(const godot::PackedByteArray &packet) const;
    godot::Dictionary resident_tile(godot::Vector3i key,int64_t revision,int64_t epoch,bool cache_packet,const godot::Callable &on_faces,bool mesh_only) const;
    godot::PackedByteArray classify_water_bricks(const godot::PackedInt32Array &origins,int64_t revision,int64_t epoch,bool layers=false,bool extrusions=false) const;
    godot::PackedByteArray classify_edit_bricks(const godot::PackedInt32Array &origins,int64_t revision,int64_t epoch) const{
        return classify_water_bricks(origins,revision,epoch,true,true);
    }
    godot::Dictionary surface_column_stats() const;
    godot::Ref<TerrainFieldReader> capture_contact_core(godot::Rect2i bounds,int64_t revision,int64_t epoch) const;
};
class TerrainCore : public godot::RefCounted {
    GDCLASS(TerrainCore, godot::RefCounted)
    friend class TerrainFieldReader;
    godot::Ref<godot::RefCounted> page_owner_;
    bool sealed_column_source_=false;
    std::shared_ptr<SealedSurfaceColumns> surface_columns_;
    BuildControl control_;
    World world_;
    std::unique_ptr<TerrainResidency> residency_;
    GenerationBakeProgress generation_progress_;
    uint64_t storage_epoch_=1;
    godot::PackedInt32Array saved_keys_;
    godot::PackedInt64Array saved_versions_;
    godot::PackedByteArray storage_reference_;
    bool storage_load_pending_=false;
    uint32_t storage_load_checksum_=0;
    int storage_load_revision_=0;

    std::mutex mutex_;
    std::atomic<int64_t> active_command_{-1};
    std::atomic<u64> snapshot_epoch_{0};
    std::optional<experimental::SnapshotWorker> snapshot_worker_;
    struct SubmitTiming{int64_t token=-1;bool accepted=false;double total_ms=0,world_lock_ms=0,startup_ms=0,world_unlock_ms=0;experimental::SnapshotWorker::SubmitTiming worker;};
    SubmitTiming last_submit_;
    std::mutex submit_timing_mutex_;
    static godot::PackedByteArray reply(uint32_t command, uint32_t status, uint32_t value=0, bool include_value=false) {
        godot::PackedByteArray result;
        result.resize(include_value ? 16 : 12);
        result.encode_u32(0,REPLY_MAGIC); result.encode_u32(4,command); result.encode_u32(8,status);
        if(include_value)result.encode_u32(12,value);
        return result;
    }
protected:
    static void _bind_methods() {
        godot::ClassDB::bind_method(godot::D_METHOD("execute","packet"), &TerrainCore::execute);
        godot::ClassDB::bind_method(godot::D_METHOD("execute_edit_with_writes","packet","include_surface_owners"), &TerrainCore::execute_edit_with_writes, false);
        godot::ClassDB::bind_method(godot::D_METHOD("try_placement_target","packet"),&TerrainCore::try_placement_target);
        godot::ClassDB::bind_method(godot::D_METHOD("capture_contact_core","bounds","revision","epoch"),&TerrainCore::capture_contact_core);
        godot::ClassDB::bind_method(godot::D_METHOD("capture_edit_field","bounds","revision","epoch"),&TerrainCore::capture_edit_field);
        godot::ClassDB::bind_method(godot::D_METHOD("capture_edit_domains","domains","revision","epoch"),&TerrainCore::capture_edit_domains);
        godot::ClassDB::bind_method(godot::D_METHOD("execute_explosion_cohort","commands"), &TerrainCore::execute_explosion_cohort);
        godot::ClassDB::bind_method(godot::D_METHOD("configure_mesh_height_cache","enabled"), &TerrainCore::configure_mesh_height_cache);
        godot::ClassDB::bind_method(godot::D_METHOD("plan_material_deposits","earthworks"), &TerrainCore::material_deposits);
        godot::ClassDB::bind_method(godot::D_METHOD("plan_exploration_sites","layouts","reservations","earthworks","road_stops"), &TerrainCore::exploration_sites,DEFVAL(godot::PackedVector3Array()));
        godot::ClassDB::bind_method(godot::D_METHOD("capture_storage_snapshot"),&TerrainCore::capture_storage_snapshot);
        godot::ClassDB::bind_method(godot::D_METHOD("field_patch_state"),&TerrainCore::field_patch_state);
        godot::ClassDB::bind_method(godot::D_METHOD("capture_field_patch","origin","size","expected_revision","expected_epoch"),&TerrainCore::capture_field_patch);
        godot::ClassDB::bind_method(godot::D_METHOD("restore_field_patch","patch","expected_revision","expected_epoch"),&TerrainCore::restore_field_patch);
        godot::ClassDB::bind_method(godot::D_METHOD("validate_field_patch","patch"),&TerrainCore::validate_field_patch);
        godot::ClassDB::bind_method(godot::D_METHOD("cube_patch_state"),&TerrainCore::field_patch_state);
        godot::ClassDB::bind_method(godot::D_METHOD("capture_cube_patch","origin","size","expected_revision","expected_epoch"),&TerrainCore::capture_cube_patch);
        godot::ClassDB::bind_method(godot::D_METHOD("restore_cube_patch","patch","expected_revision","expected_epoch"),&TerrainCore::restore_cube_patch);
        godot::ClassDB::bind_method(godot::D_METHOD("validate_cube_patch","patch"),&TerrainCore::validate_cube_patch);
        godot::ClassDB::bind_method(godot::D_METHOD("commit_storage_snapshot","capture","checkpoint"),&TerrainCore::commit_storage_snapshot);
        godot::ClassDB::bind_method(godot::D_METHOD("configure_storage_checkpoint","checkpoint","checksum"),&TerrainCore::configure_storage_checkpoint);
        godot::ClassDB::bind_method(godot::D_METHOD("mount_storage_checkpoint","directory","checkpoint","resident_limit"),&TerrainCore::mount_storage_checkpoint,DEFVAL(MAX_PAGES));
        godot::ClassDB::bind_method(godot::D_METHOD("residency_stats"),&TerrainCore::residency_stats);

        godot::ClassDB::bind_method(godot::D_METHOD("plan_regional_route","start","finish","reservations"), &TerrainCore::plan_route);
        godot::ClassDB::bind_method(godot::D_METHOD("plan_region_network","districts","reservations","loops","trails","seed","streets","corridor_extent"), &TerrainCore::plan_network,DEFVAL(godot::Array()),DEFVAL(5.0));
        godot::ClassDB::bind_method(godot::D_METHOD("render_plan_map","pixels","roads","lots","water"), &TerrainCore::render_plan_map,DEFVAL(godot::PackedByteArray()));
        godot::ClassDB::bind_method(godot::D_METHOD("plan_lots","center","lots","roads","default_streets"), &TerrainCore::plan_lots);
        godot::ClassDB::bind_method(godot::D_METHOD("fit_generated_lakes","records"), &TerrainCore::fit_lakes);
        godot::ClassDB::bind_method(godot::D_METHOD("plan_lake_crossings","metropolis"), &TerrainCore::lake_crossings,DEFVAL(false));
        godot::ClassDB::bind_method(godot::D_METHOD("plan_land_footbridges","roads","reservations","seed"), &TerrainCore::land_footbridges);
        godot::ClassDB::bind_method(godot::D_METHOD("plan_streets","roads","junctions"), &TerrainCore::plan_streets);
        godot::ClassDB::bind_method(godot::D_METHOD("normalize_roads","roads","protected_areas"), &TerrainCore::normalize_roads);
        godot::ClassDB::bind_method(godot::D_METHOD("fit_road_network","roads","protected_areas","footprint_policy"), &TerrainCore::fit_road_network,DEFVAL(false));
        godot::ClassDB::bind_method(godot::D_METHOD("survey_overview","size"), &TerrainCore::survey_overview);
        godot::ClassDB::bind_method(godot::D_METHOD("survey_surface_map"), &TerrainCore::survey_surface_map);
        godot::ClassDB::bind_method(godot::D_METHOD("survey_water_visibility","points"), &TerrainCore::survey_water_visibility);
        godot::ClassDB::bind_method(godot::D_METHOD("bake_generated_earthworks","packets"), &TerrainCore::bake_generated_earthworks);
        godot::ClassDB::bind_method(godot::D_METHOD("bake_generated_earthworks_staged","packets","directory","resident_limit","checkpoint_commands","expected_epoch","test_stop_at_checkpoint","optimized"), &TerrainCore::bake_generated_earthworks_staged,DEFVAL(MAX_PAGES),DEFVAL(64),DEFVAL(-1),DEFVAL(-1),DEFVAL(true));
        godot::ClassDB::bind_method(godot::D_METHOD("generation_bake_progress"),&TerrainCore::generation_bake_progress);
        godot::ClassDB::bind_method(godot::D_METHOD("survey_generated_lake_surfaces","records"), &TerrainCore::survey_generated_lake_surfaces);
        godot::ClassDB::bind_method(godot::D_METHOD("shore_habitat_program"), &TerrainCore::shore_habitat_program);
        godot::ClassDB::bind_method(godot::D_METHOD("generated_lake_sources","bounds","level"), &TerrainCore::generated_lake_sources);
        godot::ClassDB::bind_method(godot::D_METHOD("survey_patch","size","x","z","width","height"), &TerrainCore::survey_patch);
        godot::ClassDB::bind_method(godot::D_METHOD("measure_material_surface","x","z","size","y_begin","y_end"), &TerrainCore::measure_material_surface);
        godot::ClassDB::bind_method(godot::D_METHOD("material_box","solid","minimum","maximum","add","solid_revision","material_revision"), &TerrainCore::material_box, DEFVAL(-1));
        godot::ClassDB::bind_method(godot::D_METHOD("geometry_cache_key","x","z","size","step"), &TerrainCore::geometry_cache_key);
        godot::ClassDB::bind_method(godot::D_METHOD("build_owned_region","x","z","size","step","y_begin","y_end","epoch"), &TerrainCore::build_owned_region);
        godot::ClassDB::bind_method(godot::D_METHOD("build_owned_column","x","z","size","step","epoch"), &TerrainCore::build_owned_column);
        godot::ClassDB::bind_method(godot::D_METHOD("supports_isolated_worlds"), &TerrainCore::supports_isolated_worlds);
        godot::ClassDB::bind_method(godot::D_METHOD("build_variant"), &TerrainCore::build_variant);
        godot::ClassDB::bind_method(godot::D_METHOD("executing_command"), &TerrainCore::executing_command);
        godot::ClassDB::bind_method(godot::D_METHOD("experimental_snapshot_submit","x","z","size","token","revision"), &TerrainCore::experimental_snapshot_submit);
        godot::ClassDB::bind_method(godot::D_METHOD("experimental_snapshot_submit_brick","x","z","size","token","revision","y_begin","y_end"), &TerrainCore::experimental_snapshot_submit_brick);
        godot::ClassDB::bind_method(godot::D_METHOD("experimental_snapshot_poll"), &TerrainCore::experimental_snapshot_poll);
        godot::ClassDB::bind_method(godot::D_METHOD("experimental_snapshot_stop"), &TerrainCore::experimental_snapshot_stop);
        godot::ClassDB::bind_method(godot::D_METHOD("experimental_snapshot_submit_timing"), &TerrainCore::experimental_snapshot_submit_timing);
        godot::ClassDB::bind_method(godot::D_METHOD("experimental_snapshot_create_mesh","packet"), &TerrainCore::experimental_snapshot_create_mesh);
        godot::ClassDB::bind_method(godot::D_METHOD("experimental_snapshot_encode","packet","x","z","size"), &TerrainCore::experimental_snapshot_encode);
        godot::ClassDB::bind_method(godot::D_METHOD("experimental_snapshot_encode_brick","packet","x","z","size"), &TerrainCore::experimental_snapshot_encode_brick);
        godot::ClassDB::bind_method(godot::D_METHOD("experimental_partition_mesh","packet"), &TerrainCore::experimental_partition_mesh);
        godot::ClassDB::bind_method(godot::D_METHOD("experimental_partition_mesh_budgeted","packet","workspace_bytes","output_bytes","expected_epoch"), &TerrainCore::experimental_partition_mesh_budgeted);
    }
public:
    godot::PackedVector3Array generated_lake_sources(const godot::AABB &bounds,double level){
        std::lock_guard<std::mutex> lock(mutex_);godot::PackedVector3Array points;
        if(world_.generator_id!=SHORE_HABITAT_GENERATOR_ID||!bounds.position.is_finite()||!bounds.size.is_finite()||!std::isfinite(level)||bounds.size.x<=0||bounds.size.y<=0||bounds.size.z<=0)return points;
        const auto end=bounds.position+bounds.size;
        for(int i=0;i<std::min(3,world_.basin_count);++i){
            const auto &b=world_.basins[i];if(std::abs(b.level-level)>.001)continue;
            const auto &field=world_.lake_fields[i];
            for(unsigned j=0;j<field.count;++j){
                const auto &s=field.segments[j];
                float ax=b.x+(b.along_x?s.ax:s.az),az=b.z+(b.along_x?s.az:s.ax);
                float dx=(b.along_x?s.bx-s.ax:s.bz-s.az),dz=(b.along_x?s.bz-s.az:s.bx-s.ax),lo=0,hi=1;
                auto clip=[&](float a,float d,float lower,float upper){
                    if(std::abs(d)<.00001f)return a>=lower&&a<upper;
                    float first=(lower-a)/d,last=(upper-a)/d;if(first>last)std::swap(first,last);
                    lo=std::max(lo,first);hi=std::min(hi,last);return lo<hi;
                };
                if(clip(ax,dx,bounds.position.x,end.x)&&clip(az,dz,bounds.position.z,end.z)){
                    float t=(lo+hi)*.5f;points.append(godot::Vector3(ax+t*dx,level-.5,az+t*dz));
                }
            }
        }
        return points;
    }
    godot::Dictionary field_patch_state(){
        std::lock_guard<std::mutex> lock(mutex_);godot::Dictionary result;
        result["revision"]=world_.revision;result["epoch"]=int64_t(storage_epoch_);
        result["seed"]=world_.seed;result["generator"]=world_.generator_id;return result;
    }
    bool validate_field_patch(const godot::PackedByteArray &patch) const {
        if(patch.size()>FIELD_PATCH_LIMIT)return false;
        FieldPatchBounds bounds;int seed=0;u32 generator=0;
        return terraforest::validate_field_patch(patch.ptr(),int(patch.size()),bounds,seed,generator);
    }
    godot::PackedByteArray capture_field_patch(godot::Vector3i origin,godot::Vector3i size,int64_t revision,int64_t epoch){
        std::lock_guard<std::mutex> lock(mutex_);
        if(revision<0||revision!=world_.revision||epoch<=0||uint64_t(epoch)!=storage_epoch_)return {};
        tr_oom=false;Bytes bytes;godot::PackedByteArray result;
        const FieldPatchBounds bounds{origin.x,origin.y,origin.z,size.x,size.y,size.z};
        if(terraforest::capture_field_patch(world_,bounds,bytes)&&result.resize(bytes.n)==godot::OK)copy_bytes(result.ptrw(),bytes.p,bytes.n);
        bytes.release();return result;
    }
    godot::Dictionary restore_field_patch(const godot::PackedByteArray &patch,int64_t revision,int64_t epoch){
        std::lock_guard<std::mutex> lock(mutex_);godot::Dictionary result;
        result["ok"]=false;result["changes"]=0;result["revision"]=world_.revision;
        result["epoch"]=int64_t(storage_epoch_);result["minimum"]=godot::Vector3();result["maximum"]=godot::Vector3();
        if(patch.size()>FIELD_PATCH_LIMIT||revision<0||revision!=world_.revision||epoch<=0||uint64_t(epoch)!=storage_epoch_)return result;
        tr_oom=false;FieldPatchResult receipt;
        if(!terraforest::restore_field_patch(world_,patch.ptr(),int(patch.size()),int(revision),receipt))return result;
        if(receipt.changes&&snapshot_worker_)snapshot_worker_->observe_density_edit(int(revision),world_.revision,receipt.minimum,receipt.maximum);
        result["ok"]=true;result["changes"]=receipt.changes;result["revision"]=world_.revision;
        result["minimum"]=godot::Vector3(receipt.minimum.x,receipt.minimum.y,receipt.minimum.z);
        result["maximum"]=godot::Vector3(receipt.maximum.x,receipt.maximum.y,receipt.maximum.z);return result;
    }
    bool validate_cube_patch(const godot::PackedByteArray &patch) const {
        if(patch.size()>CUBE_PATCH_LIMIT)return false;
        CubePatchBounds bounds;int seed=0;u32 generator=0;
        return terraforest::validate_cube_patch(patch.ptr(),int(patch.size()),bounds,seed,generator);
    }
    godot::PackedByteArray capture_cube_patch(godot::Vector3i origin,godot::Vector3i size,int64_t revision,int64_t epoch){
        std::lock_guard<std::mutex> lock(mutex_);
        if(revision<0||revision!=world_.revision||epoch<=0||uint64_t(epoch)!=storage_epoch_)return {};
        tr_oom=false;Bytes bytes;godot::PackedByteArray result;
        const CubePatchBounds bounds{origin.x,origin.y,origin.z,size.x,size.y,size.z};
        if(terraforest::capture_cube_patch(world_,bounds,bytes)&&result.resize(bytes.n)==godot::OK)copy_bytes(result.ptrw(),bytes.p,bytes.n);
        bytes.release();return result;
    }
    godot::Dictionary restore_cube_patch(const godot::PackedByteArray &patch,int64_t revision,int64_t epoch){
        std::lock_guard<std::mutex> lock(mutex_);godot::Dictionary result;
        result["ok"]=false;result["changes"]=0;result["revision"]=world_.revision;
        result["epoch"]=int64_t(storage_epoch_);result["minimum"]=godot::Vector3();result["maximum"]=godot::Vector3();
        if(patch.size()>CUBE_PATCH_LIMIT||revision<0||revision!=world_.revision||epoch<=0||uint64_t(epoch)!=storage_epoch_)return result;
        tr_oom=false;CubePatchResult receipt;
        if(!terraforest::restore_cube_patch(world_,patch.ptr(),int(patch.size()),int(revision),receipt))return result;
        result["ok"]=true;result["changes"]=receipt.changes;result["revision"]=world_.revision;
        result["minimum"]=godot::Vector3(receipt.minimum.x,receipt.minimum.y,receipt.minimum.z);
        result["maximum"]=godot::Vector3(receipt.maximum.x,receipt.maximum.y,receipt.maximum.z);return result;
    }
    godot::Dictionary material_deposits(const godot::Array &earthworks){
        std::lock_guard<std::mutex> lock(mutex_);return terraforest::plan_material_deposits(world_,earthworks);
    }
    godot::Dictionary exploration_sites(const godot::Array &layouts,const godot::Array &reservations,const godot::Array &earthworks,const godot::PackedVector3Array &road_stops){
        std::lock_guard<std::mutex> lock(mutex_);return terraforest::plan_exploration_sites(world_,layouts,reservations,earthworks,road_stops);
    }
    godot::Dictionary fit_road_network(const godot::Array &roads,const godot::Array &protected_areas,bool footprint_policy=false){
        std::lock_guard<std::mutex> lock(mutex_);tr_oom=false;auto result=fit_generated_road_network(world_,roads,protected_areas,footprint_policy);return tr_oom?godot::Dictionary():result;
    }
    godot::Dictionary normalize_roads(const godot::Array &roads,const godot::Array &protected_areas){
        std::lock_guard<std::mutex> lock(mutex_);tr_oom=false;auto result=normalize_generated_roads(world_,roads,protected_areas);return tr_oom?godot::Dictionary():result;
    }
    godot::Dictionary plan_network(const godot::Array &districts,const godot::Array &reservations,int loops,int trails,int64_t seed,const godot::Array &streets=godot::Array(),double corridor_extent=5.0){
        std::lock_guard<std::mutex> lock(mutex_);tr_oom=false;auto result=plan_region_network(world_,districts,reservations,loops,trails,seed,streets,corridor_extent);return tr_oom?godot::Dictionary():result;
    }
    godot::Dictionary fit_lakes(const godot::Array &records){std::lock_guard<std::mutex> lock(mutex_);tr_oom=false;auto result=fit_generated_lakes(world_,records);return tr_oom?godot::Dictionary():result;}
    godot::Dictionary lake_crossings(bool metropolis=false){std::lock_guard<std::mutex> lock(mutex_);tr_oom=false;auto result=plan_lake_crossings(world_,metropolis);return tr_oom?godot::Dictionary():result;}
    godot::Dictionary land_footbridges(const godot::Array &roads,const godot::Array &reserved,int64_t seed){std::lock_guard<std::mutex> lock(mutex_);tr_oom=false;auto result=plan_land_footbridges(world_,roads,reserved,seed);return tr_oom?godot::Dictionary():result;}
    godot::Dictionary plan_route(godot::Vector3 start,godot::Vector3 finish,const godot::Array &reservations){
        std::lock_guard<std::mutex> lock(mutex_);tr_oom=false;auto result=plan_regional_route(world_,start,finish,reservations);return tr_oom?godot::Dictionary():result;
    }
    godot::PackedByteArray render_plan_map(const godot::PackedByteArray &pixels,const godot::Array &roads,const godot::Array &lots,const godot::PackedByteArray &water=godot::PackedByteArray()){return render_generation_map(pixels,roads,lots,water);}
    godot::Dictionary plan_lots(godot::Vector3 center,const godot::Array &lots,const godot::Array &roads,bool default_streets){
        std::lock_guard<std::mutex> lock(mutex_);tr_oom=false;auto result=plan_settlement_lots(world_,center,lots,roads,default_streets);return tr_oom?godot::Dictionary():result;
    }
    godot::Dictionary plan_streets(const godot::Array &roads,const godot::PackedVector3Array &junctions){
        std::lock_guard<std::mutex> lock(mutex_);tr_oom=false;auto result=plan_street_network(world_,roads,junctions);return tr_oom?godot::Dictionary():result;
    }
    godot::Dictionary survey_water_visibility(const godot::PackedVector3Array &points){
        std::lock_guard<std::mutex> lock(mutex_);tr_oom=false;auto result=terraforest_survey_water_visibility(world_,points);return tr_oom?godot::Dictionary():result;
    }
    godot::Dictionary survey_patch(int64_t size,int64_t x,int64_t z,int64_t width,int64_t height){
        if(size<64||size>1024||x<0||z<0||x>=size||z>=size||width<1||height<1||width>16||height>16)return {};
        std::lock_guard<std::mutex> lock(mutex_);tr_oom=false;auto result=terraforest_survey_patch(world_,int(size),int(x),int(z),int(width),int(height));return tr_oom?godot::Dictionary():result;
    }
    godot::Dictionary survey_overview(int64_t size){
        std::lock_guard<std::mutex> lock(mutex_);tr_oom=false;auto result=terraforest_survey_map(world_,size);return tr_oom?godot::Dictionary():result;
    }
    godot::Dictionary survey_surface_map(){
        std::lock_guard<std::mutex> lock(mutex_);tr_oom=false;auto result=terraforest_survey_surface(world_);return tr_oom?godot::Dictionary():result;
    }
    godot::Dictionary measure_material_surface(int64_t x,int64_t z,int64_t size,int64_t y_begin,int64_t y_end){
        godot::Dictionary result;result["valid"]=false;
        if(x<0||x>WORLD||z<0||z>WORLD||size<1||size>32||y_begin<1||y_end>255||y_end<=y_begin||y_end-y_begin>32)return result;
        std::lock_guard<std::mutex> lock(mutex_);tr_oom=false;
        double integral=0;int triangles=0;bool closed=false;
        if(!::measure_material_surface(world_,int(x),int(z),int(size),int(y_begin),int(y_end),integral,triangles,closed))return result;
        result["valid"]=true;result["signed_integral_m3"]=integral;result["closed"]=closed;
        result["triangles"]=triangles;result["revision"]=world_.revision;
        // An open patch's origin-dependent integral is not its physical volume.
        if(closed)result["volume_m3"]=integral<0?-integral:integral;
        return result;
    }
    godot::Dictionary material_box(const godot::Ref<TerrainCore>&solid,godot::Vector3 minimum,godot::Vector3 maximum,bool add,int64_t solid_revision,int64_t material_revision=-1){
        godot::Dictionary result;result["accepted"]=false;result["changes"]=0;
        if(solid.is_null()||solid.ptr()==this)return result;
        // A single lock transaction prevents terrain changes between exclusion and commit.
        std::scoped_lock lock(mutex_,solid->mutex_);
        if(solid_revision!=solid->world_.revision||(material_revision>=0&&material_revision!=world_.revision))return result;
        tr_oom=false;V3 lo,hi;int changes=0;
        bool ok=world_.material_box(solid->world_,{float(minimum.x),float(minimum.y),float(minimum.z)},
            {float(maximum.x),float(maximum.y),float(maximum.z)},add,lo,hi,changes);
        if(changes)snapshot_epoch_.fetch_add(1);
        result["accepted"]=ok;result["changes"]=changes;result["revision"]=world_.revision;
        result["solid_revision"]=solid->world_.revision;
        if(ok){result["minimum"]=godot::Vector3(lo.x,lo.y,lo.z);result["maximum"]=godot::Vector3(hi.x,hi.y,hi.z);}
        return result;
    }
    godot::PackedByteArray build_owned_region(int64_t x,int64_t z,int64_t size,int64_t step,int64_t y_begin,int64_t y_end,int64_t epoch){
        if(x<0||z<0||x>=2048||z>=2048||size<16||size>64||step<1||step>8||y_begin<0||y_end>WORLD_Y||epoch<0||epoch>0xffffffffLL)return {};
        std::lock_guard<std::mutex> lock(mutex_);tr_oom=false;
        Mesh mesh;Bytes bytes;godot::PackedByteArray result;
        if(::build_owned_region(world_,int(x),int(z),int(size),int(step),int(y_begin),int(y_end),mesh,u32(epoch))){
            encode_mesh(mesh,int(x),int(z),int(size),int(step),bytes);
            if(!tr_oom&&terrain_build_epoch(&world_)==u32(epoch)){
                result.resize(bytes.n);if(bytes.n)copy_bytes(result.ptrw(),bytes.p,bytes.n);
            }
        }
        mesh.release();bytes.release();return result;
    }
    godot::PackedByteArray build_owned_column(int64_t origin_x,int64_t origin_z,int64_t size,int64_t step,int64_t epoch){
        if(origin_x<0||origin_z<0||origin_x>=2048||origin_z>=2048||size<16||size>64||step<1||step>8||epoch<0||epoch>0xffffffffLL)return {};
        std::lock_guard<std::mutex> lock(mutex_);tr_oom=false;
        Mesh mesh;Bytes bytes;godot::PackedByteArray result;
        if(::build_owned_column(world_,int(origin_x),int(origin_z),int(size),int(step),mesh,u32(epoch))){
            encode_mesh(mesh,int(origin_x),int(origin_z),int(size),int(step),bytes);
            if(!tr_oom&&terrain_build_epoch(&world_)==u32(epoch)){
                result.resize(bytes.n);if(bytes.n)copy_bytes(result.ptrw(),bytes.p,bytes.n);
            }
        }
        mesh.release();bytes.release();return result;
    }
    godot::Dictionary geometry_cache_key(int64_t x,int64_t z,int64_t size,int64_t step) {
        if(x<0||z<0||x>=2048||z>=2048||size<16||size>256||step<1||step>8)return {};
        std::lock_guard<std::mutex> lock(mutex_);
        tr_oom=false;auto result=terraforest::geometry_content_key(world_,int(x),int(z),int(size),int(step));return tr_oom?godot::Dictionary():result;
    }
    TerrainCore() {
        control_.parallel_edit=[](void (*work)(void*,u32),void *context,int count){
            auto *pool=godot::WorkerThreadPool::get_singleton();
            auto task=pool?pool->add_native_group_task(work,context,count,4,true,"Terrain edit pages"):-1;
            if(task>=0)pool->wait_for_group_task_completion(task);
            else for(int i=0;i<count;++i)work(context,u32(i));
        };
        world_.build_control=&control_;tr_oom=false;world_.init();
    }
    ~TerrainCore() {
        snapshot_worker_.reset();
        if(page_owner_.is_valid()){
            world_.pages={};world_.pages_by_key={};world_.blocks={};
            world_.block_columns={};world_.edit_columns=nullptr;world_.caves={};
        }
        world_.release();
    }
    godot::Dictionary experimental_partition_mesh_budgeted(const godot::PackedByteArray&packet,int64_t workspace,int64_t output,int64_t expected){
        godot::Dictionary result;result["packets"]=godot::Array();result["workspace_peak"]=0;result["denied"]=0;result["cancelled"]=false;
        if(workspace<1||workspace>128*1024*1024||output<1||output>128*1024*1024||expected<0||expected>0xffffffffLL)return result;
        struct Context{BuildControl*control;u32 epoch;}context{&control_,u32(expected)};
        experimental::PartitionLimits limits;limits.workspace_bytes=size_t(workspace);limits.output_bytes=size_t(output);limits.context=&context;
        limits.cancelled=[](void*p){auto*c=static_cast<Context*>(p);return __atomic_load_n(&c->control->epoch,__ATOMIC_RELAXED)!=c->epoch;};
        experimental::PartitionStats stats;
        result["packets"]=experimental::partition_mesh(packet,limits,&stats);result["workspace_peak"]=int64_t(stats.workspace_peak);result["denied"]=int64_t(stats.denied);result["cancelled"]=stats.cancelled;return result;
    }
    godot::Array experimental_partition_mesh(const godot::PackedByteArray&packet){
        return experimental_partition_mesh_budgeted(packet,128*1024*1024,128*1024*1024,__atomic_load_n(&control_.epoch,__ATOMIC_RELAXED))["packets"];
    }
    godot::PackedByteArray experimental_snapshot_encode(const godot::Dictionary&packet,int64_t x,int64_t z,int64_t size){
        // The legacy column codec adds full-height blocks and owns a column.
        // Bounded surfaces must not be published through it as complete columns.
        if(int64_t(packet.get("y_begin",0))!=0||int64_t(packet.get("y_end",WORLD_Y))!=WORLD_Y)return {};
        return encode_snapshot_surface(packet,x,z,size,0,WORLD_Y);
    }
    godot::Dictionary experimental_snapshot_encode_brick(const godot::Dictionary&packet,int64_t x,int64_t z,int64_t size){
        for(const char*key:{"y_begin","y_end"})if(!packet.has(key)||godot::Variant(packet[key]).get_type()!=godot::Variant::INT)return {};
        int64_t begin=packet["y_begin"],end=packet["y_end"];
        if(begin<0||begin>=end||end>WORLD_Y)return {};
        auto bytes=encode_snapshot_surface(packet,x,z,size,int(begin),int(end));if(bytes.is_empty())return {};
        godot::Dictionary result;result["packet"]=bytes;
        result["origin"]=godot::Vector3i(int(x),int(begin),int(z));result["extent"]=godot::Vector3i(int(size),int(end-begin),int(size));
        result["epoch"]=packet["epoch"];result["revision"]=packet["validated_revision"];return result;
    }
private:
    godot::PackedByteArray encode_snapshot_surface(const godot::Dictionary&packet,int64_t x,int64_t z,int64_t size,int y_begin,int y_end){
        if(x<0||z<0||(size!=16&&size!=32)||x>WORLD-size||z>WORLD-size)return {};
        for(const char*key:{"status","epoch","validated_revision","source_id"})
            if(!packet.has(key)||godot::Variant(packet[key]).get_type()!=godot::Variant::INT)return {};
        if(int64_t(packet["status"])!=0||bool(packet.get("stale",true))||int64_t(packet["source_id"])!=int64_t(get_instance_id()))return {};
        auto arrays=experimental::surface_arrays(packet);if(arrays.is_empty())return {};
        godot::PackedVector3Array positions=arrays[godot::Mesh::ARRAY_VERTEX],normals=arrays[godot::Mesh::ARRAY_NORMAL];
        godot::PackedInt32Array indices=arrays[godot::Mesh::ARRAY_INDEX];
        std::lock_guard<std::mutex> lock(mutex_);
        if(int64_t(packet["validated_revision"])!=world_.revision||int64_t(packet["epoch"])<0||u64(int64_t(packet["epoch"]))!=snapshot_epoch_.load())return {};
        const u32 build_epoch=terrain_build_epoch(&world_);tr_oom=false;
        Mesh mesh;mesh.v.resize(int(positions.size()));mesh.i.resize(int(indices.size()));
        if(tr_oom){mesh.release();return {};}
        for(int at=0;at<positions.size();at++){
            auto p=positions[at],n=normals[at];
            if(p.x<x||p.x>x+size||p.z<z||p.z>z+size||p.y<y_begin||p.y>y_end){mesh.release();return {};}
            mesh.v[at].p={float(p.x),float(p.y),float(p.z)};mesh.v[at].n={float(n.x),float(n.y),float(n.z)};
        }
        for(int at=0;at<indices.size();at++)mesh.i[at]=u32(indices[at]);
        add_blocks(world_,int(x),int(z),int(size),mesh,y_begin,y_end);
        if(!tr_oom)shade_mesh(world_,mesh,build_epoch);
        Bytes encoded;
        if(!tr_oom&&build_epoch==terrain_build_epoch(&world_))encode_mesh(mesh,int(x),int(z),int(size),1,encoded);
        godot::PackedByteArray result;
        if(!tr_oom&&u64(int64_t(packet["epoch"]))==snapshot_epoch_.load()&&result.resize(encoded.n)==godot::OK&&encoded.n)copy_bytes(result.ptrw(),encoded.p,encoded.n);
        mesh.release();encoded.release();return result;
    }
public:
    godot::Ref<godot::ArrayMesh> experimental_snapshot_create_mesh(const godot::Dictionary&packet){
        for(const char*key:{"status","epoch","validated_revision","source_id"})
            if(!packet.has(key)||godot::Variant(packet[key]).get_type()!=godot::Variant::INT)return {};
        if(int64_t(packet["status"])!=0||bool(packet.get("stale",true))||int64_t(packet["source_id"])!=int64_t(get_instance_id()))return {};
        const int64_t revision=packet["validated_revision"],epoch=packet["epoch"];
        {std::lock_guard<std::mutex> lock(mutex_);if(revision!=world_.revision||epoch<0||u64(epoch)!=snapshot_epoch_.load())return {};}
        auto mesh=experimental::make_surface_mesh(packet);
        // Engine allocation/upload is outside the authoritative-world mutex.
        {std::lock_guard<std::mutex> lock(mutex_);if(revision!=world_.revision||u64(epoch)!=snapshot_epoch_.load())return {};}
        return mesh;
    }
    bool experimental_snapshot_submit(int64_t x,int64_t z,int64_t size,int64_t token,int64_t revision){
        return experimental_snapshot_submit_brick(x,z,size,token,revision,0,WORLD_Y);
    }
    bool experimental_snapshot_submit_brick(int64_t x,int64_t z,int64_t size,int64_t token,int64_t revision,int64_t y_begin,int64_t y_end){
        if(x<0||z<0||x>WORLD||z>WORLD||size<1||size>32||token<0||revision<0||y_begin<0||y_begin>=y_end||y_end>WORLD_Y)return false;
        using Clock=std::chrono::steady_clock;auto begin=Clock::now();
        std::unique_lock<std::mutex> lock(mutex_);
        SubmitTiming timing;timing.token=token;
        timing.world_lock_ms=std::chrono::duration<double,std::milli>(Clock::now()-begin).count();
        if(revision==world_.revision){
            auto startup=Clock::now();
            if(!snapshot_worker_)snapshot_worker_.emplace(3*1024*1024,32*1024*1024);
            timing.startup_ms=std::chrono::duration<double,std::milli>(Clock::now()-startup).count();
            timing.accepted=snapshot_worker_->submit(world_,int(x),int(z),int(size),snapshot_epoch_.load(),u64(token),&timing.worker,int(y_begin),int(y_end));
        }
        auto unlocking=Clock::now();lock.unlock();
        timing.world_unlock_ms=std::chrono::duration<double,std::milli>(Clock::now()-unlocking).count();
        timing.total_ms=std::chrono::duration<double,std::milli>(Clock::now()-begin).count();
        {std::lock_guard<std::mutex> timing_lock(submit_timing_mutex_);last_submit_=timing;}
        return timing.accepted;
    }
    godot::Dictionary experimental_snapshot_submit_timing(){
        SubmitTiming timing;{std::lock_guard<std::mutex> lock(submit_timing_mutex_);timing=last_submit_;}
        godot::Dictionary row;
        row["token"]=timing.token;row["accepted"]=timing.accepted;row["total_ms"]=timing.total_ms;
        row["world_lock_ms"]=timing.world_lock_ms;row["startup_ms"]=timing.startup_ms;
        row["worker_lock_ms"]=timing.worker.lock_ms;row["capture_ms"]=timing.worker.capture_ms;
        row["handoff_ms"]=timing.worker.handoff_ms;row["world_unlock_ms"]=timing.world_unlock_ms;return row;
    }
    godot::Array experimental_snapshot_poll(){
        std::lock_guard<std::mutex> lock(mutex_);godot::Array rows;
        if(!snapshot_worker_)return rows;
        const u64 epoch=snapshot_epoch_.load();
        snapshot_worker_->consume_surface(epoch,world_.revision,[&](u64 token,u64 captured,int revision,bool stale,const experimental::Result&r,const experimental::NormalResult&n){
            godot::Dictionary row;row["token"]=int64_t(token);row["epoch"]=int64_t(captured);row["revision"]=revision;row["stale"]=stale;
            row["source_id"]=int64_t(get_instance_id());
            row["validated_revision"]=stale?-1:world_.revision;
            row["y_begin"]=r.y_begin;row["y_end"]=r.y_end;
            int status=int(r.status);godot::PackedByteArray positions,indices,normals;
            if(r.status==experimental::MeshStatus::ok){
                static_assert(sizeof(V3)==12);
                if(n.status!=experimental::MeshStatus::ok||n.values.size()!=r.p.size()){
                    status=int(experimental::MeshStatus::internal_error);
                }else if(positions.resize(r.p.size()*sizeof(V3))!=godot::OK||indices.resize(r.indices.size()*sizeof(u32))!=godot::OK||normals.resize(n.values.size()*sizeof(V3))!=godot::OK){
                    positions.clear();indices.clear();normals.clear();status=int(experimental::MeshStatus::allocation_failed);
                }else{
                    if(!r.p.empty())copy_bytes(positions.ptrw(),r.p.data(),r.p.size()*sizeof(V3));
                    if(!r.indices.empty())copy_bytes(indices.ptrw(),r.indices.data(),r.indices.size()*sizeof(u32));
                    if(!n.values.empty())copy_bytes(normals.ptrw(),n.values.data(),n.values.size()*sizeof(V3));
                }
            }
            row["status"]=status;row["positions"]=positions;row["indices"]=indices;row["normals"]=normals;rows.push_back(row);
        });
        // Command 12 can invalidate concurrently without acquiring the world lock.
        if(snapshot_epoch_.load()!=epoch)for(int i=0;i<rows.size();i++){
            godot::Dictionary row=rows[i];row["stale"]=true;row["status"]=int(experimental::MeshStatus::cancelled);
            row["validated_revision"]=-1;
            row["positions"]=godot::PackedByteArray();row["indices"]=godot::PackedByteArray();row["normals"]=godot::PackedByteArray();
        }
        return rows;
    }
    void experimental_snapshot_stop(){std::lock_guard<std::mutex> lock(mutex_);if(snapshot_worker_)snapshot_worker_->stop();}
    bool supports_isolated_worlds() const {return true;}
    int64_t executing_command() const {return active_command_.load(std::memory_order_relaxed);}
    godot::String build_variant() const {
#ifdef DEBUG_ENABLED
        return "template_debug";
#else
        return "template_release";
#endif
    }
    // Offline new-world admission only. Apply the exact ordinary command28
    // sequence once, before any mesh/collision or immutable snapshot is exposed.
    godot::Dictionary bake_generated_earthworks(const godot::Array &packets) {
        godot::Dictionary result;result["ok"]=false;result["completed"]=0;
        if(packets.is_empty()||packets.size()>16384){result["reason"]="Invalid generation command count";return result;}
        int64_t total=0;
        std::vector<godot::PackedByteArray> commands;
        for(int64_t i=0;i<packets.size();++i){
            if(packets[i].get_type()!=godot::Variant::PACKED_BYTE_ARRAY){result["reason"]="Generation command is not a byte packet";result["command"]=i;return result;}
            godot::PackedByteArray packet=packets[i];total+=packet.size();
            if(packet.size()<44||packet.size()>1080||(packet.decode_u32(0)!=28&&packet.decode_u32(0)!=41)){result["reason"]="Invalid generation command format";result["command"]=i;return result;}
            if(total>4*1024*1024){result["reason"]="Generation command data exceeds the 4 MiB budget";result["command_bytes"]=total;return result;}
            commands.push_back(packet);
        }
        std::lock_guard<std::mutex> lock(mutex_);
        if(world_.revision||world_.edits||world_.pages.n||world_.blocks.n||snapshot_worker_){result["reason"]="Generation requires a pristine unpublished world";return result;}
        const int seed=world_.seed;const auto generator=world_.generator_id;
        const auto started=std::chrono::steady_clock::now();
        snapshot_epoch_.fetch_add(1);active_command_.store(28,std::memory_order_relaxed);
        int completed=0;bool good=true;
        for(const auto &packet:commands){
            tr_oom=false;Bytes response;process_request(world_,packet.ptr(),int(packet.size()),response);
            good=!tr_oom&&response.n>=12&&response.p[8]==0;response.release();
            if(!good){result["completed"]=completed;break;}++completed;
        }
        active_command_.store(-1,std::memory_order_relaxed);
        if(!good){
            // No published state exists. Discard every partial edit on rejection.
            tr_oom=false;world_.release();world_=World{};world_.build_control=&control_;world_.init(seed,generator);
            result["reason"]="Generation command rejected; unpublished edits discarded";return result;
        }
        result["ok"]=true;result["completed"]=completed;result["revision"]=world_.revision;
        result["worker_ms"]=std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-started).count();return result;
    }
    // Unpublished generation only. Durable private checkpoints make clean pages
    // evictable without publishing a compound-world root or losing prior edits.
    godot::Dictionary generation_bake_progress()const{return generation_progress_.read();}
    godot::Dictionary bake_generated_earthworks_staged(const godot::Array &packets,const godot::String &directory,int64_t limit=MAX_PAGES,int64_t batch=64,int64_t expected_epoch=-1,int64_t test_stop_at_checkpoint=-1,bool optimized=true){
        godot::Dictionary result;result["ok"]=false;result["completed"]=0;
        if(packets.is_empty()||packets.size()>16384||limit<8||limit>MAX_PAGES||batch<1||batch>16384||expected_epoch< -1||expected_epoch>0xffffffffll||test_stop_at_checkpoint< -1||test_stop_at_checkpoint>8193||!directory.is_absolute_path()){
            result["reason"]="Invalid staged generation bounds";return result;
        }
        std::vector<godot::PackedByteArray> commands;int64_t total=0;
        for(int64_t i=0;i<packets.size();++i){
            if(packets[i].get_type()!=godot::Variant::PACKED_BYTE_ARRAY){result["reason"]="Generation command is not a byte packet";result["command"]=i;return result;}
            godot::PackedByteArray packet=packets[i];total+=packet.size();
            if(packet.size()<44||packet.size()>1080||(packet.decode_u32(0)!=28&&packet.decode_u32(0)!=41)){result["reason"]="Invalid generation command format";result["command"]=i;return result;}
            if(total>4*1024*1024){result["reason"]="Generation command data exceeds the 4 MiB budget";result["command_bytes"]=total;return result;}
            commands.push_back(packet);
        }
        std::lock_guard<std::mutex> lock(mutex_);
        if(expected_epoch>=0&&terrain_build_epoch(&world_)!=uint32_t(expected_epoch)){result["reason"]="Generation cancelled before staging";return result;}
        if(world_.revision||world_.edits||world_.pages.n||world_.blocks.n||snapshot_worker_||residency_||!storage_reference_.is_empty()){
            result["reason"]="Generation requires a pristine unpublished world";return result;
        }
        if(godot::DirAccess::dir_exists_absolute(directory)||godot::FileAccess::file_exists(directory)){
            result["reason"]="Generation staging directory already exists";return result;
        }
        godot::Ref<NativeTerrainRegionStore> store;store.instantiate();
        if(!store->open_store(directory,true)){result["reason"]="Cannot create private terrain staging store";return result;}
        const int seed=world_.seed;const auto generator=world_.generator_id;
        const u32 epoch=expected_epoch>=0?uint32_t(expected_epoch):terrain_build_epoch(&world_);const auto started=std::chrono::steady_clock::now();
        uint64_t apply_us=0,checkpoint_us=0;
        godot::PackedByteArray reference;int completed=0,checkpoints=0,retries=0,checkpoint_revision=-1;
        int64_t capture_high=0;
        generation_progress_.publish(GenerationBakeProgress::RUNNING,GenerationBakeProgress::APPLYING,completed,int(commands.size()),checkpoints);
        auto checkpoint=[&](){
            if(terrain_build_epoch(&world_)!=epoch)return false;
            if(checkpoint_revision==world_.revision)return true;
            generation_progress_.publish(GenerationBakeProgress::RUNNING,GenerationBakeProgress::CHECKPOINT,completed,int(commands.size()),checkpoints);
            const auto checkpoint_start=std::chrono::steady_clock::now();
            auto capture=capture_storage_snapshot_locked();if(capture.is_null())return false;
            capture_high=std::max(capture_high,int64_t(capture->stats()["sample_bytes"]));
            auto next=store->publish_capture(capture,reference,checkpoints==test_stop_at_checkpoint?(checkpoints==0?0:1):-1);
            if(next.size()!=40||terrain_build_epoch(&world_)!=epoch||!commit_storage_snapshot_locked(capture,next))return false;
            reference=next;checkpoint_revision=world_.revision;++checkpoints;
            checkpoint_us+=std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now()-checkpoint_start).count();
            generation_progress_.publish(GenerationBakeProgress::RUNNING,GenerationBakeProgress::APPLYING,completed,int(commands.size()),checkpoints);return true;
        };
        snapshot_epoch_.fetch_add(1);active_command_.store(28,std::memory_order_relaxed);
        bool good=checkpoint()&&mount_storage_checkpoint_locked(directory,reference,limit);
        // Mount installs a fresh World. Set the private optimization after that
        // transaction, and always clear it before exposing ordinary editing.
        world_.generation_road_columns=optimized;world_.generation_road_columns_count=0;
        struct ColumnGuard {World &world;~ColumnGuard(){world.generation_road_columns=false;}} column_guard{world_};
        for(const auto &packet:commands){
            if(!good||terrain_build_epoch(&world_)!=epoch){good=false;break;}
            bool retryable=false;
            auto apply=[&](){
                const auto apply_start=std::chrono::steady_clock::now();
                tr_oom=false;Bytes response;process_request(world_,packet.ptr(),int(packet.size()),response);
                apply_us+=std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now()-apply_start).count();
                bool ok=!tr_oom&&response.n>=12&&response.p[8]==0;retryable=response.n>=12&&response.p[8]==2;response.release();return ok;
            };
            good=apply();
            // Ordinary edits roll back exactly on failed admission. Checkpoint
            // earlier commands once, then retry; an indivisible oversized edit
            // still rejects rather than raising the resident limit.
            if(!good&&retryable&&world_.revision!=checkpoint_revision&&terrain_build_epoch(&world_)==epoch){
                ++retries;good=checkpoint()&&apply();
            }
            if(!good)break;
            ++completed;
            generation_progress_.publish(GenerationBakeProgress::RUNNING,GenerationBakeProgress::APPLYING,completed,int(commands.size()),checkpoints);
            if(completed%batch==0)good=checkpoint();
        }
        if(good)good=checkpoint()&&terrain_build_epoch(&world_)==epoch;
        active_command_.store(-1,std::memory_order_relaxed);
        result["completed"]=completed;result["checkpoints"]=checkpoints;result["admission_retries"]=retries;
        result["capture_sample_bytes_high"]=capture_high;result["resident_limit"]=limit;
        result["resident_high"]=residency_?residency_->resident_high():0;
        result["worker_ms"]=std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-started).count();
        result["storage"]=store->stats();
        result["apply_us"]=int64_t(apply_us);result["checkpoint_us"]=int64_t(checkpoint_us);
        result["road_columns_optimized"]=optimized;result["road_columns"]=int64_t(world_.generation_road_columns_count);
        world_.generation_road_columns=false;
        if(!good){
            generation_progress_.publish(terrain_build_epoch(&world_)!=epoch?GenerationBakeProgress::CANCELLED:GenerationBakeProgress::FAILED,GenerationBakeProgress::NONE,completed,int(commands.size()),checkpoints);
            // Only immutable staging products may remain. No canonical root was
            // published; invalidate captures and discard every partial world edit.
            tr_oom=false;world_.release();residency_.reset();world_=World{};world_.build_control=&control_;world_.init(seed,generator);
            saved_keys_=godot::PackedInt32Array();saved_versions_=godot::PackedInt64Array();storage_reference_=godot::PackedByteArray();
            storage_load_pending_=false;++storage_epoch_;snapshot_epoch_.fetch_add(1);
            result["reason"]="Staged generation rejected or cancelled; unpublished edits discarded";return result;
        }
        generation_progress_.publish(GenerationBakeProgress::COMPLETE,GenerationBakeProgress::NONE,completed,int(commands.size()),checkpoints);
        result["ok"]=true;result["revision"]=world_.revision;result["checkpoint"]=reference;return result;
    }
    godot::PackedByteArray shore_habitat_program(){
        std::lock_guard<std::mutex> lock(mutex_);
        if(world_.generator_id!=SHORE_HABITAT_GENERATOR_ID)return {};
        unsigned count=0;for(int i=0;i<std::min(3,world_.basin_count);i++)count+=world_.lake_fields[i].count;
        if(count>terraforest::landforms::ShoreHabitat::MAX_SEGMENTS)return {};
        godot::PackedByteArray out;out.resize(16+count*24);out.encode_u32(0,terraforest::landforms::ShoreHabitat::MAGIC);out.encode_u32(4,1);out.encode_u32(8,count);out.encode_u32(12,world_.seed);
        int at=16;
        for(int i=0;i<std::min(3,world_.basin_count);i++){
            const auto&b=world_.basins[i];const auto&field=world_.lake_fields[i];
            for(unsigned j=0;j<field.count;j++){
                const auto&s=field.segments[j];float values[]={b.x+(b.along_x?s.ax:s.az),b.z+(b.along_x?s.az:s.ax),s.aw,b.x+(b.along_x?s.bx:s.bz),b.z+(b.along_x?s.bz:s.bx),s.bw};
                for(float value:values){out.encode_float(at,value);at+=4;}
            }
        }
        return out;
    }
    godot::Dictionary survey_generated_lake_surfaces(const godot::Array &records){std::lock_guard<std::mutex> lock(mutex_);tr_oom=false;auto result=terraforest::survey_generated_lake_surfaces(world_,records);return tr_oom?godot::Dictionary():result;}
    godot::Ref<NativeTerrainCapture> capture_storage_snapshot(){
        std::lock_guard<std::mutex> lock(mutex_);
        return capture_storage_snapshot_locked();
    }
    godot::Ref<NativeTerrainCapture> capture_storage_snapshot_locked(){
        tr_oom=false;int count=world_.pages.n;if(count<0||count>MAX_AUTHORED_PAGES)return {};
        const int32_t *saved=saved_keys_.ptr();const int64_t *versions=saved_versions_.ptr();
        auto dirty=[&](int i){return i>=saved_keys_.size()||saved[i]!=int32_t(world_.pages[i].key)||uint64_t(versions[i])!=world_.pages[i].storage_version;};
        int changed=0;for(int i=0;i<count;i++)changed+=dirty(i);
        uint64_t bytes=256+uint64_t(count)*12+uint64_t(changed)*(PAGE_SAMPLES*3+4)+uint64_t(world_.blocks.n)*8;
        constexpr uint64_t limit=256*1024*1024;
        uint64_t previous=NativeTerrainCapture::pending_bytes_.load();
        do{if(bytes>limit||previous>limit-bytes)return {};}
        while(!NativeTerrainCapture::pending_bytes_.compare_exchange_weak(previous,previous+bytes));
        godot::Ref<NativeTerrainCapture> capture;capture.instantiate();if(capture.is_null()){NativeTerrainCapture::pending_bytes_.fetch_sub(bytes);return {};}capture->reserved_=bytes;
        if(capture->keys_.resize(count)!=godot::OK||capture->versions_.resize(count)!=godot::OK||capture->changed_.resize(changed)!=godot::OK||capture->samples_.resize(int64_t(changed)*PAGE_SAMPLES*3)!=godot::OK||capture->blocks_.resize(int64_t(world_.blocks.n)*8)!=godot::OK)return {};
        auto *keys=capture->keys_.ptrw();auto *stamps=capture->versions_.ptrw();auto *indices=capture->changed_.ptrw();auto *samples=capture->samples_.ptrw();
        int next=0;
        for(int i=0;i<count;i++){
            const auto &page=world_.pages[i];keys[i]=page.key;stamps[i]=int64_t(page.storage_version);
            if(dirty(i)){if(!world_.resident_page(i))return {};indices[next]=i;copy_bytes(samples+int64_t(next)*PAGE_SAMPLES*3,page.d,PAGE_SAMPLES*2);copy_bytes(samples+int64_t(next)*PAGE_SAMPLES*3+PAGE_SAMPLES*2,page.mat,PAGE_SAMPLES);++next;}
        }
        int64_t at=0;auto *blocks=capture->blocks_.ptrw();
        for(int i=0;i<world_.blocks.cap;i++)if(world_.blocks.p[i].key&&world_.blocks.p[i].key!=0xffffffffu){
            uint32_t key=world_.blocks.p[i].key,value=world_.blocks.p[i].value;copy_bytes(blocks+at,&key,4);copy_bytes(blocks+at+4,&value,4);at+=8;
        }
        if(at!=capture->blocks_.size())return {};
        capture->owner_=get_instance_id();capture->epoch_=storage_epoch_;capture->seed_=world_.seed;capture->generator_=world_.generator_id;capture->revision_=world_.revision;capture->edits_=world_.edits;
        capture->source_=storage_reference_;capture->expected_=storage_reference_;capture->sealed_=true;return capture;
    }
    bool configure_storage_checkpoint(const godot::PackedByteArray &reference,int64_t checksum){
        std::lock_guard<std::mutex> lock(mutex_);
        if(!storage_load_pending_||world_.revision!=storage_load_revision_||checksum<0||checksum>0xffffffffll||uint32_t(checksum)!=storage_load_checksum_||reference.size()!=40||reference.slice(0,4).get_string_from_ascii()!="TFTR"||reference.decode_u32(4)!=1)return false;
        godot::PackedInt32Array keys;godot::PackedInt64Array versions;
        if(keys.resize(world_.pages.n)!=godot::OK||versions.resize(world_.pages.n)!=godot::OK)return false;
        for(int i=0;i<world_.pages.n;i++){keys.set(i,world_.pages[i].key);versions.set(i,int64_t(world_.pages[i].storage_version));}
        saved_keys_=keys;saved_versions_=versions;storage_reference_=reference;storage_load_pending_=false;return true;
    }
    bool commit_storage_snapshot(const godot::Ref<NativeTerrainCapture> &capture,const godot::PackedByteArray &reference){
        std::lock_guard<std::mutex> lock(mutex_);return commit_storage_snapshot_locked(capture,reference);
    }
    bool commit_storage_snapshot_locked(const godot::Ref<NativeTerrainCapture> &capture,const godot::PackedByteArray &reference){
        if(capture.is_null())return false;std::lock_guard<std::mutex> publication(capture->publication_mutex_);
        if(!capture->sealed_||capture->owner_!=get_instance_id()||capture->epoch_!=storage_epoch_||capture->source_!=storage_reference_||capture->published_!=reference||reference.size()!=40||capture->keys_.size()>world_.pages.n)return false;
        for(int i=0;i<capture->keys_.size();i++)if(uint32_t(capture->keys_[i])!=world_.pages[i].key)return false;
        // Newer edits keep their newer page stamps and remain dirty.
        saved_keys_=capture->keys_;saved_versions_=capture->versions_;storage_reference_=reference;storage_load_pending_=false;
        for(int i=0;i<capture->keys_.size();i++)world_.pages[i].clean_version=uint64_t(capture->versions_[i]);
        if(residency_)residency_->checkpoint(reference);return true;
    }
    bool mount_storage_checkpoint(const godot::String &directory,const godot::PackedByteArray &reference,int64_t limit=MAX_PAGES){
        std::lock_guard<std::mutex> lock(mutex_);return mount_storage_checkpoint_locked(directory,reference,limit);
    }
    bool mount_storage_checkpoint_locked(const godot::String &directory,const godot::PackedByteArray &reference,int64_t limit){
        if(limit<8||limit>MAX_PAGES)return false;
        godot::Ref<NativeTerrainRegionStore> store;store.instantiate();if(!store->open_store(directory,false))return false;
        godot::Dictionary description=store->describe_snapshot(reference);if(!bool(description.get("ok",false)))return false;
        godot::PackedInt32Array keys;godot::PackedInt64Array versions;int64_t count=description["pages"];
        if(keys.resize(count)!=godot::OK||versions.resize(count)!=godot::OK)return false;
        auto residency=std::make_unique<TerrainResidency>(store,reference,int(limit));
        tr_oom=false;if(!store->mount_world(world_,reference))return false;
        snapshot_worker_.reset(); // Old immutable jobs must not survive the new owner epoch.
        residency_=std::move(residency);world_.page_access=residency_.get();
        ++storage_epoch_;snapshot_epoch_.fetch_add(1);storage_load_pending_=false;storage_reference_=reference;
        for(int i=0;i<world_.pages.n;i++){keys.set(i,world_.pages[i].key);versions.set(i,int64_t(world_.pages[i].storage_version));}
        saved_keys_=keys;saved_versions_=versions;
        return true;
    }
    godot::Dictionary residency_stats(){std::lock_guard<std::mutex> lock(mutex_);godot::Dictionary d;if(residency_)d=residency_->stats(world_);else{d["active"]=false;d["catalog_pages"]=world_.pages.n;d["resident_pages"]=world_.pages.n;d["resident_limit"]=MAX_PAGES;}d["generator"]=world_.generator_id;d["seed"]=world_.seed;return d;}
    godot::Ref<TerrainCore> capture_contact_core(godot::Rect2i bounds,int64_t revision,int64_t epoch){
        return copy_contact_field(bounds,revision,epoch,false);
    }
    godot::Ref<TerrainFieldReader> capture_edit_field(godot::Rect2i bounds,int64_t revision,int64_t epoch){
        return make_reader(bounds,revision,epoch,false);
    }
    godot::Array capture_edit_domains(const godot::Array &domains,int64_t revision,int64_t epoch){
        if(domains.size()<2||domains.size()>9)return {};
        godot::Rect2i footprint;
        for(int i=0;i<domains.size();++i){
            if(domains[i].get_type()!=godot::Variant::RECT2I)return {};
            const godot::Rect2i r=domains[i];
            if(r.size.x<=0||r.size.y<=0||r.size.x>64||r.size.y>64||
               r.position.x<0||r.position.y<0||r.position.x>WORLD-r.size.x||r.position.y>WORLD-r.size.y)return {};
            footprint=i?footprint.merge(r):r;
        }
        // Charge overlapping lighting halos once. The snapshot still refuses
        // nonresident pages and enforces the ordinary 256-page copy limit.
        auto root=copy_contact_field(footprint,revision,epoch,false,128);
        if(root.is_null())return {};
        root->sealed_column_source_=true;
        godot::Array result;
        for(int i=0;i<domains.size();++i){
            const godot::Rect2i r=domains[i];
            auto reader=root->make_reader(r,revision,epoch,true);
            if(reader.is_null())return {};
            godot::Dictionary group;group["bounds"]=r;group["core"]=reader;result.push_back(group);
        }
        return result;
    }
private:
    godot::Ref<TerrainFieldReader> make_reader(godot::Rect2i bounds,int64_t revision,int64_t epoch,bool borrow){
        auto field=copy_contact_field(bounds,revision,epoch,borrow);
        if(field.is_null())return {};
        field->surface_columns_=borrow&&surface_columns_?surface_columns_:std::make_shared<SealedSurfaceColumns>(
            bounds.position.x,bounds.position.y,bounds.size.x,bounds.size.y);
        field->world_.surface_columns=field->surface_columns_.get();
        godot::Ref<TerrainFieldReader> reader;reader.instantiate();
        reader->field_=field;return reader;
    }
    godot::Ref<TerrainCore> copy_contact_field(godot::Rect2i bounds,int64_t revision,int64_t epoch,bool borrow,int max_side=64){
        std::lock_guard<std::mutex> lock(mutex_);
        if(revision!=world_.revision||epoch!=terrain_build_epoch(&world_)||
           bounds.size.x<=0||bounds.size.y<=0||bounds.size.x>max_side||bounds.size.y>max_side||
           bounds.position.x<0||bounds.position.y<0||bounds.position.x>WORLD-bounds.size.x||
           bounds.position.y>WORLD-bounds.size.y)return {};
        const int x0=imx(0,bounds.position.x-32),z0=imx(0,bounds.position.y-32);
        const int x1=imn(WORLD,bounds.get_end().x+32),z1=imn(WORLD,bounds.get_end().y+32);
        // A worker lane can fork a smaller reader from an already pinned
        // surface. It must never synthesize an omitted authored page or cave.
        if(world_.contact_snapshot&&(x0<world_.contact_x0||z0<world_.contact_z0||
           x1>world_.contact_x1||z1>world_.contact_z1))return {};
        godot::Ref<TerrainCore> copy;copy.instantiate();
        if(copy.is_null()||tr_oom)return {};
        // The sealed parent survives workers and may be released by the scene
        // or superseded by a gameplay edit at any time. Grandchildren pin the
        // same root, without retaining intermediate geometry caches.
        World &dst=copy->world_;
        dst.contact_snapshot=true;dst.seed=world_.seed;dst.generator_id=world_.generator_id;
        dst.revision=world_.revision;dst.contact_revision=dst.revision;dst.surface_style=world_.surface_style;dst.cache_mesh_heights=true;
        dst.profile_mesh=world_.profile_mesh;
        dst.regional_roads=world_.regional_roads;dst.site_count=world_.site_count;dst.basin_count=world_.basin_count;
        copy_bytes(dst.sites,world_.sites,sizeof(dst.sites));
        copy_bytes(dst.road_points,world_.road_points,sizeof(dst.road_points));
        copy_bytes(dst.buildable_weights,world_.buildable_weights,sizeof(dst.buildable_weights));
        copy_bytes(dst.basins,world_.basins,sizeof(dst.basins));
        copy_bytes(dst.basin_cells,world_.basin_cells,sizeof(dst.basin_cells));
        copy->control_.epoch=u32(epoch);
        dst.contact_x0=x0;dst.contact_z0=z0;dst.contact_x1=x1;dst.contact_z1=z1;
        if(borrow){
            // Only immutable TerrainFieldReaders can enter here. Keep one
            // sparse page/block index for all lanes; mutable reconstruction,
            // visibility caches and revision counters remain private.
            if(!world_.contact_snapshot)return {};
            dst.caves.release();dst.block_columns.release();tr_free(dst.edit_columns);
            dst.pages=world_.pages;dst.pages_by_key=world_.pages_by_key;dst.blocks=world_.blocks;
            dst.caves=world_.caves;dst.block_columns=world_.block_columns;dst.edit_columns=world_.edit_columns;
            dst.indexed_caves=world_.indexed_caves;copy_bytes(dst.cave_columns,world_.cave_columns,sizeof(dst.cave_columns));
            copy->page_owner_=page_owner_.is_valid()?page_owner_:godot::Ref<godot::RefCounted>(this);
            if(!copy_surface_columns(world_,dst,bounds.position.x,bounds.position.y,bounds.size.x,bounds.size.y,true,sealed_column_source_))return {};
            return copy;
        }
        dst.caves.resize(world_.caves.n);if(tr_oom)return {};
        copy_bytes(dst.caves.p,world_.caves.p,sizeof(Cave)*dst.caves.n);
        dst.index_cave_columns();
        for(int z=z0/16;z<=z1/16;++z)for(int x=x0/16;x<=x1/16;++x){
            u32 mask=world_.edit_columns[x+WORLD_PAGE_COLUMNS*z];
            dst.edit_columns[x+WORLD_PAGE_COLUMNS*z]=mask;
            while(mask){
                int y=__builtin_ctz(mask);mask&=mask-1;
                u32 key=1+x+WORLD_PAGE_COLUMNS*(z+WORLD_PAGE_COLUMNS*y);
                int id=world_.pages_by_key.get(key);
                if(id<0||dst.pages.n>=256)return {};
                const Page &source=world_.pages[id];
                // A foreground copy never causes disk I/O or evicts another page.
                if(!source.d||!source.mat)return {};
                int at=dst.pages.push(Page{});if(tr_oom)return {};
                Page &page=dst.pages[at];page.key=key;
                page.d=static_cast<i16*>(tr_alloc(PAGE_SAMPLES*sizeof(i16)));
                page.mat=static_cast<u8*>(tr_alloc(PAGE_SAMPLES));
                if(!page.d||!page.mat)return {};
                copy_bytes(page.d,source.d,PAGE_SAMPLES*sizeof(i16));
                copy_bytes(page.mat,source.mat,PAGE_SAMPLES);
                dst.pages_by_key.put(key,at);if(tr_oom)return {};
            }
        }
        for(int z=z0/32;z<=z1/32;++z)for(int x=x0/32;x<=x1/32;++x){
            const auto &column=world_.block_columns[x+64*z];
            if(column.n>8192-dst.blocks.n)return {};
            for(int i=0;i<column.n;++i)
                if(!dst.set_block(column[i],world_.blocks.get(column[i]))||tr_oom)return {};
        }
        if(!copy_surface_columns(world_,dst,bounds.position.x,bounds.position.y,bounds.size.x,bounds.size.y))return {};
        return copy;
    }
public:
    // The click path may read one 5x5x5 mask. Contended locks and paged-out
    // samples fall back to the ordered worker without blocking the render thread.
    godot::PackedByteArray try_placement_target(const godot::PackedByteArray &packet) {
        if(packet.size()!=36 || packet.decode_u32(0)!=39)return {};
        std::unique_lock<std::mutex> guard(mutex_,std::try_to_lock);
        if(!guard || storage_load_pending_)return {};
        const auto point=godot::Vector3(packet.decode_float(12),packet.decode_float(16),packet.decode_float(20));
        if(!point.is_finite() || point.x<0 || point.z<0 || point.x>WORLD || point.z>WORLD || point.y<0 || point.y>WORLD_Y)return {};
        const int x=int(point.x+.5f),y=int(point.y+.5f),z=int(point.z+.5f);
        for(int py=imx(0,y-2)/16;py<=imn(WORLD_Y,y+2)/16;++py)
            for(int pz=imx(0,z-2)/16;pz<=imn(WORLD,z+2)/16;++pz)
                for(int px=imx(0,x-2)/16;px<=imn(WORLD,x+2)/16;++px) {
                    const int page=world_.pages_by_key.get(1+px+WORLD_PAGE_COLUMNS*(pz+WORLD_PAGE_COLUMNS*py));
                    if(page>=0 && !world_.pages[page].d)return {};
                }
        return execute_locked(packet);
    }
    godot::Dictionary execute_edit_with_writes(const godot::PackedByteArray &packet,bool include_surface_owners) {
        godot::Dictionary result;
        if(packet.size()<4||packet.size()>512LL*1024*1024||!fixed_edit_reply(packet.decode_u32(0)))return result;
        std::lock_guard<std::mutex> lock(mutex_);
        const uint32_t prior=world_.revision;
        TerrainEditWrites writes;
        world_.edit_writes=&writes;
        godot::PackedByteArray reply=execute_locked(packet);
        world_.edit_writes=nullptr;
        result["reply"]=reply;
        if(reply.size()<12||reply.decode_u32(8)!=0||!writes.complete)return result;
        godot::PackedByteArray packed;
        const int bytes=writes.records.n*sizeof(TerrainEditWrites::Record);
        static_assert(sizeof(TerrainEditWrites::Record)==8);
        if(packed.resize(12+bytes)!=godot::OK)return result;
        packed.encode_u32(0,1);packed.encode_u32(4,prior);packed.encode_u32(8,world_.revision);
        if(bytes)copy_bytes(packed.ptrw()+12,writes.records.p,bytes);
        result["writes"]=packed;
        if(!include_surface_owners)return result;
        godot::PackedByteArray owners;
        if(owners.resize(TerrainEditWrites::OWNER_BYTES)==godot::OK){
            auto *bits=owners.ptrw();
            zero_bytes(bits,TerrainEditWrites::OWNER_BYTES);
            writes.mark_surface_owners(bits);
            result["surface_owners"]=owners;
        }
        godot::PackedByteArray pages;
        if(pages.resize(8192)==godot::OK){
            auto *bits=pages.ptrw();zero_bytes(bits,8192);
            writes.mark_surface_owners(bits,8);
            result["triangle_owners"]=pages;
        }
        return result;
    }
    godot::PackedByteArray execute(const godot::PackedByteArray &packet) {
        if(packet.size()<4 || packet.size()>512LL*1024*1024)return reply(0,1);
        const uint32_t command=packet.decode_u32(0);
        // Cancellation must remain nonblocking while a worker owns world state.
        // Access owner storage directly: reset/load may replace World concurrently.
        if(command==12 || command==13) {
            if(packet.size()!=4)return reply(command,1);
            if(command==12)snapshot_epoch_.fetch_add(1);
            const uint32_t epoch=command==12 ? __atomic_add_fetch(&control_.epoch,1u,__ATOMIC_RELAXED)
                                           : __atomic_load_n(&control_.epoch,__ATOMIC_RELAXED);
            return reply(command,0,epoch,true);
        }
        std::lock_guard<std::mutex> lock(mutex_);
        return execute_locked(packet);
    }
    // Preparation primitive, NOT a rollback-capable destruction transaction.
    // Preserve every ordered receipt and stop on failure, reporting partial progress.
    godot::Dictionary execute_explosion_cohort(const godot::Array &commands) {
        godot::Dictionary out;out["ok"]=false;out["processed"]=0;out["completed"]=0;
        if(commands.is_empty()||commands.size()>256)return out;
        for(int i=0;i<commands.size();++i){
            if(commands[i].get_type()!=godot::Variant::PACKED_BYTE_ARRAY)return out;
            godot::PackedByteArray p=commands[i];
            if(p.size()!=44||p.decode_u32(0)!=2||p.decode_u32(32)!=0||p.decode_u32(36)!=0)return out;
        }
        std::lock_guard<std::mutex> lock(mutex_);
        godot::Array replies;godot::PackedInt32Array revisions;
        if(replies.resize(commands.size())!=godot::OK||revisions.resize(commands.size())!=godot::OK)return out;
        EditHeightCache cache;world_.edit_height_cache=&cache;
        bool ok=true;int processed=0,completed=0;
        for(int i=0;i<commands.size();++i){
            godot::PackedByteArray p=commands[i];auto response=execute_locked(p);
            replies[i]=response;revisions.set(i,world_.revision);++processed;
            if(response.size()<12||response.decode_u32(8)!=0){ok=false;break;}
            ++completed;
        }
        world_.edit_height_cache=nullptr;
        replies.resize(processed);revisions.resize(processed);
        out["ok"]=ok;out["processed"]=processed;out["completed"]=completed;out["replies"]=replies;out["revisions"]=revisions;
        out["height_requests"]=cache.requests;out["height_hits"]=cache.hits;
        return out;
    }
    void configure_mesh_height_cache(bool enabled){std::lock_guard<std::mutex> lock(mutex_);world_.cache_mesh_heights=enabled;}
private:
    godot::PackedByteArray execute_locked(const godot::PackedByteArray &packet) {
        const uint32_t command=packet.decode_u32(0);
        godot::PackedByteArray result;
        const int expected_reply=fixed_edit_reply_size(command);
        const bool edit_reply=expected_reply>0;
        if(edit_reply&&result.resize(expected_reply)!=godot::OK)return {};
        // Load/reset may reuse revision values; invalidate even a failed attempt.
        if(command==5||command==6){snapshot_epoch_.fetch_add(1);++storage_epoch_;saved_keys_=godot::PackedInt32Array();saved_versions_=godot::PackedInt64Array();storage_reference_=godot::PackedByteArray();storage_load_pending_=false;}
        tr_oom=false;
        Bytes bytes;
        const int previous_revision=world_.revision;
        active_command_.store(command,std::memory_order_relaxed);
        process_request(world_,packet.ptr(),int(packet.size()),bytes);
        if(tr_oom&&bytes.n>=12)bytes.p[8]=2;
        if((command==5||command==6)&&bytes.n>=12&&bytes.p[8]==0){
            generation_progress_.reset();
            residency_.reset();world_.page_access=nullptr;
            storage_load_pending_=command==5;storage_load_checksum_=command==5?packet.decode_u32(packet.size()-4):0;storage_load_revision_=world_.revision;
        }

        if(command==2){
            if(bytes.n>=52&&bytes.p[8]==0){
                Reader bounds{bytes.p,bytes.n,28};V3 lo=bounds.vec(),hi=bounds.vec();
                if(snapshot_worker_&&bounds.good)snapshot_worker_->observe_density_edit(previous_revision,world_.revision,lo,hi);
            }else{
                // Rejected edits retain the field; invalidate outstanding
                // admission tokens conservatively before another attempt.
                snapshot_epoch_.fetch_add(1);
            }
        }
        active_command_.store(-1,std::memory_order_relaxed);
        if(edit_reply&&bytes.n>EDIT_REPLY_CAPACITY){bytes.release();return {};}
        bool ready=edit_reply&&bytes.n==expected_reply;
        if(!ready)ready=result.resize(bytes.n)==godot::OK;
        if(ready&&bytes.n)copy_bytes(result.ptrw(),bytes.p,size_t(bytes.n));
        bytes.release();
        return result;
    }
};
void TerrainFieldReader::_bind_methods(){
    godot::ClassDB::bind_method(godot::D_METHOD("execute","packet"),&TerrainFieldReader::execute);
    godot::ClassDB::bind_method(godot::D_METHOD("resident_tile","key","revision","epoch","cache_packet","on_faces","mesh_only"),&TerrainFieldReader::resident_tile,godot::Callable(),false);
    godot::ClassDB::bind_method(godot::D_METHOD("surface_column_stats"),&TerrainFieldReader::surface_column_stats);
    godot::ClassDB::bind_method(godot::D_METHOD("classify_water_bricks","origins","revision","epoch","include_layers","include_extrusions"),&TerrainFieldReader::classify_water_bricks,false,false);
    godot::ClassDB::bind_method(godot::D_METHOD("classify_edit_bricks","origins","revision","epoch"),&TerrainFieldReader::classify_edit_bricks);
    godot::ClassDB::bind_method(godot::D_METHOD("capture_contact_core","bounds","revision","epoch"),&TerrainFieldReader::capture_contact_core);
}
godot::Dictionary TerrainFieldReader::resident_tile(godot::Vector3i key,int64_t revision,int64_t epoch,bool cache_packet,const godot::Callable &on_faces,bool mesh_only) const{
    auto *field=godot::Object::cast_to<TerrainCore>(field_.ptr());
    const int x=key.x,z=key.y,size=key.z;
    if(!field||(size!=16&&size!=32)||x<0||z<0||x>WORLD-size||z>WORLD-size||x%16||z%16||
       epoch<0||epoch>0xffffffffLL)return {};
    auto &w=field->world_;
    if(imx(0,x-2)<w.contact_x0||imx(0,z-2)<w.contact_z0||
       imn(WORLD,x+size+2)>w.contact_x1||imn(WORLD,z+size+2)>w.contact_z1)return {};
    ::Mesh mesh;
    godot::PackedFloat32Array stages;
    godot::PackedVector3Array faces;
    godot::Array early_pieces;
    const bool early=on_faces.is_valid();
    u64 replayed=0;
    {
        std::lock_guard<std::mutex> guard(field->mutex_);
        if(revision!=w.revision||u32(epoch)!=terrain_build_epoch(&w))return {};
        tr_oom=false;w.contact_outside=false;
        if(w.profile_mesh)replayed=w.replayed_triangles;
        if(!build_patch(w,x,z,size,1,mesh,u32(epoch),true,false,early,mesh_only)||tr_oom||w.contact_outside){
            mesh.release();return {};
        }
        if(w.profile_mesh){
            if(stages.resize(4)!=godot::OK){mesh.release();return {};}
            std::copy_n(w.mesh_stage_ms,4,stages.ptrw());
            replayed=w.replayed_triangles-replayed;
        }
    }
    if(early){
        // The mesh is private. Only its materials and light can still change.
        // Never call into script with a field mutex held.
        if(faces.resize(mesh.i.n)!=godot::OK){mesh.release();return {};}
        auto *out=faces.ptrw();
        for(int i=0;i<mesh.i.n;++i)copy_bytes(out+i,&mesh.v[mesh.i[i]].p,sizeof(V3));
        auto recipes=on_faces.call(faces);
        if(recipes.get_type()==godot::Variant::ARRAY)early_pieces=recipes;
        std::lock_guard<std::mutex> guard(field->mutex_);
        if(revision!=w.revision||u32(epoch)!=terrain_build_epoch(&w)){mesh.release();return {};}
        tr_oom=false;w.contact_outside=false;
        auto began=std::chrono::steady_clock::now();
        shade_mesh(w,mesh,u32(epoch));
        if(tr_oom||w.contact_outside||u32(epoch)!=terrain_build_epoch(&w)){mesh.release();return {};}
        if(!stages.is_empty())stages.set(3,std::chrono::duration<float,std::milli>(std::chrono::steady_clock::now()-began).count());
    }
    // Geometry is now private. Write the engine's final typed streams once.
    // The optional derived cache is the only consumer of a serialized tile.
    const int nv=mesh.v.n,ni=mesh.i.n;
    godot::PackedVector3Array vertices,normals;
    godot::PackedVector2Array uv,uv2;godot::PackedColorArray colors;godot::PackedInt32Array indices;
    if(vertices.resize(nv)!=godot::OK||normals.resize(nv)!=godot::OK||
       uv.resize(nv)!=godot::OK||uv2.resize(nv)!=godot::OK||colors.resize(nv)!=godot::OK||
       indices.resize(ni)!=godot::OK||faces.resize(ni)!=godot::OK){mesh.release();return {};}
    static_assert(sizeof(godot::Vector3)==12&&sizeof(godot::Vector2)==8&&sizeof(godot::Color)==16);
    MeshChannels channels{(u8*)vertices.ptrw(),(u8*)normals.ptrw(),(u8*)uv.ptrw(),(u8*)uv2.ptrw(),
        (u8*)colors.ptrw(),(u8*)indices.ptrw(),(u8*)faces.ptrw()};
    const bool cavity=write_mesh_channels(mesh,1,early?0:ni,channels);
    mesh.release();
    godot::Dictionary result;
    const int bytes=36+nv*56+ni*16;
    if(cache_packet){
        godot::PackedByteArray packet;if(packet.resize(bytes)!=godot::OK)return {};
        auto *target=packet.ptrw();const u32 header[]={MESH_MAGIC,5,u32(x),u32(z),u32(size),1,u32(nv),u32(ni),u32(ni)};
        copy_bytes(target,header,sizeof(header));target+=sizeof(header);
        auto append=[&](const u8 *data,int length){if(length)copy_bytes(target,data,length);target+=length;};
        append(channels.positions,12*nv);append(channels.normals,12*nv);append(channels.uv,8*nv);
        append(channels.uv2,8*nv);append(channels.colors,16*nv);append(channels.indices,4*ni);append(channels.collision,12*ni);
        result["cache_packet"]=packet;
    }
    godot::Array arrays;arrays.resize(godot::Mesh::ARRAY_MAX);
    arrays[godot::Mesh::ARRAY_VERTEX]=vertices;arrays[godot::Mesh::ARRAY_NORMAL]=normals;arrays[godot::Mesh::ARRAY_TEX_UV]=uv;
    arrays[godot::Mesh::ARRAY_TEX_UV2]=uv2;arrays[godot::Mesh::ARRAY_COLOR]=colors;arrays[godot::Mesh::ARRAY_INDEX]=indices;
    result["key"]=key;result["arrays"]=arrays;result["faces"]=faces;result["cavity_visibility"]=cavity;
    result["step"]=1;result["triangles"]=ni/3;result["bytes"]=bytes;
    if(!early_pieces.is_empty())result["collision_pieces"]=early_pieces;
    if(!stages.is_empty()){
        result["resident_mesh_ms"]=stages;
        result["resident_replayed_triangles"]=int64_t(replayed);
    }
    return u32(epoch)==terrain_build_epoch(&w)?result:godot::Dictionary{};
}
godot::Dictionary TerrainFieldReader::surface_column_stats() const{
    const auto *field=godot::Object::cast_to<TerrainCore>(field_.ptr());
    godot::Dictionary out;
    if(field&&field->surface_columns_){
        const auto &columns=*field->surface_columns_;
        out["columns"]=int64_t(columns.built.load());out["bytes"]=int64_t(columns.retained.load());
        out["meshes"]=int64_t(columns.mesh_reads.load());out["contacts"]=int64_t(columns.contact_reads.load());
        out["connected_columns"]=int64_t(columns.connected_columns.load());
        out["indexed_contacts"]=int64_t(columns.connected_contacts.load());
    }
    out["parallel_contact_packets"]=int64_t(lane_packets_.load());
    return out;
}
godot::PackedByteArray TerrainFieldReader::classify_water_bricks(const godot::PackedInt32Array &origins,int64_t revision,int64_t epoch,bool layers,bool extrusions) const{
    const auto *field=godot::Object::cast_to<TerrainCore>(field_.ptr());
    if(!field||origins.size()%3||origins.size()>3*2048)return {};
    const auto &world=field->world_;
    if(revision!=world.revision||epoch!=terrain_build_epoch(&world))return {};
    const int stride=layers?17:1;
    godot::PackedByteArray result;if(result.resize(origins.size()/3*stride)!=godot::OK)return {};
    auto *out=result.ptrw();const auto *p=origins.ptr();
    for(int64_t i=0;i<origins.size()/3;++i,p+=3,out+=stride){
        int x=p[0],y=p[1],z=p[2];
        zero_bytes(out,stride);
        if(x<world.contact_x0+2||x>world.contact_x1-5||z<world.contact_z0+2||z>world.contact_z1-5)continue;
        out[0]=water_brick_occupancy(world,x,y,z);
        i16 signature[8];
        if(layers&&!out[0]&&water_layer_signature(world,x,y,z,signature)){
            out[0]=3;
            for(int j=0;j<8;++j){out[1+2*j]=u16(signature[j])&255;out[2+2*j]=u16(signature[j])>>8;}
        }else if(layers&&extrusions&&!out[0]){
            std::array<i16,66> section;
            if(!water_extrusion_signature(world,x,y,z,section.data()))continue;
            std::lock_guard<std::mutex> lock(extrusion_mutex_);
            auto known=extrusion_ids_.find(section);
            if(known==extrusion_ids_.end()){
                if(extrusion_ids_.size()>=512)continue;
                known=extrusion_ids_.emplace(section,uint32_t(extrusion_ids_.size()+1)).first;
            }
            out[0]=4;
            uint64_t owner=get_instance_id();
            for(int j=0;j<8;++j)out[1+j]=uint8_t(owner>>(8*j));
            for(int j=0;j<4;++j)out[9+j]=uint8_t(known->second>>(8*j));
        }
    }
    return result;
}
godot::Ref<TerrainFieldReader> TerrainFieldReader::capture_contact_core(godot::Rect2i bounds,int64_t revision,int64_t epoch) const{
    auto *field=godot::Object::cast_to<TerrainCore>(field_.ptr());
    return field?field->make_reader(bounds,revision,epoch,true):godot::Ref<TerrainFieldReader>();
}
godot::PackedByteArray TerrainFieldReader::execute(const godot::PackedByteArray &packet) const{
    auto *field=godot::Object::cast_to<TerrainCore>(field_.ptr());
    if(!field||packet.size()<4)return {};
    const auto command=packet.decode_u32(0);
    const auto &world=field->world_;
    auto inside=[&](int x,int z,int extent,int halo){
        return x>=0&&z>=0&&x<=WORLD-extent&&z<=WORLD-extent&&
            imx(0,x-halo)>=world.contact_x0&&imx(0,z-halo)>=world.contact_z0&&
            imn(WORLD,x+extent+halo)<=world.contact_x1&&imn(WORLD,z+extent+halo)<=world.contact_z1;
    };
    bool allowed=false;
    if(command==0||command==13)allowed=packet.size()==4;
    if((command==1||command==20||command==47)&&packet.size()>=20){
        const int size=int(packet.decode_u32(12));
        allowed=(size==16||size==32||size==64)&&inside(packet.decode_u32(4),packet.decode_u32(8),size,2);
    }
    if((command==32||command==43||command==48||command==49)&&packet.size()==24)
        allowed=inside(packet.decode_u32(12),packet.decode_u32(20),4,2);
    if((command==48||command==49)&&allowed){
        tr_oom=false;Bytes bytes;
        if(read_homogeneous_water(world,packet.decode_u32(12),packet.decode_u32(16),packet.decode_u32(20),
                                  packet.decode_u32(4),packet.decode_u32(8),bytes)){
            godot::PackedByteArray result;
            if(!tr_oom&&result.resize(bytes.n)==godot::OK)copy_bytes(result.ptrw(),bytes.p,bytes.n);
            bytes.release();return result;
        }
        // A terrain mesh or another mixed receiver may already own the root
        // reconstruction cache. The revision and page bytes are immutable.
        // Route concurrent readers to independent contact scratch immediately.
        std::unique_lock<std::mutex> root(field->mutex_,std::try_to_lock);
        if(root.owns_lock())return field->execute_locked(packet);
        for(auto &lane:contact_lanes_){
            std::unique_lock<std::mutex> guard(lane.mutex,std::try_to_lock);
            if(!guard.owns_lock())continue;
            if(!lane.view)lane.view=std::make_unique<SealedWaterContact>(world);
            lane.view->read(packet.ptr(),int(packet.size()),bytes);
            godot::PackedByteArray result;
            if(tr_oom&&bytes.n>=12)bytes.p[8]=2;
            if(result.resize(bytes.n)==godot::OK&&bytes.n)copy_bytes(result.ptrw(),bytes.p,size_t(bytes.n));
            bytes.release();++lane_packets_;return result;
        }
    }
    if((command==31||command==40)&&packet.size()>=12){
        const auto count=packet.decode_u32(8);
        allowed=count>=1&&count<=512&&packet.size()==12+12*int(count);
        for(uint32_t i=0;allowed&&i<count;++i){
            const float x=packet.decode_float(12+i*12),z=packet.decode_float(20+i*12);
            allowed=x>=world.contact_x0&&z>=world.contact_z0&&x<world.contact_x1&&z<world.contact_z1;
        }
    }
    return allowed?field->execute(packet):TerrainCore::reply(command,1);
}
}

static void initialize(godot::ModuleInitializationLevel level) {
    if(level!=godot::MODULE_INITIALIZATION_LEVEL_SCENE)return;
    // Installed once before any instance exists; thereafter immutable across workers.
    tr_alloc=std::malloc; tr_realloc=std::realloc; tr_free=std::free;
    GDREGISTER_CLASS(terraforest::NativeTerrainCapture);
    GDREGISTER_CLASS(terraforest::TerrainFieldReader);
    GDREGISTER_CLASS(terraforest::TerrainCore);
    GDREGISTER_CLASS(terraforest::NativeTerrainRegionStore);
    GDREGISTER_CLASS(terraforest::NativeTerrainPlanner);
    GDREGISTER_CLASS(terraforest::NativeRoadProfile);
    GDREGISTER_CLASS(terraforest::NativeTerrainCollisionPiece);
    GDREGISTER_CLASS(terraforest::NativeTerrainCollision);
}
static void terminate(godot::ModuleInitializationLevel) {}
extern "C" GDExtensionBool GDE_EXPORT terrain_library_init(
    GDExtensionInterfaceGetProcAddress address, GDExtensionClassLibraryPtr library,
    GDExtensionInitialization *initialization) {
    godot::GDExtensionBinding::InitObject init(address,library,initialization);
    init.register_initializer(initialize); init.register_terminator(terminate);
    init.set_minimum_library_initialization_level(godot::MODULE_INITIALIZATION_LEVEL_SCENE);
    return init.init();
}
