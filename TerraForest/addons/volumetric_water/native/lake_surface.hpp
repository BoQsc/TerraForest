// SPDX-License-Identifier: 0BSD
// Included in lake_volume.cpp inside terraforest. Uses the bake's density field;
// only packed final geometry survives publication, never the 3D sampling scratch.
Array NativeLakeVolume::build_smooth_surface() const {
    const int width=size_.x,depth=size_.z,stride=width+1;
    const float fy=(level_-origin_.y)/spacing_;
    const int y=int(std::ceil(fy))-1;
    const float blend=fy-y;
    std::vector<float> field(size_t(stride)*(depth+1));
    for(int z=0;z<=depth;++z)for(int x=0;x<=width;++x)
        field[x+stride*z]=density_[node(x,y,z)]*(1-blend)+density_[node(x,y+1,z)]*blend;
    const int offsets[2][3][2]={{{0,0},{1,0},{1,1}},{{0,0},{1,1},{0,1}}};
    std::vector<uint8_t> reached(size_t(width)*depth*2,0),full(size_t(width)*depth,0);
    std::vector<int> queue;queue.reserve(reached.size());
    auto admit=[&](int id){if(!reached[id]){reached[id]=1;queue.push_back(id);}};
    for(int z=0;z<depth;++z)for(int x=0;x<width;++x)
        if(wet_[index(x,y,z)]){admit(2*(x+width*z));admit(2*(x+width*z)+1);}
    for(size_t head=0;head<queue.size();++head){
        const int id=queue[head],t=id%2,x=(id/2)%width,z=(id/2)/width;
        for(int e=0;e<3;++e){
            const auto &a=offsets[t][e],&b=offsets[t][(e+1)%3];
            if(field[x+a[0]+stride*(z+a[1])]<=0&&field[x+b[0]+stride*(z+b[1])]<=0)continue;
            int nx=x,nz=z,nt=1-t;
            if(t==0&&e==0)--nz;else if(t==0&&e==1)++nx;
            else if(t==1&&e==1)++nz;else if(t==1&&e==2)--nx;
            // A sub-voxel opening can disagree with conservative volume fill.
            // Preserve the original contained surface instead of drawing a leak.
            if(nx<0||nz<0||nx>=width||nz>=depth)return surface_arrays();
            admit(2*(nx+width*nz)+nt);
        }
    }
    Array arrays;arrays.resize(Mesh::ARRAY_MAX);
    PackedVector3Array vertices,normals;PackedVector2Array uv;PackedInt32Array indices;
    auto polygon=[&](const Vector2 *points,int count){
        const int base=int(vertices.size());
        for(int i=0;i<count;++i){
            Vector3 p(origin_.x+points[i].x*spacing_,level_,origin_.z+points[i].y*spacing_);
            vertices.push_back(p);normals.push_back(Vector3(0,1,0));uv.push_back(Vector2(p.x,p.z));
        }
        for(int i=1;i+1<count;++i){
            // Exact zero crossings at lattice vertices can repeat a corner.
            if(std::abs((points[i]-points[0]).cross(points[i+1]-points[0]))<1e-8f)continue;
            indices.push_back(base);indices.push_back(base+i);indices.push_back(base+i+1);
        }
    };
    for(int z=0;z<depth;++z)for(int x=0;x<width;++x){
        const int id=2*(x+width*z);
        full[x+width*z]=reached[id]&&reached[id+1]&&field[x+stride*z]>0&&field[x+1+stride*z]>0&&field[x+stride*(z+1)]>0&&field[x+1+stride*(z+1)]>0;
        if(full[x+width*z])continue;
        for(int t=0;t<2;++t){
            if(!reached[id+t])continue;
            Vector2 clipped[6];int count=0;
            for(int e=0;e<3;++e){
                const auto &a=offsets[t][e],&b=offsets[t][(e+1)%3];
                Vector2 pa(x+a[0],z+a[1]),pb(x+b[0],z+b[1]);
                float da=field[x+a[0]+stride*(z+a[1])],db=field[x+b[0]+stride*(z+b[1])];
                if(da>0)clipped[count++]=pa;
                if((da>0)!=(db>0))clipped[count++]=pa+(pb-pa)*(da/(da-db));
            }
            if(count>=3)polygon(clipped,count);
        }
    }
    // Large fully wet interiors still collapse into rectangles.
    for(int z=0;z<depth;++z)for(int x=0;x<width;++x){
        if(!full[x+width*z])continue;
        int end_x=x+1,end_z=z+1;
        while(end_x<width&&full[end_x+width*z])++end_x;
        while(end_z<depth){bool complete=true;for(int j=x;j<end_x;++j)if(!full[j+width*end_z]){complete=false;break;}if(!complete)break;++end_z;}
        for(int k=z;k<end_z;++k)std::fill(full.begin()+x+width*k,full.begin()+end_x+width*k,0);
        Vector2 points[4]={Vector2(x,z),Vector2(end_x,z),Vector2(end_x,end_z),Vector2(x,end_z)};polygon(points,4);
    }
    arrays[Mesh::ARRAY_VERTEX]=vertices;arrays[Mesh::ARRAY_NORMAL]=normals;
    arrays[Mesh::ARRAY_TEX_UV]=uv;arrays[Mesh::ARRAY_INDEX]=indices;return arrays;
}
