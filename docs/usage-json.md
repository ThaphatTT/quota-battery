# usage.json — data contract

The collector writes one JSON file. Every widget only reads it. Writers must replace the file
atomically (write `usage.json.tmp`, then rename).

## Locations

| Copy | Path | Reader |
|---|---|---|
| Mac | `~/Library/Application Support/AIUsage/usage.json` | macOS app + WidgetKit extension |
| iPhone | `~/Library/Mobile Documents/iCloud~dk~simonbs~Scriptable/Documents/ai-usage.json` | Scriptable widget (`FileManager.iCloud()`, file `ai-usage.json`) |
| Settings | `~/Library/Application Support/AIUsage/settings.json` | written by the Mac app; read by the collector on every run and by the Mac widget |
| Known accounts | `~/Library/Application Support/AIUsage/known-accounts.json` | written by the collector; read by the Mac app (Accounts list, "New" tag) |
| Extra folders | `~/Library/Application Support/AIUsage/accounts.json` | optional, written by hand; read by the collector |

Both copies have identical content. The iPhone copy is written only when the Scriptable folder
exists in iCloud Drive.

## Shape (schema 1)

The numbers below are samples.

```json
{
  "schema": 1,
  "generated_at": "2026-11-19T04:30:00Z",
  "accounts": [
    {
      "id": "claude-main",
      "provider": "claude",
      "label": "Claude",
      "plan": "Max",
      "status": "ok",
      "error": null,
      "error_code": null,
      "updated_at": "2026-11-19T04:30:00Z",
      "limits": [
        { "key": "five_hour", "label": "5 ชม.",   "window_seconds": 18000,  "used_percent": 40.0, "resets_at": "2026-11-19T06:40:00Z" },
        { "key": "seven_day", "label": "สัปดาห์", "window_seconds": 604800, "used_percent": 60.0, "resets_at": "2026-11-24T02:00:00Z" }
      ],
      "usage": {
        "today": { "tokens": 1000000, "cost_usd": 10.0 },
        "month": { "tokens": 20000000, "cost_usd": 300.0 }
      },
      "credits": { "extra_usage_enabled": true, "used_usd": 0, "limit_usd": 50, "balance_usd": null }
    },
    {
      "id": "codex-main", "provider": "codex", "label": "ChatGPT", "plan": "Plus",
      "status": "ok", "error": null, "error_code": null, "updated_at": "2026-11-19T04:30:00Z",
      "limits": [
        { "key": "primary", "label": "สัปดาห์", "window_seconds": 604800, "used_percent": 50.0, "resets_at": "2026-11-20T02:00:00Z" }
      ],
      "usage": { "today": { "tokens": 500000, "cost_usd": null }, "month": { "tokens": 5000000, "cost_usd": null } },
      "credits": { "extra_usage_enabled": false, "used_usd": null, "limit_usd": null, "balance_usd": 0 }
    },
    {
      "id": "agy-main", "provider": "agy", "label": "agy", "plan": "free-tier",
      "status": "ok", "error": null, "error_code": null, "updated_at": "2026-11-19T04:30:00Z",
      "limits": [
        { "key": "claude",       "label": "Claude",       "window_seconds": null, "used_percent": 0.0, "resets_at": "2026-11-19T09:00:00Z" },
        { "key": "gemini_pro",   "label": "Gemini Pro",   "window_seconds": null, "used_percent": 0.0, "resets_at": "2026-11-19T09:00:00Z" },
        { "key": "gemini_flash", "label": "Gemini Flash", "window_seconds": null, "used_percent": 0.0, "resets_at": "2026-11-19T09:00:00Z" }
      ],
      "usage": null,
      "credits": null
    }
  ]
}
```

## Field rules

- `provider`: `claude` | `codex` | `agy`. `id` is stable for the life of the account. See "Accounts" below.
- `accounts` lists the enabled accounts whose login the provider's CLI reports in this run, in the chosen order
  (see "Account order"). An account that is not logged in is left out, and so is a hidden one. That is not an
  error. The list can be empty, and readers must not assume that all three providers, or any provider, are present.
- `label`: the name to show for the account. It is the nickname set in settings.json when there is one,
  otherwise the provider name. When a provider has two or more accounts, its default name is numbered in
  discovery order: `Claude 1`, `Claude 2`, `ChatGPT 1`, `ChatGPT 2`. The numbers count only the accounts in
  this run's output, so a folder that is not logged in does not take a number. A provider with one account keeps
  the plain name (`Claude`, `ChatGPT`, `agy`).
- `status`:
  - `ok`: fresh data. `error` and `error_code` are `null`.
  - `stale`: this run failed. The account keeps the previous run's `plan`, `limits`, `credits` and
    `updated_at`, and `error` and `error_code` say why. `usage` is always fresh: it comes from the
    local logs on this Mac, even when the provider call fails.
  - `error`: the login is there, but no data has ever been fetched. `limits` is empty and `error`
    and `error_code` say why. `usage` is still fresh when the local logs have it.
- `error`: a short Thai message for the user, or `null`. The collector always writes it. It must
  never contain tokens or emails. Readers show their own text for `error_code` and use `error` only
  as a fallback.
- `error_code`: a language-neutral code, or `null` when `status` is `ok`. It says why this run
  failed. The codes are listed below. Readers map each code to their own text.
- `limits`: ordered for display, most important first. `used_percent` is a number from 0 to 100.
  `resets_at` is ISO-8601 UTC or `null`.
  - `label` is the Thai window label that the collector writes. It is kept for older readers.
  - `window_seconds` is the window length in seconds, or `null`. Claude: `five_hour` is 18000 and
    every `seven_day*` key is 604800 (`seven_day_opus` and `seven_day_sonnet` keep their key). Codex:
    the length the CLI reports (`windowDurationMins` × 60, or the API's `limit_window_seconds` in direct
    mode). agy: `null` for every bucket and group, because the window is then part of the label.
  - Readers build the limit label from `window_seconds` and `key` in their own language. When
    `window_seconds` is `null`, show `label`, which is then a model-group name such as `Gemini Pro`, or a
    bucket label such as `Gemini Models · 5h`.
  - `key` stays the same from run to run, because notifications and stale data are kept by key:
    - Claude: `five_hour`, `seven_day`, `seven_day_opus`, `seven_day_sonnet`. Other models have no key, since
      the widgets have no name to show for them.
    - Codex: `primary` and `secondary`, one per window in the answer. The length says which window it is.
    - agy, default mode: the bucket `id` from the CLI, for example `gemini-5h` or `3p-weekly`.
    - agy, direct mode: `claude`, `gemini_pro`, `gemini_flash` and `gpt_oss`.
- `usage`: can be `null`. `cost_usd` is an estimate at API list prices, or `null` when unknown.
  For Claude, `tokens` counts input, output and cache writes. Cache reads are left out of that count,
  but they are included in `cost_usd`.
- `credits`: can be `null`. Any money field can be `null`.
- Widgets draw the quota that is left (`100 - used_percent`). They turn yellow at `used_percent >= 80`
  and red at `used_percent >= 95`. The collector sends a macOS notification once per window
  when it crosses 80 and again at 95.
- Readers must ignore unknown fields. Readers must treat a missing file or broken JSON as
  "no data yet", never crash.
- Readers must also treat `window_seconds` and `error_code` as optional. A file written before they
  were added does not have them. The two fields were added in schema 1, because readers ignore
  unknown fields and an older reader keeps working.
- The file must never contain access tokens, refresh tokens, emails or account ids.

## Accounts

A provider can have several accounts, one per login folder. The collector finds the folders on every run:

- Claude: `~/.claude` (id `claude-main`), and each `~/.claude-*` folder that holds a Claude Code config
  (`.claude.json` or `projects/`). `~/.claude` also counts when `~/.claude.json` exists. No Keychain item is
  read for Claude. Whether a folder is logged in is found by the `claude` CLI when the account is collected.
- Codex: `~/.codex` (id `codex-main`), and each `~/.codex-*` folder that has an `auth.json`. Only the file's
  existence is checked.
- agy: one account (id `agy-main`). Only the existence of its Keychain item is checked, never the item itself.
- The folders listed in `accounts.json` (below), when they hold such a config.

Ids are `claude-<name>` and `codex-<name>`. `<name>` is the folder name without the leading dot and without
the `claude-` or `codex-` prefix, so `~/.claude-2` gives `claude-2`. Names use lower-case letters, digits and
dashes. When two folders give the same id, the second gets `-2`, then `-3`. A folder keeps its id.

Each CLI reads the login in its own folder, so the collector does not need to know where it is kept. For an
extra Claude folder it runs `claude` with `CLAUDE_CONFIG_DIR` set to that folder; for an extra Codex folder it
runs `codex` with `CODEX_HOME` set to that folder. A login for another Claude folder is made by running
`CLAUDE_CONFIG_DIR=<folder> claude` (the Mac app's Add account does this). Codex keeps its login in `auth.json`
inside its folder. The collector never reads these logins in default mode.

`accounts.json` is optional and written by hand, in the same folder as settings.json:

```json
{ "claude": ["~/work/claude"], "codex": ["~/work/codex"] }
```

It lists folders outside the `~/.claude-*` and `~/.codex-*` pattern. Use absolute or `~` paths only. A
missing or broken file lists nothing. A listed Claude folder must hold `.claude.json` or `projects/`, and a
listed Codex folder must hold `auth.json`; other folders are ignored.

A hidden account (`"enabled": false` in settings.json) is still collected, so its CLI is still run and its login
stays fresh. It is not written to usage.json, and it sends no notifications.

## Account order

The collector sorts `accounts` once, so every reader shows the same order. `sort` in settings.json picks the rule:

- `manual` (default): `order` from settings.json, ascending. An account with no order comes after the ordered
  ones, in discovery order.
- `lowest`: the account with the least quota left comes first. Quota left is `100 - used_percent` of the
  account's most used limit. Ties keep the manual order. An account with no limits comes last.
- `provider`: Claude, then ChatGPT (codex), then agy. Manual order inside each provider.

Readers draw the accounts in file order. The small and medium widgets show the first 3. The large widget
shows as many as fit.

## Where the numbers come from

By default no provider token is read, refreshed or stored. Each provider's own command-line tool answers the
usage question, and no model is called. Each run is stopped after 30 seconds, and its whole process group is
killed. A CLI's output is never written to the log, and the collector reads only the fields listed here.
Each CLI gets only `HOME`, `USER`, `LOGNAME`, `SHELL`, `TMPDIR`, the `LANG` and `LC_*` variables, a search
`PATH`, and, for an extra account, its one folder variable (`CLAUDE_CONFIG_DIR` or `CODEX_HOME`). No other
variable is passed on, so no API key or token from the environment reaches a CLI.

- Claude: `claude -p --input-format stream-json --output-format stream-json --verbose --no-session-persistence`.
  The collector sends an `initialize` and a `get_usage` control request, and nothing else. The limits come from
  `rate_limits` (`five_hour`, `seven_day`, and the Opus and Sonnet weeks). When that answer cannot be used, the
  collector runs `claude -p "/usage" --output-format json` and reads the percentages and reset times from its
  text. `plan` is `null` in that case, and it is not known from the text.
  The `get_usage` request is an experimental API of Claude Code. No CLI version is pinned, so a reply that changes
  shows as an error for that account, unless the `/usage` text can be read instead.
- Codex: `codex app-server --listen stdio://`. The collector sends `initialize`, `initialized` and
  `account/rateLimits/read` and nothing else. It never sends a method that uses a reset credit, sends an
  e-mail or changes the login.
- agy: `agy -p "/usage" --output-format json`. The limits come from `command.data.groups[].buckets[]`, using
  `remaining_fraction` and `reset_time`. `plan` is `null`.

Direct mode (opt-in through `direct_mode`, Codex and agy only) reads the Codex login file or the agy Keychain
item and calls the provider's usage endpoint. It is described in the README.

## error_code

| `error_code` | Meaning |
|---|---|
| `login_expired` | The login ran out. Opening the provider's app renews it. |
| `relogin_needed` | The login is gone or revoked. The user has to sign in again. |
| `not_set_up` | agy has a login, but no project exists for it yet (direct mode only). |
| `network` | The provider could not be reached, or its CLI did not answer within 30 seconds. |
| `rate_limited` | The provider asked the collector to slow down (HTTP 429). |
| `server_error` | The provider answered with a server error (HTTP 5xx). |
| `unknown` | Anything else: a CLI that is not installed, or an answer in a shape the collector does not know. Readers show their own "unknown error" text in the chosen language. |

Readers must fall back to the Thai `error` text when `error_code` is missing or is a code they do not know.

## settings.json (written by the Mac app)

The Mac app writes `~/Library/Application Support/AIUsage/settings.json`. The file is optional. The
collector reads it on every run. A missing file, broken JSON, a missing key or an unknown value counts as
the default.

| Key | Values | Default | Meaning |
|---|---|---|---|
| `language` | `"system"`, `"th"`, `"en"` | `"system"` | The language of the macOS notification texts. `"system"` follows the first preferred language: Thai when it starts with `th`, English otherwise. |
| `notify` | `true`, `false` | `true` | `false` turns macOS notifications off. Only the JSON value `false` does this. |
| `sort` | `"manual"`, `"lowest"`, `"provider"` | `"manual"` | The order of the accounts in usage.json. See "Account order". |
| `accounts` | object keyed by account `id` | `{}` | Per account: `label` (a nickname), `enabled` (only the JSON value `false` hides the account) and `order` (an integer). See "Accounts". |
| `direct_mode` | object: `{"codex": true, "agy": true}` | `{}` (all off) | Only the JSON value `true` turns direct mode on for that provider (Codex or agy). Claude has no direct mode. See "Where the numbers come from". |

The Mac app writes `sort` and `accounts`, and each write changes only its own keys.

- With `notify` set to `false`, the collector sends no notifications. It still records each 80% and 95%
  crossing in `notify-state.json`, so turning the switch back on does not send alerts for crossings that
  happened while it was off. A higher threshold reached later still alerts.
- The collector's `--no-notify` option has the same effect as `notify` set to `false`.
- Examples of the notification text for Claude's 5-hour limit at 85%:
  - `th`: title "Quota Battery", text "Claude · 5 ชม. ใช้ไปแล้ว 85%"
  - `en`: title "Quota Battery", text "Claude · 5h used 85%"

## known-accounts.json

The collector writes `~/Library/Application Support/AIUsage/known-accounts.json` on every run, except in
`--dry-run`:

```json
{
  "schema": 1,
  "accounts": [
    { "id": "claude-main", "provider": "claude", "source": "Claude Code (main)", "first_seen": "2026-11-19T04:30:00Z" },
    { "id": "claude-2", "provider": "claude", "source": "Claude Code (~/.claude-2)", "first_seen": "2026-11-19T06:00:00Z" }
  ]
}
```

It lists every account whose CLI reported a login in this run, hidden ones included, in discovery order. `source` is
display text: the folder, with `~` for the home folder. It never holds a secret. `first_seen` is kept while the
account stays found. An account that is no longer found is dropped from the file, and if its login comes back
it gets a new `first_seen`.
