// SPDX-License-Identifier: 0BSD
#pragma once
#include <stdint.h>
#include <stddef.h>

using u8=uint8_t; using u16=uint16_t; using u32=uint32_t; using u64=uint64_t;
using i16=int16_t; using i32=int32_t; using i64=int64_t;
extern void *(*tr_alloc)(size_t);
extern void *(*tr_realloc)(void *,size_t);
extern void (*tr_free)(void *);
extern bool tr_oom;
inline void copy_bytes(void *dst,const void *src,size_t n) { auto d=(u8*)dst;auto s=(const u8*)src;for(size_t i=0;i<n;++i)d[i]=s[i]; }
inline void zero_bytes(void *dst,size_t n) { auto d=(u8*)dst;for(size_t i=0;i<n;++i)d[i]=0; }
template<class T> struct List {
 T *p=nullptr; int n=0,cap=0;
 bool reserve(int k) { if(k<=cap)return true;int c=cap?cap:16;while(c<k)c=c+c/2+16;void *q=tr_realloc(p,size_t(c)*sizeof(T));if(!q){tr_oom=true;return false;}p=(T*)q;cap=c;return true; }
 void resize(int k){if(reserve(k)){if(k>n)zero_bytes(p+n,size_t(k-n)*sizeof(T));n=k;}}
 int push(const T &v){int r=n;if(reserve(n+1))p[n++]=v;return r;}
 void clear(){n=0;}
 void release(){if(p)tr_free(p);p=nullptr;n=cap=0;}
 T& operator[](int i){return p[i];} const T& operator[](int i)const{return p[i];}
};
inline float mn(float a,float b){return a<b?a:b;} inline float mx(float a,float b){return a>b?a:b;}
inline int imn(int a,int b){return a<b?a:b;} inline int imx(int a,int b){return a>b?a:b;}
inline float ab(float a){return a<0?-a:a;} inline float clampf(float a,float l,float h){return mn(h,mx(l,a));}
inline int fl(float a){int i=(int)a;return i-(float(i)>a);}
inline float root(float a){return __builtin_sqrtf(mx(a,0.f));}
struct V3 {float x=0,y=0,z=0;};
inline V3 operator+(V3 a,V3 b){return {a.x+b.x,a.y+b.y,a.z+b.z};}
inline V3 operator-(V3 a,V3 b){return {a.x-b.x,a.y-b.y,a.z-b.z};}
inline V3 operator*(V3 a,float b){return {a.x*b,a.y*b,a.z*b};}
inline V3 operator/(V3 a,float b){return a*(1.f/b);}
inline float dot(V3 a,V3 b){return a.x*b.x+a.y*b.y+a.z*b.z;}
inline V3 cross(V3 a,V3 b){return {a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x};}
inline float length(V3 a){return root(dot(a,a));}
inline V3 normal(V3 a){float l=length(a);return l>1e-12f?a/l:V3{0,1,0};}
inline u32 hash32(u32 x){x^=x>>16;x*=0x7feb352du;x^=x>>15;x*=0x846ca68bu;x^=x>>16;return x;}
struct MapSlot{u32 key; i32 value;};
// Key 0 = vacant, UINT32_MAX = tombstone; caller keys are offset by one.
struct Map {
 MapSlot *p=nullptr;int cap=0,n=0,used=0;
 void release(){if(p)tr_free(p);p=nullptr;cap=n=used=0;}
 void rehash(int c){MapSlot *old=p;int oc=cap;p=(MapSlot*)tr_alloc(size_t(c)*sizeof(MapSlot));if(!p){p=old;tr_oom=true;return;}zero_bytes(p,size_t(c)*sizeof(MapSlot));cap=c;n=used=0;for(int i=0;i<oc;i++)if(old[i].key&&old[i].key!=0xffffffffu)put(old[i].key,old[i].value);if(old)tr_free(old);}
 int get(u32 k)const{if(!cap)return -1;u32 j=hash32(k)&(cap-1);for(int t=0;t<cap;t++,j=(j+1)&(cap-1)){if(!p[j].key)return -1;if(p[j].key==k)return p[j].value;}return -1;}
 void put(u32 k,int v){if(!cap)rehash(64);if((used+1)*10>=cap*7)rehash((n+1)*10>=cap*5?cap*2:cap);if(!p)return;u32 j=hash32(k)&(cap-1);int tomb=-1;for(;;j=(j+1)&(cap-1)){if(p[j].key==k){p[j].value=v;return;}if(p[j].key==0xffffffffu&&tomb<0)tomb=int(j);if(!p[j].key){if(tomb>=0)j=tomb;else used++;p[j]={k,v};n++;return;}}}
 void erase(u32 k){if(!cap)return;u32 j=hash32(k)&(cap-1);for(int t=0;t<cap;t++,j=(j+1)&(cap-1)){if(!p[j].key)return;if(p[j].key==k){p[j].key=0xffffffffu;n--;return;}}}
};
struct Bytes:List<u8>{
 void raw(const void*s,int count){int at=n;resize(n+count);if(n>=at+count)copy_bytes(p+at,s,count);}
 void u(u32 a){raw(&a,4);}void f(float a){raw(&a,4);}void vec(V3 a){f(a.x);f(a.y);f(a.z);}
};
struct Reader {const u8*p;int n,at=0;bool good=true;
 u32 u(){if(at+4>n){good=false;return 0;}u32 v;copy_bytes(&v,p+at,4);at+=4;return v;}
 float f(){u32 x=u();float v;copy_bytes(&v,&x,4);return v;}
 V3 vec(){return {f(),f(),f()};}
};
