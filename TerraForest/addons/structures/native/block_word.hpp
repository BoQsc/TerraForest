#pragma once
namespace terraforest {
constexpr int BLOCK_SHAPE_COUNT=36;
// Appearance words use previously forbidden bit 14. Legacy words are unchanged.
// A 15-bit payload skips marker bit 14: appearance 0..2, structure 3..4,
// pose ordinal 5..14. Poses 0..31 are 8 legacy shapes x 4 turns; remaining
// poses are modular shapes x 24 mounts. This retains a two-byte cell.
inline bool styled_block(int word) {return (word&16384)!=0;}
inline int block_style_payload(int word) {return (word&16383)|((word>>1)&16384);}
inline bool valid_block_word(int word) {
    if(word<0||word>65535)return false;
    if(styled_block(word))return (block_style_payload(word)>>5)<32+(BLOCK_SHAPE_COUNT-8)*24;
    if(word&32768)return word>0 && word<=65535 && !(word&24704) && ((word>>8)&31)<BLOCK_SHAPE_COUNT-8 && (word&31)<24;
    return word==0 || (word>0 && word<128 && (word&7)!=0) || (word>=128 && word<256 && (word&7)==0);
}
inline int block_shape(int word) {int pose=block_style_payload(word)>>5;return styled_block(word)?(pose<32?1+pose/4:9+(pose-32)/24):(word&32768)?9+((word>>8)&31):(word&128)?8:(word&7);}
inline bool extended_block(int word) {return block_shape(word)>8;}
inline int block_rotation(int word) {int pose=block_style_payload(word)>>5;return styled_block(word)?(pose<32?pose%4:(pose-32)%24):(word&32768)?word&31:(word>>3)&3;}
inline int block_material(int word) {return styled_block(word)?(block_style_payload(word)>>3)&3:(word>>5)&3;}
inline int block_appearance(int word) {return styled_block(word)?block_style_payload(word)&7:-1;}
inline int block_render_material(int word) {return styled_block(word)?4+block_appearance(word):block_material(word);}
inline int block_word(int shape,int rotation,int material=0,int appearance=-1) {
    if(shape<1||shape>BLOCK_SHAPE_COUNT||rotation<0||rotation>=(shape>8?24:4)||material<0||material>3||appearance< -1||appearance>7)return -1;
    if(appearance>=0){int pose=shape<=8?(shape-1)*4+rotation:32+(shape-9)*24+rotation;int payload=(pose<<5)|(material<<3)|appearance;return 16384|(payload&16383)|((payload&16384)<<1);}
    return shape>8?32768|((shape-9)<<8)|rotation|(material<<5):(shape==8?128:shape)+(rotation<<3)+(material<<5);
}
inline int yaw_block(int word,int turns) {
    int rotation=block_rotation(word);
    return block_word(block_shape(word),(rotation&~3)|((rotation+turns)&3),block_material(word),block_appearance(word));
}
}
