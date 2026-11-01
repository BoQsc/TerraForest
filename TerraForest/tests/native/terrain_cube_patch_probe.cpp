// SPDX-License-Identifier: 0BSD
#include "terrain_cube_patch.hpp"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <chrono>

using namespace terraforest;
static int failures=0,allocations=0,denied_at=0,live_allocations=0;
static void *allocate(size_t bytes){
    if(denied_at&&++allocations==denied_at)return nullptr;
    void *memory=std::malloc(bytes);if(memory)++live_allocations;return memory;
}
static void *reallocate(void *memory,size_t bytes){
    if(denied_at&&++allocations==denied_at)return nullptr;
    void *result=std::realloc(memory,bytes);if(result&&!memory)++live_allocations;return result;
}
static void release(void *memory){if(memory)--live_allocations;std::free(memory);}
static bool equal(const Bytes &left,const Bytes &right){return left.n==right.n&&(!left.n||!std::memcmp(left.p,right.p,left.n));}
static void check(const char *name,bool passed){failures+=!passed;std::printf("{\"case\":\"%s\",\"passed\":%s}\n",name,passed?"true":"false");}
static void checksum(Bytes &bytes){const u32 value=cube_patch_checksum(bytes.p,bytes.n-4);copy_bytes(bytes.p+bytes.n-4,&value,4);}
static void fill(Bytes &bytes,u8 material){for(int offset=CUBE_PATCH_HEADER;offset<bytes.n-4;++offset)bytes.p[offset]=material;checksum(bytes);}
static bool columns_valid(const World &world){
    int total=0;
    for(int column=0;column<world.block_columns.n;++column){
        const auto &keys=world.block_columns[column];Map seen;
        for(int index=0;index<keys.n;++index){
            const u32 key=keys[index],packed=key-1;
            if(world.blocks.get(key)<1||seen.get(key)>=0||int(((packed&2047)>>5)+64*(((packed>>11)&2047)>>5))!=column){seen.release();return false;}
            seen.put(key,1);++total;
        }
        seen.release();
    }
    return total==world.blocks.n;
}
static void roundtrip(){
    for(u32 generator:{1u,5u,31u}){
        World world;world.init(1703,generator);Bytes baseline,modified,restored,before,after;
        const CubePatchBounds bounds{31,63,31,3,3,3};
        world.set_block(cube_patch_key(31,63,31),1);world.set_block(cube_patch_key(33,65,33),3);
        world.serialize(before,true);
        bool passed=capture_cube_patch(world,bounds,baseline);world.serialize(after,true);
        check("capture_read_only_and_includes_air",passed&&equal(before,after)&&baseline.n==75&&baseline.p[44]==1&&baseline.p[45]==0&&baseline.p[70]==3);
        modified.raw(baseline.p,baseline.n);fill(modified,2);CubePatchResult result;
        passed=restore_cube_patch(world,modified.p,modified.n,0,result)&&result.changes==27&&world.revision==1&&columns_valid(world);
        passed&=capture_cube_patch(world,bounds,restored)&&equal(modified,restored);
        check("cross_column_material_roundtrip",passed);
        passed=restore_cube_patch(world,modified.p,modified.n,1,result)&&result.changes==0&&world.revision==1&&world.edits==1;
        check("identical_restore_has_no_mutation",passed);
        passed=restore_cube_patch(world,baseline.p,baseline.n,1,result)&&result.changes==27&&world.blocks.n==2&&columns_valid(world);
        passed&=capture_cube_patch(world,bounds,restored)&&equal(baseline,restored);
        check("baseline_restore_removes_only_inside_cubes",passed);
        World reopened;reopened.init(1703,generator);after.n=0;world.serialize(after,true);
        passed=reopened.deserialize(after.p,after.n)&&capture_cube_patch(reopened,bounds,restored)&&equal(restored,baseline)&&columns_valid(reopened);
        check("ordinary_binary_save_reopen",passed);reopened.release();
        baseline.release();modified.release();restored.release();before.release();after.release();world.release();
    }
}
static void ownership(){
    World world;world.init(1703,5);Bytes patch;capture_cube_patch(world,{31,63,31,3,3,3},patch);fill(patch,2);
    const u32 neighbors[]={cube_patch_key(30,63,31),cube_patch_key(34,63,31),cube_patch_key(31,62,31),cube_patch_key(31,66,31),cube_patch_key(31,63,30),cube_patch_key(31,63,34)};
    for(u32 key:neighbors)world.set_block(key,3);
    auto *page=world.ensure(1,3,1);page->d[0]=-2048;page->mat[0]=7;
    CubePatchResult result;bool passed=restore_cube_patch(world,patch.p,patch.n,0,result);
    for(u32 key:neighbors)passed&=world.blocks.get(key)==3;
    check("outside_cubes_preserved_on_all_six_faces",passed&&columns_valid(world));
    check("field_density_material_and_versions_untouched",page->d[0]==-2048&&page->mat[0]==7&&page->storage_version==0&&world.changed_samples==0);
    check("lighting_and_inclusive_geometry_extent",world.lighting_revision==-1&&result.minimum.x==31&&result.maximum.x==34&&result.maximum.y==66);
    Bytes before,after;world.serialize(before,true);
    check("stale_revision_rejects",!restore_cube_patch(world,patch.p,patch.n,0,result)&&result.changes==0);
    world.serialize(after,true);check("stale_restore_preserves_serialized_world",equal(before,after));
    fill(patch,0);passed=restore_cube_patch(world,patch.p,patch.n,1,result)&&world.blocks.n==6&&columns_valid(world);
    check("bulk_removal_preserves_column_index",passed);
    patch.release();before.release();after.release();world.release();
}
static void malformed(){
    World world;world.init(1703,5);Bytes patch,variant,before,after;capture_cube_patch(world,{10,10,10,2,2,2},patch);fill(patch,3);world.serialize(before,true);
    CubePatchResult result;bool passed=true;
    for(int length=0;length<patch.n;++length)passed&=!restore_cube_patch(world,patch.p,length,0,result);
    check("all_truncated_prefixes_reject",passed);
    passed=true;
    for(int offset=0;offset<patch.n;++offset){variant.n=0;variant.raw(patch.p,patch.n);variant.p[offset]^=1;passed&=!restore_cube_patch(world,variant.p,variant.n,0,result);}
    check("every_byte_corruption_rejects",passed);
    struct Invalid {int offset;u32 value;};
    const Invalid invalids[]={{0,0},{4,2},{8,42},{12,1},{12,0},{12,32},{16,2000},{16,UINT32_MAX},{20,0},{20,254},{24,2000},{28,0},{28,129},{32,UINT32_MAX},{36,0},{40,10}};
    passed=true;
    for(auto invalid:invalids){variant.n=0;variant.raw(patch.p,patch.n);copy_bytes(variant.p+invalid.offset,&invalid.value,4);checksum(variant);passed&=!restore_cube_patch(world,variant.p,variant.n,0,result);}
    check("identity_bounds_count_version_reject_with_correct_checksum",passed);
    variant.n=0;variant.raw(patch.p,patch.n);fill(variant,4);
    check("invalid_material_rejects",!restore_cube_patch(world,variant.p,variant.n,0,result));
    variant.n=0;variant.raw(patch.p,patch.n);variant.u(0);
    check("trailing_bytes_reject",!restore_cube_patch(world,variant.p,variant.n,0,result));
    world.serialize(after,true);check("invalid_inputs_never_mutate",equal(before,after));
    variant.n=0;variant.u(17);
    check("oversize_capture_retains_destination",!capture_cube_patch(world,{1,1,1,128,128,128},variant)&&variant.n==4&&variant.p[0]==17);
    world.revision=INT_MAX;check("revision_overflow_rejects",!restore_cube_patch(world,patch.p,patch.n,INT_MAX,result));
    world.revision=0;world.edits=INT_MAX;check("edit_counter_overflow_rejects",!restore_cube_patch(world,patch.p,patch.n,0,result));
    patch.release();variant.release();before.release();after.release();world.release();
}
static void fault_sweep(){
    World seed;seed.init(1703,5);Bytes patch;capture_cube_patch(seed,{31,63,31,3,3,3},patch);fill(patch,2);seed.release();
    int forced=0;bool passed=true;
    for(int existing=0;existing<2;++existing)for(int fault=1;fault<=10;++fault){
        const int retained=live_allocations;tr_oom=false;World world;world.init(1703,5);
        if(existing)for(int index=0;index<43;++index)world.set_block(cube_patch_key(30,5+index,30),3);
        Bytes before,after;world.serialize(before,true);allocations=0;denied_at=fault;CubePatchResult result;
        const bool accepted=restore_cube_patch(world,patch.p,patch.n,0,result),hit=allocations>=fault;
        denied_at=0;tr_oom=false;forced+=hit;world.serialize(after,true);
        passed&=hit?(!accepted&&equal(before,after)&&world.revision==0&&result.changes==0):accepted;
        passed&=columns_valid(world);before.release();after.release();world.release();passed&=live_allocations==retained;
    }
    check("all_preflight_allocation_failures_atomic",passed&&forced>=8);
    World world;world.init(1703,5);Bytes output;output.u(17);allocations=0;denied_at=1;
    const bool captured=capture_cube_patch(world,{1,1,1,2,2,2},output);denied_at=0;tr_oom=false;
    check("capture_allocation_failure_preserves_output",!captured&&output.n==4&&output.p[0]==17);
    output.release();world.release();patch.release();
}
static void capacity(){
    World world;world.init(1703,5);
    for(int index=0;index<2000000;++index)world.set_block(cube_patch_key(index%2000,1,index/2000),3);
    Bytes patch;CubePatchResult result;capture_cube_patch(world,{31,2,31,1,1,1},patch);fill(patch,2);
    check("world_capacity_rejects_addition_without_mutation",!restore_cube_patch(world,patch.p,patch.n,0,result)&&world.blocks.n==2000000&&world.blocks.get(cube_patch_key(31,2,31))<0&&world.revision==0);
    capture_cube_patch(world,{31,1,31,1,2,1},patch);patch.p[44]=0;patch.p[45]=2;checksum(patch);
    check("full_world_allows_capacity_neutral_replacement",restore_cube_patch(world,patch.p,patch.n,0,result)&&result.changes==2&&world.blocks.n==2000000&&world.blocks.get(cube_patch_key(31,1,31))<0&&world.blocks.get(cube_patch_key(31,2,31))==2&&columns_valid(world));
    patch.release();world.release();
}
static void benchmark(){
    World world;world.init(1703,5);Bytes patch;CubePatchResult result;
    auto start=std::chrono::steady_clock::now();bool passed=capture_cube_patch(world,{31,10,31,128,16,128},patch);
    const double capture_ms=std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-start).count();
    fill(patch,3);start=std::chrono::steady_clock::now();
    passed&=restore_cube_patch(world,patch.p,patch.n,0,result)&&result.changes==262144;
    const double restore_ms=std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-start).count();
    passed&=columns_valid(world);
    std::printf("{\"case\":\"maximum_dense_patch\",\"passed\":%s,\"cells\":%d,\"bytes\":%d,\"capture_ms\":%.6f,\"restore_ms\":%.6f}\n",passed?"true":"false",result.changes,patch.n,capture_ms,restore_ms);failures+=!passed;
    fill(patch,0);passed=restore_cube_patch(world,patch.p,patch.n,world.revision,result)&&result.changes==262144&&world.blocks.n==0&&columns_valid(world);
    check("dense_bulk_remove_and_tombstones",passed);
    fill(patch,1);passed=restore_cube_patch(world,patch.p,patch.n,world.revision,result)&&result.changes==262144&&columns_valid(world);
    check("dense_refill_reuses_valid_index",passed);patch.release();world.release();
}
int main(){
    tr_alloc=allocate;tr_realloc=reallocate;tr_free=release;
    roundtrip();ownership();malformed();fault_sweep();capacity();benchmark();
    check("all_allocations_released",live_allocations==0);return failures?1:0;
}
