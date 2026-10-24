#pragma once
namespace terraforest {
inline bool valid_block_word(int word) {
    return word==0 || (word>0 && word<128 && (word&7)!=0) || (word>=128 && word<256 && (word&7)==0);
}
inline int block_shape(int word) {return (word&128)?8:(word&7);}
inline int block_material(int word) {return (word>>5)&3;}
inline int block_word(int shape,int rotation,int material=0) {return (shape==8?128:shape)+(rotation<<3)+(material<<5);}
}
