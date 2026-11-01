# SPDX-License-Identifier: 0BSD
extends SceneTree
## Original parametric garment patterns. No source character vertices are read.
const OUT="res://addons/characters/wearables/woven"
const BONES=["Hips","Spine","Spine1","Spine2","Neck","Head","LeftLeg","LeftFoot","RightLeg","RightFoot"]
var surfaces:Array[SurfaceTool]=[]
var materials:Array[StandardMaterial3D]=[]
var garment:=301
var triangles:=0

func _initialize()->void:run.call_deferred()

func weights(p:Vector3)->Dictionary:
	if garment==301:
		var head:=smoothstep(1.49,1.61,p.y)
		return {"bones":PackedInt32Array([3,5,0,0]),"weights":PackedFloat32Array([1-head,head,0,0])}
	if garment==303:
		var leg:=smoothstep(.12,.25,p.y)
		var index:=6 if p.x>0 else 8
		return {"bones":PackedInt32Array([index,index+1,0,0]),"weights":PackedFloat32Array([leg,1-leg,0,0])}
	var levels:=[1.01,1.11,1.23,1.36]
	for index in 3:
		if p.y<levels[index+1]:
			var blend:=smoothstep(levels[index],levels[index+1],p.y)
			return {"bones":PackedInt32Array([index,index+1,0,0]),"weights":PackedFloat32Array([1-blend,blend,0,0])}
	return {"bones":PackedInt32Array([3,0,0,0]),"weights":PackedFloat32Array([1,0,0,0])}

func triangle(a:Vector3,b:Vector3,c:Vector3,surface:int=0)->void:
	if (b-a).cross(c-a).length_squared()<1e-13:return
	var st:=surfaces[surface]
	for p in [a,b,c]:
		var w:=weights(p);st.set_bones(w.bones);st.set_weights(w.weights)
		st.set_uv(Vector2(p.x+p.z*.37,p.y)*12.0);st.add_vertex(p)
	triangles+=1

func quad(a:Vector3,b:Vector3,c:Vector3,d:Vector3,surface:int=0)->void:
	triangle(a,b,c,surface);triangle(a,c,d,surface)

func ribbon(points:Array,width:float,surface:int=1)->void:
	# Small round stitched binding; ends meet at the underlying fabric.
	for i in points.size()-1:
		var along:Vector3=(points[i+1]-points[i]).normalized()
		var across:=along.cross(Vector3.FORWARD).normalized()
		if across.length_squared()<.01:across=along.cross(Vector3.UP).normalized()
		var other:=along.cross(across).normalized()
		for j in 6:
			var a:=TAU*j/6;var b:=TAU*(j+1)/6
			var da:Vector3=(across*cos(a)+other*sin(a))*width
			var db:Vector3=(across*cos(b)+other*sin(b))*width
			quad(points[i]+da,points[i]+db,points[i+1]+db,points[i+1]+da,surface)

func box(center:Vector3,size:Vector3,surface:int)->void:
	var p:Array=[]
	for y in [-1,1]:
		for z in [-1,1]:
			for x in [-1,1]:p.append(center+size*Vector3(x,y,z)*.5)
	for f in [[0,1,3,2],[4,6,7,5],[0,4,5,1],[2,3,7,6],[0,2,6,4],[1,5,7,3]]:quad(p[f[0]],p[f[1]],p[f[2]],p[f[3]],surface)

func hood()->void:
	# y / lateral radius / depth radius / center z / open-face half angle.
	var rings:=[Vector4(1.465,.235,.185,-.035),Vector4(1.53,.14,.15,-.035),Vector4(1.61,.14,.165,-.035),Vector4(1.70,.145,.165,-.035),Vector4(1.78,.128,.15,-.04),Vector4(1.825,.085,.105,-.045),Vector4(1.85,.006,.01,-.05)]
	var opening:=[.65,.85,.87,.77,.45,0.,0.]
	var rows:Array=[]
	for k in rings.size():
		var r:Vector4=rings[k];var row:Array=[]
		for j in 41:
			var angle:float=lerpf(opening[k],TAU-opening[k],j/40.0)
			row.append(Vector3(.003+sin(angle)*r.y,r.x,cos(angle)*r.z+r.w))
		rows.append(row)
	for k in rows.size()-1:
		for j in 40:quad(rows[k][j],rows[k+1][j],rows[k+1][j+1],rows[k][j+1])
	for j in [0,40]:
		var edge:Array=[]
		for row:Array in rows:edge.append(row[j])
		ribbon(edge,.007)
	ribbon(rows[0],.006)
	var seam:Array=[]
	for row:Array in rows:seam.append(row[20]+Vector3(0,0,-.004))
	ribbon(seam,.003,1)
	for side in [-1,1]:
		ribbon([Vector3(side*.10,1.52,.075),Vector3(side*.06,1.465,.155),Vector3(side*.025,1.44,.17)],.004,2)
	box(Vector3(0,1.445,.174),Vector3(.055,.012,.014),2)

func vest_point(t:float,v:float,offset:float=0)->Vector3:
	var side:=absf(sin(t))
	# A scalloped upper edge leaves real armholes and an open neck.
	var top:=lerpf(1.445,1.53,smoothstep(.20,.64,side))
	top=lerpf(top,1.295,smoothstep(.76,.98,side))
	var y:=lerpf(1.035,top,v)
	var chest:=smoothstep(1.1,1.4,y)
	var rx:=lerpf(.205,.243,chest)+offset
	var rz:=lerpf(.168,.194,chest)+offset
	return Vector3(.003+sin(t)*rx,y,cos(t)*rz-.018)

func vest()->void:
	var rows:Array=[]
	for k in 13:
		var row:Array=[]
		for j in 65:row.append(vest_point(lerpf(.045,TAU-.045,j/64.0),k/12.0))
		rows.append(row)
	for k in 12:
		for j in 64:quad(rows[k][j],rows[k+1][j],rows[k+1][j+1],rows[k][j+1])
	ribbon(rows[0],.007,1);ribbon(rows[12],.007,1)
	for j in [0,64]:
		var line:Array=[]
		for row:Array in rows:line.append(row[j]+Vector3(0,0,.003))
		ribbon(line,.009,2)
	# Arched shoulder bridges connect the front and back panels.
	for side in [-1,1]:
		var edge_a:Array=[];var edge_b:Array=[]
		for j in 13:
			var t:=j/12.0;var z:=lerpf(.15,-.186,t)
			var y:=1.49+.058*sin(PI*t)
			edge_a.append(Vector3(side*.116+.003,y,z));edge_b.append(Vector3(side*.192+.003,y-.012,z))
			if j>0:quad(edge_a[j-1],edge_a[j],edge_b[j],edge_b[j-1])
		ribbon(edge_a,.006);ribbon(edge_b,.006)
		# Bellows pocket and contrasting flap, fitted to the front quarters.
		var c:=Vector3(side*.108+.003,1.175,.147)
		box(c,Vector3(.123,.135,.042),0)
		box(c+Vector3(0,.056,.024),Vector3(.13,.037,.009),1)
		box(c+Vector3(0,.047,.032),Vector3(.013,.013,.009),2)
		ribbon([c+Vector3(-.058,.045,.025),c+Vector3(-.058,-.064,.025),c+Vector3(.058,-.064,.025),c+Vector3(.058,.045,.025)],.0025,1)
	for y in [1.30,1.38,1.435]:
		var p:=Vector3(.003,y,.184)
		box(p,Vector3(.065,.013,.018),2)
		for x in [-.021,.021]:ribbon([p+Vector3(x,-.013,.002),p+Vector3(x,.013,.005)],.003,1)

func boot_point(side:int,t:float,k:int)->Vector3:
	var y:float=[-.009,.025,.068,.105,.15,.205,.24][k]
	var rx:float=[.09,.092,.09,.078,.068,.071,.075][k]
	var rz:float=[.169,.17,.158,.118,.092,.088,.085][k]
	var z:float=[.015,.015,.014,-.005,-.046,-.052,-.052][k]
	return Vector3(side*.148+.003+sin(t)*rx,y,cos(t)*rz+z)

func footwraps()->void:
	for side in [-1,1]:
		for k in 6:
			for j in 32:
				var a:=TAU*j/32;var b:=TAU*(j+1)/32
				quad(boot_point(side,a,k),boot_point(side,a,k+1),boot_point(side,b,k+1),boot_point(side,b,k),2 if k==0 else 0)
		for j in 32:triangle(Vector3(side*.148+.003,-.009,.015),boot_point(side,TAU*j/32,0),boot_point(side,TAU*(j+1)/32,0),2)
		var rim:Array=[]
		for j in 33:rim.append(boot_point(side,TAU*j/32,6))
		ribbon(rim,.005,1)
		# Two opposing spiral bindings read as overlapping woven strips.
		for turn in [-1,1]:
			for j in 96:
				var a:=j/96.0;var b:=(j+1)/96.0
				var p:Array=[]
				for t in [a,b]:
					var angle:float=t*TAU*2*turn
					var y:float=lerpf(.07,.225,t);var section:=clampf((y-.105)/.045+3,2,5.99)
					var k:=int(section);var f:=section-k
					var at:=boot_point(side,angle,k).lerp(boot_point(side,angle,k+1),f)+Vector3(sin(angle)*.004,0,cos(angle)*.004)
					p.append(at+Vector3(0,-.008,0));p.append(at+Vector3(0,.008,0))
				quad(p[0],p[1],p[3],p[2],1)

func make_material(color:String,cloth:bool)->StandardMaterial3D:
	var mat:=StandardMaterial3D.new();mat.albedo_color=Color(color);mat.roughness=.94
	mat.cull_mode=BaseMaterial3D.CULL_DISABLED
	if cloth:
		var pattern:=Image.create(64,64,false,Image.FORMAT_RGB8)
		for y in 64:
			for x in 64:
				var warp:bool=(x/4+y/4)%2==0
				var value:=.83+.17*sin((x if warp else y)%4*PI/4.0)
				pattern.set_pixel(x,y,Color(value,value,value))
		pattern.generate_mipmaps();mat.albedo_texture=ImageTexture.create_from_image(pattern)
	return mat

func run()->void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var records:Array=[]
	for id in [301,302,303]:
		garment=id;triangles=0;surfaces.clear();materials.clear()
		materials.append(make_material("697754" if id==301 else ("8d9673" if id==302 else "827557"),true))
		materials.append(make_material("c1b58b",true));materials.append(make_material("544330",false))
		for mat in materials:
			var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES);st.set_material(mat);surfaces.append(st)
		if id==301:hood()
		elif id==302:vest()
		else:footwraps()
		var mesh:=ArrayMesh.new();var portable:=ArrayMesh.new()
		for st in surfaces:
			st.generate_normals();st.index();st.commit(mesh)
		mesh.set_meta("bone_names",BONES);mesh.set_meta("license","CC0-1.0");mesh.set_meta("item_id",id)
		var path:=OUT.path_join("%d.res"%id)
		if ResourceSaver.save(mesh,path,ResourceSaver.FLAG_COMPRESS)!=OK:quit(1);return
		for s in mesh.get_surface_count():
			var arrays:=mesh.surface_get_arrays(s);arrays[Mesh.ARRAY_BONES]=null;arrays[Mesh.ARRAY_WEIGHTS]=null
			portable.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);portable.surface_set_material(s,mesh.surface_get_material(s))
		var node:=MeshInstance3D.new();node.name={301:"Woven_Hood",302:"Woven_Vest",303:"Woven_Footwraps"}[id];node.mesh=portable
		var doc:=GLTFDocument.new();var state:=GLTFState.new()
		if doc.append_from_scene(node,state)!=OK or doc.write_to_filesystem(state,OUT.path_join("%d.glb"%id))!=OK:node.free();quit(1);return
		node.free()
		records.append({"id":id,"triangles":triangles,"resource":path,"sha256":FileAccess.get_sha256(path),"portable_sha256":FileAccess.get_sha256(OUT.path_join("%d.glb"%id))})
		print("WOVEN_MESH ",id," triangles=",triangles," bounds=",mesh.get_aabb())
	var receipt:=FileAccess.open(OUT.path_join("manifest.json"),FileAccess.WRITE)
	receipt.store_string(JSON.stringify({"version":1,"license":"CC0-1.0","author":"TerraForest contributors with OpenAI Codex","date":"2026-11-01","source":"Original mathematical garment patterns; no imported garment geometry or textures","prompt":"Author/add a wearable 3D clothes items pack for the existing 3D character view","authoring_tool":Engine.get_version_info().string,"recipe":"tools/author_woven_clothes.gd","recipe_sha256":FileAccess.get_sha256("res://tools/author_woven_clothes.gd"),"bones":BONES,"items":records},"  ")+"\n")
	print("WOVEN_AUTHOR complete");quit()
