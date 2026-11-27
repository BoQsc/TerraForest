// SPDX-License-Identifier: 0BSD
shader_type spatial;
render_mode cull_disabled, diffuse_burley;
// Far-only Gaussian moment approximation of each authored triangle.
// Area is normalized before opacity clamping and the finite 3-sigma crop.
uniform vec3 cover_eye;
uniform float cover_clock = 0.0;
varying flat vec2 center_px;
varying flat vec3 inverse_cov;
varying flat float amplitude;
varying flat float visibility;
varying vec2 point_px;
varying flat float shade;
varying flat float ao;
varying flat float variation;
vec3 bend(vec3 point, float phase) {
    float weight=clamp(point.y/0.65,0.0,1.0);
    vec2 fixed_bend=(fract(sin(vec2(phase,phase+19.7))*vec2(43758.5453,19642.349))-0.5)*0.07;
    float sway=sin(TIME*1.35+phase)*0.009+sin(TIME*2.1+phase*1.7)*0.003;
    point.xz+=(fixed_bend+vec2(sway,sway*0.55))*weight*weight;
    return point;
}
void vertex() {
    vec3 origin=MODEL_MATRIX[3].xyz;
    float phase=dot(origin.xz,vec2(0.71,0.43));
    vec3 a=bend(CUSTOM0.xyz,phase),b=bend(CUSTOM1.xyz,phase),c=bend(CUSTOM2.xyz,phase);
    mat4 mvp=PROJECTION_MATRIX*MODELVIEW_MATRIX;
    vec4 ca=mvp*vec4(a,1.0),cb=mvp*vec4(b,1.0),cc=mvp*vec4(c,1.0);
    vec2 pa=ca.xy/ca.w*VIEWPORT_SIZE*0.5,pb=cb.xy/cb.w*VIEWPORT_SIZE*0.5,pc=cc.xy/cc.w*VIEWPORT_SIZE*0.5;
    center_px=(pa+pb+pc)/3.0;
    vec2 da=pa-center_px,db=pb-center_px,dc=pc-center_px;
    float xx=(da.x*da.x+db.x*db.x+dc.x*dc.x)/12.0+0.25;
    float yy=(da.y*da.y+db.y*db.y+dc.y*dc.y)/12.0+0.25;
    float xy=(da.x*da.y+db.x*db.y+dc.x*dc.y)/12.0;
    float determinant=max(xx*yy-xy*xy,0.000001);
    inverse_cov=vec3(yy,-xy,xx)/determinant;
    float area=abs((pb.x-pa.x)*(pc.y-pa.y)-(pb.y-pa.y)*(pc.x-pa.x))*0.5;
    amplitude=area/(6.28318530718*sqrt(determinant));
    vec2 extent=3.0*sqrt(vec2(xx,yy));
    point_px=center_px+(UV*2.0-1.0)*extent;
    VERTEX=(a+b+c)/3.0;
    vec4 clip=mvp*vec4(VERTEX,1.0);
    POSITION=vec4(point_px/(VIEWPORT_SIZE*0.5)*clip.w,clip.z,clip.w);
    float distance_to_eye=distance(origin.xz,cover_eye.xz);
    visibility=1.0-smoothstep(100.0,124.0,distance_to_eye);
    float age=cover_clock-INSTANCE_CUSTOM.x;
    visibility*=INSTANCE_CUSTOM.y>0.5?smoothstep(0.0,0.65,max(0.0,age)):1.0;
    float root_shade=mix(0.64,1.0,smoothstep(0.015,0.19,(CUSTOM0.y+CUSTOM1.y+CUSTOM2.y)/3.0));
    float canopy=1.0-0.28*smoothstep(24.0,56.0,distance_to_eye)*(1.0-smoothstep(0.0,0.9,1.0/3.0));
    shade=root_shade*canopy;
    ao=mix(0.62,1.0,smoothstep(0.0,0.30,1.0/3.0));
    variation=0.95+0.05*sin(phase*3.7);
}
void fragment() {
    vec2 p=point_px-center_px;
    float q=inverse_cov.x*p.x*p.x+2.0*inverse_cov.y*p.x*p.y+inverse_cov.z*p.y*p.y;
    ALPHA=clamp(amplitude*exp(-0.5*q),0.0,1.0)*visibility;
    // Quad orientation is artificial; face the authored blade normal explicitly.
    if(dot(NORMAL,VIEW)<0.0) NORMAL=-NORMAL;
    ALBEDO=COLOR.rgb*variation*shade*0.90;
    AO=ao; AO_LIGHT_AFFECT=0.35;
    ROUGHNESS=0.92; SPECULAR=0.136; BACKLIGHT=COLOR.rgb*0.116;
}
