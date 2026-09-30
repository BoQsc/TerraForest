// SPDX-License-Identifier: 0BSD
#pragma once
#include <cstdlib>
#include <cstring>
#include <limits>
#include <type_traits>
#include <utility>
#include <new>

namespace terraforest::experimental {
struct BufferAllocator {
 void*context=nullptr;
 void*(*allocate)(void*,size_t)=[](void*,size_t bytes){return std::malloc(bytes);};
 void(*release)(void*,void*)=[](void*,void*pointer){std::free(pointer);};
};

// Move-only trivial-element storage. Allocation failure preserves the old buffer.
// A custom allocator's context must outlive every buffer using it.
template<class T>class FallibleBuffer {
 static_assert(std::is_trivially_copyable<T>::value&&std::is_trivially_destructible<T>::value);
 T*data_=nullptr;size_t size_=0,capacity_=0;BufferAllocator allocator_;
 void take(FallibleBuffer&&other){
  data_=other.data_;size_=other.size_;capacity_=other.capacity_;allocator_=other.allocator_;
  other.data_=nullptr;other.size_=other.capacity_=0;
 }
public:
 FallibleBuffer()=default;
 FallibleBuffer(const FallibleBuffer&)=delete;
 FallibleBuffer&operator=(const FallibleBuffer&)=delete;
 FallibleBuffer(FallibleBuffer&&other)noexcept{take(std::move(other));}
 FallibleBuffer&operator=(FallibleBuffer&&other)noexcept{if(this!=&other){clear();take(std::move(other));}return *this;}
 ~FallibleBuffer(){clear();}
 void set_allocator(BufferAllocator allocator){clear();allocator_=allocator;}
 void clear(){if(data_)allocator_.release(allocator_.context,data_);data_=nullptr;size_=capacity_=0;}
 bool reserve(size_t capacity){
  if(capacity<=capacity_)return true;
  if(capacity>std::numeric_limits<size_t>::max()/sizeof(T)||!allocator_.allocate||!allocator_.release)return false;
  void*memory=allocator_.allocate(allocator_.context,capacity*sizeof(T));
  if(!memory)return false;
  T*next=static_cast<T*>(memory);
  for(size_t i=0;i<size_;i++)::new(static_cast<void*>(next+i)) T(data_[i]);
  if(data_)allocator_.release(allocator_.context,data_);
  data_=static_cast<T*>(memory);capacity_=capacity;return true;
 }
 bool resize(size_t count){
  if(!reserve(count))return false;
  while(size_<count){::new(static_cast<void*>(data_+size_)) T{};size_++;}
  size_=count;return true;
 }
 // Callers reserve and check their logical output limit before these operations.
 void push_back(const T&value){::new(static_cast<void*>(data_+size_)) T(value);size_++;}
 size_t size()const{return size_;}
 size_t capacity()const{return capacity_;}
 bool empty()const{return size_==0;}
 T*data(){return data_;}const T*data()const{return data_;}
 T*begin(){return data_;}const T*begin()const{return data_;}
 T*end(){return size_?data_+size_:data_;}const T*end()const{return size_?data_+size_:data_;}
 T&operator[](size_t index){return data_[index];}const T&operator[](size_t index)const{return data_[index];}
 bool operator!=(const FallibleBuffer&other)const{return size_!=other.size_||(size_&&std::memcmp(data_,other.data_,size_*sizeof(T))!=0);}
};
} // namespace terraforest::experimental
