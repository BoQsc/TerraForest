// SPDX-License-Identifier: 0BSD
// v0.4.5: continuous material weights; cached cavity visibility; no field rays per pixel.
shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_schlick_ggx, ambient_light_disabled;
uniform sampler2D grass : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D gravel : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D sand : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D snow : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform bool show_lod = false;
uniform bool show_material = false;
uniform bool show_visibility = false;
uniform vec3 sky_fill : source_color = vec3(0.30, 0.34, 0.40);
uniform float snow_reflectance = 0.68;
uniform bool alpine_snow_enabled = false;
uniform int debug_view = 0;
uniform bool cached_sun_enabled = true;
varying vec3 wp;
varying vec3 wn;
varying vec2 visibility;
varying vec4 material_weights;
// Gradients are computed before the material branches. Implicit derivatives
// inside non-uniform branches can choose invalid mip levels on some drivers.
vec3 triplanar(sampler2D tex, vec3 p, vec3 w, vec3 dx, vec3 dy) {
 return textureGrad(tex,p.zy,dx.zy,dy.zy).rgb*w.x
      + textureGrad(tex,p.xz,dx.xz,dy.xz).rgb*w.y
      + textureGrad(tex,p.xy,dx.xy,dy.xy).rgb*w.z;
}
void vertex(){
 wp=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
 wn=normalize(MODEL_NORMAL_MATRIX*NORMAL);
 visibility=UV;
 material_weights=COLOR;
}
void fragment(){
 vec3 n=normalize(wn);
 vec3 w=pow(abs(n),vec3(4.0));w/=max(dot(w,vec3(1.0)),0.0001);
 vec3 p=wp/5.0;
 vec3 dx=dFdx(p),dy=dFdy(p);
 float exact_material=UV2.x;
 vec3 color;
 METALLIC=0.0;ROUGHNESS=0.98;SPECULAR=0.15;
 if(exact_material>6.5){color=vec3(0.32,0.37,0.42);METALLIC=0.65;ROUGHNESS=0.45;}
 else if(exact_material>5.5){color=vec3(0.28,0.14,0.055);}
 else if(exact_material>4.5){color=triplanar(gravel,p,w,dx,dy);}
 else {
  vec3 blend=clamp(material_weights.rgb,vec3(0.0),vec3(1.0));
  float total=clamp(dot(blend,vec3(1.0)),0.0,1.0);
  float exposed=max(material_weights.a,1.0-smoothstep(0.52,0.76,n.y));
  // Never interpolate a categorical material ID and threshold it. That was
  // painting unmodified corner vertices with rectangular stone fringes.
  float rock_weight=exposed*(1.0-total)+blend.r;
  float biome_weight=(1.0-exposed)*(1.0-total);
  vec3 wood=vec3(0.28,0.14,0.055)*(0.94+0.06*sin(wp.y*18.0+sin(wp.x*1.8)));
  color=wood*blend.g+vec3(0.32,0.37,0.42)*blend.b;
  if(rock_weight>0.001)color+=triplanar(gravel,p,w,dx,dy)*rock_weight;
  if(biome_weight>0.001){
   vec2 climate=smoothstep(vec2(940.0),vec2(1060.0),wp.xz);
   vec4 biome=vec4((1.0-climate.x)*climate.y,(1.0-climate.x)*(1.0-climate.y),climate.x*climate.y,climate.x*(1.0-climate.y));
   vec3 natural=vec3(0.0);
   // One texture in biome interiors; extra samples only inside transition bands.
   if(biome.x>0.001)natural+=triplanar(grass,p,w,dx,dy)*biome.x;
   if(biome.y>0.001)natural+=triplanar(gravel,p,w,dx,dy)*biome.y;
   if(biome.z>0.001)natural+=triplanar(sand,p,w,dx,dy)*biome.z;
   if(biome.w>0.001)natural+=triplanar(snow,p,w,dx,dy)*snow_reflectance*biome.w;
   float alpine=alpine_snow_enabled?smoothstep(150.0,185.0,wp.y)*smoothstep(0.60,0.85,n.y):0.0;
   if(alpine>0.001)natural=mix(natural,triplanar(snow,p,w,dx,dy)*snow_reflectance,alpine);
   color+=natural*biome_weight;
  }
  METALLIC=0.65*blend.b;ROUGHNESS=mix(0.98,0.45,blend.b);
 }
 ALBEDO=min(color,vec3(0.82));
 // There is no uniform ambient source inside sealed caves. This is a cached
 // direct-sky fill, NOT GI. The flashlight is an ordinary shadow-casting light.
 EMISSION=ALBEDO*sky_fill*sqrt(clamp(visibility.x,0.0,1.0));
 if(show_lod){float s=UV2.y;ALBEDO=s<1.5?vec3(0.16,0.75,0.3):(s<3.0?vec3(0.9,0.75,0.1):(s<6.0?vec3(0.95,0.36,0.1):vec3(0.15,0.38,0.95)));}
 if(show_material){ALBEDO=material_weights.rgb;EMISSION=ALBEDO;}
 if(show_visibility){ALBEDO=vec3(visibility.y,visibility.x,0.0);EMISSION=ALBEDO;}
 if(debug_view>0){
  vec3 diagnostic=color;
  if(debug_view==1)diagnostic=wp.x>=1000.0?(wp.z>=1000.0?vec3(.8,.55,.16):vec3(.85,.9,1.0)):(wp.z>=1000.0?vec3(.1,.65,.15):vec3(.4,.4,.4));
  if(debug_view==2){float coverage=wp.x>=1000.0&&wp.z<1000.0?1.0:0.0;if(alpine_snow_enabled)coverage=max(coverage,smoothstep(150.0,185.0,wp.y)*smoothstep(.60,.85,n.y));diagnostic=vec3(coverage);}
  if(debug_view==4)diagnostic=vec3(visibility.x);
  if(debug_view==5)diagnostic=vec3(visibility.y);
  if(debug_view==6)diagnostic=n*.5+.5;
  ALBEDO=vec3(0.0);EMISSION=diagnostic;
 }
}
void light(){
 // Directional ATTENUATION already contains engine shadowing. Use the
 // more occluded mask, not their product (which doubled fractional darkness).
 float attenuation=ATTENUATION;
 if(LIGHT_IS_DIRECTIONAL&&cached_sun_enabled)attenuation=min(attenuation,clamp(visibility.y,0.0,1.0));
 if(debug_view>0)attenuation=0.0;
 DIFFUSE_LIGHT+=max(dot(NORMAL,LIGHT),0.0)*attenuation*LIGHT_COLOR/PI;
 // Rough terrain has no highlight. Preserve a cheap direct highlight for metal.
 if(METALLIC>0.01){vec3 h=normalize(LIGHT+VIEW);SPECULAR_LIGHT+=pow(max(dot(NORMAL,h),0.0),32.0)*attenuation*LIGHT_COLOR*METALLIC*0.15;}
}
