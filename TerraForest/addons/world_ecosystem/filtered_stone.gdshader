// SPDX-License-Identifier: 0BSD
shader_type spatial;
render_mode cull_disabled, diffuse_burley;
#include "res://addons/world_ecosystem/proxy_projection.gdshaderinc"
const bool proxy_lod_transition = false;
uniform float near_lod_metric = 703.74;
uniform vec2 proxy_lod_edges = vec2(0.037,0.0448);
varying flat float proxy_lod_weight;
uniform sampler2D stone_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D stone_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 stone_area_vectors[48];
uniform vec3 cover_eye=vec3(0.0);
uniform float cover_clock=0.0;
uniform float distance_fade_start=100.0;
uniform float distance_fade_end=124.0;
const vec3 RADII=vec3(0.31,0.175,0.255);
// Carry the individual MultiMesh transform from the vertex stage. The fragment
// MODEL_MATRIX describes the draw batch, not the individual stone.
varying flat mat3 stone_view_basis;
varying flat vec3 inverse_shape;
varying flat vec3 row_x;
varying flat vec3 row_y;
varying flat vec3 face_axis;
varying flat vec3 blurred_inverse;
varying flat float blurred_amplitude;
varying flat float point_weight;
varying flat float coverage;
varying flat float variation;
varying vec2 point_px;

void vertex(){
    stone_view_basis=mat3(MODELVIEW_MATRIX);
    vec3 origin=MODEL_MATRIX[3].xyz;
    vec3 proxy_delta=origin-cover_eye;
    vec2 proxy_limits=proxy_lod_edges*near_lod_metric;
    proxy_lod_weight=proxy_lod_transition?smoothstep(proxy_limits.x*proxy_limits.x,proxy_limits.y*proxy_limits.y,dot(proxy_delta,proxy_delta)):1.0;

    float distance_weight=1.0-smoothstep(distance_fade_start,distance_fade_end,distance(origin.xz,cover_eye.xz));
    float age=cover_clock-INSTANCE_CUSTOM.x;
    coverage=distance_weight*(INSTANCE_CUSTOM.y>0.5?smoothstep(0.0,0.65,max(0.0,age)):1.0);
    // Fully faded instances need no projection or silhouette-area work.
    if(coverage<=0.0 || (proxy_lod_transition && proxy_lod_weight<=0.0)){POSITION=vec4(2.0,2.0,2.0,1.0);}else{
    mat4 mvp=PROJECTION_MATRIX*MODELVIEW_MATRIX;
    vec4 center=mvp*vec4(0.0,0.0,0.0,1.0);
    if (proxy_stone_in_view(center)) {
    vec3 row_w=vec3(mvp[0].w,mvp[1].w,mvp[2].w);
    vec3 jac_x=(vec3(mvp[0].x,mvp[1].x,mvp[2].x)*center.w-center.x*row_w)/(center.w*center.w)*VIEWPORT_SIZE.x*0.5;
    vec3 jac_y=(vec3(mvp[0].y,mvp[1].y,mvp[2].y)*center.w-center.y*row_w)/(center.w*center.w)*VIEWPORT_SIZE.y*0.5;
    row_x=jac_x*RADII;row_y=jac_y*RADII;
    float xx=dot(row_x,row_x),yy=dot(row_y,row_y),xy=dot(row_x,row_y);
    float determinant=max(xx*yy-xy*xy,0.000001);
    // Closed low-poly stone: half the absolute projected face areas equals its
    // silhouette area. Preserve this instead of making an oversized bright disk.
    vec3 projected_normal=cross(jac_x,jac_y);
    float area=0.0;
    for(int i=0;i<48;i++){area+=abs(dot(projected_normal,stone_area_vectors[i]))*0.5;}
    float gain=area/(3.14159265359*sqrt(determinant));
    row_x*=sqrt(gain);row_y*=sqrt(gain);xx*=gain;yy*=gain;xy*=gain;
    determinant=max(xx*yy-xy*xy,0.000001);
    inverse_shape=vec3(yy,-xy,xx)/determinant;
    face_axis=normalize(cross(row_x,row_y));
    // Projection Y orientation must not select the rear hemisphere.
    if((MODELVIEW_MATRIX*vec4(face_axis*RADII,0.0)).z<0.0)face_axis=-face_axis;
    float bx=xx*0.25+0.25,by=yy*0.25+0.25,bxy=xy*0.25;
    float bd=max(bx*by-bxy*bxy,0.000001);
    blurred_inverse=vec3(by,-bxy,bx)/bd;
    blurred_amplitude=area/(6.28318530718*sqrt(bd));
    point_weight=1.0-smoothstep(0.6,1.0,sqrt(max(xx,yy)));
    vec2 center_px=center.xy/center.w*VIEWPORT_SIZE*0.5;
    vec2 extent=max(sqrt(vec2(xx,yy))+vec2(1.0),3.0*sqrt(vec2(bx,by))*point_weight);
    point_px=(UV*2.0-1.0)*extent;
    POSITION=vec4((center_px+point_px)/(VIEWPORT_SIZE*0.5)*center.w,center.z,center.w);
    variation=0.95+0.05*sin(dot(origin.xz,vec2(0.71,0.43))*3.7);
    } else { POSITION=vec4(2.0,2.0,2.0,1.0); }
}

}
void fragment(){
    // Complement the opaque screen mask. Multiplying both representations by
    // alpha would expose extra terrain in the middle of the transition.
    if(proxy_lod_transition && fract(52.9829189*fract(dot(floor(FRAGCOORD.xy),vec2(0.06711056,0.00583715))))>=proxy_lod_weight)discard;

    vec2 delta=point_px;
    vec2 weighted=vec2(inverse_shape.x*delta.x+inverse_shape.y*delta.y,inverse_shape.y*delta.x+inverse_shape.z*delta.y);
    float radius=sqrt(max(dot(delta,weighted),0.0));
    float gradient=max(length(weighted)/max(radius,0.00001),0.00001);
    float edge=clamp(0.5+(1.0-radius)/gradient,0.0,1.0);
    float quadratic=blurred_inverse.x*delta.x*delta.x+2.0*blurred_inverse.y*delta.x*delta.y+blurred_inverse.z*delta.y*delta.y;
    ALPHA=mix(edge,clamp(blurred_amplitude*exp(-0.5*quadratic),0.0,1.0),point_weight)*coverage;
    if(ALPHA<0.0001)discard;
    vec3 surface=row_x*weighted.x+row_y*weighted.y;
    surface/=max(length(surface),1.0);
    surface+=face_axis*sqrt(max(0.0,1.0-dot(surface,surface)));
    vec2 stone_uv=vec2(atan(surface.z,surface.x)/6.28318530718,acos(clamp(surface.y,-1.0,1.0))/3.14159265359);
    NORMAL=normalize(stone_view_basis*(surface*RADII*vec3(1.0,2.3,1.0)));
    vec3 local_tangent=vec3(-surface.z*RADII.x,0.0,surface.x*RADII.z);
    if(dot(local_tangent,local_tangent)<0.00000001)local_tangent=vec3(1.0,0.0,0.0);
    vec3 tangent=stone_view_basis*local_tangent;
    TANGENT=normalize(tangent-NORMAL*dot(tangent,NORMAL));
    BINORMAL=normalize(cross(NORMAL,TANGENT));
    ALBEDO=texture(stone_color,stone_uv).rgb*variation;
    NORMAL_MAP=texture(stone_normal,stone_uv).rgb;
    NORMAL_MAP_DEPTH=0.55;
    ROUGHNESS=0.94;SPECULAR=0.24;
    // Reconstructed surface depth preserves intersection with the actual terrain.
    vec4 view_surface=vec4(stone_view_basis*(surface*RADII)+VERTEX,1.0);
    LIGHT_VERTEX=view_surface.xyz;
    vec4 clip=PROJECTION_MATRIX*view_surface;
    DEPTH=clip.z/clip.w;
}
