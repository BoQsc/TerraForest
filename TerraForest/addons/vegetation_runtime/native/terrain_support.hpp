#pragma once
#include "scatter.hpp"
#include <godot_cpp/variant/aabb.hpp>
namespace terraforest {
class NativeVegetationSupport : public RefCounted {
    GDCLASS(NativeVegetationSupport,RefCounted)
    static void append(PackedInt64Array &ids,PackedVector3Array &points,PackedInt32Array &offsets,int64_t identity,Vector3 root,double height,const AABB &bounds){
        if(!root.is_finite()||root.x<bounds.position.x||root.x>bounds.get_end().x||root.z<bounds.position.z||root.z>bounds.get_end().z||root.y+height<bounds.position.y||root.y-.08>bounds.get_end().y||root.x<0||root.x>=2000||root.z<0||root.z>=2000||root.y<.1||root.y>=255.8)return;
        ids.append(identity);offsets.append(points.size());points.append(root-Vector3(0,.08,0));points.append(root+Vector3(0,.08,0));
        double top=std::min(255.9,double(root.y)+height);
        for(double level=std::floor(root.y+.08)+1;level<top;++level)points.append(Vector3(root.x,level,root.z));
        if(top>root.y+.08)points.append(Vector3(root.x,top,root.z));
    }
protected:
    static void _bind_methods(){
        ClassDB::bind_method(D_METHOD("ground_probes","rows","bounds"),&NativeVegetationSupport::ground_probes);
        ClassDB::bind_method(D_METHOD("tree_probes","ids","poses","bounds"),&NativeVegetationSupport::tree_probes);
        ClassDB::bind_method(D_METHOD("lost_roots","snapshot","before","after"),&NativeVegetationSupport::lost_roots);
        ClassDB::bind_method(D_METHOD("filter_ground","rows","removed","selected"),&NativeVegetationSupport::filter_ground,DEFVAL(false));
        ClassDB::bind_method(D_METHOD("filter_trees","ids","poses","removed"),&NativeVegetationSupport::filter_trees);
    }
public:
    Dictionary ground_probes(const Array &rows,const AABB &bounds)const{
        PackedInt64Array selected;PackedVector3Array points;PackedInt32Array offsets;
        if(rows.size()!=9)return Dictionary();
        for(int species=0;species<9;++species){
            Dictionary row=rows[species];PackedInt64Array ids=row["ids"];PackedFloat32Array values=row["transforms"];
            if(values.size()!=ids.size()*12||ids.size()>1280)return Dictionary();
            for(int64_t index=0;index<ids.size();++index){
                const float *pose=values.ptr()+index*12;Vector3 root(pose[3],pose[7],pose[11]);
                if(ids[index]<(int64_t(1)<<32)){
                    double scale=Vector3(pose[0],pose[4],pose[8]).length();
                    root.y+=.03;
                    if(species==0&&scale>=6)root.y-=Vector3(pose[1],pose[5],pose[9]).length()*.12;
                }else root.y-=.02;
                double height=(species==0?.26:(species==8?1.1:.8))*Vector3(pose[1],pose[5],pose[9]).length();
                append(selected,points,offsets,ids[index],root,height,bounds);
            }
        }
        offsets.append(points.size());Dictionary result;result["ids"]=selected;result["points"]=points;result["offsets"]=offsets;return result;
    }
    Dictionary tree_probes(const PackedInt64Array &ids,const TypedArray<Transform3D> &poses,const AABB &bounds)const{
        if(ids.size()!=poses.size()||ids.size()>4096)return Dictionary();
        PackedInt64Array selected;PackedVector3Array points;PackedInt32Array offsets;
        for(int64_t index=0;index<ids.size();++index){Transform3D pose=poses[index];append(selected,points,offsets,ids[index],pose.origin+Vector3(0,.2,0),8*pose.basis.get_column(1).length(),bounds);}
        offsets.append(points.size());Dictionary result;result["ids"]=selected;result["points"]=points;result["offsets"]=offsets;return result;
    }
    Dictionary lost_roots(const Dictionary &snapshot,const Dictionary &before,const Dictionary &after)const{
        Dictionary result;result["ok"]=false;
        if(!snapshot.has("ids")||!snapshot.has("offsets")||!before.has("density")||!after.has("density"))return result;
        PackedInt64Array ids=snapshot["ids"];PackedInt32Array offsets=snapshot["offsets"];
        PackedFloat32Array old_density=before["density"],new_density=after["density"],old_blocks=before.get("blocks",PackedFloat32Array()),new_blocks=after.get("blocks",PackedFloat32Array());
        PackedFloat32Array paved=after.get("paved",PackedFloat32Array());
        if(offsets.size()!=ids.size()+1||offsets[0]!=0)return result;
        int64_t count=offsets[offsets.size()-1];
        if(old_density.size()!=count||new_density.size()!=count||(old_blocks.size()&&old_blocks.size()!=count)||(new_blocks.size()&&new_blocks.size()!=count)||(paved.size()!=0&&paved.size()!=count))return result;
        const int64_t *identities=ids.ptr();const int32_t *starts=offsets.ptr();
        const float *old_values=old_density.ptr(),*new_values=new_density.ptr(),*old_voxels=old_blocks.ptr(),*new_voxels=new_blocks.ptr(),*roads=paved.ptr();
        PackedInt64Array removed,destroyed;removed.resize(ids.size());destroyed.resize(ids.size());
        int64_t removed_count=0,destroyed_count=0,*removed_ids=removed.ptrw(),*destroyed_ids=destroyed.ptrw();
        for(int64_t index=0;index<ids.size();++index){
            if(starts[index]<0||starts[index+1]-starts[index]<2||starts[index+1]>count)return result;
            bool lost=false;
            for(int64_t offset=starts[index];offset<starts[index+1];++offset){
                if(!std::isfinite(old_values[offset])||!std::isfinite(new_values[offset])||(old_voxels&&!std::isfinite(old_voxels[offset]))||(new_voxels&&!std::isfinite(new_voxels[offset]))||(roads&&!std::isfinite(roads[offset])))return result;
                bool was_solid=old_values[offset]<0||(old_voxels&&old_voxels[offset]>0);
                bool is_solid=new_values[offset]<0||(new_voxels&&new_voxels[offset]>0);
                lost|=offset==starts[index]?(was_solid&&!is_solid):(!was_solid&&is_solid);
            }
            if(lost)destroyed_ids[destroyed_count++]=identities[index];
            if(lost||(roads&&roads[starts[index]]>0))removed_ids[removed_count++]=identities[index];
        }
        removed.resize(removed_count);destroyed.resize(destroyed_count);
        result["ok"]=true;result["ids"]=removed;result["destroyed"]=destroyed;return result;
    }
    Array filter_ground(const Array &rows,const PackedInt64Array &removed,bool selected=false)const{
        if(rows.size()!=9)return Array();
        std::unordered_set<int64_t> rejected;for(int64_t identity:removed)rejected.insert(identity);
        Array output;
        for(int species=0;species<9;++species){
            Dictionary row=rows[species];PackedInt64Array ids=row["ids"],kept;PackedFloat32Array values=row["transforms"],poses;
            if(values.size()!=ids.size()*12)return Array();
            kept.resize(ids.size());poses.resize(values.size());int64_t count=0;
            int64_t *kept_ids=kept.ptrw();const int64_t *identities=ids.ptr();float *kept_poses=poses.ptrw();const float *source=values.ptr();
            for(int64_t index=0;index<ids.size();++index)if(bool(rejected.count(identities[index]))==selected){kept_ids[count]=identities[index];std::copy(source+index*12,source+(index+1)*12,kept_poses+count*12);++count;}
            kept.resize(count);poses.resize(count*12);
            Dictionary next;next["ids"]=kept;next["transforms"]=poses;output.append(next);
        }
        return output;
    }
    Dictionary filter_trees(const PackedInt64Array &ids,const TypedArray<Transform3D> &poses,const PackedInt64Array &removed)const{
        if(ids.size()!=poses.size())return Dictionary();
        std::unordered_set<int64_t> rejected;for(int64_t identity:removed)rejected.insert(identity);
        PackedInt64Array kept;TypedArray<Transform3D> transforms;
        for(int64_t index=0;index<ids.size();++index)if(!rejected.count(ids[index])){kept.append(ids[index]);transforms.append(poses[index]);}
        Dictionary result;result["ids"]=kept;result["transforms"]=transforms;return result;
    }
};
}
