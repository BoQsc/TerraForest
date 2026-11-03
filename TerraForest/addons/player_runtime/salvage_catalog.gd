# SPDX-License-Identifier: 0BSD
extends RefCounted
const NAMES={224:"Metal offcuts",225:"Cloth scraps",226:"Copper wire",227:"Loose fasteners"}
const DESCRIPTIONS={224:"Bent sheet offcuts. Recycle 3 into 1 metal.",225:"Worn fabric strips. Unravel 2 into 3 plant fibre.",226:"Short coils of copper wire. Recycle 2 into 1 copper ore.",227:"Mixed nuts, bolts and washers. Recycle 4 into 1 metal."}
static func supplies(seed_value:int,identity:int)->PackedInt64Array:
	var random:=RandomNumberGenerator.new();random.seed=seed_value^identity^0x192aff31
	var first:int=224+random.randi_range(0,3)
	var second:int=224+posmod(first-224+random.randi_range(1,3),4)
	var stock:=PackedInt64Array([first,random.randi_range(2,5),second,random.randi_range(1,4)])
	if random.randi_range(0,2)==0:stock.append_array(PackedInt64Array([210,random.randi_range(1,3)]))
	if random.randi_range(0,3)==0:stock.append_array(PackedInt64Array([218,1]))
	return stock
