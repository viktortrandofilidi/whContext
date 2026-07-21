---
name: windfall-story-644-video-findings
description: "Windfall Story 644 — bugs from two onboarding screen-share videos (CSV→Compass field mapping): unknown/unknown auto-map regression, person.name canonical keys vs generic \"custom attributes\", person ID with dash rejected, \"classification doesn't exist\" on new field, empty Compass dataset after mapping, field-key uniqueness error, spouse-age wrong calc / form disables, default single data source, ID not auto-mapped. Recall when the user pastes any bullet from Story 644."
metadata: 
  node_type: memory
  type: project
  originSessionId: 8c94e749-d69c-4ce7-a1b7-a926db9939c1
---

Context for **Windfall Story 644** (Jira: windfalldata.atlassian.net). NOTE: this has nothing to
do with the streemerDVR repo the session runs from — it's Windfall product work. The author
walks through the **new-account onboarding / CSV → Compass field-mapping flow** in two
screen-share videos and reports UX/UI + data bugs, addressed to the dev team ("Eugene or Victor").

Product vocabulary: **Compass** (+ "Compass shadow mode" data-processing mode), **Segment** (the
team/integration that owns orchestration), **data sources / datasets** (same thing, "dataset" in
UI), **classification keys** (canonical field keys like `person.name.first_name`; a lot depends on
these), **custom fields / attributes**, CSV upload → mapping → introspection → suggested mapping.
Domain metric mentioned: "measure of giving" (a number field). This confirms the videos are the
Windfall product.

The two source videos live in ~/Downloads ("Screenshare - 2026-07-16 10_11_51 PM.mp4" 5:00, and
"Screenshare - 2026-07-17 2_18_15 AM.mp4" ~4:04). They were transcribed with whisper.cpp
(medium.en); transcripts were in session scratchpad (ephemeral). Some transcription noise exists;
bug meanings below are reliable.

## Consolidated fix list (both videos)

- **Person ID with a dash breaks the "add people" wizard.** Next fails because dashes are "no
  longer allowed" in the ID — a mismatch with the allowed classification keys after recent
  changes, making the wizard impossible to complete. Allow valid dashed IDs again.
- **After selecting the data source, all fields auto-map to "unknown / unknown" (regression).**
  There was a prior fix so it wouldn't be unknown; appears regressed. Should name-match:
  `Person → person`, `email → person email`, `first name`, `last name`.
- **"Classification doesn't exist" error when creating a new text custom field (e.g. "hobby").**
  New issue; author only says "this should work differently" and works around it by skipping the
  field — he did NOT propose a concrete fix. (Discussion in this session floated: extend the
  existing "no dataset → banner → create dataset" middle-path pattern to also offer creating a
  classification. Open question that decides root-cause vs band-aid: **is a classification meant to
  be auto-created as part of field/mapping creation, or is it a user-created prerequisite like a
  dataset?** The empty-dataset bug's phrasing "modification of the classification didn't work"
  suggests classifications are auto-managed → then the banner papers over a real auto-create/lookup
  bug and risks two divergent creation paths.)
- **Compass dataset shows zero objects after mapping 5 CSV fields.** Frontend reports success but
  the backend doesn't persist — "the modification of the classification didn't work successfully."
  Silent failure. Investigate where the data is lost.
- **Mapped person fields resolve to generic "custom attributes" instead of canonical person keys**
  (video 2). After mapping first/last name + home address they come out as `custom attributes /
  first name` etc., but must be `person.name.first_name` etc. because a ton of things depend on it,
  including the CSV back-column mapping the author is building. Server config has the correct keys,
  so he suspects the **frontend mangles them**. Fix so mapping produces canonical tags/keys.
- **Creating a new field from an already-existing name errors with "field needs to be unique."**
  The display **name** should stay (e.g. "last name") and the field **key** should be
  auto-uniquified — don't force the user to rename to "last name two". Duplicate inferred names are
  common (e.g. "last name" vs "last name" without a space) and the user has no control over the key.
- **Auto-mapping suggestion misses the ID column** (video 2) — suggestion works overall but doesn't
  pick up ID.
- **"Spouse's age" custom field is calculated from the wrong source, and clicking it disables/greys
  out all other fields** in the form (video 1). Fix calc source + remove the unexpected disabling.
- **Add validation for incompatible field types** — some combos shouldn't be selectable (e.g. `age`
  is a number and "measure of giving" is also a number; they can be confused). (Audio cut ~4:57, so
  this thought is slightly truncated.)
- **When only one data source exists, pre-select it as the default** instead of a manual pick.
- **Clarify whether creating custom fields should be permission-gated ("protected").** Author was
  unsure if he should even be able to create one.

## Explicitly NOT this team's fix

- The orchestration/integration next step is expected to fail, but that's on the author's/Segment's
  side ("not on you guys segment to fix, but rather on us getting that integration right") — data
  must still be correct.

See [[clip-pipeline-state]] is unrelated (different project); reply language per
[[user-communicates-in-russian]].
