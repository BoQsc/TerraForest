// SPDX-License-Identifier: 0BSD
#include "terrain_field_patch.hpp"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <chrono>

using namespace terraforest;
static int failures=0,allocations=0,denied_at=0,live_allocations=0;
static bool deny_realloc=false;
static void *allocate(size_t bytes){
    if(denied_at&&!deny_realloc&&++allocations==denied_at)return nullptr;
    void *memory=std::malloc(bytes);if(memory)++live_allocations;return memory;
}
static void *reallocate(void *memory,size_t bytes){
    if(denied_at&&deny_realloc&&++allocations==denied_at)return nullptr;
    void *result=std::realloc(memory,bytes);if(result&&!memory)++live_allocations;return result;
}
static void release(void *memory){if(memory)--live_allocations;std::free(memory);}
static bool equal(const Bytes &left,const Bytes &right){return left.n==right.n&&(!left.n||!std::memcmp(left.p,right.p,left.n));}
static void check(const char *name,bool passed){
    failures+=!passed;std::printf("{\"case\":\"%s\",\"passed\":%s}\n",name,passed?"true":"false");
}
static void update_checksum(Bytes &bytes){const u32 checksum=field_patch_checksum(bytes.p,bytes.n-4);copy_bytes(bytes.p+bytes.n-4,&checksum,4);}
static void set_u32(Bytes &bytes,int offset,u32 value){copy_bytes(bytes.p+offset,&value,4);update_checksum(bytes);}
static void fill(Bytes &bytes,i16 density,u8 material){
    for(int offset=FIELD_PATCH_HEADER;offset<bytes.n-4;offset+=3){bytes.p[offset]=u8(density);bytes.p[offset+1]=u8(u16(density)>>8);bytes.p[offset+2]=material;}
    update_checksum(bytes);
}
static void roundtrip(){
    for(u32 generator:{1u,5u,31u}){
        tr_oom=false;World world;world.init(1703,generator);
        FieldPatchBounds bounds{1278,63,1278,5,5,5};Bytes baseline,before,after,modified,roundtrip;
        world.serialize(before,true);
        bool passed=capture_field_patch(world,bounds,baseline);
        world.serialize(after,true);passed&=equal(before,after)&&world.revision==0;
        check("capture_does_not_edit_field",passed);
        modified.raw(baseline.p,baseline.n);fill(modified,-2048,7);FieldPatchResult result;
        passed=restore_field_patch(world,modified.p,modified.n,world.revision,result)&&result.changes>0&&world.revision==1;
        passed&=capture_field_patch(world,bounds,roundtrip)&&equal(modified,roundtrip);
        check("cross_page_density_material_roundtrip",passed);
        const int revision=world.revision,edits=world.edits;const u64 serial=world.storage_serial;
        passed=restore_field_patch(world,modified.p,modified.n,revision,result)&&result.changes==0&&world.revision==revision&&world.edits==edits&&world.storage_serial==serial;
        check("identical_restore_has_no_revision_or_storage_cost",passed);
        World reopened;reopened.init(1703,generator);
        passed=restore_field_patch(reopened,modified.p,modified.n,0,result)&&capture_field_patch(reopened,bounds,roundtrip)&&equal(roundtrip,modified);
        check("fresh_owner_binary_restore",passed);reopened.release();
        passed=restore_field_patch(world,baseline.p,baseline.n,world.revision,result)&&capture_field_patch(world,bounds,roundtrip)&&equal(roundtrip,baseline);
        check("restore_original_baseline",passed);
        baseline.release();before.release();after.release();modified.release();roundtrip.release();world.release();
    }
}
static void ownership(){
    World world;world.init(1703,5);FieldPatchBounds bounds{1278,63,1278,5,5,5};Bytes patch,outside_before,outside_after;
    bool passed=capture_field_patch(world,bounds,patch);fill(patch,-1024,3);
    V3 low,high;int changes=0;const V3 center{1277,63,1278};
    passed&=world.edit(center,center,1,0,true,2,low,high,changes);
    FieldPatchBounds outside{1276,62,1277,2,7,7};passed&=capture_field_patch(world,outside,outside_before);
    const u32 cube=1+u32(1279|(1279<<11)|(64<<22));passed&=world.set_block(cube,4);
    FieldPatchResult result;
    passed&=restore_field_patch(world,patch.p,patch.n,world.revision,result)&&capture_field_patch(world,outside,outside_after);
    check("outside_samples_in_shared_pages_preserved",passed&&equal(outside_before,outside_after));
    check("exact_voxel_cubes_remain_separate_owner",world.blocks.get(cube)==4);
    check("geometry_and_lighting_invalidated",world.lighting_revision==-1&&world.changed_samples>=u64(result.changes)&&result.minimum.x==1278&&result.maximum.z==1282);
    Bytes before,after;world.serialize(before,true);
    check("stale_revision_rejected",!restore_field_patch(world,patch.p,patch.n,world.revision-1,result));
    world.serialize(after,true);check("stale_revision_preserves_field",equal(before,after));
    patch.release();outside_before.release();outside_after.release();before.release();after.release();world.release();
}
static void malformed(){
    World world;world.init(1703,5);Bytes valid,variant,before,after;FieldPatchBounds bounds{100,50,100,2,2,2};
    capture_field_patch(world,bounds,valid);fill(valid,-1024,3);world.serialize(before,true);FieldPatchResult result;
    bool passed=true;
    for(int length=0;length<valid.n;++length)passed&=!restore_field_patch(world,valid.p,length,0,result);
    check("all_truncated_prefixes_rejected",passed);
    for(int offset=0;offset<valid.n;++offset){variant.n=0;variant.raw(valid.p,valid.n);variant.p[offset]^=1;passed&=!restore_field_patch(world,variant.p,variant.n,0,result);}
    check("every_single_byte_corruption_rejected",passed);
    struct Invalid {int offset;u32 value;};
    const Invalid cases[]={{0,0},{4,2},{8,42},{12,1},{12,0},{12,32},{16,0},{16,2000},{16,UINT32_MAX},{20,3},{20,254},{24,2000},{28,0},{28,129},{32,UINT32_MAX},{36,0},{40,10}};
    passed=true;
    for(auto invalid:cases){variant.n=0;variant.raw(valid.p,valid.n);set_u32(variant,invalid.offset,invalid.value);passed&=!restore_field_patch(world,variant.p,variant.n,0,result);}
    check("valid_checksum_does_not_bypass_identity_or_bounds",passed);
    for(auto invalid:std::array<std::array<int,2>,3>{{{{-4097,3}},{{4097,3}},{{-1024,16}}}}){
        variant.n=0;variant.raw(valid.p,valid.n);fill(variant,i16(invalid[0]),u8(invalid[1]));
        passed&=!restore_field_patch(world,variant.p,variant.n,0,result);
    }
    check("invalid_density_or_material_rejected",passed);
    variant.n=0;variant.raw(valid.p,valid.n);variant.u(0);
    check("trailing_data_rejected",!restore_field_patch(world,variant.p,variant.n,0,result));
    world.serialize(after,true);check("malformed_patch_never_mutates_field",equal(before,after));
    Bytes unchanged;unchanged.u(17);
    check("invalid_capture_preserves_destination",!capture_field_patch(world,{1,4,1,128,128,128},unchanged)&&unchanged.n==4&&unchanged.p[0]==17);
    valid.release();variant.release();before.release();after.release();unchanged.release();world.release();
}
static void fault_sweep(){
    World seed;seed.init(1703,5);Bytes patch;capture_field_patch(seed,{1278,63,1278,5,5,5},patch);fill(patch,-1024,3);seed.release();
    int forced=0,attempts=0;bool passed=true;
    for(int existing=0;existing<2;++existing)for(int allocator=0;allocator<2;++allocator)for(int fault=1;fault<=24;++fault){
        const int retained=live_allocations;tr_oom=false;World world;world.init(1703,5);
        if(existing)world.ensure(79,3,79);
        Bytes before,after;world.serialize(before,true);const u64 serial=world.storage_serial,samples=world.changed_samples;
        allocations=0;denied_at=fault;deny_realloc=allocator;tr_oom=false;FieldPatchResult result;
        const bool accepted=restore_field_patch(world,patch.p,patch.n,world.revision,result);
        const bool hit=allocations>=fault;forced+=hit;++attempts;denied_at=0;tr_oom=false;
        world.serialize(after,true);
        bool exact=hit?(!accepted&&equal(before,after)&&world.storage_serial==serial&&world.changed_samples==samples&&result.changes==0):accepted;
        before.release();after.release();world.release();exact&=live_allocations==retained;passed&=exact;
    }
    std::printf("{\"case\":\"atomic_allocation_failure_sweep\",\"passed\":%s,\"attempts\":%d,\"forced\":%d}\n",passed&&forced>0?"true":"false",attempts,forced);
    failures+=!passed||forced==0;
    patch.release();
}
static void capture_failure(){
    World world;world.init(1703,5);Bytes output,before,after;output.u(17);world.serialize(before,true);
    allocations=0;denied_at=1;deny_realloc=true;tr_oom=false;
    const bool accepted=capture_field_patch(world,{1278,63,1278,5,5,5},output);
    denied_at=0;tr_oom=false;world.serialize(after,true);
    check("capture_allocation_failure_preserves_output_and_world",!accepted&&output.n==4&&output.p[0]==17&&equal(before,after));
    output.release();before.release();after.release();world.release();
}
struct DeniedResidency : PageAccess {
    int count=0,removed_count=0;
    bool load(World&,int) override {return false;}
    bool admit(World&) override {return count<1;}
    void inserted(World&,int) override {++count;}
    void touch(World&,int) override {}
    void removed(World&,int) override {--count;++removed_count;}
};
static void residency(){
    World world;world.init(1703,5);Bytes patch,before,after;capture_field_patch(world,{1278,63,1278,5,5,5},patch);fill(patch,-1024,3);
    world.serialize(before,true);DeniedResidency residency;world.page_access=&residency;FieldPatchResult result;
    const bool accepted=restore_field_patch(world,patch.p,patch.n,0,result);
    world.serialize(after,true);
    check("residency_exhaustion_rolls_back_new_pages",!accepted&&equal(before,after)&&residency.count==0&&residency.removed_count==1&&!world.pages_pinned);
    world.page_access=nullptr;world.ensure(79,3,79);Page &page=world.pages[0];i16 *density=page.d;u8 *material=page.mat;page.d=nullptr;page.mat=nullptr;
    world.page_access=&residency;tr_oom=false;
    check("unavailable_storage_page_rejects_capture_and_restore",!capture_field_patch(world,{1278,63,1278,5,5,5},after)&&!restore_field_patch(world,patch.p,patch.n,0,result)&&world.revision==0);
    page.d=density;page.mat=material;world.page_access=nullptr;tr_oom=false;
    patch.release();before.release();after.release();world.release();
}
static void benchmark(){
    World world;world.init(1703,5);Bytes patch;FieldPatchResult result;
    auto start=std::chrono::steady_clock::now();
    bool passed=capture_field_patch(world,{100,20,100,128,64,128},patch);
    double capture_ms=std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-start).count();
    fill(patch,-1024,3);start=std::chrono::steady_clock::now();
    passed&=restore_field_patch(world,patch.p,patch.n,0,result)&&result.changes==1048576;
    double restore_ms=std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-start).count();
    std::printf("{\"case\":\"bounded_maximum_patch\",\"passed\":%s,\"samples\":%d,\"bytes\":%d,\"capture_ms\":%.6f,\"restore_ms\":%.6f,\"pages\":%d}\n",passed?"true":"false",result.changes,patch.n,capture_ms,restore_ms,world.pages.n);
    failures+=!passed;patch.release();world.release();
}
int main(){
    tr_alloc=allocate;tr_realloc=reallocate;tr_free=release;
    roundtrip();ownership();malformed();fault_sweep();capture_failure();residency();benchmark();
    check("all_owned_allocations_released",live_allocations==0);
    return failures?1:0;
}
