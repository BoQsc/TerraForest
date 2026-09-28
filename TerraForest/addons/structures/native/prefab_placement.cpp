#include "block_world.hpp"

namespace terraforest {
bool NativeBlockWorld::prefab_records(const Ref<NativeBlockPrefab> &prefab,Vector3i origin,int turns,bool replace,PackedInt32Array *out) const {
    if(prefab.is_null()||prefab->cells.empty()||turns<0||turns>3)return false;
    if(out)out->resize(prefab->cells.size()*4);
    std::set<BlockKey> new_chunks;
    int i=0;
    for(const auto &c:prefab->cells) {
        int64_t x=c.x,z=c.z,y=int64_t(c.y)+origin.y;
        for(int r=0;r<turns;r++) {int64_t old=x;x=-z;z=old;}
        x+=origin.x;z+=origin.z;
        for(auto v:{x,y,z})if(v<-1048575||v>1048575)return false;
        if(!replace&&cell(int(x),int(y),int(z)))return false;
        BlockKey k=key_for(int(x),int(y),int(z));
        if(!chunks.count(k))new_chunks.insert(k);
        if(chunks.size()+new_chunks.size()>2048)return false;
        int word=(c.word&~24)|((((c.word>>3)+turns)&3)<<3);
        if(out) {out->set(i++,int(x));out->set(i++,int(y));out->set(i++,int(z));out->set(i++,word);}
    }
    return true;
}
bool NativeBlockWorld::can_place_prefab(const Ref<NativeBlockPrefab> &prefab,Vector3i origin,int turns,bool replace) const {
    return prefab_records(prefab,origin,turns,replace,nullptr);
}
bool NativeBlockWorld::place_prefab(const Ref<NativeBlockPrefab> &prefab,Vector3i origin,int turns,bool replace) {
    PackedInt32Array records;
    return prefab_records(prefab,origin,turns,replace,&records)&&set_cells(records);
}
Ref<NativeBlockPrefab> NativeBlockWorld::capture_prefab(Vector3i origin,Vector3i size) const {
    int64_t volume=1;
    for(int a=0;a<3;a++) {
        if(size[a]<=0||size[a]>256||origin[a]<-1048575||int64_t(origin[a])+size[a]-1>1048575)return {};
        volume*=size[a];
    }
    if(volume>262144)return {};
    PackedInt32Array records;
    for(int z=0;z<size.z;z++)for(int y=0;y<size.y;y++)for(int x=0;x<size.x;x++) {
        int w=cell(origin.x+x,origin.y+y,origin.z+z);
        if(w) {records.append(x);records.append(y);records.append(z);records.append(w);}
    }
    Ref<NativeBlockPrefab> prefab;prefab.instantiate();
    if(!prefab->configure(records))return {};
    return prefab;
}
}
