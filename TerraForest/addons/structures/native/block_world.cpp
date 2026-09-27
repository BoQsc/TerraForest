#include "block_world.hpp"
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
static bool valid_word(int w) { return w==0 || (w>0&&w<128&&(w&7)>=1&&(w&7)<=5); }
static PackedByteArray sha(const PackedByteArray &data) {
    Ref<HashingContext> h; h.instantiate(); h->start(HashingContext::HASH_SHA256); h->update(data); return h->finish();
}
void NativeBlockWorld::_bind_methods() {
    ClassDB::bind_method(D_METHOD("set_cells","records"),&NativeBlockWorld::set_cells);
    ClassDB::bind_method(D_METHOD("get_cell","position"),&NativeBlockWorld::get_cell);
    ClassDB::bind_method(D_METHOD("stats"),&NativeBlockWorld::stats);
    ClassDB::bind_method(D_METHOD("set_focus","position"),&NativeBlockWorld::set_focus);
    ClassDB::bind_method(D_METHOD("set_collision_radius","radius"),&NativeBlockWorld::set_collision_radius);
    ClassDB::bind_method(D_METHOD("is_idle"),&NativeBlockWorld::is_idle);
    ClassDB::bind_method(D_METHOD("flush_bakes"),&NativeBlockWorld::flush_bakes);
    ClassDB::bind_method(D_METHOD("capture_snapshot"),&NativeBlockWorld::capture_snapshot);
    ClassDB::bind_method(D_METHOD("validate_snapshot","bytes"),&NativeBlockWorld::validate_snapshot);
    ClassDB::bind_method(D_METHOD("restore_snapshot","bytes"),&NativeBlockWorld::restore_snapshot);
    ClassDB::bind_method(D_METHOD("create_showcase"),&NativeBlockWorld::create_showcase);
    ADD_SIGNAL(MethodInfo("changed"));
}
NativeBlockWorld::~NativeBlockWorld() { if(worker.valid()) worker.wait(); }
uint16_t NativeBlockWorld::cell(int x,int y,int z) const {
    auto it=chunks.find(key_for(x,y,z)); return it==chunks.end()?0:it->second.cells[index(x,y,z)];
}
void NativeBlockWorld::invalidate(BlockKey key) {
    bool active=worker.valid()&&!(key<worker_key)&&!(worker_key<key);
    if(!chunks.count(key)&&!visuals.count(key)&&!active) {
        dirty.erase(key);tickets.erase(key);return;
    }
    dirty.insert(key); tickets[key]=++revision;
}
bool NativeBlockWorld::set_cells(const PackedInt32Array &records) {
    if(records.size()%4 || records.size()>4*262144) return false;
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
        c.count+=(w!=0)-(v!=0); v=uint16_t(w);
    }
    int final_count=int(chunks.size());
    for(auto &entry:staged) final_count+=(entry.second.count>0)-(chunks.count(entry.first)>0);
    if(final_count>MAX_CHUNKS) return false;
    bool changed=false;
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
    if(changed) { set_process(true); emit_signal("changed"); }
    return true;
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
BlockBake NativeBlockWorld::bake(BlockKey key,uint64_t ticket,std::array<uint16_t,5832> halo) {
    BlockBake out; out.key=key; out.revision=ticket;
    // Quarter-cell occupancy makes stairs/slabs/posts meet exactly, while greedy
    // rectangles collapse flat regions back to large polygons. This is offline
    // bake work, not persistent high-resolution storage or per-frame iteration.
    constexpr int N=64,H=66;
    std::vector<uint8_t> voxels(H*H*H,0);
    auto at=[&](int x,int y,int z)->uint8_t& { return voxels[(x+1)+H*((y+1)+H*(z+1))]; };
    for(int z=-1;z<=N;z++) for(int y=-1;y<=N;y++) for(int x=-1;x<=N;x++) {
        int bx=x<0?-1:x/4,by=y<0?-1:y/4,bz=z<0?-1:z/4;
        int w=halo[(bx+1)+18*((by+1)+18*(bz+1))],shape=w&7;
        int sx=x&3,sy=y&3,sz=z&3;
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
                Vector3 p,du,dv,n; p[axis]=plane*.25f;p[u]=i*.25f;p[v]=j*.25f;
                du[u]=width*.25f;dv[v]=height*.25f;n[axis]=m>0?1:-1;
                if(m>0) quad(out,{p,p+du,p+du+dv,p+dv},n,std::abs(m)-1);
                else quad(out,{p,p+dv,p+du+dv,p+du},n,std::abs(m)-1);
                for(int h=0;h<height;h++) for(int k=0;k<width;k++) mask[i+k+N*(j+h)]=0;
                i+=width;
            }
        }
    }
    // True planar wedges, rather than staircase approximations of slopes.
    // Wedge boundary faces are currently conservative; see addon limitations.
    for(int z=0;z<16;z++) for(int y=0;y<16;y++) for(int x=0;x<16;x++) {
        int w=halo[(x+1)+18*((y+1)+18*(z+1))]; if((w&7)!=4) continue;
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
void NativeBlockWorld::launch() {
    while(!worker.valid()&&!dirty.empty()) {
        // Nearest dirty chunk first; pending work is deduplicated and bounded by resident cells.
        auto best=dirty.begin(); double distance=1e300;
        for(auto it=dirty.begin();it!=dirty.end();++it) {
            Vector3 c(it->x*16+8,it->y*16+8,it->z*16+8); double d=c.distance_squared_to(focus);
            if(d<distance) { distance=d;best=it; }
        }
        BlockKey k=*best; dirty.erase(best); uint64_t ticket=tickets[k];
        if(!chunks.count(k)) { BlockBake empty;empty.key=k;empty.revision=ticket;publish(std::move(empty));continue; }
        std::array<uint16_t,5832> halo{};
        for(int z=-1;z<=16;z++) for(int y=-1;y<=16;y++) for(int x=-1;x<=16;x++)
            halo[(x+1)+18*((y+1)+18*(z+1))]=cell(k.x*16+x,k.y*16+y,k.z*16+z);
        worker_key=k;
        worker=std::async(std::launch::async,[k,ticket,halo](){return bake(k,ticket,halo);});
    }
}
void NativeBlockWorld::publish(BlockBake &&b) {
    auto t=tickets.find(b.key);
    if(t==tickets.end()||t->second!=b.revision) { rejected++;return; }
    auto old=visuals.find(b.key);
    if(old!=visuals.end()) {
        if(old->second.body) memdelete(old->second.body);
        memdelete(old->second.mesh); visuals.erase(old);
    }
    tickets.erase(b.key);
    if(b.indices.empty()) return;
    ensure_material();
    PackedVector3Array vertices,normals; PackedVector2Array uv,uv2; PackedInt32Array indices;
    int count=int(b.vertices.size()); vertices.resize(count);normals.resize(count);uv.resize(count);uv2.resize(count);
    for(int i=0;i<count;i++) { auto &v=b.vertices[i];vertices.set(i,Vector3(v.x,v.y,v.z));normals.set(i,Vector3(v.nx,v.ny,v.nz));uv.set(i,Vector2(v.u,v.v));uv2.set(i,Vector2(v.material,0)); }
    indices.resize(b.indices.size());std::memcpy(indices.ptrw(),b.indices.data(),b.indices.size()*sizeof(int32_t));
    Array arrays; arrays.resize(Mesh::ARRAY_MAX);arrays[Mesh::ARRAY_VERTEX]=vertices;arrays[Mesh::ARRAY_NORMAL]=normals;arrays[Mesh::ARRAY_TEX_UV]=uv;arrays[Mesh::ARRAY_TEX_UV2]=uv2;arrays[Mesh::ARRAY_INDEX]=indices;
    Ref<ArrayMesh> mesh;mesh.instantiate();mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES,arrays);mesh->surface_set_material(0,material);
    auto *instance=memnew(MeshInstance3D);instance->set_mesh(mesh);instance->set_position(Vector3(b.key.x*16,b.key.y*16,b.key.z*16));add_child(instance);
    visuals[b.key]={instance,nullptr,int(b.indices.size()/3)};published++;
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
    if(worker.valid()&&worker.wait_for(std::chrono::seconds(0))==std::future_status::ready) publish(worker.get());
    launch(); update_collisions();
}
void NativeBlockWorld::flush_bakes() {
    while(!is_idle()) { launch();if(worker.valid()) publish(worker.get()); }
    for(size_t i=0;i<visuals.size();i++) update_collisions();
}
Dictionary NativeBlockWorld::stats() const {
    int cells=0,triangles=0,bodies=0;
    for(auto &e:chunks) cells+=e.second.count;
    for(auto &e:visuals) {triangles+=e.second.triangles;bodies+=e.second.body!=nullptr;}
    Dictionary d;d["cells"]=cells;d["chunks"]=int(chunks.size());d["cell_bytes"]=int(chunks.size())*8192;d["mesh_chunks"]=int(visuals.size());d["triangles"]=triangles;d["collision_chunks"]=bodies;d["dirty_chunks"]=int(dirty.size());d["worker_jobs"]=worker.valid()?1:0;d["stale_bakes_rejected"]=int64_t(rejected);d["published_bakes"]=int64_t(published);d["max_chunks"]=MAX_CHUNKS;return d;
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
        if(out)(*out)[k]=std::move(chunk);
    }
    return p==n;
}
bool NativeBlockWorld::restore_snapshot(const PackedByteArray &bytes) {
    std::map<BlockKey,BlockChunk> restored;if(!parse(bytes,&restored))return false;
    std::set<BlockKey> affected;for(auto &e:chunks)affected.insert(e.first);for(auto &e:restored)affected.insert(e.first);
    for(auto &e:visuals)affected.insert(e.first);
    // Preserve pending keys so any in-flight publication receives a new ticket.
    for(auto &e:tickets)affected.insert(e.first);
    chunks=std::move(restored);dirty.clear();tickets.clear();for(auto k:affected)invalidate(k);
    set_process(true);emit_signal("changed");return true;
}
}
