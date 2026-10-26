// SPDX-License-Identifier: 0BSD
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform float clock = 0.0;
uniform float seed = 0.0;
float noise(vec2 p) {
    // Continuous warped turbulence avoids a visible grid in the fire silhouette.
    return .5+.5*sin(p.x*1.7+sin(p.y*1.3))*sin(p.y*1.4+cos(p.x*1.9));
}
void vertex() {
    // Camera-facing tongues occupy different depths; all rise from the crown.
    MODELVIEW_MATRIX=VIEW_MATRIX*mat4(INV_VIEW_MATRIX[0],INV_VIEW_MATRIX[1],INV_VIEW_MATRIX[2],MODEL_MATRIX[3]);
}
void fragment() {
    float y=1.0-UV.y;
    vec2 p=vec2(UV.x*5.0+seed,y*6.0-clock*3.4);
    float n=noise(p)*.63+noise(p*2.07+clock*.41)*.27+noise(p*4.1)*.10;
    float bend=sin(y*8.0-clock*3.7+seed)*y*.12+(n-.5)*y*.22;
    float x=abs(UV.x-.5+bend)*2.0;
    float width=pow(max(0.0,1.0-y),.70)*.80;
    float edge=(width-x)+(n-.5)*.34;
    float alpha=smoothstep(-.06,.12,edge)*smoothstep(0.0,.18,y)*smoothstep(0.0,.10,UV.x)*(1.0-smoothstep(.90,1.0,UV.x))*(1.0-smoothstep(.65,1.0,y));
    float hot=clamp((edge-.10)*2.4+(1.0-y)*.65,0.0,1.0);
    vec3 color=mix(vec3(.85,.075,.008),vec3(1.0,.38,.035),smoothstep(.0,.5,hot));
    color=mix(color,vec3(1.0,.70,.22),smoothstep(.55,1.0,hot));
    ALBEDO=color; EMISSION=color*.95; ALPHA=alpha*.90;
}
