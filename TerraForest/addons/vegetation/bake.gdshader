shader_type spatial;
render_mode unshaded,cull_disabled,depth_draw_opaque,fog_disabled;
uniform sampler2D base_tex : source_color,filter_linear,repeat_enable;
uniform sampler2D normal_tex : hint_normal,filter_linear,repeat_enable;
uniform sampler2D orm_tex : filter_linear,repeat_enable;
uniform bool foliage = false;
uniform float normal_strength = 0.48;
uniform float ao_strength = 0.45;
uniform int channel = 0;
uniform vec3 eye_direction = vec3(0.0,0.0,1.0);
varying vec3 object_pos;
varying vec3 n_local;
varying vec3 t_local;
varying vec3 b_local;
void vertex(){object_pos=VERTEX;n_local=NORMAL;t_local=TANGENT;b_local=BINORMAL;}
void fragment(){
 vec4 base=texture(base_tex,UV);if(foliage && base.a<0.24)discard;
 ALPHA=1.0;ALPHA_SCISSOR_THRESHOLD=0.24;
 if(channel==0){ALBEDO=base.rgb*COLOR.rgb;}
 if(channel==1){vec3 n=n_local;if(!FRONT_FACING)n=-n;vec2 xy=texture(normal_tex,UV).rg*2.0-1.0;float z=sqrt(max(0.0,1.0-dot(xy,xy)));n=normalize(mix(n,t_local*xy.x+b_local*xy.y+n*z,normal_strength));ALBEDO=n*0.5+0.5;}
 if(channel==2){float d=dot(object_pos-vec3(0.0,9.23563575,0.0),eye_direction);ALBEDO=vec3(clamp(d/24.0+0.5,0.005,0.995));}
}
