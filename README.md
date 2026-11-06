# fragment

**fragment** is a minimal, modern, anonymous pastebin web application built with **Elixir**, **Phoenix**, and **SQLite3** (via `ecto_sqlite3` + `exqlite`).

## Features

- **Zero accounts or login** — Anyone can create and share code or plain-text pastes anonymously.
- **One-time claim / edit secret** — Every paste returns a one-time secret token (`frag_...`) at creation. Only its SHA-256 hash is stored in the database, allowing the creator to edit or delete the paste later via the web UI or REST API.
- **Language auto-detection & server-side syntax highlighting** — Automatically detects common languages (`elixir`, `javascript`, `typescript`, `python`, `go`, `rust`, `html`, `css`, `json`, `sql`, `markdown`, `bash`, `ruby`, `c`, `yaml`, `plaintext`) with manual dropdown override. Server-side tokenization emits semantic HTML with zero client-side syntax highlighting libraries.
- **Raw view & cloning** — `/raw/:id` serves unescaped `text/plain; charset=utf-8` (`X-Content-Type-Options: nosniff`). Clicking **Clone** (`/?clone=:id`) loads the paste into a new form.
- **Configurable expiration & automatic purging** — Pastes can expire `never`, or after `10m`, `1h`, `1d`, `7d`, or `30d`. Expired pastes immediately return `404` and are periodically purged from SQLite by `Fragment.Pastes.ExpirationWorker`.
- **Dark & light theme toggle** — Dark mode by default with an instant light/dark toggle and `prefers-color-scheme` support.
- **Abuse protections** — Per-IP ETS rate limiting (`Fragment.RateLimiter`), 512 KB maximum paste size validation, and strict HTML escaping across all views and highlighters.

---

## Quick Start

### Prerequisites

- **Elixir** `~> 1.17` (tested on Elixir 1.18 / Erlang/OTP 28)
- **SQLite3** (bundled via `exqlite`)

### Setup & Run

```bash
# Install dependencies, create & migrate the SQLite database, seed sample pastes, and build assets
mix setup

# Start the Phoenix server at http://localhost:4000
mix phx.server
```

Then open [http://localhost:4000](http://localhost:4000) in your browser.
Interactive API documentation is available at [http://localhost:4000/api](http://localhost:4000/api).

### Running Tests

```bash
mix test
```

---

## REST API Documentation

All API endpoints are served under `/api/pastes` and mirror the web UI.

### 1. Create a Paste

```http
POST /api/pastes
Content-Type: application/json
```

**Request Body:**

| Field | Type | Required | Description |
| :--- | :--- | :--- | :--- |
| `content` | `string` | Yes | Paste text (up to 512 KB / 524,288 bytes). |
| `language` | `string` | No | `"auto"` (default) or one of: `elixir`, `javascript`, `typescript`, `python`, `go`, `rust`, `html`, `css`, `json`, `sql`, `markdown`, `bash`, `ruby`, `c`, `yaml`, `plaintext`. |
| `expires_in` | `string` | No | `"never"` (default), `"10m"`, `"1h"`, `"1d"`, `"7d"`, or `"30d"`. |

**Example:**

```bash
curl -X POST http://localhost:4000/api/pastes \
  -H "Content-Type: application/json" \
  -d '{
    "content": "defmodule Hello do\n  def world, do: :ok\nend",
    "language": "auto",
    "expires_in": "1d"
  }'
```

**Response (`201 Created`):**

```json
{
  "id": "k9Xm2pQr",
  "content": "defmodule Hello do\n  def world, do: :ok\nend",
  "language": "elixir",
  "size_bytes": 43,
  "expires_at": "2026-11-07T21:45:00Z",
  "inserted_at": "2026-11-06T21:45:00Z",
  "updated_at": "2026-11-06T21:45:00Z",
  "url": "http://localhost:4000/k9Xm2pQr",
  "raw_url": "http://localhost:4000/raw/k9Xm2pQr",
  "api_url": "http://localhost:4000/api/pastes/k9Xm2pQr",
  "edit_token": "frag_aBcDeFgHiJkLmNoPqRsTuVwXyZ012345",
  "delete_token": "frag_aBcDeFgHiJkLmNoPqRsTuVwXyZ012345"
}
```

---

### 2. Get a Paste (JSON)

```http
GET /api/pastes/:id
```

```bash
curl http://localhost:4000/api/pastes/k9Xm2pQr
```

Returns `200 OK` with paste metadata and content (excluding `edit_token` / `delete_token`), or `404 Not Found` if the paste does not exist or has expired.

---

### 3. Get Raw Paste Content

```http
GET /api/pastes/:id/raw
GET /raw/:id
```

```bash
curl http://localhost:4000/api/pastes/k9Xm2pQr/raw
```

Returns `200 OK` with `Content-Type: text/plain; charset=utf-8` and the exact unescaped paste content, or `404 Not Found` if missing/expired.

---

### 4. Update a Paste

```http
PUT /api/pastes/:id
Authorization: Bearer <edit_token>
Content-Type: application/json
```

```bash
curl -X PUT http://localhost:4000/api/pastes/k9Xm2pQr \
  -H "Authorization: Bearer frag_aBcDeFgHiJkLmNoPqRsTuVwXyZ012345" \
  -H "Content-Type: application/json" \
  -d '{"content": "updated content", "language": "elixir"}'
```

---

### 5. Delete a Paste

```http
DELETE /api/pastes/:id
Authorization: Bearer <edit_token>
```

The secret edit/delete token can be passed via:
- `Authorization: Bearer <token>` header
- `X-Edit-Token: <token>` or `X-Delete-Token: <token>` header
- JSON request body: `{"edit_token": "<token>"}` or `{"delete_token": "<token>"}`
- Query string: `?token=<token>`

```bash
curl -X DELETE http://localhost:4000/api/pastes/k9Xm2pQr \
  -H "Authorization: Bearer frag_aBcDeFgHiJkLmNoPqRsTuVwXyZ012345"
```

**Response (`200 OK`):**

```json
{
  "deleted": true,
  "id": "k9Xm2pQr"
}
```
