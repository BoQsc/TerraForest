// SPDX-License-Identifier: 0BSD
// Far-only screen-space approximations must reject invalid support BEFORE the
// perspective divide. A proxy crossing the eye plane can otherwise expand into
// a foreground strip before hardware clipping ever sees the generated quad.
// The doubled side bounds leave ample room for filtered tails at screen edges,
// while rejecting off-screen support with ill-conditioned perspective depth.
bool proxy_triangle_in_view(vec4 a, vec4 b, vec4 c) {
    return min(a.w,min(b.w,c.w))>0.0 && a.z<=a.w && b.z<=b.w && c.z<=c.w
        && !(a.x>2.0*a.w && b.x>2.0*b.w && c.x>2.0*c.w)
        && !(a.x< -2.0*a.w && b.x< -2.0*b.w && c.x< -2.0*c.w)
        && !(a.y>2.0*a.w && b.y>2.0*b.w && c.y>2.0*c.w)
        && !(a.y< -2.0*a.w && b.y< -2.0*b.w && c.y< -2.0*c.w);
}

bool proxy_stone_in_view(vec4 center) {
    // This far-only approximation is never the representation near the player.
    // Reserve half a metre of forward depth for its authored 0.31 m radius.
    return center.w>0.5 && center.z<=center.w
        && abs(center.x)<=2.0*center.w && abs(center.y)<=2.0*center.w;
}
