# Island API

The Island API lets other apps on your Mac use cLockIn's notch, the way apps share the Dynamic Island on iPhone. An app sends content: text, colors, SF Symbols and buttons. cLockIn draws it in its own style, decides what shows when, and tells the app when someone presses one of its buttons.

An app can show three things:

| | What it looks like | Example |
|---|---|---|
| **Pill** | A symbol or ring left of the notch, short text on the right | `💼 2d`, a deadline in two days |
| **Alert** | Grows out of the notch with up to 3 buttons, then closes by itself | "3 new jobs" [View] |
| **Tab** | The app's own tab in the expanded notch: rows with buttons, plus footer buttons | Due soon, each with [Applied] |

## Connecting

The server listens on `127.0.0.1` only, so other devices can't reach it. The port is in `~/Library/Application Support/cLockIn/island.json` (usually `47823`):

```json
{"port": 47823, "version": 1, "pid": 1234}
```

Every request needs two headers:

- `X-Island-Client: <anything>`. Browsers can't send this to another site without asking the server first, and cLockIn never agrees, so web pages can't post to the notch.
- `Content-Type: application/json` on requests with a body.

The `Host` header must be `127.0.0.1:<port>` or `localhost:<port>`. Most HTTP clients set this for you.

### 1. Register

```http
POST /v1/register
{"app": "jobcrack", "name": "JobCrack", "symbol": "briefcase.fill", "tint": "#6e8bff",
 "callback": "http://127.0.0.1:8765/island/action"}
```

`app` is a short id: letters, digits, `.` and `-`. The first time, cLockIn asks in the notch whether to allow the app:

| Response | Meaning |
|---|---|
| `202 {"status": "pending"}` | Waiting for the user. Register again in a minute. |
| `200 {"status": "allowed", "token": "…"}` | Send the token as `X-Island-Token` from now on. |
| `403 {"status": "denied"}` | The user said no. They can change it in Settings → Connected Apps. |

Register again on every launch, and whenever a request returns `403`. cLockIn may have restarted, or the user may have removed the app.

### 2. Pill

```http
PUT /v1/apps/<app>/activity
{"text": "2d", "title": "BlackRock closes in 2 days", "symbol": "briefcase.fill",
 "tint": "#ffb340", "progress": 0.85, "priority": "normal"}
```

- `text` is cut to 10 characters, and `title` shows in the menu bar menu.
- `progress` (0–1) draws a ring. Leave it out to show just the symbol.
- `priority` decides placement against cLockIn's own timers. The notch has two sides, and things fill them in this order:
  1. a finished timer waiting for an answer
  2. `high`
  3. running timers
  4. `normal`
  5. paused timers
  6. `low`

`DELETE /v1/apps/<app>/activity` removes the pill.

### 3. Alert

```http
POST /v1/apps/<app>/alert
{"id": "job-12", "title": "Shell closes tomorrow", "subtitle": "Graduate Programme 2027",
 "symbol": "clock.fill", "tint": "#ffb340", "duration": 15, "sound": true,
 "buttons": [{"id": "applied", "label": "Applied ✓", "prominent": true},
             {"id": "open", "label": "Open", "url": "https://…"}]}
```

Alerts wait their turn behind cLockIn's own alerts and each other, and close after `duration` seconds (3–60, default 8). A button with a `url` opens that link (web links only). Any other button is reported back to the app.

### 4. Tab

```http
PUT /v1/apps/<app>/panel
{"title": "Jobs", "symbol": "briefcase.fill", "tint": "#6e8bff",
 "sections": [{"title": "Due soon", "rows": [
    {"id": "job-12", "title": "Shell", "subtitle": "Graduate Programme", "detail": "1d",
     "tint": "#ffb340", "url": "https://…", "buttons": [{"id": "applied", "label": "Applied"}]}]}],
 "footer": [{"id": "check", "label": "Check now"}],
 "emptyText": "Nothing due"}
```

There's room for 30 rows in total and 2 buttons per row. Clicking a row opens its `url`. Up to three apps get a tab, after cLockIn's own tabs. `DELETE /v1/apps/<app>/panel` removes the tab.

Send the whole tab again whenever something changes. Sending the same content again is cheap: cLockIn only redraws when something is different.

## Button presses

cLockIn posts to the app's `callback` with its token in `X-Island-Token`, so the app can tell the press really came from cLockIn:

```json
{"type": "action", "app": "jobcrack", "source": "panel", "target": "job-12", "action": "applied"}
```

`source` is `alert`, `panel` (a row's button) or `footer`. For an alert, `target` is the alert's `id`; for a row, the row's `id`.

## Status

`GET /v1/status` returns `{"version": 1, "apps": ["JobCrack"]}`.

## Turning it off

Settings → Connected Apps has a switch for the whole API, plus an Allowed switch and a Remove button for each app.
