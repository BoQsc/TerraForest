// SPDX-License-Identifier: 0BSD
#pragma once
#include <array>
#include <memory>

namespace terraforest {
// Region-sized copy-on-write storage. A snapshot copies only this owner handle;
// the live main-thread owner detaches before any write, while save workers read
// const frozen regions. Never retain a writable reference across a snapshot.
// This is not concurrent mutation of one handle: owners are handed off only at
// the existing frame/worker boundary. The shared payload becomes immutable.
template<class T,size_t N> class SnapshotArray {
    using Values=std::array<T,N>;
    std::shared_ptr<Values> values=std::make_shared<Values>();
    Values &write(){if(!values.unique())values=std::make_shared<Values>(*values);return *values;}
public:
    static constexpr size_t retained_bytes=sizeof(Values)+2*sizeof(void*);
    SnapshotArray()=default;
    SnapshotArray(const SnapshotArray &)=default;
    SnapshotArray &operator=(const SnapshotArray &)=default;
    SnapshotArray &operator=(const Values &source){write()=source;return *this;}
    operator const Values &() const{return *values;}
    const T &operator[](size_t index) const{return (*values)[index];}
    T &operator[](size_t index){return write()[index];}
    auto begin() const{return values->cbegin();}
    auto end() const{return values->cend();}
    auto begin(){return write().begin();}
    auto end(){return write().end();}
};
}
