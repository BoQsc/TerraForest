#include "block_world.hpp"
#include "block_shapes.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/classes/collision_shape3d.hpp>
#include <godot_cpp/classes/concave_polygon_shape3d.hpp>
#include <godot_cpp/classes/hashing_context.hpp>
#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/classes/texture2d_array.hpp>
#include <godot_cpp/classes/shader.hpp>
#include <algorithm>
#include <cmath>
#include <chrono>
#include <cstring>

namespace terraforest {
static constexpr int MAX_CHUNKS=2048, LIMIT=1048575;
static bool valid_word(int w) { return w==0 || (w>0&&w<128&&(w&7)>=1&&(w&7)<=6); }
static PackedByteArray sha(const PackedByteArray &data) {
    Ref<HashingContext> h; h.instantiate(); h->start(HashingContext::HASH_SHA256); h->update(data); return h->finish();
}
void NativeBlockWorld::_bind_methods() {
    ClassDB::bind_method(D_METHOD("raycast_cells","from","to"),&NativeBlockWorld::raycast_cells);
    ClassDB::bind_method(D_METHOD("raycast_scene","from","to","collision_mask","exclude"),&NativeBlockWorld::raycast_scene,DEFVAL(3),DEFVAL(TypedArray<RID>()));
    ClassDB::bind_method(D_METHOD("set_cells","records"),&NativeBlockWorld::set_cells);
    ClassDB::bind_method(D_METHOD("configure_history","byte_limit","step_limit"),&NativeBlockWorld::configure_history);
    ClassDB::bind_method(D_METHOD("clear_history"),&NativeBlockWorld::clear_history);
    ClassDB::bind_method(D_METHOD("history_stats"),&NativeBlockWorld::history_stats);
    ClassDB::bind_method(D_METHOD("can_undo"),&NativeBlockWorld::can_undo);
    ClassDB::bind_method(D_METHOD("can_redo"),&NativeBlockWorld::can_redo);
    ClassDB::bind_method(D_METHOD("undo","protected_bounds"),&NativeBlockWorld::undo,DEFVAL(AABB()));
    ClassDB::bind_method(D_METHOD("redo","protected_bounds"),&NativeBlockWorld::redo,DEFVAL(AABB()));
    ClassDB::bind_method(D_METHOD("can_place_prefab","prefab","origin","quarter_turns","replace"),&NativeBlockWorld::can_place_prefab,DEFVAL(false));
    ClassDB::bind_method(D_METHOD("place_prefab","prefab","origin","quarter_turns","replace"),&NativeBlockWorld::place_prefab,DEFVAL(false));
    ClassDB::bind_method(D_METHOD("capture_prefab","origin","size"),&NativeBlockWorld::capture_prefab);
    ClassDB::bind_method(D_METHOD("get_cell","position"),&NativeBlockWorld::get_cell);
    ClassDB::bind_method(D_METHOD("overlap_mask","transforms","prototype_bounds"),&NativeBlockWorld::overlap_mask);
    ClassDB::bind_method(D_METHOD("stats"),&NativeBlockWorld::stats);
    ClassDB::bind_method(D_METHOD("set_focus","position"),&NativeBlockWorld::set_focus);
    ClassDB::bind_method(D_METHOD("configure_streaming","enabled","radius","chunk_limit","mesh_byte_limit","cache_byte_limit"),&NativeBlockWorld::configure_streaming);
    ClassDB::bind_method(D_METHOD("streaming_stats"),&NativeBlockWorld::streaming_stats);
    ClassDB::bind_method(D_METHOD("set_collision_radius","radius"),&NativeBlockWorld::set_collision_radius);
    ClassDB::bind_method(D_METHOD("is_idle"),&NativeBlockWorld::is_idle);
    ClassDB::bind_method(D_METHOD("flush_bakes"),&NativeBlockWorld::flush_bakes);
    ClassDB::bind_method(D_METHOD("capture_snapshot"),&NativeBlockWorld::capture_snapshot);
    ClassDB::bind_method(D_METHOD("validate_snapshot","bytes"),&NativeBlockWorld::validate_snapshot);
    ClassDB::bind_method(D_METHOD("restore_snapshot","bytes"),&NativeBlockWorld::restore_snapshot);
    ClassDB::bind_method(D_METHOD("create_showcase"),&NativeBlockWorld::create_showcase);
    ADD_SIGNAL(MethodInfo("changed"));
}
uint16_t NativeBlockWorld::cell(int x,int y,int z) const {
    auto it=chunks.find(key_for(x,y,z)); return it==chunks.end()?0:it->second.cells[index(x,y,z)];
}
void NativeBlockWorld::invalidate(BlockKey key) {
    residency_dirty=true;settled.erase(key);budget_blocked.erase(key);erase_cached(key);
    bool active=worker_active&&!(key<worker_key)&&!(worker_key<key);
    if(!chunks.count(key)&&!visuals.count(key)&&!active) {
        dirty.erase(key);tickets.erase(key);return;
    }
    dirty.insert(key); tickets[key]=++revision;
}
bool NativeBlockWorld::set_cells(const PackedInt32Array &records) {
    bool changed=false;
    if(!apply_cells(records,true,changed))return false;
    if(changed)emit_signal("changed");
    return true;
}
bool NativeBlockWorld::apply_cells(const PackedInt32Array &records,bool record_history,bool &changed) {
    changed=false;
    if(records.size()%4 || records.size()>4*262144) return false;
    const bool capture=record_history&&history_budget&&history_steps;
    std::vector<BlockChange> changes;
    if(capture)changes.reserve(records.size()/4);
    // Stage touched chunks: bad records or a capacity overflow cannot partially edit a building.
    std::map<BlockKey,BlockChunk> staged;
    for(int64_t i=0;i<records.size();i+=4) {
        int x=records[i],y=records[i+1],z=records[i+2],w=records[i+3];
        if(x<-LIMIT||x>LIMIT||y<-LIMIT||y>LIMIT||z<-LIMIT||z>LIMIT||!valid_word(w)) return false;
        BlockKey k=key_for(x,y,z);
        auto it=staged.find(k);
        if(it==staged.end()) {
            if(staged.size()>=MAX_CHUNKS) return false;
            auto old=chunks.find(k);
            it=staged.emplace(k,old==chunks.end()?BlockChunk{}:old->second).first;
        }
        auto &c=it->second; auto &v=c.cells[index(x,y,z)];
        if(capture)changes.push_back({x,y,z,v,uint16_t(w)});
        c.count+=(w!=0)-(v!=0); v=uint16_t(w);
        auto &column=c.columns[(x&15)+16*(z&15)];
        const uint16_t bit=uint16_t(1u<<(y&15));
        column=w?uint16_t(column|bit):uint16_t(column&~bit);
    }
    int final_count=int(chunks.size());
    for(auto &entry:staged) final_count+=(entry.second.count>0)-(chunks.count(entry.first)>0);
    if(final_count>MAX_CHUNKS) return false;
    for(auto &entry:staged) {
        auto old=chunks.find(entry.first);
        if(old!=chunks.end()&&old->second.cells==entry.second.cells) continue;
        if(old==chunks.end()&&entry.second.count==0) continue;
        auto k=entry.first; changed=true;
        if(entry.second.count) chunks[k]=std::move(entry.second); else chunks.erase(k);
        invalidate(k);
        // Halo dependencies are face neighbours. Conservatively invalidate all six.
        invalidate({k.x-1,k.y,k.z}); invalidate({k.x+1,k.y,k.z});
        invalidate({k.x,k.y-1,k.z}); invalidate({k.x,k.y+1,k.z});
        invalidate({k.x,k.y,k.z-1}); invalidate({k.x,k.y,k.z+1});
    }
    if(changed) {
        if(record_history)remember_edit(std::move(changes));
        set_process(true);
    }
    return true;
}

// Full occupied cells are conservative exclusion volumes for every block shape.
// Query cost is bounded by resident chunks even for enormous caller bounds.
bool NativeBlockWorld::occupied(const AABB &bounds) const {
    Vector3 lo=bounds.position, hi=bounds.get_end();
    for(int axis=0;axis<3;axis++) {
        if(hi[axis]<=-LIMIT || lo[axis]>=LIMIT+1) return false;
        lo[axis]=std::max(double(lo[axis]),double(-LIMIT));
        hi[axis]=std::min(double(hi[axis]),double(LIMIT+1));
    }
    int low[3],high[3];
    for(int a=0;a<3;a++) {low[a]=int(std::floor(lo[a]));high[a]=int(std::ceil(hi[a]))-1;}
    auto test=[&](BlockKey k,const BlockChunk &c) {
        int origin[3]={k.x*16,k.y*16,k.z*16},a[3],b[3];
        for(int axis=0;axis<3;axis++) {
            a[axis]=std::max(0,low[axis]-origin[axis]);b[axis]=std::min(15,high[axis]-origin[axis]);
            if(a[axis]>b[axis]) return false;
        }
        uint16_t mask=uint16_t(((1u<<(b[1]+1))-1)&~((1u<<a[1])-1));
        for(int z=a[2];z<=b[2];z++)for(int x=a[0];x<=b[0];x++)
            if(c.columns[x+16*z]&mask)return true;
        return false;
    };
    BlockKey first=key_for(low[0],low[1],low[2]),last=key_for(high[0],high[1],high[2]);
    int64_t volume=int64_t(last.x-first.x+1)*(last.y-first.y+1)*(last.z-first.z+1);
    if(volume<=int64_t(chunks.size())) {
        for(int z=first.z;z<=last.z;z++)for(int y=first.y;y<=last.y;y++)for(int x=first.x;x<=last.x;x++) {
            BlockKey k{x,y,z};auto it=chunks.find(k);if(it!=chunks.end()&&test(k,it->second))return true;
        }
    } else for(const auto &entry:chunks)if(test(entry.first,entry.second))return true;
    return false;
}
PackedByteArray NativeBlockWorld::overlap_mask(const TypedArray<Transform3D> &transforms,const AABB &bounds) const {
    PackedByteArray result;
    if(transforms.size()>65536||!bounds.position.is_finite()||!bounds.size.is_finite()||
       bounds.size.x<=0||bounds.size.y<=0||bounds.size.z<=0)return result;
    Transform3D frame=is_inside_tree()?get_global_transform():get_transform();
    if(!frame.is_finite()||std::abs(frame.basis.determinant())<1e-12)return result;
    Transform3D inverse=frame.affine_inverse();
    result.resize(transforms.size());
    for(int64_t i=0;i<transforms.size();i++) {
        Transform3D t=transforms[i];if(!t.is_finite()||std::abs(t.basis.determinant())<1e-12)return PackedByteArray();
        AABB box=(inverse*t).xform(bounds);
        if(!box.position.is_finite()||!box.get_end().is_finite())return PackedByteArray();
        result.set(i,occupied(box)?1:0);
    }
    return result;
}

static void quad(BlockBake &b,const std::array<Vector3,4>&p,Vector3 n,int material) {
    int base=int(b.vertices.size());
    int axis=std::abs(n.x)>.5?0:std::abs(n.y)>.5?1:2;
    for(auto v:p) {
        float u=axis==0?v.z:v.x, t=axis==1?v.z:v.y;
        b.vertices.push_back({v.x,v.y,v.z,n.x,n.y,n.z,u,t,float(material)});
    }
    // Godot uses clockwise front faces.
    for(int i:{0,2,1,0,3,2}) b.indices.push_back(base+i);
}
static void triangle(BlockBake &b,Vector3 a,Vector3 c,Vector3 d,int material) {
    Vector3 n=(c-a).cross(d-a).normalized(); int base=int(b.vertices.size());
    for(auto v:{a,c,d}) b.vertices.push_back({v.x,v.y,v.z,n.x,n.y,n.z,v.x+v.z,v.y,float(material)});
    b.indices.insert(b.indices.end(),{base,base+2,base+1});
}
static Vector3 rotate_shape(Vector3 p,int r) {
    for(int i=0;i<r;i++) p=Vector3(1-p.z,p.y,p.x); return p;
}
static void sphere(BlockBake &out,Vector3 origin,int rotation,int material) {
    // One immutable indexed template shared by all workers/instances. Six latitude
    // bands and twelve sectors: 120 nondegenerate triangles, 91 seam-aware vertices.
    const auto &geometry=sphere_template();
    int base=int(out.vertices.size());
    for(auto v:geometry.vertices) {
        Vector3 p=origin+rotate_shape(Vector3(v.x,v.y,v.z),rotation),n(v.nx,v.ny,v.nz);
        for(int r=0;r<rotation;r++)n=Vector3(-n.z,n.y,n.x);
        out.vertices.push_back({p.x,p.y,p.z,n.x,n.y,n.z,v.u,v.v,float(material)});
    }
    for(auto index:geometry.indices)out.indices.push_back(base+index);
}
template<int scale>
static void bake_lattice(BlockBake &out,const std::array<uint16_t,5832> &halo) {
    // Compile each exact grid separately so the inner loops retain constant
    // strides/divisors, including the unchanged quarter-cell case.
    constexpr int N=16*scale,H=N+2;
    constexpr float unit=1.f/scale;
    out.lattice_width=N;
    std::vector<uint8_t> voxels(H*H*H,0);
    auto at=[&](int x,int y,int z)->uint8_t& { return voxels[(x+1)+H*((y+1)+H*(z+1))]; };
    for(int z=-1;z<=N;z++) for(int y=-1;y<=N;y++) for(int x=-1;x<=N;x++) {
        int bx=x<0?-1:x/scale,by=y<0?-1:y/scale,bz=z<0?-1:z/scale;
        int w=halo[(bx+1)+18*((by+1)+18*(bz+1))],shape=w&7;
        int sx=(x&(scale-1))*(4/scale),sy=(y&(scale-1))*(4/scale),sz=(z&(scale-1))*(4/scale);
        for(int r=0;r<((w>>3)&3);r++) { int old=sx; sx=sz; sz=3-old; }
        bool full=shape==1 || (shape==2&&sy<2) || (shape==3&&sy<=sz) || (shape==5&&sx>=1&&sx<=2&&sz>=1&&sz<=2);
        if(full) at(x,y,z)=1+(w>>5);
    }
    // One material surface; signed mask separates opposite-facing coplanar faces.
    for(int axis=0;axis<3;axis++) {
        int u=(axis+1)%3,v=(axis+2)%3;
        std::array<int,4096> mask{};
        for(int plane=0;plane<=N;plane++) {
            for(int j=0;j<N;j++) for(int i=0;i<N;i++) {
                int a[3]={0,0,0},c[3]={0,0,0}; a[axis]=plane-1;c[axis]=plane;a[u]=c[u]=i;a[v]=c[v]=j;
                int left=at(a[0],a[1],a[2]),right=at(c[0],c[1],c[2]);
                // Only emit surfaces owned by this chunk, never halo geometry.
                mask[i+N*j]=(left&&!right&&plane>0)?left:((right&&!left&&plane<N)?-right:0);
            }
            for(int j=0;j<N;j++) for(int i=0;i<N;) {
                int m=mask[i+N*j]; if(!m) { i++;continue; }
                int width=1,height=1;
                while(i+width<N&&mask[i+width+N*j]==m) width++;
                bool extend=true;
                while(j+height<N&&extend) {
                    for(int k=0;k<width;k++) if(mask[i+k+N*(j+height)]!=m) {extend=false;break;}
                    if(extend) height++;
                }
                Vector3 p,du,dv,n; p[axis]=plane*unit;p[u]=i*unit;p[v]=j*unit;
                du[u]=width*unit;dv[v]=height*unit;n[axis]=m>0?1:-1;
                if(m>0) quad(out,{p,p+du,p+du+dv,p+dv},n,std::abs(m)-1);
                else quad(out,{p,p+dv,p+du+dv,p+du},n,std::abs(m)-1);
                for(int h=0;h<height;h++) for(int k=0;k<width;k++) mask[i+k+N*(j+h)]=0;
                i+=width;
            }
        }
    }
}
BlockBake NativeBlockWorld::bake(BlockKey key,uint64_t ticket,std::array<uint16_t,5832> halo) {
    BlockBake out; out.key=key; out.revision=ticket;
    // Include the halo: a neighboring stair/post can expose quarter-cell
    // fragments on an otherwise ordinary cube wall. Wedges/spheres are separate.
    int scale=1;
    for(uint16_t word:halo) {
        const int shape=word&7;
        if(shape==3||shape==5) {scale=4;break;}
        if(shape==2)scale=2;
    }
    if(scale==1)bake_lattice<1>(out,halo);
    else if(scale==2)bake_lattice<2>(out,halo);
    else bake_lattice<4>(out,halo);
    // True planar wedges, rather than staircase approximations of slopes.
    // Wedge boundary faces are currently conservative; see addon limitations.
    for(int z=0;z<16;z++) for(int y=0;y<16;y++) for(int x=0;x<16;x++) {
        int at=(x+1)+18*((y+1)+18*(z+1)),w=halo[at];
        if((w&7)==6) {
            bool enclosed=true;for(int step:{-1,1,-18,18,-324,324})if((halo[at+step]&7)!=1){enclosed=false;break;}
            if(!enclosed)sphere(out,Vector3(x,y,z),(w>>3)&3,w>>5);
            continue;
        }
        if((w&7)!=4) continue;
        Vector3 origin(x,y,z); int r=(w>>3)&3,m=w>>5;
        auto p=[&](float a,float b,float c){return origin+rotate_shape(Vector3(a,b,c),r);};
        auto q=[&](Vector3 a,Vector3 b,Vector3 c,Vector3 d){quad(out,{a,b,c,d},(b-a).cross(c-a).normalized(),m);};
        q(p(0,0,0),p(1,0,0),p(1,0,1),p(0,0,1));
        q(p(0,0,1),p(1,0,1),p(1,1,1),p(0,1,1));
        q(p(0,0,0),p(0,1,1),p(1,1,1),p(1,0,0));
        triangle(out,p(0,0,0),p(0,0,1),p(0,1,1),m);
        triangle(out,p(1,0,0),p(1,1,1),p(1,0,1),m);
    }
    return out;
}
void NativeBlockWorld::launch(bool allow_cached_upload) {
    while(!worker_active&&!dirty.empty()) {
        // Nearest dirty chunk first; pending work is deduplicated and bounded by resident cells.
        auto best=dirty.begin(); double distance=1e300;
        for(auto it=dirty.begin();it!=dirty.end();++it) {
            Vector3 c(it->x*16+8,it->y*16+8,it->z*16+8); double d=c.distance_squared_to(focus);
            if(d<distance) { distance=d;best=it; }
        }
        BlockKey k=*best;
        auto cached=bake_cache.find(k);
        if(cached!=bake_cache.end()&&!allow_cached_upload)return;
        dirty.erase(best); uint64_t ticket=tickets[k];
        if(!chunks.count(k)) { BlockBake empty;empty.key=k;empty.revision=ticket;publish(std::move(empty));continue; }
        if(cached!=bake_cache.end()) {
            cache_bytes-=cached->second.bake.vertices.capacity()*sizeof(BlockVertex)+cached->second.bake.indices.capacity()*sizeof(int32_t);
            BlockBake restored=std::move(cached->second.bake);bake_cache.erase(cached);
            restored.revision=ticket;cache_hits++;publish(std::move(restored));return;
        }
        cache_misses++;
        std::array<uint16_t,5832> halo{};
        for(int z=-1;z<=16;z++) for(int y=-1;y<=16;y++) for(int x=-1;x<=16;x++)
            halo[(x+1)+18*((y+1)+18*(z+1))]=cell(k.x*16+x,k.y*16+y,k.z*16+z);
        submit_bake(k,ticket,halo);
    }
}
bool NativeBlockWorld::publish(BlockBake &&b) {
    auto t=tickets.find(b.key);
    if(t==tickets.end()||t->second!=b.revision) {
        rejected++;
        if(!wanted.count(b.key))tickets.erase(b.key);
        else if(chunks.count(b.key)&&!dirty.count(b.key)) {tickets[b.key]=++revision;dirty.insert(b.key);}
        return false;
    }
    tickets.erase(b.key);
    release_visual(b.key);
    if(!wanted.count(b.key)) {cache_bake(std::move(b));return false;}
    if(b.indices.empty()) {settled.insert(b.key);cache_bake(std::move(b));return false;}
    uint64_t payload=b.vertices.size()*40+b.indices.size()*sizeof(int32_t);
    if(!admit_mesh(b.key,payload)) {budget_blocked.insert(b.key);cache_bake(std::move(b));return false;}
    ensure_material();
    PackedVector3Array vertices,normals; PackedVector2Array uv,uv2; PackedInt32Array indices;
    int count=int(b.vertices.size()); vertices.resize(count);normals.resize(count);uv.resize(count);uv2.resize(count);
    for(int i=0;i<count;i++) { auto &v=b.vertices[i];vertices.set(i,Vector3(v.x,v.y,v.z));normals.set(i,Vector3(v.nx,v.ny,v.nz));uv.set(i,Vector2(v.u,v.v));uv2.set(i,Vector2(v.material,0)); }
    indices.resize(b.indices.size());std::memcpy(indices.ptrw(),b.indices.data(),b.indices.size()*sizeof(int32_t));
    Array arrays; arrays.resize(Mesh::ARRAY_MAX);arrays[Mesh::ARRAY_VERTEX]=vertices;arrays[Mesh::ARRAY_NORMAL]=normals;arrays[Mesh::ARRAY_TEX_UV]=uv;arrays[Mesh::ARRAY_TEX_UV2]=uv2;arrays[Mesh::ARRAY_INDEX]=indices;
    Ref<ArrayMesh> mesh;mesh.instantiate();mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES,arrays);mesh->surface_set_material(0,material);
    auto *instance=memnew(MeshInstance3D);instance->set_mesh(mesh);instance->set_position(Vector3(b.key.x*16,b.key.y*16,b.key.z*16));add_child(instance);
    visuals[b.key]={instance,nullptr,int(b.indices.size()/3),payload,b.lattice_width};mesh_bytes+=payload;
    settled.insert(b.key);budget_blocked.erase(b.key);published++;cache_bake(std::move(b));return true;
}
void NativeBlockWorld::set_collision_radius(double radius) {
    if(!std::isfinite(radius)||radius<0||radius>256) return; collision_radius=radius;collisions=radius>0;
}
void NativeBlockWorld::update_collisions() {
    // At most one new physics shape per frame; remove far shapes immediately.
    bool created=false;
    for(auto &entry:visuals) {
        auto &v=entry.second;Vector3 center=v.mesh->get_position()+Vector3(8,8,8);
        bool near=collisions&&center.distance_squared_to(focus)<=(collision_radius+14)*(collision_radius+14);
        if(!near&&v.body) {memdelete(v.body);v.body=nullptr;}
        if(near&&!v.body&&!created) {
            auto shape=v.mesh->get_mesh()->create_trimesh_shape();
            if(shape.is_valid()) {
                v.body=memnew(StaticBody3D);v.body->set_position(v.mesh->get_position());v.body->set_collision_layer(2);
                auto *collision=memnew(CollisionShape3D);collision->set_shape(shape);v.body->add_child(collision);add_child(v.body);created=true;
            }
        }
    }
}
void NativeBlockWorld::_process(double) {
    refresh_residency();
    bool uploaded=false;
    BlockBake completed;
    if(take_bake(completed,false))uploaded=publish(std::move(completed));
    launch(!uploaded); update_collisions();
}
void NativeBlockWorld::flush_bakes() {
    refresh_residency();
    while(!is_idle()) {
        refresh_residency();launch();
        BlockBake completed;
        if(take_bake(completed,true))publish(std::move(completed));
    }
    for(size_t i=0;i<visuals.size();i++) update_collisions();
}
Dictionary NativeBlockWorld::stats() const {
    int cells=0,triangles=0,bodies=0;
    int lattice16=0,lattice32=0,lattice64=0;
    for(auto &e:chunks) cells+=e.second.count;
    for(auto &e:visuals) {
        triangles+=e.second.triangles;bodies+=e.second.body!=nullptr;
        lattice16+=e.second.lattice_width==16;lattice32+=e.second.lattice_width==32;lattice64+=e.second.lattice_width==64;
    }
    Dictionary d;d["cells"]=cells;d["chunks"]=int(chunks.size());d["cell_bytes"]=int(chunks.size())*8192;d["mesh_chunks"]=int(visuals.size());d["triangles"]=triangles;d["collision_chunks"]=bodies;d["dirty_chunks"]=int(dirty.size());d["worker_jobs"]=worker_active?1:0;d["stale_bakes_rejected"]=int64_t(rejected);d["published_bakes"]=int64_t(published);d["max_chunks"]=MAX_CHUNKS;
    d["bake_lattice_16_chunks"]=lattice16;d["bake_lattice_32_chunks"]=lattice32;d["bake_lattice_64_chunks"]=lattice64;
    d["worker_threads_started"]=int64_t(worker_starts);d["worker_jobs_submitted"]=int64_t(worker_submissions);d["worker_results_consumed"]=int64_t(worker_consumed);return d;
}
void NativeBlockWorld::ensure_material() {
    if(material.is_valid()) return;
    // Original deterministic tile textures generated once. Texture arrays retain
    // independent mip chains and repeat without atlas bleeding or material splits.
    TypedArray<Image> images;
    for(int layer=0;layer<4;layer++) {
        Ref<Image> img=Image::create_empty(128,128,false,Image::FORMAT_RGB8);
        for(int y=0;y<128;y++) for(int x=0;x<128;x++) {
            uint32_t hash=uint32_t(x*1973+y*9277+layer*26699);hash=(hash^(hash>>13))*1274126177u;
            float noise=float(hash&255)/255.f-.5f;Color c;
            if(layer==0) {
                int row=y/32,xx=(x+(row&1)*32)%64;bool mortar=(y%32<3||xx<3);
                c=mortar?Color(.49,.46,.40):Color(.51+noise*.07,.235+noise*.04,.13+noise*.03);
            } else if(layer==1) {
                bool seam=x%32<2;float grain=std::sin(y*.16f+std::sin(x*.7f)*2)*.035f+noise*.025f;
                c=seam?Color(.15,.095,.04):Color(.48+grain,.32+grain,.15+grain);
            } else if(layer==2) c=Color(.58+noise*.07,.60+noise*.07,.59+noise*.07);
            else {bool seam=x<2||y<2; c=seam?Color(.08,.11,.13):Color(.19+noise*.015,.26+noise*.015,.29+noise*.015);}
            img->set_pixel(x,y,c);
        }
        img->generate_mipmaps();images.append(img);
    }
    Ref<Texture2DArray> textures;textures.instantiate();textures->create_from_images(images);
    Ref<Shader> shader;shader.instantiate();shader->set_code(R"(
shader_type spatial;
uniform sampler2DArray tiles : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
void fragment() {
    ALBEDO = texture(tiles,vec3(UV,UV2.x)).rgb;
    ROUGHNESS = UV2.x > 2.5 ? 0.48 : 0.92;
    METALLIC = UV2.x > 2.5 ? 0.5 : 0.0;
}
)");
    material.instantiate();material->set_shader(shader);material->set_shader_parameter("tiles",textures);
}

PackedByteArray NativeBlockWorld::capture_snapshot() const {
    std::vector<uint8_t> bytes={'T','F','B','L',1,0,0,0};
    auto u32=[&](uint32_t v){for(int i=0;i<4;i++)bytes.push_back(uint8_t(v>>(8*i)));};
    auto u16=[&](uint16_t v){bytes.push_back(v&255);bytes.push_back(v>>8);};
    u32(uint32_t(chunks.size()));
    for(auto &e:chunks) {
        u32(uint32_t(e.first.x));u32(uint32_t(e.first.y));u32(uint32_t(e.first.z));
        for(int i=0;i<4096;) {int end=i+1;while(end<4096&&e.second.cells[end]==e.second.cells[i])end++;u16(uint16_t(end-i));u16(e.second.cells[i]);i=end;}
    }
    PackedByteArray result;result.resize(bytes.size());std::memcpy(result.ptrw(),bytes.data(),bytes.size());result.append_array(sha(result));return result;
}
bool NativeBlockWorld::parse(const PackedByteArray &bytes,std::map<BlockKey,BlockChunk> *out) {
    if(bytes.size()<44||bytes.size()>34*1024*1024||std::memcmp(bytes.ptr(),"TFBL\1\0\0\0",8)) return false;
    auto payload=bytes.slice(0,bytes.size()-32); if(sha(payload)!=bytes.slice(bytes.size()-32)) return false;
    size_t p=8,n=payload.size();const uint8_t *d=payload.ptr();
    auto u32=[&](){uint32_t v=uint32_t(d[p])|uint32_t(d[p+1])<<8|uint32_t(d[p+2])<<16|uint32_t(d[p+3])<<24;p+=4;return v;};
    uint32_t count=u32();if(count>MAX_CHUNKS) return false;
    std::set<BlockKey> seen;
    for(uint32_t c=0;c<count;c++) {
        if(p+12>n)return false;
        BlockKey k{int32_t(u32()),int32_t(u32()),int32_t(u32())};
        for(int v:{k.x,k.y,k.z}) if(v<-65536||v>65535) return false;
        if(!seen.insert(k).second)return false;
        BlockChunk chunk;int pos=0;
        while(pos<4096) {
            if(p+4>n)return false;int run=d[p]|int(d[p+1])<<8,w=d[p+2]|int(d[p+3])<<8;p+=4;
            if(!run||run>4096-pos||!valid_word(w))return false;
            std::fill(chunk.cells.begin()+pos,chunk.cells.begin()+pos+run,uint16_t(w));if(w)chunk.count+=run;pos+=run;
        }
        if(!chunk.count)return false;
        // Reject cells outside the public coordinate range, including the one
        // asymmetric negative boundary cell within the last storage chunk.
        if(k.x==-65536||k.y==-65536||k.z==-65536)
            for(int z=0;z<16;z++)for(int y=0;y<16;y++)for(int x=0;x<16;x++)
                if(chunk.cells[index(x,y,z)]&&(k.x*16+x<-LIMIT||k.y*16+y<-LIMIT||k.z*16+z<-LIMIT))return false;
        if(out) {
            for(int z=0;z<16;z++)for(int y=0;y<16;y++)for(int x=0;x<16;x++)
                if(chunk.cells[index(x,y,z)])chunk.columns[x+16*z]|=uint16_t(1u<<y);
            (*out)[k]=std::move(chunk);
        }
    }
    return p==n;
}
bool NativeBlockWorld::restore_snapshot(const PackedByteArray &bytes) {
    std::map<BlockKey,BlockChunk> restored;if(!parse(bytes,&restored))return false;
    std::set<BlockKey> affected;for(auto &e:chunks)affected.insert(e.first);for(auto &e:restored)affected.insert(e.first);
    for(auto &e:visuals)affected.insert(e.first);
    // Preserve pending keys so any in-flight publication receives a new ticket.
    for(auto &e:tickets)affected.insert(e.first);
    bake_cache.clear();cache_bytes=0;settled.clear();budget_blocked.clear();residency_dirty=true;
    chunks=std::move(restored);dirty.clear();tickets.clear();for(auto k:affected)invalidate(k);
    clear_history();
    set_process(true);emit_signal("changed");return true;
}
}
