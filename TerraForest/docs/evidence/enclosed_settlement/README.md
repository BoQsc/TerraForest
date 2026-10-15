# Generated enclosed settlement

Fresh preparation selects `Furnished cottage with door and windows` through
the existing frontage/editor survey/grading/staged-publication workflow.
Persistence comparison now includes door and window model snapshots alongside
blocks, roads and furnishings. Two real processes create/save and reopen/save
at 1920x1080. The reopened interior screenshot was inspected.

`Review Enclosed Settlement.cmd` prepares only if `combined_enclosed_review`
does not exist, then launches normal gameplay with actors and fleet support.
It preserves existing review and normal gameplay saves. The configurable
destination uses the same ASCII slot restrictions as the launcher; six Python
tests cover preservation, invalid destinations, publication failure and locking.

This checks generation and exact persistence, not full traversal, driving,
actor navigation through the now-closed doors, performance or human acceptance.
The source report is reports/combined_preparation/20261015T170024154113Z.
No existing saved settlements are retrofitted automatically.
