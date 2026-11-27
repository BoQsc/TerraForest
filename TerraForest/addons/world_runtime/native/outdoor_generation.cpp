// SPDX-License-Identifier: 0BSD
// Native generation job. Scene scripts provide owners and poll completion only.
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/resource_loader.hpp>
#include <godot_cpp/classes/random_number_generator.hpp>
#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/classes/marshalls.hpp>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/object.hpp>
#include <godot_cpp/core/gdextension_interface_loader.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <algorithm>
#include <array>
#include <cmath>
#include <map>
#include <vector>

using namespace godot;
namespace terraforest {
class NativeOutdoorGeneration : public RefCounted {
    GDCLASS(NativeOutdoorGeneration,RefCounted)
    static constexpr int ATTEMPTS=48,TARGET=16,LIMIT=4096;
    static constexpr std::array<int,13> ITEMS={828,827,822,823,824,825,821,826,829,798,799,736,735};
    struct Road {Vector3 a,b; double half_width;};
    struct Model {String key;Ref<Mesh> mesh;AABB bounds;uint64_t owner=0;};
    struct Lot {AABB bounds;Vector3i origin;int rotation;String label;};
    struct Candidate {int model;Transform3D pose;AABB bounds;Vector3 ground;bool valid=false,supported=false;};
    struct Trees {PackedVector3Array points;PackedInt64Array ids;};
    std::vector<Road> roads;
    std::array<std::vector<int>,1024> road_bins;
    std::vector<int> broad_roads;
    struct Placement {int model;int64_t id;Transform3D pose;int lot;};
    std::vector<Placement> placements;
    std::vector<Lot> lots;
    std::array<Model,13> assets;
    std::vector<uint64_t> collections;
    std::vector<AABB> protected_bounds,support_bounds;
    std::vector<Candidate> candidates_;
    std::vector<int> support_indices;
    std::vector<Vector2i> spans;
    std::map<int,Trees> trees;
    Ref<RefCounted> scatter,harvest,water,fleet;
    uint64_t game_id=0,terrain_id=0,blocks_id=0;
    int64_t seed=0,tree_seed=0,token=0,epoch=0,density_revision=0,surface_revision=0;
    double tree_density=0;
    int biome=0,lot_index=0,support_cursor=0,skipped=0,requests=0,samples=0;
    enum Phase {IDLE,LOT,SURFACE,SUPPORT,DENSITY,INSERT,DONE};
    Phase phase=IDLE;
    bool sent=false,received=false,failed=false,support_only=false,attempted=false;
    uint64_t deadline=0,started=0,wait_started=0;
    std::array<uint64_t,6> timing{}; // candidates, surface wait, filters, support, density wait, insertion
    PackedVector3Array points,positions,normals;
    PackedFloat32Array densities;
    Dictionary result;
    static uint64_t now(){return Time::get_singleton()->get_ticks_usec();}
    Object *terrain() const{return ObjectDB::get_instance(terrain_id);}
    static Object *member(Object *owner,const char *name){return owner?static_cast<Object*>(owner->get(name)):nullptr;}
    static bool positive_box(const AABB &box){return box.position.is_finite()&&box.size.is_finite()&&box.size.x>0&&box.size.y>0&&box.size.z>0;}
    void disconnect(){
        if(auto *owner=terrain()){
            const Callable surface=callable_mp(this,&NativeOutdoorGeneration::on_surface),density=callable_mp(this,&NativeOutdoorGeneration::on_density);
            if(owner->has_signal("surface_batch_ready")&&owner->is_connected("surface_batch_ready",surface))owner->disconnect("surface_batch_ready",surface);
            if(owner->is_connected("density_batch_ready",density))owner->disconnect("density_batch_ready",density);
        }
    }
    void fail(const String &reason){disconnect();phase=DONE;result.clear();result["ok"]=false;result["reason"]=reason;}
    bool stable() const {
        auto *owner=terrain();
        return owner&&!bool(owner->get("stopping"))&&int64_t(owner->get("epoch"))==epoch&&int64_t(owner->get("density_revision"))==density_revision;
    }
    static bool road_contact(const Road &road,Vector3 point,double margin){
        const Vector2 delta(road.b.x-road.a.x,road.b.z-road.a.z),offset(point.x-road.a.x,point.z-road.a.z);
        const double t=std::clamp(double(offset.dot(delta))/std::max(.0001,double(delta.length_squared())),0.0,1.0);
        return (offset-delta*real_t(t)).length()<road.half_width+margin;
    }
    bool near_road(Vector3 point,double margin) const {
        const int x=int(std::floor(point.x/64)),z=int(std::floor(point.z/64));
        if(margin>16||x<0||x>=32||z<0||z>=32){for(const auto &road:roads)if(road_contact(road,point,margin))return true;return false;}
        for(int index:road_bins[z*32+x])if(road_contact(roads[index],point,margin))return true;
        for(int index:broad_roads)if(road_contact(roads[index],point,margin))return true;
        return false;
    }
    bool load_roads(const Array &input){
        if(input.size()>16384)return false;
        roads.clear();roads.reserve(input.size());broad_roads.clear();for(auto &bin:road_bins)bin.clear();
        for(int i=0;i<input.size();i++){
            if(input[i].get_type()!=Variant::DICTIONARY)return false;
            const Dictionary row=input[i];const Vector3 missing(INFINITY,INFINITY,INFINITY);
            const Vector3 a=row.get("a",row.get("start",missing)),b=row.get("b",row.get("finish",missing));
            if(!a.is_finite()||!b.is_finite())continue;
            const double width=row.get("width",double(row.get("half_width",4.0))*2.0);
            if(!std::isfinite(width))return false;
            const int index=roads.size();roads.push_back({a,b,width*.5});
            const double radius=std::max(0.0,width*.5+16.0);
            const int x0=int(std::clamp(std::floor((std::min(a.x,b.x)-radius)/64),0.0,31.0)),x1=int(std::clamp(std::floor((std::max(a.x,b.x)+radius)/64),0.0,31.0));
            const int z0=int(std::clamp(std::floor((std::min(a.z,b.z)-radius)/64),0.0,31.0)),z1=int(std::clamp(std::floor((std::max(a.z,b.z)+radius)/64),0.0,31.0));
            // Long/wide corridors stay once in the broad list, bounding duplication.
            if((x1-x0+1)*(z1-z0+1)>256)broad_roads.push_back(index);
            else for(int z=z0;z<=z1;z++)for(int x=x0;x<=x1;x++)road_bins[z*32+x].push_back(index);
        }
        return true;
    }
    bool load_assets(const Dictionary &catalog,const Dictionary &models){
        for(int i=0;i<int(ITEMS.size());i++){
            if(!catalog.has(ITEMS[i]))return false;
            const Dictionary row=catalog[ITEMS[i]];
            auto &asset=assets[i];asset.key=row.get("key",String());
            asset.mesh=ResourceLoader::get_singleton()->load(String(row.get("directory",String()))+"/models/"+String(row.get("id",String()))+".tres");
            if(asset.mesh.is_null())return false;
            asset.bounds=asset.mesh->get_aabb();const Array parts=asset.mesh->get_meta("collision_boxes",Array());
            if(parts.is_empty()||parts.size()>64)return false;
            for(int j=0;j<parts.size();j++){
                if(parts[j].get_type()!=Variant::AABB||!positive_box(parts[j]))return false;
                asset.bounds=asset.bounds.merge(parts[j]);
            }
            if(!positive_box(asset.bounds))return false;
            Object *owner=models.get(asset.key,Variant());asset.owner=owner?owner->get_instance_id():0;
        }
        return true;
    }
    static bool load_lot(const Dictionary &input,Lot &lot){
        Object *asset=input.get("asset",Variant());
        if(!asset||!input.has("origin")||!input.has("rotation"))return false;
        lot.bounds=asset->call("placement_bounds",Vector3i(),0);lot.origin=input["origin"];lot.rotation=input["rotation"];
        lot.label=input.get("label",String("Building"));
        return positive_box(lot.bounds)&&lot.rotation>=0&&lot.rotation<4;
    }
    static Basis yaw_basis(double angle){
        // Use the engine's native constructor (pinned Basis constructor 3 ABI).
        // Independently compiled libm sin/cos can differ by one float ULP, which
        // would change saved placement bytes despite visually identical poses.
        static const auto construct=gdextension_interface::variant_get_ptr_constructor(GDEXTENSION_VARIANT_TYPE_BASIS,3);
        const Vector3 axis(0,1,0);const GDExtensionConstTypePtr arguments[]={&axis,&angle};
        Basis out;construct(&out,arguments);return out;
    }
    void make_candidates(const Lot &lot){
        candidates_.clear();points.clear();
        const Basis rotation=yaw_basis(-lot.rotation*3.14159265358979323846*.5);const Vector3 half(.5,0,.5);
        const Transform3D frame(rotation,Vector3(lot.origin)+half-rotation.xform(half));
        Ref<RandomNumberGenerator> random;random.instantiate();
        random->set_seed(uint64_t(seed^(int64_t(lot.origin.x)*73856093)^(int64_t(lot.origin.z)*19349663)));
        for(int i=0;i<ATTEMPTS;i++){
            Vector3 point=lot.bounds.get_center();const int side=i%3;
            const double amount=random->randf_range(.1,.85),distance=random->randf_range(1.2,3.8);
            const Vector3 end=lot.bounds.get_end();
            if(side==0){point.x=double(lot.bounds.position.x)-distance;point.z=double(lot.bounds.position.z)+(double(end.z)-lot.bounds.position.z)*amount;}
            else if(side==1){point.x=double(end.x)+distance;point.z=double(lot.bounds.position.z)+(double(end.z)-lot.bounds.position.z)*amount;}
            else {point.z=double(lot.bounds.position.z)-distance;point.x=double(lot.bounds.position.x)+(double(end.x)-lot.bounds.position.x)*amount;}
            point=frame.xform(point);
            if(point.x<5||point.z<5||point.x>1995||point.z>1995||near_road(point,2))continue;
            Candidate candidate;candidate.model=i%ITEMS.size();candidate.pose=Transform3D(yaw_basis(double(random->randf())*6.28318530717958647692),point);
            candidates_.push_back(candidate);points.push_back(point);
        }
    }
    static PackedVector3Array probes(const AABB &box){
        PackedVector3Array out;
        if(!positive_box(box))return out;
        const double columns_value=std::max(1.0,std::ceil(double(box.size.x)/.35)),rows_value=std::max(1.0,std::ceil(double(box.size.z)/.35));
        if(columns_value>LIMIT||rows_value>LIMIT||(columns_value+1)*(rows_value+1)*2>LIMIT)return out;
        const int columns=int(columns_value),rows=int(rows_value);out.resize((columns+1)*(rows+1)*2);
        const Vector3 end=box.get_end();int at=0;
        for(int x=0;x<=columns;x++)for(int z=0;z<=rows;z++){
            const double ax=double(box.position.x)+.002,bx=double(end.x)-.002,az=double(box.position.z)+.002,bz=double(end.z)-.002;
            const Vector3 point(ax+(bx-ax)*(double(x)/columns),box.position.y,az+(bz-az)*(double(z)/rows));
            out.set(at++,point-Vector3(0,1,0)*real_t(.04));out.set(at++,point+Vector3(0,1,0)*real_t(.04));
        }
        return out;
    }
    bool tree_blocked(const AABB &bounds){
        const auto center=bounds.get_center();const int cell_x=int(std::floor(center.x/64)),cell_z=int(std::floor(center.z/64));
        const Rect2 footprint=Rect2(Vector2(bounds.position.x,bounds.position.z),Vector2(bounds.size.x,bounds.size.z)).grow(.8);
        for(int z=std::max(0,cell_z-1);z<=std::min(31,cell_z+1);z++)for(int x=std::max(0,cell_x-1);x<=std::min(31,cell_x+1);x++){
            const int key=z*32+x;
            auto found=trees.find(key);
            if(found==trees.end()){
                const Dictionary data=scatter->call("candidates",Vector2i(x,z),tree_seed,tree_density,true,biome);
                Trees row;row.points=data.get("points",PackedVector3Array());row.ids=data.get("ids",PackedInt64Array());
                if(row.points.size()!=row.ids.size()||row.points.size()>4096){failed=true;return true;}
                found=trees.emplace(key,std::move(row)).first;
            }
            const auto &row=found->second;
            for(int i=0;i<row.points.size();i++){
                const Vector3 root=row.points[i];
                // Contains is read-only; avoid the native boundary for distant roots.
                if(footprint.has_point(Vector2(root.x,root.z))&&!bool(harvest->call("contains",row.ids[i])))return true;
            }
        }
        return false;
    }
    void prepare_candidates(){
        support_bounds.clear();support_indices.clear();support_cursor=0;
        for(int i=0;i<int(candidates_.size());i++){
            auto &entry=candidates_[i];const Vector3 point=positions[i];
            if(!point.is_finite()||normals[i].y<.96||double(water->call("depth_at",point))>.02)continue;
            const AABB prototype=assets[entry.model].bounds;entry.pose.origin=point-Vector3(0,1,0)*prototype.position.y;
            entry.bounds=entry.pose.xform(prototype);entry.ground=point;
            bool blocked=false;for(const auto &box:protected_bounds)if(box.intersects(entry.bounds.grow(.3))){blocked=true;break;}
            if(blocked||near_road(point,std::max(double(entry.bounds.size.x),double(entry.bounds.size.z))*.5+1.2)||tree_blocked(entry.bounds))continue;
            entry.valid=true;support_bounds.push_back(entry.bounds);support_indices.push_back(i);
        }
    }
    bool clear(const AABB &bounds){
        TypedArray<Transform3D> query;query.push_back(Transform3D());
        auto *blocks=ObjectDB::get_instance(blocks_id);if(!blocks)return false;
        PackedByteArray mask=blocks->call("overlap_mask",query,bounds);
        if(mask.size()!=1||mask[0])return false;
        for(auto id:collections){
            auto *owner=ObjectDB::get_instance(id);if(!owner){failed=true;return false;}
            mask=owner->call("overlap_mask",query,bounds);if(mask.size()!=1||mask[0])return false;
        }
        return true;
    }
    void insert(){
        int inserted=0;
        for(const auto &entry:candidates_){
            if(inserted>=TARGET)break;
            if(!entry.valid){++skipped;continue;}
            if(!clear(entry.bounds.grow(.15))){++skipped;continue;}
            const Dictionary car=fleet->call("query_near",entry.ground,6,32,128);
            if(!bool(car.get("ok",false))||!bool(car.get("complete",false))||!PackedInt64Array(car.get("ids",PackedInt64Array())).is_empty()){++skipped;continue;}
            if(!entry.supported){++skipped;continue;}
            PackedFloat32Array packed;packed.resize(12);
            for(int row=0;row<3;row++){for(int column=0;column<3;column++)packed.set(row*4+column,entry.pose.basis[row][column]);packed.set(row*4+3,entry.pose.origin[row]);}
            auto *owner=ObjectDB::get_instance(assets[entry.model].owner);if(!owner){fail("Outdoor model owner disappeared");return;}
            const int64_t identity=owner->call("insert_instance",packed,AABB());
            if(identity<=0){fail("Outdoor object publication failed");return;}
            placements.push_back({entry.model,identity,entry.pose,lot_index});++inserted;
        }
    }
    void begin_wait(Phase next){phase=next;sent=false;received=false;failed=false;wait_started=now();deadline=wait_started+10000000;}
    void on_surface(int64_t id,const PackedVector3Array &p,const PackedVector3Array &n,int64_t e,int64_t r){
        if(phase!=SURFACE||id!=token)return;
        received=true;positions=p;normals=n;failed=e!=epoch||r!=surface_revision||p.size()!=points.size()||n.size()!=points.size();
    }
    void on_density(const Dictionary &data){
        if(phase!=DENSITY||int64_t(data.get("token",-1))!=token)return;
        received=true;densities=data.get("values",PackedFloat32Array());
        failed=String(data.get("status",String()))!="ok"||int64_t(data.get("epoch",-1))!=epoch||int64_t(data.get("revision",-1))!=density_revision||densities.size()!=points.size();
    }
    bool connect_owner(Object *owner,int64_t identity,bool only_support){
        if(phase!=IDLE||!owner||identity<1||!owner->has_signal("density_batch_ready")||(!only_support&&!owner->has_signal("surface_batch_ready")))return false;
        terrain_id=owner->get_instance_id();token=identity;epoch=owner->get("epoch");density_revision=owner->get("density_revision");
        if(!only_support)surface_revision=owner->get("published_revision");
        if(!only_support&&owner->connect("surface_batch_ready",callable_mp(this,&NativeOutdoorGeneration::on_surface))!=OK)return false;
        if(owner->connect("density_batch_ready",callable_mp(this,&NativeOutdoorGeneration::on_density))!=OK){disconnect();return false;}
        started=now();support_only=only_support;return true;
    }
    void finish(){
        disconnect();phase=DONE;result["ok"]=true;result["requests"]=requests;result["samples"]=samples;
        if(support_only){Array mask;for(const auto &entry:candidates_)mask.push_back(entry.supported);result["supported"]=mask;}
        else {
            Array diagnostic;
            for(const auto &entry:placements){
                PackedFloat32Array packed;packed.resize(12);
                for(int row=0;row<3;row++){for(int column=0;column<3;column++)packed.set(row*4+column,entry.pose.basis[row][column]);packed.set(row*4+3,entry.pose.origin[row]);}
                Dictionary row;row["model"]=assets[entry.model].key;row["id"]=entry.id;row["position"]=entry.pose.origin;
                row["transform"]=Marshalls::get_singleton()->raw_to_base64(packed.to_byte_array());row["lot"]=lots[entry.lot].label;diagnostic.push_back(row);
            }
            result["placements"]=diagnostic;result["skipped"]=skipped;result["target_per_lot"]=TARGET;result["density_requests"]=requests;result["density_samples"]=samples;if(!placements.empty()&&terrain())terrain()->set("changed_since_save",true);}
        Dictionary profile;const char *names[]={"candidates_us","surface_wait_us","filter_us","support_pack_us","density_wait_us","insertion_us"};
        for(int i=0;i<6;i++)profile[names[i]]=int64_t(timing[i]);profile["total_us"]=int64_t(now()-started);profile["implementation"]="native-v1";result["profile"]=profile;
    }
protected:
    static void _bind_methods(){
        ClassDB::bind_method(D_METHOD("start","game","lots","roads","seed","catalog","token"),&NativeOutdoorGeneration::start);
        ClassDB::bind_method(D_METHOD("start_support","terrain","bounds","token"),&NativeOutdoorGeneration::start_support);
        ClassDB::bind_method(D_METHOD("advance"),&NativeOutdoorGeneration::advance);
        ClassDB::bind_method(D_METHOD("get_result"),&NativeOutdoorGeneration::get_result);
        ClassDB::bind_method(D_METHOD("cancel"),&NativeOutdoorGeneration::cancel);
        ClassDB::bind_method(D_METHOD("propose","lot","seed","roads","catalog"),&NativeOutdoorGeneration::propose);
        ClassDB::bind_method(D_METHOD("support_probes","bounds"),&NativeOutdoorGeneration::support_probes);
    }
public:
    ~NativeOutdoorGeneration(){disconnect();}
    Dictionary get_result() const{return result;}
    void cancel(){if(phase!=DONE)fail("Outdoor generation cancelled");}
    PackedVector3Array support_probes(AABB bounds) const{return probes(bounds);}
    Array propose(const Dictionary &input,int64_t world_seed,const Array &input_roads,const Dictionary &catalog){
        Array output;Lot lot;if(phase!=IDLE||!load_lot(input,lot)||!load_roads(input_roads)||!load_assets(catalog,Dictionary()))return output;
        seed=world_seed;make_candidates(lot);
        for(const auto &entry:candidates_){Dictionary row;row["item"]=ITEMS[entry.model];row["model"]=assets[entry.model].key;row["pose"]=entry.pose;row["mesh"]=assets[entry.model].mesh;output.push_back(row);}
        return output;
    }
    bool start(Object *game,const Array &input_lots,const Array &input_roads,int64_t world_seed,const Dictionary &catalog,int64_t identity){
        if(phase!=IDLE||attempted||!game||input_lots.size()>256||world_seed<0||world_seed>0x7fffffff||!load_roads(input_roads))return false;
        attempted=true;
        auto *structure=member(game,"structures"),*eco=member(game,"ecosystem"),*lake=member(game,"lakes"),*vehicle=member(game,"world_vehicle"),*quests=member(game,"quests");
        if(!structure||!eco||!lake||!vehicle||!quests)return false;
        Object *blocks=member(structure,"blocks"),*quest_store=member(quests,"store");
        if(!blocks||!quest_store)return false;
        const Dictionary models=structure->call("model_collections");
        if(models.size()>256||!load_assets(catalog,models))return false;
        for(const auto &asset:assets)if(!asset.owner)return false;
        const Array values=models.values();for(int i=0;i<values.size();i++){Object *owner=values[i];if(!owner)return false;collections.push_back(owner->get_instance_id());}
        scatter=Ref<RefCounted>(Object::cast_to<RefCounted>(static_cast<Object*>(eco->call("_scatter"))));harvest=Ref<RefCounted>(Object::cast_to<RefCounted>(member(eco,"harvest_state")));
        water=Ref<RefCounted>(Object::cast_to<RefCounted>(member(lake,"water")));fleet=Ref<RefCounted>(Object::cast_to<RefCounted>(member(vehicle,"fleet")));
        if(scatter.is_null()||harvest.is_null()||water.is_null()||fleet.is_null())return false;
        auto *backend=member(member(game,"terrain"),"backend");if(!backend)return false;tree_seed=backend->get("world_seed");
        tree_density=eco->get("density");biome=eco->get("biome_profile");seed=world_seed;
        protected_bounds.push_back(AABB(Vector3(game->get("_initial_generation_spawn"))-Vector3(2,0,2),Vector3(4,3,4)));
        const Array locations=quest_store->call("get_locations");if(locations.size()>4096)return false;
        for(int i=0;i<locations.size();i++){const Dictionary row=locations[i];protected_bounds.push_back(row["bounds"]);}
        for(int i=0;i<input_lots.size();i++){if(input_lots[i].get_type()!=Variant::DICTIONARY)return false;Lot lot;if(!load_lot(input_lots[i],lot))return false;lots.push_back(lot);}
        if(!connect_owner(member(game,"terrain"),identity,false))return false;
        game_id=game->get_instance_id();blocks_id=blocks->get_instance_id();phase=LOT;return true;
    }
    bool start_support(Object *owner,const TypedArray<AABB> &input,int64_t identity){
        if(attempted||input.size()>4096)return false;attempted=true;
        if(!connect_owner(owner,identity,true))return false;
        for(int i=0;i<input.size();i++){support_bounds.push_back(input[i]);support_indices.push_back(i);candidates_.push_back(Candidate());}
        phase=SUPPORT;return true;
    }
    bool advance(){
        const uint64_t began=now();
        // Continue dependent native work immediately; yield only for an actual
        // asynchronous reply or the owner-thread quantum, never once per object.
        for(int step=0;step<512;step++){
            if(advance_one())return true;
            if(phase==SURFACE||phase==DENSITY||now()-began>=4000)return false;
        }
        return false;
    }
    bool advance_one(){
        if(phase==DONE)return true;
        if(phase==IDLE){fail("Outdoor generation not started");return true;}
        if(!stable()){fail("Outdoor terrain survey changed or stopped");return true;}
        if(!support_only){auto *game=ObjectDB::get_instance(game_id);if(!game||bool(game->get("shutdown_requested"))){cancel();return true;}}
        const uint64_t began=now();
        if(phase==LOT){
            if(lot_index==int(lots.size())){finish();return true;}
            if(placements.size()+TARGET>LIMIT){fail("Outdoor generation exceeds its 4096-object authoring budget");return true;}
            make_candidates(lots[lot_index]);timing[0]+=now()-began;
            if(candidates_.empty()){++lot_index;return false;}
            begin_wait(SURFACE);
        }
        if(phase==SURFACE||phase==DENSITY){
            const bool surface=phase==SURFACE;
            if(!sent)sent=surface?bool(terrain()->call("request_surface_batch",points,token)):bool(terrain()->call("request_density_scan",points,token,0,true));
            if(!received){if(now()>=deadline){fail("Outdoor terrain survey timed out");return true;}return false;}
            timing[surface?1:4]+=now()-wait_started;
            if(failed||!stable()){fail("Outdoor terrain survey unavailable");return true;}
            const uint64_t work=now();
            if(surface){prepare_candidates();timing[2]+=now()-work;if(failed){fail("Outdoor tree survey unavailable");return true;}phase=SUPPORT;}
            else {
                for(const auto &span:spans){bool valid=true;for(int i=0;i<span.y;i++){const float value=densities[span.x+i];if(!std::isfinite(value)||((value<0)!=(i%2==0))){valid=false;break;}}
                    const int index=support_indices[support_cursor-int(spans.size())+(&span-spans.data())];candidates_[index].supported=valid;
                }
                timing[3]+=now()-work;phase=SUPPORT;
            }
        }
        if(phase==SUPPORT){
            if(support_cursor<int(support_bounds.size())){
                const uint64_t work=now();points.clear();spans.clear();
                while(support_cursor<int(support_bounds.size())){
                    const auto part=probes(support_bounds[support_cursor]);if(part.is_empty()){fail("Outdoor support footprint exceeds sample budget");return true;}
                    if(points.size()+part.size()>LIMIT)break;
                    spans.push_back(Vector2i(points.size(),part.size()));points.append_array(part);++support_cursor;
                }
                ++requests;samples+=points.size();timing[3]+=now()-work;begin_wait(DENSITY);sent=bool(terrain()->call("request_density_scan",points,token,0,true));return false;
            }
            if(support_only){finish();return true;}phase=INSERT;
        }
        if(phase==INSERT){const uint64_t work=now();insert();timing[5]+=now()-work;if(phase==DONE)return true;if(failed){fail("Outdoor owner disappeared");return true;}++lot_index;phase=LOT;}
        return false;
    }
};
void register_outdoor_generation(){GDREGISTER_CLASS(NativeOutdoorGeneration);}
}
