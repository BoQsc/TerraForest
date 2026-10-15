# Enclosed combined route — superseded diagnosis

Correction: the Y79.5 value was the changed review save's PLAYER position,
not a cottage floor. Actual doors are Y49, supported by terrain Y47. Source
canonical hash changed after publication; one door was also removed. The
retained original generation stage passes the combined route. See
../enclosed_combined_pass/. Logs below remain evidence of the unsuitable fixture
state, not a demonstrated grading or save/load defect.

The existing gather/build/store/travel/reopen runner now accepts a validated
`--source` slot. Testing `combined_enclosed_review` on exclusive disposable
clones stops before travel: no five nearby stones can be collected within the
unchanged 25 m fixture radius. Source canonical hashes remain unchanged.

Saved cottage spawn is Y79.5. Three nearest natural stones are around Y47.6–49.3.
Async terrain density rays return corresponding surfaces only about .03 m above
those stone origins. This rules out those sampled stones simply being buried
under a continuous filled platform up to cottage height. It does not yet locate
the cause: grading footprint, foundation height, generation profile and restored
terrain edits need comparison at the actual house/road coordinates.

Initial diagnostic called the asynchronous ray API without waiting and returned
empty dictionaries; that was not evidence of absent terrain. diagnostic.log
retains the corrected awaited ray results. The radius has not been widened.

Travel fixture now knows how to interact with an enclosed doorway before leaving
and record hinge/model snapshots for reopening. Those added steps have NOT run
because gathering fails first. They remain unverified. Next test should compare
authoritative terrain under house and road in creation and fresh reopen, rather
than repeating this unchanged route.
