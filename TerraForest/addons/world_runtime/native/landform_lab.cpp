// SPDX-License-Identifier: 0BSD
#include "landform_program.hpp"
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/array_mesh.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <chrono>
#include <queue>
using namespace godot;
namespace terraforest {
class NativeLandformLab:public RefCounted {
 GDCLASS(NativeLandformLab,RefCounted)
 using Clock=std::chrono::steady_clock;
 static double ms(Clock::time_point start){return std::chrono::duration<double,std::milli>(Clock::now()-start).count();}
 static Dictionary failure(const String&reason){Dictionary d;d["ok"]=false;d["reason"]=reason;return d;}
 static bool number(const Variant &v,double &out){if(v.get_type()!=Variant::FLOAT&&v.get_type()!=Variant::INT)return false;out=double(v);return std::isfinite(out);}
 static bool field(const Dictionary&d,const char*key,double &out,double fallback){return d.has(key)?number(d[key],out):(out=fallback,true);}
 static bool keys(const Dictionary&d,const char*allowed){Array names=d.keys();String list=String("|")+allowed+"|";for(int i=0;i<names.size();i++)if(names[i].get_type()!=Variant::STRING||!list.contains(String("|")+String(names[i])+"|"))return false;return true;}
protected:
 static void _bind_methods(){
  ClassDB::bind_method(D_METHOD("compile","library","case_id","seed_override"),&NativeLandformLab::compile,DEFVAL(-1));
  ClassDB::bind_method(D_METHOD("validate","program"),&NativeLandformLab::validate);
  ClassDB::bind_method(D_METHOD("raster","program","size","meshes"),&NativeLandformLab::raster,DEFVAL(false));
 }
public:
 Dictionary compile(const Dictionary&library,const String&case_id,int64_t seed_override)const{
  auto start=Clock::now();using namespace landforms;
  if(String(library.get("schema",""))!="terraforest.landform-library.v1"||library.get("modules",Variant()).get_type()!=Variant::DICTIONARY||library.get("cases",Variant()).get_type()!=Variant::ARRAY)return failure("Invalid landform library schema");
  Dictionary modules=library["modules"],selected;Array cases=library["cases"];if(cases.size()>16||modules.size()>64)return failure("Library limit exceeded");
  for(int i=0;i<cases.size();i++){if(cases[i].get_type()!=Variant::DICTIONARY)return failure("Invalid case");Dictionary row=cases[i];if(String(row.get("id",""))==case_id){if(!selected.is_empty())return failure("Duplicate case identity");selected=row;}}
  if(selected.is_empty()||!keys(selected,"id|title|intent|seed|extent|base_height|sea_level|instances")||selected.get("instances",Variant()).get_type()!=Variant::ARRAY)return failure("Unknown or malformed case");
  double seed,extent,base,sea;if(!field(selected,"seed",seed,1703)||!field(selected,"extent",extent,768)||!field(selected,"base_height",base,64)||!field(selected,"sea_level",sea,40))return failure("Invalid case numbers");
  if(seed_override!=-1)seed=double(seed_override);if(seed<0||seed>2147483647||std::floor(seed)!=seed||extent<256||extent>2000)return failure("Invalid seed or extent");
  Program program;program.seed=uint32_t(seed);program.extent=float(extent);program.base=float(base);program.sea=float(sea);
  Array instances=selected["instances"];if(instances.is_empty()||instances.size()>MAX_FEATURES)return failure("At most 32 reusable instances are supported");
  const char *kinds[]={"coast","ridge","lake","island","woodland","clearing"};
  for(int i=0;i<instances.size();i++){
   if(instances[i].get_type()!=Variant::DICTIONARY)return failure("Invalid instance");Dictionary instance=instances[i];
   if(!keys(instance,"module|translation|rotation_degrees|scale")||instance.get("module",Variant()).get_type()!=Variant::STRING||instance.get("translation",Variant()).get_type()!=Variant::ARRAY)return failure("Invalid instance fields");
   String name=instance["module"];if(!modules.has(name)||modules[name].get_type()!=Variant::DICTIONARY)return failure("Missing reusable module: "+name);
   Dictionary module=modules[name];if(!keys(module,"kind|level|depth|bank|variation|closed|paths")||module.get("paths",Variant()).get_type()!=Variant::ARRAY)return failure("Invalid module fields: "+name);
   int kind=-1;for(int j=0;j<6;j++)if(String(module.get("kind",""))==kinds[j])kind=j;if(kind<0)return failure("Unknown module kind");
   Array translate=instance["translation"];double tx,tz,rotation,scale,level,depth,bank,variation;
   if(translate.size()!=2||!number(translate[0],tx)||!number(translate[1],tz)||!field(instance,"rotation_degrees",rotation,0)||!field(instance,"scale",scale,1)||scale<.1||scale>4||std::abs(rotation)>360||!field(module,"level",level,base)||!field(module,"depth",depth,0)||!field(module,"bank",bank,24)||!field(module,"variation",variation,0))return failure("Invalid module transform or parameters");
   bool closed=module.get("closed",false);if(module.has("closed")&&module["closed"].get_type()!=Variant::BOOL)return failure("closed must be boolean");
   if(kind==COAST&&!closed)return failure("Coasts must be closed");
   Array paths=module["paths"];if(paths.is_empty()||paths.size()>8)return failure("Invalid path count");
   for(int path_index=0;path_index<paths.size();path_index++){
    if(paths[path_index].get_type()!=Variant::ARRAY)return failure("Invalid guide path");Array path=paths[path_index];
    if(path.size()<(closed?4:2)||path.size()>32)return failure("Guide paths need 2..32 knots (4 for a coast)");std::vector<Point> knots;
    double angle=rotation*3.141592653589793/180,c=std::cos(angle),s=std::sin(angle);
    for(int j=0;j<path.size();j++){if(path[j].get_type()!=Variant::ARRAY)return failure("Invalid knot");Array p=path[j];double x,z,w;if(p.size()!=3||!number(p[0],x)||!number(p[1],z)||!number(p[2],w)||w<=0)return failure("Knots are [x,z,half_width]");knots.push_back({float(tx+scale*(x*c-z*s)),float(tz+scale*(x*s+z*c)),float(w*scale)});}
    int count=int(knots.size());auto point=[&](int k){return knots[closed?(k+count)%count:std::clamp(k,0,count-1)];};
    for(int j=0;j<(closed?count:count-1);j++){
     Point previous=point(j);
     for(int step=1;step<=8;step++){
      Point next=step==8?point(j+1):curve(point(j-1),point(j),point(j+1),point(j+2),float(step)/8);
      if(program.segments.size()>=MAX_SEGMENTS)return failure("Compiled segment budget exceeded");
      program.segments.push_back({uint32_t(kind),uint32_t(i),previous,next,float(level),float(depth),float(bank*scale),float(variation)});previous=next;
     }
    }
   }
  }
  auto raw=program.encode();if(raw.empty())return failure("Module geometry violates the bounded program contract");PackedByteArray bytes;bytes.resize(raw.size());std::memcpy(bytes.ptrw(),raw.data(),raw.size());
  Dictionary out;out["ok"]=true;out["program"]=bytes;out["compile_ms"]=ms(start);out["segments"]=int(program.segments.size());out["instances"]=instances.size();return out;
 }
 bool validate(const PackedByteArray&bytes)const{landforms::Program p;return p.decode(bytes.ptr(),bytes.size());}
 Dictionary raster(const PackedByteArray&bytes,int size,bool meshes)const{
  auto start=Clock::now();landforms::Program p;if(!p.decode(bytes.ptr(),bytes.size()))return failure("Invalid compiled program");
  if(size!=65&&size!=129&&size!=257&&size!=513)return failure("Raster resolution must be 65, 129, 257 or 513");
  if(meshes&&size>257)return failure("Interactive mesh budget is 257 squared");
  int count=size*size;float step=p.extent/(size-1);std::vector<landforms::Sample> samples(count);
  for(int z=0;z<size;z++)for(int x=0;x<size;x++)samples[x+z*size]=p.sample(x*step,z*step);
  double sample_ms=ms(start);PackedByteArray pixels,ecology;pixels.resize(count*4);ecology.resize(count*4);auto*rgba=pixels.ptrw();auto*eco=ecology.ptrw();
  PackedFloat32Array heights,water,trees,grass;heights.resize(count);water.resize(count);trees.resize(count);grass.resize(count);
  PackedVector3Array vertices,normals;PackedColorArray colors; if(meshes){vertices.resize(count);normals.resize(count);colors.resize(count);}
  int wet=0,tree_cells=0,grass_cells=0,buildable=0,edges=0,coast_water=0;double slopes=0;
  std::vector<uint8_t> lake(count,0);float low=1e9f,high=-1e9f;
  for(int z=0;z<size;z++)for(int x=0;x<size;x++){
   int i=x+z*size;auto&s=samples[i];float dx=(samples[std::min(x+1,size-1)+z*size].height-samples[std::max(0,x-1)+z*size].height)/((x>0&&x<size-1?2:1)*step);
   float dz=(samples[x+std::min(z+1,size-1)*size].height-samples[x+std::max(0,z-1)*size].height)/((z>0&&z<size-1?2:1)*step);float slope=std::sqrt(dx*dx+dz*dz);slopes+=slope;
   s.grass*=1-landforms::smooth((slope-.35f)/.5f);s.trees*=1-landforms::smooth((slope-.45f)/.5f);
   low=std::min(low,s.height);high=std::max(high,s.height);lake[i]=s.water>p.sea+.01f;wet+=lake[i];coast_water+=s.water>0&&!lake[i];
   tree_cells+=s.trees>.5f;grass_cells+=s.grass>.3f;buildable+=s.water==0&&slope<.12f;
   if(lake[i]&&(x==0||z==0||x==size-1||z==size-1))edges++;
   heights.set(i,s.height);water.set(i,s.water);trees.set(i,s.trees);grass.set(i,s.grass);
   Vector3 n=Vector3(-dx,1,-dz).normalized();float light=.62f+.38f*std::max(0.f,float(n.dot(Vector3(-.45,.8,-.4).normalized())));
   Color color=s.water>0?Color(.10,.40,.53):s.height<p.sea+3?Color(.68,.61,.39):Color(.37,.48,.24).lerp(Color(.37,.36,.31),std::clamp((slope-.4f)*1.2f,0.f,1.f));
   if(!s.water)color=color.lerp(Color(.13,.29,.16),s.trees*.55f);color.r*=light;color.g*=light;color.b*=light;
   Color mask=s.water>0?Color(.08,.30,.52):Color(.80,.70,.35).lerp(Color(.08,.40,.20),s.trees);
   for(int j=0;j<3;j++){rgba[i*4+j]=uint8_t(std::clamp(color[j],0.f,1.f)*255+.5f);eco[i*4+j]=uint8_t(std::clamp(mask[j],0.f,1.f)*255+.5f);}rgba[i*4+3]=eco[i*4+3]=255;
   if(meshes){vertices.set(i,Vector3(x*step,s.height,z*step));normals.set(i,n);colors.set(i,color);}
  }
  int components=0,shore_edges=0;std::vector<uint8_t> visited(count,0);std::vector<int> queue;queue.reserve(count);
  for(int i=0;i<count;i++)if(lake[i]){
   int x=i%size,z=i/size;for(int k:{-1,1,-size,size}){int j=i+k;if(j<0||j>=count||(k==-1&&x==0)||(k==1&&x==size-1))continue;if(!lake[j])shore_edges++;}
   if(visited[i])continue;components++;queue.clear();queue.push_back(i);visited[i]=1;
   for(size_t q=0;q<queue.size();q++){int at=queue[q],cx=at%size;for(int k:{-1,1,-size,size}){int j=at+k;if(j<0||j>=count||(k==-1&&cx==0)||(k==1&&cx==size-1)||!lake[j]||visited[j])continue;visited[j]=1;queue.push_back(j);}}
  }
  Dictionary out,metrics;out["ok"]=true;out["size"]=size;out["extent"]=p.extent;out["pixels"]=pixels;out["ecology_pixels"]=ecology;out["heights"]=heights;out["water"]=water;out["trees"]=trees;out["grass"]=grass;
  metrics["sample_ms"]=sample_ms;metrics["lake_components"]=components;metrics["lake_area_m2"]=wet*step*step;metrics["shoreline_m"]=shore_edges*step;metrics["lake_boundary_cells"]=edges;metrics["sea_cells"]=coast_water;metrics["woodland_fraction"]=double(tree_cells)/count;metrics["grass_fraction"]=double(grass_cells)/count;metrics["buildable_fraction"]=double(buildable)/count;metrics["height_min"]=low;metrics["height_max"]=high;metrics["mean_slope"]=slopes/count;metrics["program_bytes"]=bytes.size();metrics["segments"]=int(p.segments.size());
  // Flood the actual sampled terrain at each lake level. A declared water mask
  // alone can conceal a basin that spills through low ground to the sea.
  int spills=0;std::vector<float> levels;
  for(const auto&s:p.segments)if(s.kind==landforms::LAKE&&std::find(levels.begin(),levels.end(),s.level)==levels.end())levels.push_back(s.level);
  for(float level:levels){
   std::fill(visited.begin(),visited.end(),0);
   for(int i=0;i<count;i++)if(!visited[i]&&lake[i]&&samples[i].water==level){
    bool escaped=false;queue.clear();queue.push_back(i);visited[i]=1;
    for(size_t q=0;q<queue.size();q++){
     int at=queue[q],x=at%size,z=at/size;if(x==0||z==0||x==size-1||z==size-1)escaped=true;
     for(int k:{-1,1,-size,size}){int j=at+k;if(j<0||j>=count||(k==-1&&x==0)||(k==1&&x==size-1)||visited[j]||samples[j].height>=level)continue;visited[j]=1;queue.push_back(j);}
    }
    if(escaped)spills++;
   }
  }
  metrics["spilling_lake_components"]=spills;
  if(meshes){
   PackedInt32Array indices;indices.resize((size-1)*(size-1)*6);int at=0;PackedVector3Array wv,wn;PackedColorArray wc;
   for(int z=0;z<size-1;z++)for(int x=0;x<size-1;x++){
    int a=x+z*size,b=a+1,c=a+size,d=c+1;for(int index:{a,b,c,b,d,c})indices.set(at++,index);
    float level=std::max({samples[a].water,samples[b].water,samples[c].water,samples[d].water});
    if(level>0)for(const auto&tri:std::array<std::array<int,3>,2>{{{a,b,c},{b,d,c}}}){
     Vector3 clipped[6];int kept=0;Vector3 previous=vertices[tri[2]];bool previous_inside=previous.y<level;
     for(int index:tri){Vector3 current=vertices[index];bool inside=current.y<level;
      if(inside!=previous_inside){float t=(level-previous.y)/(current.y-previous.y);clipped[kept++]=previous.lerp(current,t);}
      if(inside)clipped[kept++]=current;previous=current;previous_inside=inside;
     }
     for(int k=1;k+1<kept;k++)for(int index:{0,k,k+1}){Vector3 v=clipped[index];v.y=level+.04f;wv.append(v);wn.append(Vector3(0,1,0));wc.append(Color(.12,.43,.58));}
    }
   }
   Array arrays;arrays.resize(Mesh::ARRAY_MAX);arrays[Mesh::ARRAY_VERTEX]=vertices;arrays[Mesh::ARRAY_NORMAL]=normals;arrays[Mesh::ARRAY_COLOR]=colors;arrays[Mesh::ARRAY_INDEX]=indices;Ref<ArrayMesh> terrain;terrain.instantiate();terrain->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES,arrays);out["terrain_mesh"]=terrain;
   if(!wv.is_empty()){Array wa;wa.resize(Mesh::ARRAY_MAX);wa[Mesh::ARRAY_VERTEX]=wv;wa[Mesh::ARRAY_NORMAL]=wn;wa[Mesh::ARRAY_COLOR]=wc;Ref<ArrayMesh> surface;surface.instantiate();surface->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES,wa);out["water_mesh"]=surface;}
  }
  metrics["total_ms"]=ms(start);out["metrics"]=metrics;return out;
 }
};
void register_landform_lab(){GDREGISTER_CLASS(NativeLandformLab);}
}
