// SPDX-License-Identifier: 0BSD
#pragma once
#include "water_spill_hierarchy.hpp"
#include <array>

namespace terraforest {
// Equal volume curves connected at their common dry floor are one reservoir:
// no member can retain a millilitre behind that connection. Contract only
// these portals. Every other sill stays in the original spill hierarchy.
struct WaterColumnCurve {
    std::array<double,8> terms{};
    double bottom=-1;
};

struct WaterSingleColumn {unsigned operator()(int) const{return 1;}};
template<class Rooms,class Curve,class Volume,class Cancel,class Width=WaterSingleColumn>
bool settle_storage_groups(Rooms &rooms,const std::vector<WaterSpillEdge> &edges,double upper,
        uint64_t total,Curve curve,Volume volume,const Cancel &cancelled,size_t &group_count,Width width={}){
    const int count=int(rooms.size());
    if(!count||(count<256&&std::is_same_v<Width,WaterSingleColumn>))return false;
    std::vector<WaterColumnCurve> curves(count);
    std::vector<int> parent(count);std::iota(parent.begin(),parent.end(),0);
    for(int i=0;i<count;++i)curves[i]=curve(i);
    auto root=[&](int i){
        while(parent[i]!=i){parent[i]=parent[parent[i]];i=parent[i];}
        return i;
    };
    int remaining=count;
    for(const auto &edge:edges){
        const auto &a=curves[edge.a],&b=curves[edge.b];
        if(a.bottom<0||a.bottom!=b.bottom||edge.level>a.bottom+2.1e-9||a.terms!=b.terms)continue;
        int left=root(edge.a),right=root(edge.b);
        if(left!=right){parent[right]=left;--remaining;}
    }
    if((remaining>count-count/8&&std::is_same_v<Width,WaterSingleColumn>)||cancelled.load())return false;
    struct Group {
        int model,first=0,count=0;unsigned columns=0;uint64_t before=0,after=0;double fraction=0;
    };
    std::vector<Group> groups;groups.reserve(remaining);
    std::vector<int> root_group(count,-1),owner(count),members(count);
    for(int i=0;i<count;++i){
        int &group=root_group[root(i)];
        if(group<0){group=int(groups.size());groups.push_back({i});}
        owner[i]=group;++groups[group].count;groups[group].columns+=width(i);groups[group].before+=rooms[i].before;
    }
    int first=0;
    for(auto &g:groups){g.first=first;first+=g.count;g.count=0;}
    for(int i=0;i<count;++i){auto &g=groups[owner[i]];members[g.first+g.count++]=i;}
    std::vector<WaterSpillEdge> external;external.reserve(edges.size());
    for(const auto &edge:edges){
        int a=owner[edge.a],b=owner[edge.b];
        if(a!=b)external.push_back({a,b,edge.level});
    }
    auto per_column=[&](int id,double h){return volume(id,h)/width(id);};
    auto capacity=[&](int i){const auto &g=groups[i];return g.columns*(rooms[g.model].capacity/width(g.model));};
    auto amount=[&](int i,double h){const auto &g=groups[i];return g.columns*per_column(g.model,h);};
    auto integer=[&](int i,double h){const auto &g=groups[i];return g.columns*uint64_t(std::floor(per_column(g.model,h)));};
    // A tile still owns one integer ledger per fine column. An extra ml
    // goes to one of those columns, even when the graph has a single node
    // for all 64. Keep member order deterministic at equal head.
    auto assign=[&](Group &g,uint64_t quantity){
        uint64_t each=quantity/g.columns,extra=quantity%g.columns;
        for(int j=0;j<g.count;++j){
            int id=members[g.first+j];auto weight=width(id);
            uint64_t add=std::min<uint64_t>(weight,extra);
            rooms[id].after=each*weight+add;extra-=add;
        }
    };
    std::vector<int> fractions;
    // Rounding still takes place per original room. Resolve all fractions
    // of one terminal basin together, including rooms in different groups.
    auto expand=[&](const std::vector<int> &order,int begin,int end,double low,double high,uint64_t quantity){
        if(cancelled.load())return false;
        if(end-begin==1){
            auto &g=groups[order[begin]];
            if(quantity>capacity(order[begin]))return false;
            assign(g,quantity);
            return true;
        }
        auto sum=[&](double h){double v=0.;
            for(int at=begin;at<end;++at)v+=amount(order[at],h);
            return v;
        };
        const double head=quantity?water_storage_level(low,high,double(quantity),sum,56):0.;
        uint64_t filled=0;fractions.clear();
        for(int at=begin;at<end;++at){
            int i=order[at];auto &g=groups[i];
            const double v=quantity?per_column(g.model,head):0.;
            const auto each=uint64_t(std::max(0.,std::floor(v)));
            g.fraction=v-each;g.after=each*g.columns;filled+=g.after;
            assign(g,g.after);
            fractions.push_back(i);
        }
        if(filled==quantity)return true;
        std::stable_sort(fractions.begin(),fractions.end(),[&](int a,int b){return groups[a].fraction>groups[b].fraction;});
        if(filled<quantity){
            for(int i:fractions){
                auto &g=groups[i];
                if(g.after>=capacity(i))continue;
                auto n=std::min<uint64_t>(g.columns,quantity-filled);
                assign(g,g.after+n);
                filled+=n;if(filled==quantity)return true;
            }
        }else for(auto it=fractions.rbegin();it!=fractions.rend();++it){
            auto &g=groups[*it];
            if(!g.after)continue;
            auto n=std::min<uint64_t>(g.columns,filled-quantity);
            assign(g,g.after-n);
            filled-=n;if(filled==quantity)return true;
        }
        return false;
    };
    int64_t exchange=0;const char *reason=nullptr;
    if(!distribute_basin_water(groups,external,-1,upper,total,exchange,amount,capacity,integer,cancelled,
        [](int){},reason,56,expand))return false;
    group_count=groups.size();return true;
}
}
