shader_type spatial;
render_mode diffuse_burley;
uniform sampler2D stone_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 mineral_color : source_color = vec3(0.47,0.51,0.56);
varying vec3 stone_position;
varying vec3 stone_normal;
void vertex(){
 stone_position=VERTEX;
 stone_normal=NORMAL;
}
void fragment(){
 vec3 weights=pow(abs(normalize(stone_normal)),vec3(4.0));
 weights/=max(dot(weights,vec3(1.0)),0.0001);
 vec3 projected=stone_position*5.0;
 vec3 granite=texture(stone_texture,projected.yz).rgb*weights.x+texture(stone_texture,projected.xz).rgb*weights.y+texture(stone_texture,projected.xy).rgb*weights.z;
 float grain=clamp(dot(granite,vec3(.2126,.7152,.0722))*2.0,.45,1.35);
 float seam=sin(dot(projected,vec3(3.0,8.0,2.0))+sin(projected.x*9.0+projected.z*6.0)*.6);
 float deposit=smoothstep(-.85,-.1,seam+granite.r*.35);
 ALBEDO=mix(granite*.62,mineral_color*grain,deposit*.92);
 METALLIC=.15*deposit;
 ROUGHNESS=.9;
 SPECULAR=.25;
}
