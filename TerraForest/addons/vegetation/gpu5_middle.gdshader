shader_type spatial;
render_mode cull_disabled,depth_draw_opaque,diffuse_burley,specular_schlick_ggx;
#include "res://addons/vegetation/fade.gdshaderinc"
uniform sampler2DArray color_views : filter_linear_mipmap,repeat_disable;
uniform sampler2DArray normal_depth_views : filter_linear_mipmap,repeat_disable;
uniform sampler2DArray depth_views : filter_linear,repeat_disable;
uniform sampler2D outline_texture : filter_nearest,repeat_disable;
uniform bool depth_shape = false;
uniform bool distant = false;
uniform bool shadow_only = false;
uniform vec3 sun_direction = vec3(0.5,0.8,0.3);
varying vec2 sample_uv0;
varying vec2 sample_uv1;
varying vec2 sample_uv2;
varying flat vec3 sample_layers;
varying flat vec3 sample_weights;

varying flat vec4 state;
varying flat vec3 axis_x;varying flat vec3 axis_y;varying flat vec3 axis_z;
// The array stores sRGB bytes. Decode explicitly, independently of driver sRGB-view support.
vec3 linear_color(vec3 c){return mix(c/12.92,pow((c+vec3(0.055))/1.055,vec3(2.4)),step(vec3(0.04045),c));}
float elevation(float row){if(row<0.5)return -0.523598775598; if(row<1.5)return 0.0;if(row<2.5)return 0.523598775598;if(row<3.5)return 1.047197551197;return 1.483529864195;}
mat3 frame_basis(float layer){float az=mod(layer,64.0)*0.098174770425;float el=elevation(floor(layer/64.0));vec3 f=vec3(sin(az)*cos(el),sin(el),cos(az)*cos(el));vec3 r=vec3(cos(az),0.0,-sin(az));return mat3(r,cross(f,r),f);}
vec2 project_uv(mat3 b,vec3 p){return vec2(dot(b[0],p)/10.0+0.5,0.5-dot(b[1],p)/20.0);}
vec3 depth_hit(mat3 b,vec3 p,float layer){vec2 uv=project_uv(b,p);float d=textureLod(depth_views,vec3(uv,layer),0.0).r*24.0-12.0;return b*vec3((uv.x-0.5)*10.0,(0.5-uv.y)*20.0,d);}
void vertex(){
 vec4 layers; vec2 blend_view;
 float sc=length(MODEL_MATRIX[1].xyz);axis_x=MODEL_MATRIX[0].xyz/sc;axis_y=MODEL_MATRIX[1].xyz/sc;axis_z=MODEL_MATRIX[2].xyz/sc;mat3 world_axes=mat3(axis_x,axis_y,axis_z);
 vec3 center=(MODEL_MATRIX*vec4(0.0,9.23563575,0.0,1.0)).xyz;state=vec4(INSTANCE_CUSTOM.x,transition_weight(INSTANCE_CUSTOM),1.0-smoothstep(far_distance*0.93,far_distance,length(eye_world-center)),INSTANCE_CUSTOM.z);
 vec3 direction=normalize(eye_world-center);vec3 v=normalize(transpose(world_axes)*direction);
 float az=mod(atan(v.x,v.z)+2.0*PI,2.0*PI)*64.0/(2.0*PI);float a0=floor(az);float a1=mod(a0+1.0,64.0);
 float el=asin(clamp(v.y,-0.999999,0.999999));float r0=0.0;if(el>=0.0)r0=1.0;if(el>=0.523598775598)r0=2.0;if(el>=1.047197551197)r0=3.0;
 float er=clamp((el-elevation(r0))/(elevation(r0+1.0)-elevation(r0)),0.0,1.0);blend_view=vec2(fract(az),er);layers=vec4(r0*64.0+a0,r0*64.0+a1,(r0+1.0)*64.0+a0,(r0+1.0)*64.0+a1);

 mat3 b0=frame_basis(layers.x),b1=frame_basis(layers.y),b2=frame_basis(layers.z),b3=frame_basis(layers.w);
 vec3 right=vec3(cos(az*2.0*PI/64.0),0.0,-sin(az*2.0*PI/64.0));vec3 up=cross(v,right);
 vec2 screen=vec2(VERTEX.x,VERTEX.y);

 vec3 p=right*screen.x+up*screen.y;
 {vec3 h=mix(mix(depth_hit(b0,p,layers.x),depth_hit(b1,p,layers.y),blend_view.x),mix(depth_hit(b2,p,layers.z),depth_hit(b3,p,layers.w),blend_view.x),blend_view.y);p+=v*clamp(dot(h-p,v),-10.0,10.0);}
 // Per-tree angular choice is uniform across a primitive. Do it once per
 // vertex, not once per covered pixel, retaining the exact three-view weights.
 float x=blend_view.x;float y=blend_view.y;
 sample_uv0=project_uv(b0,p);sample_uv2=project_uv(b3,p);
 if(x>=y){sample_weights=vec3(1.0-x,x-y,y);sample_uv1=project_uv(b1,p);sample_layers=vec3(layers.x,layers.y,layers.w);}
 else{sample_weights=vec3(1.0-y,y-x,x);sample_uv1=project_uv(b2,p);sample_layers=vec3(layers.x,layers.z,layers.w);}
 VERTEX=sway(p+vec3(0.0,9.23563575,0.0),INSTANCE_CUSTOM.x);NORMAL=v;
}
void fragment(){
 if(transition_reject(FRAGCOORD.xy,state))discard;
 // Fully in-range pixels do not need the distance-fade hash.
 if(state.z<1.0 && pixel_noise(FRAGCOORD.yx,state.x+0.314)>state.z)discard;
 vec4 c0=texture(color_views,vec3(sample_uv0,sample_layers.x));
 vec4 c1=texture(color_views,vec3(sample_uv1,sample_layers.y));
 vec4 c2=texture(color_views,vec3(sample_uv2,sample_layers.z));
 // Capture gradients BEFORE the alpha kill. Explicit gradients keep normal-map
 // filtering independent of which neighboring lanes survived the coverage test.
 vec2 dx0=dFdx(sample_uv0),dy0=dFdy(sample_uv0);
 vec2 dx1=dFdx(sample_uv1),dy1=dFdy(sample_uv1);
 vec2 dx2=dFdx(sample_uv2),dy2=dFdy(sample_uv2);
 vec3 w=sample_weights*vec3(c0.a,c1.a,c2.a);
 float alpha=dot(w,vec3(1.0));
 if(alpha<0.24)discard;
 ALPHA=alpha;ALPHA_SCISSOR_THRESHOLD=0.24;
 // Normal samples and color transfer/lighting are not needed for empty pixels.
 vec3 n0=textureGrad(normal_depth_views,vec3(sample_uv0,sample_layers.x),dx0,dy0).rgb;
 vec3 n1=textureGrad(normal_depth_views,vec3(sample_uv1,sample_layers.y),dx1,dy1).rgb;
 vec3 n2=textureGrad(normal_depth_views,vec3(sample_uv2,sample_layers.z),dx2,dy2).rgb;
 vec3 lit_color=linear_color(c0.rgb)*w.x+linear_color(c1.rgb)*w.y;lit_color+=linear_color(c2.rgb)*w.z;
 ALBEDO=lit_color/max(alpha,0.001);
 vec3 n=normalize((n0*w.x+n1*w.y+n2*w.z)/max(alpha,0.001)*2.0-1.0+vec3(0.00001));
 NORMAL=normalize(mat3(VIEW_MATRIX)*mat3(axis_x,axis_y,axis_z)*n);
 METALLIC=0.0;SPECULAR=0.18;ROUGHNESS=0.93;
}
