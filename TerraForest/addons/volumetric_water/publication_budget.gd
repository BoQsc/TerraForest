# SPDX-License-Identifier: 0BSD
extends RefCounted
# Gameplay keeps short publication slices. Loading can spend more of a frame
# draining restored surfaces while player actions are blocked.
const MAX_PACKETS:=4
const SOFT_TIME_US:=1000

const LOADING_MAX_PACKETS:=16
const LOADING_SOFT_TIME_US:=4000
