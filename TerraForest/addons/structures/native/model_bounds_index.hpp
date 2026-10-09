// SPDX-License-Identifier: 0BSD
#pragma once
#include "block_world.hpp"
#include <algorithm>
#include <memory>

namespace terraforest {
// AVL tree ordered by interleaved region coordinates. Each subtree carries its
// actual union bounds, including prototypes extending beyond the origin cell.
// Updates touch a logarithmic path; scene-thread readers hold no persistent pointers.
class ModelBoundsIndex {
public:
    struct Node {
        uint64_t code;BlockKey key;AABB box,bounds;
        int height=1;
        std::unique_ptr<Node> left,right;
        Node(uint64_t code_,BlockKey key_,AABB box_):code(code_),key(key_),box(box_),bounds(box_){}
    };
private:
    std::unique_ptr<Node> root_;
    size_t size_=0;
    uint64_t revision_=0;
    static int height(const std::unique_ptr<Node> &n){return n?n->height:0;}
    static void update(Node &n) {
        n.height=1+std::max(height(n.left),height(n.right));n.bounds=n.box;
        if(n.left)n.bounds=n.bounds.merge(n.left->bounds);
        if(n.right)n.bounds=n.bounds.merge(n.right->bounds);
    }
    static std::unique_ptr<Node> left(std::unique_ptr<Node> n) {
        auto top=std::move(n->right);n->right=std::move(top->left);update(*n);
        top->left=std::move(n);update(*top);return top;
    }
    static std::unique_ptr<Node> right(std::unique_ptr<Node> n) {
        auto top=std::move(n->left);n->left=std::move(top->right);update(*n);
        top->right=std::move(n);update(*top);return top;
    }
    static std::unique_ptr<Node> balance(std::unique_ptr<Node> n) {
        if(!n)return n;update(*n);
        if(height(n->left)-height(n->right)>1) {
            if(height(n->left->left)<height(n->left->right))n->left=left(std::move(n->left));
            return right(std::move(n));
        }
        if(height(n->right)-height(n->left)>1) {
            if(height(n->right->right)<height(n->right->left))n->right=right(std::move(n->right));
            return left(std::move(n));
        }
        return n;
    }
    static std::unique_ptr<Node> put(std::unique_ptr<Node> n,uint64_t code,BlockKey key,AABB box) {
        if(!n)return std::make_unique<Node>(code,key,box);
        if(code<n->code)n->left=put(std::move(n->left),code,key,box);
        else if(code>n->code)n->right=put(std::move(n->right),code,key,box);
        else n->box=box;
        return balance(std::move(n));
    }
    static std::unique_ptr<Node> remove(std::unique_ptr<Node> n,uint64_t code) {
        if(!n)return n;
        if(code<n->code)n->left=remove(std::move(n->left),code);
        else if(code>n->code)n->right=remove(std::move(n->right),code);
        else {
            if(!n->left)return std::move(n->right);
            if(!n->right)return std::move(n->left);
            const Node *next=n->right.get();while(next->left)next=next->left.get();
            n->code=next->code;n->key=next->key;n->box=next->box;
            n->right=remove(std::move(n->right),n->code);
        }
        return balance(std::move(n));
    }
public:
    static uint64_t code(BlockKey key) {
        const uint32_t axes[3]={uint32_t(key.x+32768),uint32_t(key.y+32768),uint32_t(key.z+32768)};
        uint64_t value=0;
        for(int bit=0;bit<16;++bit)for(int axis=0;axis<3;++axis)value|=uint64_t((axes[axis]>>bit)&1)<<(bit*3+axis);
        return value;
    }
    const Node *find(uint64_t code) const {
        const Node *n=root_.get();while(n&&n->code!=code)n=code<n->code?n->left.get():n->right.get();return n;
    }
    void insert(BlockKey key,AABB box) {const auto value=code(key);if(!find(value))++size_;root_=put(std::move(root_),value,key,box);++revision_;}
    void erase(BlockKey key) {const auto value=code(key);if(find(value)){root_=remove(std::move(root_),value);--size_;++revision_;}}
    void clear(){root_.reset();size_=0;++revision_;}
    const Node *root() const{return root_.get();}
    size_t size() const{return size_;}
    int height() const{return height(root_);}
    uint64_t revision() const{return revision_;}
};
}
