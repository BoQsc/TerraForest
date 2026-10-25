#pragma once
namespace terraforest {
constexpr int BLOCK_SHAPE_COUNT=14;
inline bool extended_block(int word) {return (word&32768)!=0;}
inline bool valid_block_word(int word) {
    if(word&32768)return word>0 && word<=65535 && !(word&24704) && ((word>>8)&31)<BLOCK_SHAPE_COUNT-8 && (word&31)<24;
    return word==0 || (word>0 && word<128 && (word&7)!=0) || (word>=128 && word<256 && (word&7)==0);
}
inline int block_shape(int word) {return extended_block(word)?9+((word>>8)&31):(word&128)?8:(word&7);}
inline int block_rotation(int word) {return extended_block(word)?word&31:(word>>3)&3;}
inline int block_material(int word) {return (word>>5)&3;}
inline int block_word(int shape,int rotation,int material=0) {
    if(shape<1||shape>BLOCK_SHAPE_COUNT||rotation<0||rotation>=(shape>8?24:4)||material<0||material>3)return -1;
    return shape>8?32768|((shape-9)<<8)|rotation|(material<<5):(shape==8?128:shape)+(rotation<<3)+(material<<5);
}
inline int yaw_block(int word,int turns) {
    int rotation=block_rotation(word);
    return block_word(block_shape(word),(rotation&~3)|((rotation+turns)&3),block_material(word));
}
}
