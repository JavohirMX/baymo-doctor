# Clinic transfer contract

This document is the contract for the iPhone app. **The iPhone UI is not in this repository change.** Baymo Doctor (the Mac app in `dr-dash`) implements the doctor side only. The phone team implements the phone side against the rules below. Do not add phone screens to the parent app as part of the Mac work.

Nothing in this transfer goes to a server. The phone and the Mac talk only on the local network.

The clinic JSON types already live in `dr-dash/Transfer/ClinicTransfer.swift`. The wire messages below carry those types. They are not a second payload schema.

## Transport

| Item | Value |
| --- | --- |
| API | Multipeer Connectivity |
| Service type | `baymo-clinic` |
| Bonjour type | `_baymo-clinic._tcp` |
| Encryption | Required |
| Data mode | Reliable |
| Mac display name | `Baymo Doctor` |
| Discovery key | `role` |
| Link role | `link` (Mac advertises, phone browses and invites) |
| Sync role | `sync` (phone advertises, Mac browses and invites) |

The invitation context is empty. The 6-digit code is not in the discovery info and not in the invitation. Discovery info is visible to every nearby device. The code is the first message inside the encrypted session.

The phone's Info.plist needs `NSBonjourServices` containing `_baymo-clinic._tcp`, plus a local-network usage string. The phone also needs the local-network and Bonjour entitlements its sandbox requires.

The Mac advertises only while the link sheet is waiting. The phone should advertise `role=sync` only while its sync code is on screen, so the Mac joins the phone the doctor is looking at.

## Code

- Exactly 6 digits, including leading zeros. Compare it as a string. `048213` is not `48213`.
- Lifetime is 5 minutes (300 seconds).
- It is expired when `now - issuedAt >= 300`. The same instant the lifetime is reached, the code is expired.
- The side that showed the code is the side that decides. The Mac issues the link code. The phone issues the sync code.
- A mismatch or an expired code does not open clinic data.

The Mac link sheet shows the code and a countdown (`5:00` down to `0:00`) while it is waiting. The sentence on that sheet is: "The phone connects directly to this Mac. Nothing is sent online."

## Version and dates

Every wire message and every clinic envelope has `"version": 1`. Any other version is rejected.

Dates are ISO-8601 from Foundation's `.iso8601` JSON strategy: UTC, no fractional seconds.

```text
2026-11-17T02:56:00Z
```

Do not send fractional seconds. The Mac's decoder rejects them. Key order does not matter. The Mac writes keys in sorted order. Unknown keys are ignored. Omitted optional fields mean null.

UUIDs are the standard `8-4-4-4-12` text form.

## Message order

Every session's first data message is `code`. Clinic JSON sent before an accepted `codeResult` is ignored and does not open the chart.

### Link

1. Phone browses for `role=link` and invites the Mac. The Mac accepts one invitation at a time.
2. Phone sends `code`.
3. Mac checks the lifetime, then the digits.
4. If the code is expired or wrong, the Mac sends `codeResult` with `accepted: false` and `reason` `expired` or `mismatch`, then disconnects that phone. It sends no `link` message. The link sheet stays open and shows the error. The child is not deleted and is not marked linked.
5. If the code matches, the Mac sends `codeResult` with `accepted: true`, then one `link` message (chunked if it is large), then `complete`.
6. The phone applies the link only after the whole `link` message and the following `complete` have arrived. It then sends `receipt` and keeps the session open long enough for that message to leave. A drop before `complete` means the link did not finish. Discard a partial link.
7. The Mac marks that child linked only after `receipt`. Queuing `complete` is not enough. A drop before `receipt` leaves the child unlinked. Closing the sheet does not delete the child.

### Sync

1. Phone advertises `role=sync`.
2. Doctor types the 6-digit code. The Mac invites the phone.
3. Mac sends `code`. This is the first data message.
4. Phone checks the code it issued.
5. If the code is wrong or expired, the phone sends `codeResult` with `accepted: false` and `reason` `mismatch` or `expired`, and sends no recordings or diary. The Mac stays on the code sheet and shows that error. It does not show the success sheet.
6. If the code matches, the phone sends `codeResult` with `accepted: true`, then `syncManifest`, then one `recording` message per recording, then one `diary` message per diary entry, then `complete`. It stays connected.
7. The Mac merges each recording or diary item when that item's message is fully reassembled. It does not wait for `complete` to keep a finished item.
8. The Mac advances the child's last sync date only after `complete`, and only when at least as many distinct recordings and diary entries as the manifest promised have been merged. It then sends `receipt` and stays connected. The phone advances its send cursor only after that `receipt`, then disconnects. The Mac treats that disconnect as success.
9. If the doctor taps Stop, the Mac sends `cancel` and disconnects. Items already fully received stay. The last sync date stays where it was. The phone does not advance its cursor.
10. If the session drops before the phone has received `receipt`, the phone shows a failed sync and does not advance its cursor. If the Mac has not yet processed `complete`, it shows a failed sync and does not move the last sync date. Items already fully received stay. A later sync sends the same items again; the Mac updates them by id.

Send each recording and each diary entry once. `recordingCount` and `diaryCount` are counts of distinct ids. Journal on the Mac progress sheet means every diary entry (symptom, activity, and journal), not only `kind: journal`.

A sensible send order is recordings by `startDate`, then diary entries by `startedAt`. The Mac does not require that order.

## What the doctor sees

| What happened | Mac sheet | Last sync date | Child deleted |
| --- | --- | --- | --- |
| Link code does not match | Link sheet stays up. "That code does not match." No clinic JSON is sent. | Unchanged | No |
| Link code expired | Link sheet stays up, countdown at `0:00`. "That code has expired." No clinic JSON is sent. | Unchanged | No |
| Link finished | "Phone linked" and the child's name. Done closes the sheet. | Unchanged | No |
| Link later, or closing the sheet | Sheet closes. | Unchanged unless a link had already finished | No |
| Sync code does not match | Code sheet stays up. "That code does not match." | Unchanged | No |
| Sync code expired | Code sheet stays up. "That code has expired." | Unchanged | No |
| Sync finished | Date span, recording count, missed days, journal count. Done, or Review this child. | Moves forward | No |
| Doctor taps Stop | "Sync stopped." Fully received items stay. | Unchanged | No |
| Phone drops before `complete` | "Sync failed." This is not the success sheet. Fully received items stay. | Unchanged | No |
| Phone drops after `complete` but before `receipt` | The Mac may already show success if `complete` covered the manifest. The phone shows a failed sync. | Moves only if `complete` covered the manifest | No |

Missed days on the success sheet are the distinct local calendar days of received recordings whose `parentStatus` is `missed`. The phone does not send a separate missed-day count.

Review this child selects that child in the patient list when the Mac has a selection binding. Otherwise the Mac calls its review closure.

## Chunking

Encode the logical message as UTF-8 JSON first.

- If that byte count is 16,384 or less, send those bytes as one data message. Do not wrap them in `chunk`.
- If it is larger, split the **bytes** (not the characters) into consecutive slices of at most 16,384 bytes. Send each slice as its own `chunk` message.
- All slices in one set share one `id`. `index` starts at 0. `count` is the number of slices. `data` is that slice; JSON base64-encodes it.
- The receiver appends slices in index order and only then parses the JSON. A single slice is not valid JSON.
- Do not wrap a `chunk` in another `chunk`.
- At most 8,192 slices per message.

Progress numbers ("Recordings 4 of 6", "Journal 11 of 11") come from the manifest and from fully reassembled items. They are not chunk indexes.

## Wire messages

`type` is one of `code`, `codeResult`, `link`, `syncManifest`, `recording`, `diary`, `complete`, `cancel`, `receipt`, `chunk`.

### code

```json
{ "code": "048213", "type": "code", "version": 1 }
```

### codeResult

Accepted:

```json
{ "accepted": true, "type": "codeResult", "version": 1 }
```

Rejected. `reason` is `mismatch` or `expired`.

```json
{ "accepted": false, "reason": "expired", "type": "codeResult", "version": 1 }
```

### link

`envelope` is a clinic envelope of kind `link`. The phone applies `envelope.link` only after `complete`.

```json
{
  "envelope": {
    "kind": "link",
    "version": 1,
    "link": {}
  },
  "type": "link",
  "version": 1
}
```

### syncManifest

`newerThan` is the exclusive cursor the phone filtered with. Omit it, or send null, for a full history. It is not the new last-sync date.

```json
{
  "childID": "6F0C2E1A-7B34-4C0D-9A11-2E5B8C4D6A70",
  "diaryCount": 11,
  "newerThan": "2026-11-01T00:00:00Z",
  "recordingCount": 6,
  "type": "syncManifest",
  "version": 1
}
```

### recording

`index` is 0-based. `count` is the total the phone intends to send. `recording` is one `ClinicRecordingPayload`.

```json
{
  "count": 6,
  "index": 0,
  "recording": {},
  "type": "recording",
  "version": 1
}
```

### diary

Same shape. `diary` is one `ClinicDiaryPayload`. Count every diary kind toward `diaryCount`.

```json
{
  "count": 11,
  "diary": {},
  "index": 0,
  "type": "diary",
  "version": 1
}
```

### complete

```json
{ "type": "complete", "version": 1 }
```

The phone sends this only after every promised recording and diary message. The Mac treats `complete` as success only when the distinct items it has merged cover the manifest counts. Fewer items is a failed sync: the merged items stay, and the last sync date does not move. After a covered `complete`, the Mac sends `receipt`. The phone does not treat its own queued `complete` as confirmation.

### receipt

```json
{ "type": "receipt", "version": 1 }
```

No clinic payload. On a link, the phone sends it once `link` and `complete` have both arrived, applies the profile only after that send returns, then disconnects. The Mac marks the child linked only when this arrives. On a sync, the Mac sends it after a covered `complete`. The phone advances its send cursor only when this arrives, then disconnects.

### cancel

```json
{ "type": "cancel", "version": 1 }
```

The Mac sends this when the doctor stops a sync that is already in progress. The phone should stop sending and should not advance its own send cursor.

### chunk

```json
{
  "count": 3,
  "data": "<base64 of one byte slice>",
  "id": "2F1C6A0E-4B7D-4E2A-8C55-91A0B3D4E5F6",
  "index": 0,
  "type": "chunk",
  "version": 1
}
```

## Clinic JSON

Files and the `link` envelope use this wrapper. A file is this object alone, not a wire message.

```json
{ "kind": "link", "link": {}, "version": 1 }
```

```json
{ "kind": "sync", "sync": {}, "version": 1 }
```

`kind` is `link` or `sync`. A link envelope has `link` and no `sync`. A sync envelope has `sync` and no `link`.

### Link body

Profile, the current baseline, and the schedule. Older baselines stay on the Mac and are not sent. Recordings, diary, review flags, doctor notes, link state, and last sync date are not in this body.

`profile`

| Field | JSON | Notes |
| --- | --- | --- |
| id | UUID | The child's id. The phone sends this back as `childID` on sync. |
| fullName | string | |
| nickname | string | May be empty. |
| birthDate | date | |
| sex | string | `male`, `female`, or `other`. |
| conditionText | string | May be empty. |
| setupNotes | string | Setup notes travel with the profile. A doctor's note on a recording does not. |

`baseline` is omitted when the child has no baseline. Otherwise:

| Field | JSON | Notes |
| --- | --- | --- |
| id | UUID | |
| version | number | Version number of this baseline. |
| fileName | string | |
| recordedAt | date | |
| createdAt | date | |
| recording | object | `StoredECGPayload`. |

`schedule`

| Field | JSON | Notes |
| --- | --- | --- |
| cadence | object | See below. |
| weekdays | number array | Calendar weekdays, 1 = Sunday through 7 = Saturday. Used when cadence is specific weekdays. |
| durationMinutes | number | 1 through 15. |
| reminderHour | number | 0 through 23. |
| reminderMinute | number | 0 through 59. |
| recordWhenSymptoms | bool | |

`cadence.kind` is `everyDay`, `specificWeekdays`, or `timesPerWeek`. `timesPerWeek` also includes `timesPerWeek` as a number of at least 1.

```json
{ "kind": "everyDay" }
```

```json
{ "kind": "specificWeekdays" }
```

```json
{ "kind": "timesPerWeek", "timesPerWeek": 3 }
```

### Sync body

Recordings and diary strictly newer than the cursor. An item whose timestamp equals the cursor is not new. A missing cursor means the whole history.

| Field | JSON | Notes |
| --- | --- | --- |
| childID | UUID | Must be the profile id from the link. |
| newerThan | date or omitted | Exclusive start cursor the phone used. Not the covered end. |
| recordings | array | `ClinicRecordingPayload`. |
| diary | array | `ClinicDiaryPayload`. |

Do not send `reviewed` or `doctorNote`. The Mac keeps those and will not overwrite them.

`recordings[]`

| Field | JSON | Notes |
| --- | --- | --- |
| id | UUID | Merge key. A repeated id updates the same row. |
| startDate | date | The cursor compares this field. |
| duration | number | Seconds. A missed check may be 0. |
| parentStatus | string | `noChange`, `changeDetected`, `urgent`, `unsure`, `missed`, `notAnalyzed`. |
| heartRate | number or omitted | Send only a measured value. |
| prMS | number or omitted | PR in milliseconds, only when measured. |
| qrsMS | number or omitted | QRS in milliseconds, only when measured. |
| axisDegrees | number or omitted | Only when the phone had two limb leads. |
| signalQuality | string | May be empty. |
| samples | object | `StoredECGPayload`. A missed check may use an empty lead list. |

`diary[]`

| Field | JSON | Notes |
| --- | --- | --- |
| id | UUID | Merge key. |
| kind | string | `symptom`, `activity`, or `journal`. |
| startedAt | date | The cursor compares this field. |
| text | string | |
| symptomName | string or omitted | |

### ECG samples

```json
{
  "leads": [
    { "name": "II", "sampleRate": 500, "samples": [0.0, 0.1] }
  ]
}
```

`samples` are millivolts, oldest first. Lead names used by the clinic are `I`, `II`, `III`, `aVR`, `aVL`, `aVF`, `V1`, `V2`, `V3`, `V4`, `V5`, `V6`.

## Last sync date

The Mac does not read a new cursor out of `newerThan`. That field is only the exclusive start the phone already applied.

When a live sync completes, the Mac sets `lastSyncDate` to the latest `startDate` or `startedAt` in the items it kept (the covered end). If the phone completed a sync that contained no items, the Mac sets `lastSyncDate` to the time that sync finished. The stored date never moves backward.

Stop, failure, a wrong code, and an expired code leave `lastSyncDate` as it was, including when some items were already saved.

The phone should keep its own send cursor. Advance it only after `receipt` has arrived and the Mac has not cancelled or dropped. Queuing `complete` is not enough, because a disconnect can drop bytes that were only queued. Use the same covered-end rule: the latest item time, or the time the empty payload was built. If the phone sends an id the Mac already has, the Mac updates the phone-owned fields and does not create a second row.

## Files for testing before the phone exists

Developer settings can export and import the envelope JSON above. That is the same schema as the live transfer, without the wire wrapper.

- Export link writes the current child's link envelope.
- Export sync writes recordings and diary strictly newer than that child's `lastSyncDate`.
- Import of a link envelope updates the child with that profile id. If no child has that id, it updates the child selected in settings and keeps that child's id. A file import does not mark the child linked.
- Import of a sync envelope merges by id into the child named by `childID`. It does not change `lastSyncDate`. Only a finished live sync moves that date.
