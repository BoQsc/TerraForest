// SPDX-License-Identifier: 0BSD
shader_type spatial;
render_mode cull_disabled, diffuse_burley;
#include "res://addons/world_ecosystem/proxy_projection.gdshaderinc"
const bool proxy_lod_transition = false;
uniform float near_lod_metric = 703.74;
uniform vec2 proxy_lod_edges = vec2(0.037,0.0448);
varying flat float proxy_lod_weight;
uniform bool stone = false;
uniform float grass_detail_strength : hint_range(0.0, 1.0) = 0.0;
uniform vec3 grass_detail_mean = vec3(1.0);
uniform sampler2D grass_detail : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D stone_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D stone_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float wind_strength : hint_range(0.0, 1.0) = 1.0;
uniform float distance_fade_start = 10000.0;
uniform float distance_fade_end = 11000.0;
uniform vec3 cover_eye = vec3(0.0);
uniform float cover_clock = 0.0;
uniform float distant_self_shade : hint_range(0.0,1.0) = 0.28;
varying float canopy_shade;
varying float coverage;
varying float variation;
varying float root_shade;


varying flat vec2 center_px;
varying flat vec3 inverse_cov;
varying flat float amplitude;
varying flat float visibility;
varying vec2 point_px;

uniform vec3 filter_area_vectors[35];

varying flat float filter_edge_squared;
varying flat float filter_uv_width;
vec3 filter_bend(vec3 point, float phase) {
    float weight=clamp(point.y/0.65,0.0,1.0);
    vec2 fixed_bend=(fract(sin(vec2(phase,phase+19.7))*vec2(43758.5453,19642.349))-0.5)*0.07;
    float sway=sin(TIME*1.35+phase)*0.009+sin(TIME*2.1+phase*1.7)*0.003;
    point.xz+=(fixed_bend+vec2(sway,sway*0.55))*weight*weight;
    return point;
}

void vertex(){
vec2 filter_corner=UV;UV=UV2;

    vec3 origin = MODEL_MATRIX[3].xyz;
    vec3 proxy_delta=origin-cover_eye;
    vec2 proxy_limits=proxy_lod_edges*near_lod_metric;
    proxy_lod_weight=proxy_lod_transition?smoothstep(proxy_limits.x*proxy_limits.x,proxy_limits.y*proxy_limits.y,dot(proxy_delta,proxy_delta)):1.0;

    if(proxy_lod_transition && proxy_lod_weight<=0.0){POSITION=vec4(2.0,2.0,2.0,1.0);}else{
    float view_distance=distance(origin.xz,cover_eye.xz);
    float distance_weight = 1.0-smoothstep(distance_fade_start,distance_fade_end,view_distance);
    // Cheap canopy self-occlusion approximation, evaluated per vertex. It is
    // not a cast shadow and deliberately adds no shadow-map/depth/texture pass.
    float far_weight=smoothstep(24.0,56.0,view_distance);
    canopy_shade=1.0-distant_self_shade*far_weight*(1.0-smoothstep(0.0,0.9,UV.y));
    float age = cover_clock-INSTANCE_CUSTOM.x;
    coverage = distance_weight * (INSTANCE_CUSTOM.y>0.5?smoothstep(0.0,0.65,max(0.0,age)):1.0);
    root_shade = mix(0.64, 1.0, smoothstep(0.015, 0.19, VERTEX.y));
    float phase = dot(origin.xz, vec2(0.71, 0.43));
    variation = 0.95 + 0.05 * sin(phase * 3.7);
    if (!stone) {
        float weight = clamp(VERTEX.y / 0.65, 0.0, 1.0);
        // Stable slight per-instance curvature; no new geometry or texture reads.
        vec2 bend=(fract(sin(vec2(phase,phase+19.7))*vec2(43758.5453,19642.349))-0.5)*0.07;
        VERTEX.xz+=bend*weight*weight;

        float sway = sin(TIME * 1.35 + phase) * 0.009 + sin(TIME * 2.1 + phase * 1.7) * 0.003;
        VERTEX.x += sway * weight * weight * wind_strength;
        VERTEX.z += sway * weight * weight * 0.55 * wind_strength;
    }
    vec3 a=filter_bend(CUSTOM0.xyz,phase),b=filter_bend(CUSTOM1.xyz,phase),c=filter_bend(CUSTOM2.xyz,phase);
    mat4 mvp=PROJECTION_MATRIX*MODELVIEW_MATRIX;
    vec4 ca=mvp*vec4(a,1.0),cb=mvp*vec4(b,1.0),cc=mvp*vec4(c,1.0);
    if (proxy_triangle_in_view(ca,cb,cc)) {
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
    point_px=center_px+(filter_corner*2.0-1.0)*extent;
    VERTEX=(a+b+c)/3.0;
    vec4 clip=mvp*vec4(VERTEX,1.0);
    POSITION=vec4(point_px/(VIEWPORT_SIZE*0.5)*clip.w,clip.z,clip.w);

    filter_edge_squared=1.0/3.0;
    filter_uv_width=1.0;
    vec3 row_w=vec3(mvp[0].w,mvp[1].w,mvp[2].w);
    vec3 jac_x=(vec3(mvp[0].x,mvp[1].x,mvp[2].x)*clip.w-clip.x*row_w)/(clip.w*clip.w)*VIEWPORT_SIZE.x*0.5;
    vec3 jac_y=(vec3(mvp[0].y,mvp[1].y,mvp[2].y)*clip.w-clip.y*row_w)/(clip.w*clip.w)*VIEWPORT_SIZE.y*0.5;
    vec3 projected_normal=cross(jac_x,jac_y);
    int group=int(CUSTOM0.w+0.5);
    float projected_area=0.0;
    for(int bin=0;bin<5;bin++){projected_area+=abs(dot(projected_normal,filter_area_vectors[group+bin]));}
    amplitude=projected_area/(6.28318530718*sqrt(determinant));

    } else { POSITION=vec4(2.0,2.0,2.0,1.0); }
    }
}
void fragment(){
    // Complement the opaque screen mask. Multiplying both representations by
    // alpha would expose extra terrain in the middle of the transition.
    if(proxy_lod_transition && fract(52.9829189*fract(dot(floor(FRAGCOORD.xy),vec2(0.06711056,0.00583715))))>=proxy_lod_weight)discard;


    // Opaque coverage dithering keeps depth writes and avoids alpha sorting/overdraw.
    float threshold=fract(52.9829189*fract(dot(floor(FRAGCOORD.xy),vec2(0.06711056,0.00583715))));
    
    if (stone) {
        vec4 rock = texture(stone_color, UV);
        ALBEDO = rock.rgb * COLOR.rgb * variation;
        NORMAL_MAP = texture(stone_normal, UV).rgb;
        NORMAL_MAP_DEPTH = 0.55;
        ROUGHNESS = 0.94;
        SPECULAR = 0.24;
    } else {
        float edge = abs(UV.x - 0.5) * 2.0;
        float width = max(filter_uv_width, 0.008);
        float vein = 1.0 - smoothstep(width, width * 2.0, abs(UV.x - 0.5));
        float ribs = 0.96;
        ALBEDO = COLOR.rgb * variation * mix(1.0, 0.79, filter_edge_squared) * ribs + COLOR.rgb * vein * 0.16;
        ALBEDO *= root_shade;
        AO = mix(0.62,1.0,smoothstep(0.0,0.30,UV.y));
        AO_LIGHT_AFFECT = 0.35;
        if (grass_detail_strength > 0.0) {
            // UV.y runs root to tip; image top is the warm tip.
            // A blade is much narrower than it is long: sample a narrow surface strip.
            // Whole-square mapping stretches fine grain into painted vertical lines.
            float strip_start = clamp((variation - 0.95) * 14.0, 0.0, 0.7);
            vec3 detail = texture(grass_detail, vec2(strip_start + UV.x * 0.20, 1.0 - UV.y)).rgb;
            vec3 modulation = detail / max(grass_detail_mean, vec3(0.01));
            // Textured mode softens the old painted central rib instead of stacking it.
            vec3 textured = COLOR.rgb * variation * root_shade * modulation * 0.90;
            ALBEDO = mix(ALBEDO, textured, grass_detail_strength);
        }
        ALBEDO *= canopy_shade;
        ROUGHNESS = mix(0.84, 0.94, grass_detail_strength);
        SPECULAR = mix(0.2, 0.12, grass_detail_strength);
        BACKLIGHT = COLOR.rgb * mix(0.18, 0.10, grass_detail_strength);
        // Godot already faces double-sided normals toward the viewer.
    }

    vec2 delta=point_px-center_px;
    float quadratic=inverse_cov.x*delta.x*delta.x+2.0*inverse_cov.y*delta.x*delta.y+inverse_cov.z*delta.y*delta.y;
    ALPHA=clamp(amplitude*exp(-0.5*quadratic),0.0,1.0)*coverage;

if(dot(NORMAL,VIEW)<0.0)NORMAL=-NORMAL;

}
