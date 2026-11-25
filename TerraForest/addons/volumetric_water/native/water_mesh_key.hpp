// SPDX-License-Identifier: 0BSD
#pragma once
#include <array>
#include <cstdint>
#include <cstring>
#include <type_traits>

// Keys are lattice coordinates, normalized float vertices or nested triangle
// keys. Hash buckets only accelerate equality lookup. Stream order is still
// the original face traversal and a collision always compares the full key.
namespace terraforest {
struct WaterMeshKeyHash {
    template<class V> static uint64_t word(const V &value){
        if constexpr(std::is_floating_point_v<V>){
            if(value==0)return 0; // Positive and negative zero compare equal.
            uint64_t bits=0;std::memcpy(&bits,&value,sizeof(V));return bits;
        }else return static_cast<uint64_t>(value);
    }
    template<class V,size_t N> static uint64_t word(const std::array<V,N> &values){
        uint64_t h=0x9e3779b97f4a7c15ULL;
        for(const auto &v:values){h^=word(v)+0x9e3779b97f4a7c15ULL+(h<<6)+(h>>2);}
        return h;
    }
    template<class V> size_t operator()(const V &value)const{
        uint64_t h=word(value);h^=h>>29;h*=0x165667919e3779f9ULL;return size_t(h^(h>>32));
    }
};
}
