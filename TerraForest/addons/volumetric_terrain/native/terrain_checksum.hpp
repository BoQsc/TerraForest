// SPDX-License-Identifier: 0BSD
#pragma once
#include "platform.h"
#if defined(__x86_64__) && defined(__clang__)
#include <cpuid.h>
#include <nmmintrin.h>
#define TERRAFOREST_CRC_HW 1
#endif
namespace terrain_checksum {
struct Table {
 u32 values[256]{};
 constexpr Table(){for(u32 i=0;i<256;i++){u32 c=i;for(int bit=0;bit<8;bit++)c=(c>>1)^((c&1)?0x82f63b78u:0u);values[i]=c;}}
};
inline u32 software(const u8 *p,int n){
 static constexpr Table table{};u32 value=0xffffffffu;
 for(int i=0;i<n;i++)value=(value>>8)^table.values[(value^p[i])&255];
 return ~value;
}
#if defined(TERRAFOREST_CRC_HW)
__attribute__((target("sse4.2,crc32"))) inline u32 accelerated(const u8 *p,int n){
 u64 value=0xffffffffu;
 while(n>=8){u64 word;copy_bytes(&word,p,8);value=_mm_crc32_u64(value,word);p+=8;n-=8;}
 while(n--)value=_mm_crc32_u8(u32(value),*p++);
 return ~u32(value);
}
inline bool available(){unsigned a,b,c,d;return __get_cpuid(1,&a,&b,&c,&d)&&(c&bit_SSE4_2);}
#endif
inline u32 checksum(const u8 *p,int n){
#if defined(TERRAFOREST_CRC_HW)
 static const bool hardware=available();if(hardware)return accelerated(p,n);
#endif
 return software(p,n);
}
}
