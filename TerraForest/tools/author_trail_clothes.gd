# SPDX-License-Identifier: 0BSD
extends "res://tools/author_woven_clothes.gd"
## A second original garment pattern using the original project's primitive helpers.
const TRAIL_OUT="res://addons/characters/wearables/trail"

func triangle(a:Vector3,b:Vector3,c:Vector3,surface:int=0)->void:
	var fit:=Vector3(0,-.06,0) if garment==301 else Vector3.ZERO
	super.triangle(a+fit,b+fit,c+fit,surface)

func hat()->void:
	# A tapered felt crown, broad curved brim and separate leather hatband.
	var rows:Array=[]
	for ring:Vector4 in [Vector4(1.775,.122,.143,-.034),Vector4(1.83,.12,.141,-.034),Vector4(1.925,.094,.112,-.04),Vector4(1.945,.082,.101,-.04)]:
		var row:Array=[]
		for i in 49:
			var t:=TAU*i/48;row.append(Vector3(.003+sin(t)*ring.y,ring.x,cos(t)*ring.z+ring.w))
		rows.append(row)
	for k in 3:
		for i in 48:quad(rows[k][i],rows[k+1][i],rows[k+1][i+1],rows[k][i+1])
	for i in 48:triangle(Vector3(.003,1.947,-.04),rows[3][i],rows[3][i+1])
	var brim:Array=[]
	for k in 5:
		var row:Array=[]
		for i in 49:
			var t:=TAU*i/48;var f:=k/4.0
			row.append(Vector3(.003+sin(t)*lerpf(.122,.249,f),1.775+f*f*(.025*absf(sin(t))-.025*cos(t)),cos(t)*lerpf(.143,.275,f)-.034))
		brim.append(row)
	for k in 4:
		for i in 48:quad(brim[k][i],brim[k+1][i],brim[k+1][i+1],brim[k][i+1])
	ribbon(brim[4],.004,1)
	for i in 48:
		var a:=TAU*i/48;var b:=TAU*(i+1)/48
		quad(Vector3(sin(a)*.124+.003,1.783,cos(a)*.145-.034),Vector3(sin(a)*.123+.003,1.814,cos(a)*.144-.034),Vector3(sin(b)*.123+.003,1.814,cos(b)*.144-.034),Vector3(sin(b)*.124+.003,1.783,cos(b)*.145-.034),1)
	for x in [-.018,.018]:box(Vector3(x+.003,1.80,.113),Vector3(.005,.029,.008),2)
	for y in [1.788,1.812]:box(Vector3(.003,y,.113),Vector3(.039,.004,.008),2)

func jerkin_point(t:float,v:float)->Vector3:
	var p:=vest_point(t,v,.005)
	# Slightly longer rounded hem, with a small front slit for hip clearance.
	p.y-=.035*(1-v)*(1-.7*pow(maxf(0,cos(t)),12))
	return p

func jerkin()->void:
	var rows:Array=[]
	for k in 13:
		var row:Array=[]
		for i in 65:row.append(jerkin_point(lerpf(.035,TAU-.035,i/64.0),k/12.0))
		rows.append(row)
	for k in 12:
		for i in 64:quad(rows[k][i],rows[k+1][i],rows[k+1][i+1],rows[k][i+1])
	ribbon(rows[0],.005,1);ribbon(rows[12],.005,1)
	for side in [-1,1]:
		var a:Array=[];var b:Array=[]
		for i in 13:
			var t:=i/12.0;var z:=lerpf(.155,-.191,t);var y:=1.49+.058*sin(PI*t)
			a.append(Vector3(side*.116+.003,y,z));b.append(Vector3(side*.198+.003,y-.012,z))
			if i>0:quad(a[i-1],a[i],b[i],b[i-1])
		ribbon(a,.005,1);ribbon(b,.005,1)
	# Broad off-centre front fastening, three brass studs and a waist belt.
	for k in 10:
		var y:=lerpf(1.075,1.435,k/10.0);var next:=lerpf(1.075,1.435,(k+1)/10.0)
		quad(Vector3(-.008,y,.185),Vector3(-.008,next,.185),Vector3(.055,next,.184),Vector3(.055,y,.184),1)
	for y in [1.18,1.29,1.40]:box(Vector3(.025,y,.196),Vector3(.016,.016,.009),2)
	for i in 64:
		var a:=TAU*i/64;var b:=TAU*(i+1)/64
		quad(Vector3(.003+sin(a)*.217,1.082,cos(a)*.18-.018),Vector3(.003+sin(a)*.218,1.124,cos(a)*.181-.018),Vector3(.003+sin(b)*.218,1.124,cos(b)*.181-.018),Vector3(.003+sin(b)*.217,1.082,cos(b)*.18-.018),1)
	for x in [-.025,.025]:box(Vector3(x+.003,1.103,.169),Vector3(.006,.043,.012),2)
	for y in [1.084,1.122]:box(Vector3(.003,y,.169),Vector3(.056,.006,.012),2)
	# One asymmetric gusseted utility pouch with flap and fastening.
	box(Vector3(-.145,1.10,.142),Vector3(.10,.142,.068),1)
	box(Vector3(-.145,1.157,.181),Vector3(.107,.043,.012),0)
	box(Vector3(-.145,1.146,.192),Vector3(.013,.013,.008),2)

func trail_boot(side:int,t:float,k:int)->Vector3:
	var y:float=[-.01,.024,.067,.108,.16,.23,.32,.39][k]
	var rx:float=[.09,.092,.09,.078,.072,.096,.098,.10][k]
	var rz:float=[.169,.17,.158,.118,.096,.108,.11,.112][k]
	var z:float=[.015,.015,.014,-.005,-.046,-.068,-.068,-.065][k]
	var x:=side*lerpf(.148,.132,smoothstep(.14,.4,y))+.003
	return Vector3(x+sin(t)*rx,y,cos(t)*rz+z)

func boots()->void:
	for side in [-1,1]:
		for k in 7:
			for i in 32:
				var a:=TAU*i/32;var b:=TAU*(i+1)/32
				quad(trail_boot(side,a,k),trail_boot(side,a,k+1),trail_boot(side,b,k+1),trail_boot(side,b,k),1 if k==0 else 0)
		for i in 32:triangle(Vector3(side*.148+.003,-.01,.015),trail_boot(side,TAU*i/32,0),trail_boot(side,TAU*(i+1)/32,0),1)
		for k in [4,7]:
			var rim:Array=[]
			for i in 33:rim.append(trail_boot(side,TAU*i/32,k)+Vector3(0,-.008 if k==7 else 0,0))
			ribbon(rim,.011 if k==7 else .006,1)
		# Four short lace crossings on the instep.
		for i in 4:
			var y:=.106+i*.019;var z:=.101-i*.012
			for s in [-1,1]:ribbon([Vector3(side*.148+s*.024+.003,y,z),Vector3(side*.148-s*.024+.003,y+.014,z-.012)],.003,1)
		box(Vector3(side*.218,.28,-.035),Vector3(.009,.032,.025),2)

func run()->void:
	DirAccess.make_dir_recursive_absolute(TRAIL_OUT)
	var records:Array=[]
	for id in [304,305,306]:
		garment=id-3;triangles=0;surfaces.clear();materials.clear()
		materials.append(make_material({304:"344b58",305:"99593e",306:"604a35"}[id],id!=306))
		materials.append(make_material("342f29",false));materials.append(make_material("b6a06a",false))
		for mat in materials:
			var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES);st.set_material(mat);surfaces.append(st)
		if id==304:hat()
		elif id==305:jerkin()
		else:boots()
		var mesh:=ArrayMesh.new();var portable:=ArrayMesh.new()
		for st in surfaces:st.generate_normals();st.index();st.commit(mesh)
		mesh.set_meta("bone_names",BONES);mesh.set_meta("license","CC0-1.0");mesh.set_meta("item_id",id)
		var path:=TRAIL_OUT.path_join("%d.res"%id)
		if ResourceSaver.save(mesh,path,ResourceSaver.FLAG_COMPRESS)!=OK:quit(1);return
		for s in mesh.get_surface_count():
			var arrays:=mesh.surface_get_arrays(s);arrays[Mesh.ARRAY_BONES]=null;arrays[Mesh.ARRAY_WEIGHTS]=null
			portable.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);portable.surface_set_material(s,mesh.surface_get_material(s))
		var node:=MeshInstance3D.new();node.name={304:"Trail_Hat",305:"Trail_Jerkin",306:"Trail_Boots"}[id];node.mesh=portable
		var doc:=GLTFDocument.new();var state:=GLTFState.new()
		if doc.append_from_scene(node,state)!=OK or doc.write_to_filesystem(state,TRAIL_OUT.path_join("%d.glb"%id))!=OK:node.free();quit(1);return
		node.free();records.append({"id":id,"triangles":triangles,"resource":path,"sha256":FileAccess.get_sha256(path),"portable_sha256":FileAccess.get_sha256(TRAIL_OUT.path_join("%d.glb"%id))})
		print("TRAIL_MESH ",id," triangles=",triangles," bounds=",mesh.get_aabb())
	var receipt:=FileAccess.open(TRAIL_OUT.path_join("manifest.json"),FileAccess.WRITE)
	receipt.store_string(JSON.stringify({"version":1,"license":"CC0-1.0","author":"TerraForest contributors with OpenAI Codex","date":"2026-11-01","source":"Original garment patterns; original woven-pack primitive helpers, no imported garment geometry or textures","prompt":"Apply the woven outfit to the trader and try more 3D clothing packs; a distinct trail hat, belted jerkin and tall boots","authoring_tool":Engine.get_version_info().string,"recipe":"tools/author_trail_clothes.gd","recipe_sha256":FileAccess.get_sha256("res://tools/author_trail_clothes.gd"),"base_recipe_sha256":FileAccess.get_sha256("res://tools/author_woven_clothes.gd"),"bones":BONES,"items":records},"  ")+"\n")
	print("TRAIL_AUTHOR complete");quit()
