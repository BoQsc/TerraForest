# SPDX-License-Identifier: 0BSD
extends RefCounted
# Offline design acceptance, separate from native edit feasibility. These are
# project defaults for ordinary inhabited sites, not universal engineering limits.
const VERSION:=1
const MAX_FILL:=2.0
const MAX_CUT:=3.0
static func site(survey:Dictionary,label:String)->Dictionary:
 var result:Dictionary={"site":label,"status":"unreviewed","issues":[]}
 if not survey.get("ok",false) or not survey.has("grade") or not survey.has("min_height") or not survey.has("max_height"):
  result.issues.append("Missing successful pre-edit surface survey")
  return result
 var low:float=survey.min_height;var high:float=survey.max_height;var grade:float=survey.grade
 if not is_finite(low) or not is_finite(high) or not is_finite(grade) or low>high:
  result.issues.append("Invalid surface survey");return result
 result.max_fill=maxf(0,grade-low);result.max_cut=maxf(0,high-grade)
 result.relief=high-low;result.grade=grade
 result.status="pass"
 if result.max_fill>MAX_FILL:
  result.issues.append("Single-grade layout requires more than 2 m fill; relocate or divide into independently graded blocks")
 if result.max_cut>MAX_CUT:
  result.issues.append("Single-grade layout requires more than 3 m cut; relocate or divide into independently graded blocks")
 if not result.issues.is_empty():result.status="rejected"
 return result
static func summary(sites:Array)->Dictionary:
 var rejected:=false
 for entry:Dictionary in sites:rejected=rejected or entry.status=="rejected"
 # A feasible site never implies a finished world. Visual/player/ecology and
 # performance acceptance require separate evidence, not a fabricated green flag.
 return {"standard_version":VERSION,"status":"rejected" if rejected else "unreviewed","sites":sites,"pending":["landscape and shoreline review","building variety and exploration review","road and pedestrian connectivity","ecology continuity","streaming and representative performance"]}
