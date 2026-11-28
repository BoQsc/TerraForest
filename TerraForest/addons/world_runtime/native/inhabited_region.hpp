// SPDX-License-Identifier: 0BSD
#pragma once
#include <godot_cpp/classes/resource.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/vector3.hpp>

namespace terraforest {
// Seed-derived district roles are shared by preview, cold planning and cache
// hydration. Existing immutable prefab definitions remain the reusable units.
inline godot::Dictionary inhabited_layout(int64_t seed) {
    using namespace godot;
    if(seed<0||seed>0x7fffffff)return {};
    const char *titles[]={"Alderwick civic quarter","Alderwick works quarter","Alderwick residential quarter","Westhaven coastal town","Ironford industrial town","Highmeadow farming community","Pinecross woodland village","Moorfield lakeside hamlet","Southwatch rural village"};
    const char *roles[]={"city_civic","city_industry","city_housing","coastal_town","industrial_town","farming_community","woodland_village","lakeside_hamlet","rural_village"};
    const Vector3 base[]={{850,0,950},{1170,0,950},{1010,0,1270},{300,0,330},{1630,0,1600},{1650,0,350},{330,0,1640},{300,0,1000},{1670,0,950}};
    Array hints,names,purposes,offsets;PackedInt32Array parts;
    uint32_t state=uint32_t(seed)^0xb29c731du;
    auto jitter=[&](){state=state*1664525u+1013904223u;return int((state>>16)%97)-48;};
    const Vector3 city_shift(jitter(),0,jitter());
    for(int i=0;i<9;i++){
        hints.append(base[i]+(i<3?city_shift:Vector3(jitter(),0,jitter())));
        names.append(titles[i]);purposes.append(roles[i]);parts.push_back(i<5?4:1);
    }
    offsets.append(Vector3());offsets.append(base[1]-base[0]);offsets.append(base[2]-base[0]);
    Dictionary out;out["hints"]=hints;out["titles"]=names;out["roles"]=purposes;out["parts"]=parts;out["city_offsets"]=offsets;out["seed"]=seed;return out;
}
inline godot::Array inhabited_assets(int district,const godot::Array &market,const godot::Array &city) {
    using namespace godot;
    if(district<3||district>8||market.size()!=8||city.size()!=12)return {};
    Array out;
    if(district<5){
        for(int i=0;i<8;i++)out.append(market[i]);
        const int coastal[]={1,3,5,6},industrial[]={4,2,1,3};
        for(int i=0;i<4;i++)out.append(city[district==3?coastal[i]:industrial[i]]);
        for(int index:{3,4,6,7})out.append(market[index]);
    }else{
        const int choices[4][4]={{0,3,4,2},{3,7,2,1},{0,1,3,6},{3,4,5,7}};
        for(int index:choices[district-5])out.append(market[index]);
    }
    return out;
}
inline godot::Array inhabited_asset_recipe(const godot::Array &assets) {
    using namespace godot;
    if(assets.size()>16)return {};
    Array out;
    for(int i=0;i<assets.size();i++){
        Ref<Resource> asset=assets[i];if(asset.is_null())return {};
        Dictionary lot;lot["asset"]=asset;lot["label"]=asset->get_name();out.append(lot);
    }
    return out;
}
inline godot::Dictionary inhabited_audit(const godot::Array &sites,const godot::Array &bridges) {
    using namespace godot;
    Dictionary out;out["ok"]=false;
    if(sites.size()!=9||bridges.size()>16)return out;
    int city=0,towns=0,villages=0,large=0,small=0;Vector3 centers[9];
    for(int i=0;i<9;i++){
        if(sites[i].get_type()!=Variant::DICTIONARY)return out;Dictionary site=sites[i];
        if(site.get("center",Variant()).get_type()!=Variant::VECTOR3||site.get("lots",Variant()).get_type()!=Variant::ARRAY)return out;
        centers[i]=site["center"];if(!centers[i].is_finite())return out;Array lots=site["lots"];
        if(i<3){if(lots.size()!=12)return out;city+=lots.size();}
        else if(i<5){if(lots.size()!=16)return out;++towns;}
        else{if(lots.size()!=4)return out;++villages;}
    }
    for(int i=0;i<bridges.size();i++){
        if(bridges[i].get_type()!=Variant::DICTIONARY)return out;Dictionary bridge=bridges[i];
        if(int(bridge.get("span",0))>=32)++large;
        else if(String(bridge.get("kind",""))=="small")++small;
    }
    const double separation=centers[3].distance_to(centers[4]);
    const bool coherent=centers[0].distance_to(centers[1])<=750&&centers[0].distance_to(centers[2])<=750;
    out["city_buildings"]=city;out["towns"]=towns;out["smaller_communities"]=villages;
    out["town_separation_m"]=separation;out["large_bridges"]=large;out["small_bridges"]=small;
    out["ok"]=coherent&&separation>=900&&large>=2&&small>=1;
    return out;
}
}
