# SPDX-License-Identifier: 0BSD
extends RefCounted
# Append-only species and inventory identity catalog. Native packing has 9 slots.
const COUNT:=9
const ITEMS: Array[int]=[201,204,205,206,207,208,209,210,212]
const NAMES: Array[String]=["Stone","Fern","Grass clump","White wildflower","Golden wildflower","Violet wildflower","Low bush","Dry twigs","Woody bush"]
const WORLD_HINTS: Array[bool]=[true,false,false,true,true,true,false,false,false]
const HARVEST_ONLY: Array[bool]=[false,false,false,false,false,false,true,false,true]
# Twigs yield and cost one existing wood unit: no conversion duplication.
const COSTS: Array[int]=[201,204,205,206,207,208,209,102,212]
const REWARDS: Array[int]=[201,204,205,206,207,208,209,102,102]
const DISTANCES: Array[float]=[112.0,96.0,80.0,80.0,80.0,80.0,96.0,80.0,112.0]
