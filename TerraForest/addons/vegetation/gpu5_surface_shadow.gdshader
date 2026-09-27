shader_type spatial;
render_mode cull_disabled,depth_draw_opaque,unshaded;
#include "res://addons/vegetation/fade.gdshaderinc"
uniform sampler2D base_tex : source_color,filter_linear_mipmap_anisotropic,repeat_enable;
uniform sampler2D normal_tex : hint_normal,filter_linear_mipmap_anisotropic,repeat_enable;
uniform sampler2D orm_tex : filter_linear_mipmap_anisotropic,repeat_enable;
uniform bool foliage = false;
uniform bool shadow_only = false;
uniform float normal_strength = 0.48;
uniform float ao_strength = 0.45;
varying flat vec4 instance_state;
void vertex(){vec3 center=(MODEL_MATRIX*vec4(0.0,9.23563575,0.0,1.0)).xyz;instance_state=vec4(INSTANCE_CUSTOM.x,transition_weight(INSTANCE_CUSTOM),1.0-smoothstep(far_distance*0.93,far_distance,length(eye_world-center)),INSTANCE_CUSTOM.z);VERTEX=sway(VERTEX,INSTANCE_CUSTOM.x);}
void fragment(){
 if(transition_reject(FRAGCOORD.xy,instance_state))discard;
 
 vec4 b=texture(base_tex,UV);if(b.a<0.24)discard;
 ALPHA=b.a;ALPHA_SCISSOR_THRESHOLD=0.24;ALBEDO=b.rgb*COLOR.rgb;METALLIC=0.0;SPECULAR=0.18;
 ROUGHNESS=0.95;
}
