// SPDX-License-Identifier: 0BSD
// Included by lake_volume.cpp inside terraforest. Version 1, little-endian.
// Identity is a caller-supplied 256-bit terrain/content digest, not a revision counter.
static uint32_t bake_checksum(const PackedByteArray &bytes) {
    uint32_t hash=2166136261u;
    for(int64_t i=16;i<bytes.size();++i)hash=(hash^bytes[i])*16777619u;
    return hash;
}
PackedByteArray NativeLakeVolume::capture_bake(const PackedByteArray &identity) const {
    PackedByteArray out;if(status_!=1||identity.size()!=32)return out;
    const PackedVector3Array vertices=smooth_surface_[Mesh::ARRAY_VERTEX];
    const PackedInt32Array indices=smooth_surface_[Mesh::ARRAY_INDEX];
    if(vertices.size()>262144||indices.size()>786432)return out;
    out.resize(104+count_+vertices.size()*8+indices.size()*4);
    out.encode_u32(0,0x31424c54);out.encode_u32(4,1);out.encode_u32(8,out.size());
    for(int i=0;i<32;++i)out.set(16+i,identity[i]);
    for(int a=0;a<3;++a){out.encode_float(48+a*4,origin_[a]);out.encode_u32(60+a*4,size_[a]);out.encode_float(80+a*4,seed_[a]);}
    out.encode_float(72,spacing_);out.encode_float(76,level_);out.encode_u32(92,count_);
    out.encode_u32(96,vertices.size());out.encode_u32(100,indices.size());
    int64_t at=104;
    for(uint32_t i=0;i<count_;++i)out.set(at++,wet_[i]);
    for(int64_t i=0;i<vertices.size();++i){out.encode_float(at,vertices[i].x);out.encode_float(at+4,vertices[i].z);at+=8;}
    for(int64_t i=0;i<indices.size();++i){out.encode_u32(at,indices[i]);at+=4;}
    out.encode_u32(12,bake_checksum(out));return out;
}
bool NativeLakeVolume::restore_bake(const PackedByteArray &bytes,const PackedByteArray &identity) {
    // Reject before allocation, and never modify an existing/published instance.
    if(count_||identity.size()!=32||bytes.size()<104||bytes.size()>6*1024*1024||bytes.decode_u32(0)!=0x31424c54||bytes.decode_u32(4)!=1||bytes.decode_u32(8)!=uint64_t(bytes.size()))return false;
    for(int i=0;i<32;++i)if(bytes[16+i]!=identity[i])return false;
    if(bytes.decode_u32(12)!=bake_checksum(bytes))return false;
    const uint32_t count=bytes.decode_u32(92),nv=bytes.decode_u32(96),ni=bytes.decode_u32(100);
    if(count>262144||nv>262144||ni>786432||ni%3||104ull+count+uint64_t(nv)*8+uint64_t(ni)*4!=uint64_t(bytes.size()))return false;
    Vector3 origin,seed;Vector3i size;
    for(int a=0;a<3;++a){origin[a]=bytes.decode_float(48+a*4);size[a]=bytes.decode_u32(60+a*4);seed[a]=bytes.decode_float(80+a*4);}
    Ref<NativeLakeVolume> stage;stage.instantiate();
    if(!stage->configure(origin,size,bytes.decode_float(72),bytes.decode_float(76),seed)||stage->count_!=count)return false;
    stage->column_top_.reset(new(std::nothrow) uint8_t[size_t(size.x)*size.z]());
    if(!stage->column_top_)return false;
    uint32_t wet_count=0;int64_t at=104;
    for(uint32_t i=0;i<count;++i){
        const uint8_t wet=bytes[at++];if(wet>1)return false;
        const int x=i%size.x,y=(i/size.x)%size.y,z=i/(size.x*size.y);
        if(wet){
            if(x==0||z==0||y==0||x==size.x-1||z==size.z-1||origin.y+y*stage->spacing_>=stage->level_)return false;
            ++wet_count;auto &top=stage->column_top_[x+size.x*z];top=std::max(top,uint8_t(y+1));
        }
        stage->wet_[i]=wet;
    }
    const Vector3 local=(seed-origin)/stage->spacing_;
    if(!wet_count||!stage->wet_[stage->index(int(local.x),int(local.y),int(local.z))])return false;
    PackedVector3Array vertices,normals;PackedVector2Array uv;PackedInt32Array indices;
    vertices.resize(nv);normals.resize(nv);uv.resize(nv);indices.resize(ni);
    for(uint32_t i=0;i<nv;++i){
        const Vector3 p(bytes.decode_float(at),stage->level_,bytes.decode_float(at+4));at+=8;
        if(!p.is_finite()||p.x<origin.x||p.z<origin.z||p.x>origin.x+size.x*stage->spacing_||p.z>origin.z+size.z*stage->spacing_)return false;
        vertices.set(i,p);normals.set(i,Vector3(0,1,0));uv.set(i,Vector2(p.x,p.z));
    }
    for(uint32_t i=0;i<ni;++i){uint32_t value=bytes.decode_u32(at);at+=4;if(value>=nv)return false;indices.set(i,value);}
    Array arrays;arrays.resize(Mesh::ARRAY_MAX);arrays[Mesh::ARRAY_VERTEX]=vertices;arrays[Mesh::ARRAY_NORMAL]=normals;arrays[Mesh::ARRAY_TEX_UV]=uv;arrays[Mesh::ARRAY_INDEX]=indices;
    origin_=stage->origin_;seed_=stage->seed_;size_=stage->size_;spacing_=stage->spacing_;level_=stage->level_;
    count_=count;node_count_=stage->node_count_;sampled_=0;wet_count_=wet_count;status_=1;
    wet_=std::move(stage->wet_);column_top_=std::move(stage->column_top_);smooth_surface_=arrays;
    return true;
}
