// Tests for ChatGPT on the iPhone in "AI Usage.js": the device code login, the token refresh, the usage row, the merge with
// the Mac copy, and the rules that a widget run never prompts and that no token reaches a screen, a log, the pasteboard or
// a URL. Everything outside the script is a stub: the Keychain, Request, Alert, UITable, Timer, Safari and Pasteboard. The
// Timer moves a fake clock forward at once, so a 15 minute login takes milliseconds. Each stub records what it was asked to
// do. Nothing here touches the network.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { createContext, runInContext } from "node:vm";

const here = dirname(fileURLToPath(import.meta.url));
const SCRIPT_SRC = readFileSync(join(here, "..", "AI Usage.js"), "utf8");
const MAC_SAMPLE = readFileSync(join(here, "usage.sample.json"), "utf8");
const MAC_FILE = "/icloud/Documents/ai-usage.json";
const T0 = Date.parse("2026-11-19T04:38:00Z");
const MIN = 60 * 1000;
const NOW_S = Math.floor(T0 / 1000);

function b64url(obj) {
  return Buffer.from(JSON.stringify(obj)).toString("base64url");
}

function jwt(payload) {
  return b64url({ alg: "none", typ: "JWT" }) + "." + b64url(payload) + ".signature-sentinel";
}

// Secrets. None of these may reach a screen, a log, the pasteboard, an alert or a URL. The id token holds the email,
// so the email must never be stored either.
const ACCESS = jwt({ exp: NOW_S + 3600, sub: "access-sentinel-7f3a" });
const ACCESS_NEW = jwt({ exp: NOW_S + 7200, sub: "access-sentinel-rotated-9b1c" });
const REFRESH = "refresh-sentinel-5b2e1d";
const REFRESH_NEW = "refresh-sentinel-rotated-0c4f7a";
const DEVICE_ID = "device-sentinel-8h2k";
const ACCOUNT_ID = "account-sentinel-3e9d";
const EMAIL = "sentinel.person@example.invalid";
const ID_TOKEN = jwt({ email: EMAIL, "https://api.openai.com/auth": { chatgpt_account_id: ACCOUNT_ID, chatgpt_plan_type: "plus" } });
const SECRETS = [ACCESS, ACCESS_NEW, REFRESH, REFRESH_NEW, DEVICE_ID, ACCOUNT_ID, EMAIL, ID_TOKEN];

const URL = {
  usercode: "https://auth.openai.com/api/accounts/deviceauth/usercode",
  poll: "https://auth.openai.com/api/accounts/deviceauth/token",
  token: "https://auth.openai.com/oauth/token",
  usage: "https://chatgpt.com/backend-api/wham/usage",
  devicePage: "https://auth.openai.com/codex/device",
};
const CLIENT_ID = "app_EMoamEEZ73f0CkXaXp7hrann";
const USER_CODE = "ABCD-1234";
const K = {
  tokens: "ai-usage.chatgpt.tokens",
  pending: "ai-usage.chatgpt.pending",
  cache: "ai-usage.chatgpt.cache",
  status: "ai-usage.chatgpt.status",
  lock: "ai-usage.chatgpt.lock",
};

// Wording from the script's tables (Thai), used to find what the user sees.
const TH = {
  title: "เชื่อม ChatGPT",
  connected: "เชื่อม ChatGPT แล้ว",
  done: "เสร็จ",
  disconnect: "ยกเลิกการเชื่อมต่อ",
  openPage: "เปิดหน้า OpenAI",
  copyCode: "คัดลอกรหัส",
  copied: "คัดลอกรหัสแล้ว",
  waiting: "กำลังรอการอนุมัติ",
  checkFailed: "ตรวจสอบยังไม่ได้ ระบบจะลองอีกครั้ง",
  timedOut: "หมดเวลาแล้ว เปิดแอปอีกครั้งเพื่อเริ่มใหม่",
  reconnect: "การเชื่อมต่อหมดอายุ ต้องเชื่อมต่อใหม่",
  startFailed: "เริ่มการเชื่อมต่อไม่สำเร็จ ลองอีกครั้ง",
  noData: "ยังไม่มีข้อมูล เปิด Mac ไว้",
  network: "เชื่อมต่อเครือข่ายไม่ได้",
  rateLimited: "ถูกจำกัดการเรียกชั่วคราว",
  serverError: "เซิร์ฟเวอร์มีปัญหา",
  reLogin: "ต้องล็อกอินใหม่",
};

// The Mac's direct-mode warning, word for word (mac/Shared/L10n.swift).
const WARNING_TH = "นี่เป็นช่องทางที่ไม่เป็นทางการ อาจใช้งานไม่ได้ หรือขัดกับข้อกำหนดของผู้ให้บริการ คุณใช้บัญชีด้วยความเสี่ยงของตนเอง";
const WARNING_EN = "This is an unofficial channel. It may stop working or conflict with the provider's terms. You use your account at your own risk.";

const ok = (json) => ({ status: 200, json });
const fail = (status, json) => ({ status, json: json === undefined ? {} : json });
const NETWORK = { network: true };
const REFRESHED = { access_token: ACCESS_NEW, refresh_token: REFRESH_NEW, expires_in: 3600 };
const USAGE_OK = {
  plan_type: "plus",
  rate_limit: {
    primary_window: { used_percent: 12.5, limit_window_seconds: 604800, reset_after_seconds: 86400 },
    secondary_window: { used_percent: 40, limit_window_seconds: 18000, reset_at: NOW_S + 3600 },
  },
  credits: { has_credits: true, balance: 3.456 },
};

function tokensJSON(extra) {
  return JSON.stringify(Object.assign({ access_token: ACCESS, refresh_token: REFRESH, account_id: ACCOUNT_ID, access_exp_ms: T0 + 3600 * 1000 }, extra || {}));
}

function cacheJSON(extra) {
  return JSON.stringify(Object.assign({
    updated_ms: T0 - MIN,
    plan: "Plus",
    limits: [{ key: "secondary", label: "5 ชม.", window_seconds: 18000, used_percent: 40, resets_at: null }],
    credits: null,
    next_try_ms: null,
  }, extra || {}));
}

function pendingJSON(extra) {
  return JSON.stringify(Object.assign({ device_auth_id: DEVICE_ID, user_code: USER_CODE, interval_s: 5, deadline_ms: T0 + 15 * MIN }, extra || {}));
}

// The sandbox for one run. The stubs are host functions, so they can wait on host promises and timers, and each one
// records into S.
function sandboxFor(S) {
  class FixedDate extends Date {
    constructor(...args) {
      if (args.length === 0) super(S.now);
      else super(...args);
    }
    static now() {
      return S.now;
    }
  }

  class WidgetText {
    constructor(text) {
      this.text = text;
      this.font = null;
      this.textColor = null;
      this.lineLimit = 0;
      this.minimumScaleFactor = 1;
    }
    leftAlignText() {}
    centerAlignText() {}
    rightAlignText() {}
  }
  class WidgetStack {
    constructor() {
      this.children = [];
    }
    addText(text) {
      const t = new WidgetText(text);
      this.children.push(t);
      return t;
    }
    addStack() {
      if (S.failStacks) throw new Error("boom");
      const s = new WidgetStack();
      this.children.push(s);
      return s;
    }
    addSpacer(length) {
      if (length === 0) throw new Error("addSpacer(0) is not defined by the docs");
      this.children.push({ spacer: true });
    }
    setPadding() {}
    useDefaultPadding() {}
    topAlignContent() {}
    centerAlignContent() {}
    bottomAlignContent() {}
    layoutHorizontally() {}
    layoutVertically() {}
  }
  class ListWidget extends WidgetStack {
    constructor() {
      super();
      this.refreshAfterDate = null;
      S.made.push(this);
    }
    presentMedium() {
      S.preview = this;
      return Promise.resolve();
    }
  }
  class Size {
    constructor(width, height) {
      this.width = width;
      this.height = height;
    }
  }
  class Rect {
    constructor(x, y, width, height) {
      Object.assign(this, { x, y, width, height });
    }
  }
  class Point {
    constructor(x, y) {
      this.x = x;
      this.y = y;
    }
  }
  class Color {
    constructor(hex, alpha = 1) {
      this.hex = hex;
      this.alpha = alpha;
    }
    static dynamic(light, dark) {
      return { dynamic: true, light, dark };
    }
  }
  class Font {
    constructor(size, weight) {
      this.size = size;
      this.weight = weight;
    }
    static systemFont(size) {
      return new Font(size, "regular");
    }
    static mediumSystemFont(size) {
      return new Font(size, "medium");
    }
    static semiboldSystemFont(size) {
      return new Font(size, "semibold");
    }
    static boldSystemFont(size) {
      return new Font(size, "bold");
    }
  }
  class Path {
    move() {}
    addLine() {}
  }
  class DrawContext {
    constructor() {
      this.size = null;
    }
    setLineWidth() {}
    setStrokeColor() {}
    strokeEllipse() {}
    addPath() {}
    strokePath() {}
    getImage() {
      return {};
    }
  }

  const Keychain = {
    set(key, value) {
      if (S.locked) throw new Error("locked");
      if (typeof value !== "string") throw new Error("Keychain values are strings");
      S.store.set(key, value);
    },
    get(key) {
      if (S.locked) throw new Error("locked");
      if (!S.store.has(key)) throw new Error("no such key");
      return S.store.get(key);
    },
    contains(key) {
      if (S.locked) throw new Error("locked");
      return S.store.has(key);
    },
    remove(key) {
      if (!S.store.has(key)) throw new Error("no such key");
      S.store.delete(key);
    },
  };

  // The next answer for a URL. A queue of answers is used in order, and its last answer repeats. A function answer
  // runs first, so a test can change the Keychain in the middle of a run (another widget rotating the token).
  function answerFor(url) {
    const queue = S.routes[url];
    if (!queue || queue.length === 0) return null;
    const next = queue.length > 1 ? queue.shift() : queue[0];
    return typeof next === "function" ? next(S) : next;
  }

  class Request {
    constructor(url) {
      this.url = url;
      this.method = "GET";
      this.headers = {};
      this.body = undefined;
      this.timeoutInterval = 60;
      this.response = undefined;
    }
    async loadString() {
      S.requests.push({ method: this.method, url: this.url, headers: Object.assign({}, this.headers), body: this.body });
      const answer = answerFor(this.url);
      if (answer === null) {
        S.unrouted.push(this.url);
        throw new Error("no route for this URL");
      }
      if (answer.network === true) throw new Error("the network is off");
      this.response = { statusCode: answer.status };
      if (typeof answer.text === "string") return answer.text;
      return JSON.stringify(answer.json === undefined ? {} : answer.json);
    }
  }

  class Alert {
    constructor() {
      this.title = "";
      this.message = "";
      this.actions = [];
      this.cancel = null;
    }
    addAction(title) {
      this.actions.push(title);
    }
    addCancelAction(title) {
      this.cancel = title;
    }
    addDestructiveAction(title) {
      this.actions.push(title);
    }
    present() {
      const answer = S.alertAnswers.length > 0 ? S.alertAnswers.shift() : -1;
      S.alerts.push({ title: this.title, message: this.message, actions: this.actions.concat(this.cancel ? [this.cancel] : []), answer });
      return Promise.resolve(answer);
    }
  }

  class UITableCell {
    constructor(title, button) {
      this.title = title;
      this.button = button;
      this.onTap = null;
      this.dismissOnTap = false;
      this.titleColor = null;
      this.titleFont = null;
      this.alignment = "left";
    }
    centerAligned() {
      this.alignment = "center";
    }
  }
  class UITableRow {
    constructor() {
      this.cells = [];
      this.isHeader = false;
      this.dismissOnSelect = true;
      this.onSelect = null;
    }
    addText(title) {
      const cell = new UITableCell(title, false);
      this.cells.push(cell);
      return cell;
    }
    addButton(title) {
      const cell = new UITableCell(title, true);
      this.cells.push(cell);
      return cell;
    }
  }
  class UITable {
    constructor() {
      this.rows = [];
      this.presented = false;
      this.closeFn = null;
      this.reloads = 0;
      S.tables.push(this);
    }
    addRow(row) {
      this.rows.push(row);
    }
    removeAllRows() {
      this.rows = [];
    }
    reload() {
      this.reloads += 1;
    }
    present() {
      this.presented = true;
      return new Promise((resolve) => {
        this.closeFn = () => {
          this.presented = false;
          resolve();
        };
      });
    }
  }

  const Timer = {
    schedule(ms, repeats, callback) {
      S.waits += 1;
      S.now += ms;
      S.tickTexts.push(tableTextsOf(S));
      if (S.onTick) S.onTick(S);
      setImmediate(async () => {
        while (S.holdTicks) await new Promise((resolve) => setTimeout(resolve, 1));
        callback();
      });
      return { invalidate() {} };
    },
  };

  const FileManager = {
    iCloud() {
      return {
        documentsDirectory: () => "/icloud/Documents",
        joinPath: (a, b) => a + "/" + b,
        fileExists: (p) => Object.prototype.hasOwnProperty.call(S.files, p),
        downloadFileFromiCloud: () => Promise.resolve(),
        readString: (p) => (Object.prototype.hasOwnProperty.call(S.files, p) ? S.files[p] : null),
      };
    },
  };

  const line = (...a) => a.map(String).join(" ");
  return {
    ListWidget, WidgetStack, WidgetText, Color, Font, Size, Rect, Point, Path, DrawContext,
    FileManager,
    Script: {
      setWidget(widget) {
        S.widgets.push(widget);
      },
      complete() {
        S.completes += 1;
      },
    },
    Keychain, Alert, Request, Timer, UITable, UITableRow,
    Safari: {
      open(url) {
        S.opened.push(url);
      },
    },
    Pasteboard: {
      copyString(text) {
        S.pasted.push(text);
      },
    },
    Device: { language: () => S.lang },
    args: { widgetParameter: null },
    config: { runsInWidget: S.widget, runsInApp: !S.widget, widgetFamily: S.widget ? S.family : undefined },
    console: {
      log: (...a) => S.logs.push(line(...a)),
      warn: (...a) => S.logs.push(line(...a)),
      error: (...a) => S.logs.push(line(...a)),
    },
    Date: FixedDate,
  };
}

function newState(opts) {
  return {
    widget: opts.widget === true,
    family: opts.family || "medium",
    lang: opts.lang || "th",
    now: opts.now !== undefined ? opts.now : T0,
    store: new Map(Object.entries(opts.keychain || {})),
    locked: opts.keychainLocked === true,
    routes: opts.routes || {},
    alertAnswers: (opts.alerts || []).slice(),
    files: opts.mac ? { [MAC_FILE]: opts.mac } : {},
    failStacks: opts.failStacks === true,
    onTick: opts.onTick || null,
    holdTicks: opts.holdTicks === true,
    alerts: [],
    requests: [],
    unrouted: [],
    tables: [],
    opened: [],
    pasted: [],
    logs: [],
    tickTexts: [],
    widgets: [],
    made: [],
    preview: null,
    completes: 0,
    waits: 0,
  };
}

// Starts one run of the script. S.finished settles when the script completes (the app waits for the panel to close).
function start(opts = {}) {
  const S = newState(opts);
  const body = `(async () => {\n"use strict";\n${SCRIPT_SRC}\n})()`;
  S.finished = withTimeout(runInContext(body, createContext(sandboxFor(S)), { filename: "AI Usage.js" }), 4000);
  return S;
}

// The helper functions of the script, without running main(). Used for the pure checks.
async function helpers() {
  const S = newState({});
  const body = `(async () => {\n"use strict";\n${SCRIPT_SRC.slice(0, SCRIPT_SRC.lastIndexOf("try {"))}\nreturn { planNameOf, windowLabelTH, jwtClaims, pendingOf, refusedForGood, codeOfStatus, parseUsage, resetMsOf, mergeAccounts, sourcesOf, exchangeBody, base64UrlBytes, utf8Text, tokensFrom, tokensOf, chatgptAccount };\n})()`;
  const raw = await runInContext(body, createContext(sandboxFor(S)), { filename: "AI Usage.js" });
  // Results made inside the vm context have another realm's Array and Object prototypes, which assert.deepEqual
  // refuses. A JSON round trip brings each result back into this realm; every helper returns plain data.
  const out = {};
  for (const name of Object.keys(raw)) {
    out[name] = (...args) => JSON.parse(JSON.stringify(raw[name](...args)));
  }
  return out;
}

function withTimeout(promise, ms) {
  let timer;
  const timeout = new Promise((_, reject) => {
    timer = setTimeout(() => reject(new Error("script did not finish")), ms);
  });
  return Promise.race([promise, timeout]).finally(() => clearTimeout(timer));
}

async function until(check, what, ms = 3000) {
  const limit = Date.now() + ms;
  while (!check()) {
    if (Date.now() > limit) throw new Error("timed out waiting for " + what);
    await new Promise((resolve) => setTimeout(resolve, 1));
  }
}

function tableTextsOf(S) {
  return S.tables.flatMap((t) => t.rows.flatMap((r) => r.cells.map((c) => c.title))).filter((x) => typeof x === "string");
}

function hasText(S, text) {
  return tableTextsOf(S).includes(text);
}

function currentTable(S) {
  assert.ok(S.tables.length > 0, "no table was shown");
  return S.tables[S.tables.length - 1];
}

function tapButton(table, title) {
  const cell = table.rows.flatMap((r) => r.cells).find((c) => c.button && c.title === title);
  assert.ok(cell, "no button named " + title);
  cell.onTap();
  if (cell.dismissOnTap) table.closeFn();
}

function tapRow(table, title) {
  const row = table.rows.find((r) => r.cells.some((c) => c.title === title));
  assert.ok(row && row.onSelect, "no selectable row named " + title);
  row.onSelect();
  if (row.dismissOnSelect) table.closeFn();
}

// Everything the user can read in a run: widget text, table text and alerts.
function screenTexts(S) {
  const out = [];
  const walk = (node) => {
    if (node && typeof node.text === "string") out.push(node.text);
    if (node && Array.isArray(node.children)) node.children.forEach(walk);
  };
  S.widgets.forEach(walk);
  if (S.preview) walk(S.preview);
  out.push(...tableTextsOf(S));
  S.alerts.forEach((a) => out.push(a.title, a.message, ...a.actions));
  return out;
}

function assertNoSecrets(S) {
  const everything = [...screenTexts(S), ...S.logs, ...S.pasted, ...S.opened, ...S.requests.map((r) => r.url)];
  for (const secret of SECRETS) {
    assert.equal(everything.some((text) => text.includes(secret)), false, "a secret reached a screen, a log, the pasteboard or a URL");
  }
  for (const value of S.store.values()) {
    assert.equal(value.includes(EMAIL) || value.includes(ID_TOKEN), false, "the id token or the email was stored");
  }
}

function widgetTexts(S) {
  const walked = [];
  const walk = (node) => {
    if (node && typeof node.text === "string") walked.push(node.text);
    if (node && Array.isArray(node.children)) node.children.forEach(walk);
  };
  const widget = S.widgets[0] || S.preview;
  assert.ok(widget, "no widget was built");
  walk(widget);
  return walked;
}

function requestsTo(S, url) {
  return S.requests.filter((r) => r.url === url);
}

function assertIdle(S) {
  assert.equal(S.alerts.length, 0, "an alert was shown");
  assert.equal(S.tables.length, 0, "a table was shown");
  assert.equal(S.opened.length, 0, "a page was opened");
  assert.equal(S.pasted.length, 0, "the pasteboard was written");
  assert.equal(S.logs.length, 0, "the script logged something");
  assert.equal(S.unrouted.length, 0, "a URL had no route");
}

// -----------------------------------------------------------------------------------------------------------------
// The Mac copy alone, the consent question and the offline rules.
// -----------------------------------------------------------------------------------------------------------------

test("with nothing stored, a widget run shows the Mac copy as before, with no ChatGPT login prompt and no network", async () => {
  const S = start({ widget: true, family: "medium", mac: MAC_SAMPLE });
  await S.finished;
  const texts = widgetTexts(S);
  assert.ok(texts.includes("อัปเดต 8 นาทีก่อน"), "the single-source age text changed");
  assert.ok(texts.includes("เหลือ 7%"), "the Mac's ChatGPT row is missing");
  assert.ok(texts.includes("Claude"), "the Mac's Claude row is missing");
  assertIdle(S);
  assert.equal(S.requests.length, 0);
  assert.equal(S.completes, 1);
});

test("an app run with nothing stored asks the consent question once, then shows the preview", async () => {
  const S = start({ widget: false, family: "medium", mac: MAC_SAMPLE, alerts: [-1] });
  await S.finished;
  assert.equal(S.alerts.length, 1);
  assert.equal(S.alerts[0].title, TH.title);
  assert.ok(S.alerts[0].message.includes("Claude และ agy ยังมาจาก Mac ตามเดิม"), "the Mac note is missing from the consent text");
  assert.ok(S.alerts[0].message.includes("ไว้ทีหลัง") === false, "the button label leaked into the message");
  assert.deepEqual(S.alerts[0].actions, ["ยินยอมและเชื่อมต่อ", "ไว้ทีหลัง"]);
  assert.ok(S.alerts[0].message.endsWith(WARNING_TH), "the Mac's warning is missing from the Thai consent text");
  assert.equal(S.tables.length, 0);
  assert.equal(S.preview !== null && S.preview.refreshAfterDate !== null, true, "the preview was not shown");
  assert.equal(S.requests.length, 0);
  assert.equal(S.logs.length, 0);
  assert.equal(S.completes, 1);
});

test("the consent question is in English when the device is in English", async () => {
  const S = start({ widget: false, family: "medium", lang: "en", alerts: [-1] });
  await S.finished;
  assert.equal(S.alerts[0].title, "Connect ChatGPT");
  assert.ok(S.alerts[0].message.includes("Claude and agy still come from the Mac."));
  assert.deepEqual(S.alerts[0].actions, ["Consent and connect", "Not now"]);
  assert.ok(S.alerts[0].message.endsWith(WARNING_EN), "the Mac's warning is missing from the English consent text");
});

test("a refused login asks to connect again, with the reconnect line added above the text", async () => {
  const S = start({ widget: false, family: "medium", keychain: { [K.status]: "reconnect" }, alerts: [-1] });
  await S.finished;
  assert.equal(S.alerts.length, 1);
  assert.ok(S.alerts[0].message.startsWith(TH.reconnect), "the reconnect line is not first");
  assert.ok(S.alerts[0].message.endsWith(WARNING_TH), "the warning is missing from the reconnect consent");
  assert.equal(S.tables.length, 0);
});

// -----------------------------------------------------------------------------------------------------------------
// Widget runs never prompt.
// -----------------------------------------------------------------------------------------------------------------

test("widget runs never prompt, whatever is stored and whichever size is shown", async () => {
  const states = [
    { name: "nothing stored", keychain: {}, routes: () => ({}) },
    { name: "a pending login", keychain: { [K.pending]: pendingJSON() }, routes: () => ({}) },
    { name: "a refused login", keychain: { [K.status]: "reconnect" }, routes: () => ({}) },
    {
      name: "a fresh login with its cache",
      keychain: { [K.tokens]: tokensJSON(), [K.cache]: cacheJSON() },
      routes: () => ({}),
    },
    {
      name: "an expired login",
      keychain: { [K.tokens]: tokensJSON({ access_exp_ms: T0 - 1000 }) },
      routes: () => ({ [URL.token]: [ok(REFRESHED)], [URL.usage]: [ok(USAGE_OK)] }),
    },
  ];
  for (const state of states) {
    for (const family of ["small", "medium", "large"]) {
      const S = start({ widget: true, family, keychain: state.keychain, mac: MAC_SAMPLE, routes: state.routes() });
      await S.finished;
      const label = state.name + " / " + family;
      assert.equal(S.alerts.length, 0, label + ": an alert");
      assert.equal(S.tables.length, 0, label + ": a table");
      assert.equal(S.opened.length, 0, label + ": a page was opened");
      assert.equal(S.pasted.length, 0, label + ": the pasteboard was written");
      assert.equal(S.logs.length, 0, label + ": the script logged");
      assert.equal(S.completes, 1, label + ": completion");
      assertNoSecrets(S);
    }
  }
});

// -----------------------------------------------------------------------------------------------------------------
// The device code login: consent, the code, the checks, the timeout and the connected panel.
// -----------------------------------------------------------------------------------------------------------------

test("device flow: consent, the code, one pending check, then approval, the plan and Done; tokens are kept, the id token is not", async () => {
  const S = start({
    widget: false,
    family: "medium",
    mac: MAC_SAMPLE,
    alerts: [0],
    routes: {
      [URL.usercode]: [ok({ device_auth_id: DEVICE_ID, user_code: USER_CODE, interval: "5" })],
      [URL.poll]: [fail(403), ok({ authorization_code: "AUTH-1", code_verifier: "VER-1" })],
      [URL.token]: [ok({ access_token: ACCESS, refresh_token: REFRESH, id_token: ID_TOKEN })],
      [URL.usage]: [ok(USAGE_OK)],
    },
  });
  await until(() => hasText(S, "เสร็จ"), "the connected panel");
  assert.ok(hasText(S, USER_CODE) || S.tickTexts.some((t) => t.includes(USER_CODE)), "the code was never shown");
  assert.ok(hasText(S, TH.connected), "the connected title is missing");
  assert.ok(hasText(S, "แผน Plus"), "the plan line is missing");
  tapRow(currentTable(S), TH.done);
  await S.finished;

  assert.deepEqual(S.requests.map((r) => r.url), [URL.usercode, URL.poll, URL.poll, URL.token, URL.usage]);
  assert.equal(S.waits, 2, "two waits: the pending check and the approved check");
  const usercodeBody = JSON.parse(requestsTo(S, URL.usercode)[0].body);
  assert.deepEqual(usercodeBody, { client_id: CLIENT_ID });
  const pollBody = JSON.parse(requestsTo(S, URL.poll)[1].body);
  assert.deepEqual(pollBody, { device_auth_id: DEVICE_ID, user_code: USER_CODE });
  assert.equal(
    requestsTo(S, URL.token)[0].body,
    "grant_type=authorization_code&code=AUTH-1&redirect_uri=https%3A%2F%2Fauth.openai.com%2Fdeviceauth%2Fcallback" +
      "&client_id=app_EMoamEEZ73f0CkXaXp7hrann&code_verifier=VER-1",
    "the token exchange body changed",
  );
  const stored = JSON.parse(S.store.get(K.tokens));
  assert.equal(stored.access_token, ACCESS);
  assert.equal(stored.refresh_token, REFRESH);
  assert.equal(stored.account_id, ACCOUNT_ID);
  assert.equal(S.store.has(K.pending), false, "the pending login was not cleared");
  assert.equal(S.store.has(K.status), false);
  assert.equal(JSON.parse(S.store.get(K.cache)).plan, "Plus");
  assert.equal(S.opened.length, 0, "nothing was opened without a tap");
  assertNoSecrets(S);
});

test("the Open and Copy buttons open the device page and copy only the code; the panel stays open", async () => {
  const S = start({
    widget: false,
    family: "medium",
    alerts: [0],
    holdTicks: true,
    routes: {
      [URL.usercode]: [ok({ device_auth_id: DEVICE_ID, user_code: USER_CODE, interval: 5 })],
      [URL.poll]: [fail(403), ok({ authorization_code: "AUTH-2", code_verifier: "VER-2" })],
      [URL.token]: [ok({ access_token: ACCESS, refresh_token: REFRESH })],
      [URL.usage]: [ok(USAGE_OK)],
    },
  });
  await until(() => hasText(S, TH.openPage), "the code panel");
  tapButton(currentTable(S), TH.openPage);
  await until(() => hasText(S, TH.copyCode), "the code panel after Open");
  tapButton(currentTable(S), TH.copyCode);
  assert.deepEqual(S.opened, [URL.devicePage]);
  assert.deepEqual(S.pasted, [USER_CODE], "only the user code may be copied");
  assert.equal(currentTable(S).presented, true, "the panel closed after a button that does not close it");
  S.holdTicks = false;
  await until(() => hasText(S, "เสร็จ"), "the connected panel");
  tapRow(currentTable(S), TH.done);
  await S.finished;
  assertNoSecrets(S);
});

test("a device code that times out after 15 minutes stops the checks, clears the pending login and says so", async () => {
  const S = start({
    widget: false,
    family: "medium",
    alerts: [0],
    routes: {
      [URL.usercode]: [ok({ device_auth_id: DEVICE_ID, user_code: USER_CODE, interval: 5 })],
      [URL.poll]: [fail(403)],
    },
  });
  await until(() => hasText(S, "เสร็จ"), "the timed-out panel");
  assert.ok(hasText(S, TH.timedOut), "the timed-out line is missing");
  tapRow(currentTable(S), TH.done);
  await S.finished;
  assert.equal(requestsTo(S, URL.poll).length, 179, "the checks did not stop at the 15 minute deadline");
  assert.equal(S.waits, 180);
  assert.equal(S.store.has(K.pending), false);
  assert.equal(S.store.has(K.tokens), false);
  assert.equal(S.alerts.length, 1, "only the consent question");
  assertNoSecrets(S);
});

test("a check that fails with a server error keeps the code and shows a line, and the next check still succeeds", async () => {
  const S = start({
    widget: false,
    family: "medium",
    alerts: [0],
    routes: {
      [URL.usercode]: [ok({ device_auth_id: DEVICE_ID, user_code: USER_CODE, interval: 5 })],
      [URL.poll]: [fail(500), fail(403), ok({ authorization_code: "AUTH-3", code_verifier: "VER-3" })],
      [URL.token]: [ok({ access_token: ACCESS, refresh_token: REFRESH })],
      [URL.usage]: [ok(USAGE_OK)],
    },
  });
  await until(() => hasText(S, "เสร็จ"), "the connected panel");
  assert.ok(S.tickTexts.some((t) => t.includes(TH.checkFailed)), "the failed check was not shown");
  tapRow(currentTable(S), TH.done);
  await S.finished;
  assert.ok(S.store.has(K.tokens));
  assertNoSecrets(S);
});

test("a device code that cannot be started asks the consent question again with one line, and stores nothing", async () => {
  const S = start({
    widget: false,
    family: "medium",
    alerts: [0, -1],
    routes: { [URL.usercode]: [fail(500)] },
  });
  await S.finished;
  assert.equal(S.alerts.length, 2);
  assert.ok(S.alerts[1].message.startsWith(TH.startFailed), "the start-failed line is not first");
  assert.ok(S.alerts[1].message.endsWith(WARNING_TH), "the warning is missing from the retry consent");
  assert.equal(S.tables.length, 0);
  assert.equal(S.store.size, 0, "something was stored");
  assertNoSecrets(S);
});

test("a pending login from an earlier run shows the same code, resumes the checks, and asks for no new code", async () => {
  const S = start({
    widget: false,
    family: "medium",
    keychain: { [K.pending]: pendingJSON() },
    routes: {
      [URL.poll]: [fail(403), ok({ authorization_code: "AUTH-4", code_verifier: "VER-4" })],
      [URL.token]: [ok({ access_token: ACCESS, refresh_token: REFRESH })],
      [URL.usage]: [ok(USAGE_OK)],
    },
  });
  await until(() => hasText(S, "เสร็จ"), "the connected panel");
  assert.ok(S.tickTexts.some((t) => t.includes(USER_CODE)), "the earlier code was not shown again");
  tapRow(currentTable(S), TH.done);
  await S.finished;
  assert.equal(requestsTo(S, URL.usercode).length, 0, "a new device code was asked for");
  assert.equal(S.alerts.length, 0, "a prompt was shown for a login that was already pending");
  assertNoSecrets(S);
});

test("closing the code panel stops the checks and keeps the pending login for the next run", async () => {
  const S = start({
    widget: false,
    family: "medium",
    keychain: { [K.pending]: pendingJSON() },
    routes: { [URL.poll]: [fail(403)] },
    onTick: (st) => {
      if (st.waits === 2) currentTable(st).closeFn();
    },
  });
  await S.finished;
  assert.equal(requestsTo(S, URL.poll).length, 1, "a check ran after the panel closed");
  assert.ok(S.store.has(K.pending), "the pending login was removed");
  assertNoSecrets(S);
});

test("a token response that is not JSON is not stored, leaks nothing, and the flow keeps going to the timeout", async () => {
  const S = start({
    widget: false,
    family: "medium",
    alerts: [0],
    routes: {
      [URL.usercode]: [ok({ device_auth_id: DEVICE_ID, user_code: USER_CODE, interval: 5 })],
      [URL.poll]: [ok({ authorization_code: "AUTH-5", code_verifier: "VER-5" })],
      [URL.token]: [{ status: 200, text: "not json: " + ACCESS + " " + REFRESH }],
    },
  });
  await until(() => hasText(S, "เสร็จ"), "the timed-out panel");
  tapRow(currentTable(S), TH.done);
  await S.finished;
  assert.equal(S.store.has(K.tokens), false, "a bad token response was stored");
  assertNoSecrets(S);
});

// -----------------------------------------------------------------------------------------------------------------
// The connected panel and the disconnect.
// -----------------------------------------------------------------------------------------------------------------

test("an app run with a login opens the connected panel; Disconnect removes the local login and sends nothing to the provider", async () => {
  const S = start({
    widget: false,
    family: "medium",
    keychain: { [K.tokens]: tokensJSON(), [K.cache]: cacheJSON() },
  });
  await until(() => hasText(S, TH.disconnect), "the connected panel");
  assert.ok(hasText(S, "แผน Plus"), "the cached plan is missing");
  tapButton(currentTable(S), TH.disconnect);
  await S.finished;
  assert.equal(S.store.has(K.tokens), false);
  assert.equal(S.store.has(K.cache), false);
  assert.equal(S.requests.length, 0, "the provider was called on disconnect");
  assertNoSecrets(S);
});

// -----------------------------------------------------------------------------------------------------------------
// Refresh, usage and the failure states.
// -----------------------------------------------------------------------------------------------------------------

test("an expired access token is refreshed first, the rotated refresh token is saved before the usage call, and the usage call carries the new token", async () => {
  const S = start({
    widget: true,
    family: "medium",
    keychain: { [K.tokens]: tokensJSON({ access_exp_ms: T0 - 1000 }) },
    routes: { [URL.token]: [ok(REFRESHED)], [URL.usage]: [ok(USAGE_OK)] },
  });
  await S.finished;
  assert.deepEqual(S.requests.map((r) => r.url), [URL.token, URL.usage]);
  const refreshBody = JSON.parse(S.requests[0].body);
  assert.deepEqual(Object.keys(refreshBody).sort(), ["client_id", "grant_type", "refresh_token"], "a scope or another field was sent");
  assert.equal(refreshBody.grant_type, "refresh_token");
  assert.equal(refreshBody.client_id, CLIENT_ID);
  assert.equal(refreshBody.refresh_token, REFRESH);
  assert.equal(S.requests[1].headers.Authorization, "Bearer " + ACCESS_NEW);
  assert.equal(S.requests[1].headers["ChatGPT-Account-Id"], ACCOUNT_ID);
  const stored = JSON.parse(S.store.get(K.tokens));
  assert.equal(stored.refresh_token, REFRESH_NEW, "the rotated refresh token was not saved");
  assert.ok(widgetTexts(S).includes("เหลือ 60%"), "the ChatGPT row is missing");
  assertNoSecrets(S);
});

test("a refused refresh whose token is unchanged removes the login and shows the reconnect row; a widget run asks nothing", async () => {
  const S = start({
    widget: true,
    family: "medium",
    mac: MAC_SAMPLE,
    keychain: { [K.tokens]: tokensJSON({ access_exp_ms: T0 - 1000 }), [K.cache]: cacheJSON({ updated_ms: T0 - 10 * MIN }) },
    routes: { [URL.token]: [fail(400, { error: "invalid_grant" })] },
  });
  await S.finished;
  assert.equal(S.store.has(K.tokens), false, "the refused login was kept");
  assert.equal(S.store.has(K.cache), false, "the cache of the refused login was kept");
  assert.equal(S.store.get(K.status), "reconnect");
  assert.ok(widgetTexts(S).includes(TH.reLogin), "the reconnect row is missing");
  assertIdle(S);
  assert.equal(requestsTo(S, URL.usage).length, 0);
  assertNoSecrets(S);
});

test("a refused refresh after another run rotated the token uses the stored tokens and removes nothing", async () => {
  const rotatedElsewhere = (st) => {
    st.store.set(K.tokens, tokensJSON({ access_token: ACCESS_NEW, refresh_token: REFRESH_NEW, access_exp_ms: T0 + 3600 * 1000 }));
    return fail(400, { error: { code: "refresh_token_reused" } });
  };
  const S = start({
    widget: true,
    family: "medium",
    keychain: { [K.tokens]: tokensJSON({ access_exp_ms: T0 - 1000 }) },
    routes: { [URL.token]: [rotatedElsewhere], [URL.usage]: [ok(USAGE_OK)] },
  });
  await S.finished;
  assert.equal(S.store.has(K.tokens), true, "the login was removed although another run had rotated it");
  assert.equal(JSON.parse(S.store.get(K.tokens)).refresh_token, REFRESH_NEW);
  assert.equal(S.store.has(K.status), false);
  assert.equal(requestsTo(S, URL.usage)[0].headers.Authorization, "Bearer " + ACCESS_NEW, "the stored token was not used");
  assert.ok(widgetTexts(S).includes("เหลือ 60%"));
  assertNoSecrets(S);
});

test("a network error on refresh keeps the login and shows the network line", async () => {
  const S = start({
    widget: true,
    family: "medium",
    keychain: { [K.tokens]: tokensJSON({ access_exp_ms: T0 - 1000 }) },
    routes: { [URL.token]: [NETWORK] },
  });
  await S.finished;
  assert.equal(S.store.has(K.tokens), true, "the login was removed on a network error");
  assert.equal(S.store.has(K.status), false);
  assert.ok(widgetTexts(S).includes(TH.network), "the network line is missing");
  assertNoSecrets(S);
});

test("a 401 from usage refreshes once, retries once, and shows the data", async () => {
  const S = start({
    widget: true,
    family: "medium",
    keychain: { [K.tokens]: tokensJSON() },
    routes: { [URL.usage]: [fail(401), ok(USAGE_OK)], [URL.token]: [ok(REFRESHED)] },
  });
  await S.finished;
  assert.deepEqual(S.requests.map((r) => r.url), [URL.usage, URL.token, URL.usage]);
  assert.equal(JSON.parse(S.store.get(K.tokens)).refresh_token, REFRESH_NEW);
  assert.ok(widgetTexts(S).includes("เหลือ 60%"));
  assertNoSecrets(S);
});

test("a 401 that survives the refresh reconnects the login", async () => {
  const S = start({
    widget: true,
    family: "medium",
    keychain: { [K.tokens]: tokensJSON(), [K.cache]: cacheJSON({ updated_ms: T0 - 10 * MIN }) },
    routes: { [URL.usage]: [fail(401)], [URL.token]: [ok(REFRESHED)] },
  });
  await S.finished;
  assert.equal(S.store.has(K.tokens), false, "the login was kept after the second 401");
  assert.equal(S.store.get(K.status), "reconnect");
  assert.ok(widgetTexts(S).includes(TH.reLogin));
  assertNoSecrets(S);
});

test("a rate limit (429) keeps the last good data as stale and waits before the next call", async () => {
  const first = start({
    widget: true,
    family: "medium",
    keychain: { [K.tokens]: tokensJSON(), [K.cache]: cacheJSON({ updated_ms: T0 - 10 * MIN }) },
    routes: { [URL.usage]: [fail(429)] },
  });
  await first.finished;
  assert.ok(widgetTexts(first).includes(TH.rateLimited), "the rate limit line is missing");
  assert.ok(widgetTexts(first).includes("เหลือ 60%"), "the last good data was dropped");
  const kept = {};
  for (const [k, v] of first.store) kept[k] = v;
  const second = start({
    widget: true,
    family: "medium",
    now: T0 + MIN,
    keychain: kept,
    routes: { [URL.usage]: [ok(USAGE_OK)] },
  });
  await second.finished;
  assert.equal(second.requests.length, 0, "the provider was called during the wait");
  assert.ok(widgetTexts(second).includes(TH.rateLimited));
  assertNoSecrets(first);
  assertNoSecrets(second);
});

test("a server error or a network error on usage keeps the last good data as stale", async () => {
  for (const [answer, line] of [[fail(500), TH.serverError], [NETWORK, TH.network]]) {
    const S = start({
      widget: true,
      family: "medium",
      keychain: { [K.tokens]: tokensJSON(), [K.cache]: cacheJSON({ updated_ms: T0 - 10 * MIN }) },
      routes: { [URL.usage]: [answer] },
    });
    await S.finished;
    assert.ok(widgetTexts(S).includes(line), "the error line " + line + " is missing");
    assert.ok(widgetTexts(S).includes("เหลือ 60%"), "the last good data was dropped");
    assert.equal(S.store.has(K.tokens), true, "the login was removed on a failure that is not a refusal");
    assertNoSecrets(S);
  }
});

test("a fresh cache serves a widget run without calling the provider; an app run is live", async () => {
  const widgetRun = start({
    widget: true,
    family: "medium",
    keychain: { [K.tokens]: tokensJSON(), [K.cache]: cacheJSON({ updated_ms: T0 - 60 * 1000 }) },
    routes: { [URL.usage]: [ok(USAGE_OK)] },
  });
  await widgetRun.finished;
  assert.equal(widgetRun.requests.length, 0, "a widget run called the provider with a fresh cache");

  const appRun = start({
    widget: false,
    family: "medium",
    keychain: { [K.tokens]: tokensJSON(), [K.cache]: cacheJSON({ updated_ms: T0 - 60 * 1000 }) },
    routes: { [URL.usage]: [ok(USAGE_OK)] },
  });
  await until(() => hasText(appRun, TH.disconnect), "the connected panel");
  tapRow(currentTable(appRun), TH.done);
  await appRun.finished;
  assert.equal(requestsTo(appRun, URL.usage).length, 1, "an app run did not call the provider");
  assertNoSecrets(appRun);
});

test("a stored lock held by another run stops this run from refreshing the same token", async () => {
  const S = start({
    widget: true,
    family: "medium",
    mac: MAC_SAMPLE,
    keychain: { [K.tokens]: tokensJSON({ access_exp_ms: T0 - 1000 }), [K.lock]: String(T0 - 1000) },
    routes: { [URL.token]: [ok(REFRESHED)], [URL.usage]: [ok(USAGE_OK)] },
  });
  await S.finished;
  assert.equal(requestsTo(S, URL.token).length, 0, "the token was refreshed while another run held the lock");
  assert.equal(S.store.has(K.tokens), true);
  assertNoSecrets(S);
});

test("a locked Keychain reads as nothing in a widget run: the Mac copy shows and nothing is prompted", async () => {
  const S = start({ widget: true, family: "medium", mac: MAC_SAMPLE, keychainLocked: true });
  await S.finished;
  assert.ok(widgetTexts(S).includes("Claude"));
  assertIdle(S);
  assert.equal(S.requests.length, 0);
});

test("a rendering error while connected logs only the error's text, never a token", async () => {
  const S = start({
    widget: true,
    family: "medium",
    keychain: { [K.tokens]: tokensJSON(), [K.cache]: cacheJSON() },
    failStacks: true,
    routes: { [URL.usage]: [ok(USAGE_OK)] },
  });
  await S.finished;
  assert.equal(S.completes, 1);
  assert.ok(S.logs.some((line) => line.includes("boom")), "the render error was not logged");
  assertNoSecrets(S);
});

// -----------------------------------------------------------------------------------------------------------------
// The merge with the Mac copy and the sources.
// -----------------------------------------------------------------------------------------------------------------

test("with a ChatGPT login, the phone's row takes the place of the Mac's ChatGPT row; Claude and agy still come from the Mac", async () => {
  const S = start({
    widget: true,
    family: "large",
    mac: MAC_SAMPLE,
    keychain: { [K.tokens]: tokensJSON(), [K.cache]: cacheJSON({ updated_ms: T0 - 60 * 1000 }) },
  });
  await S.finished;
  const texts = widgetTexts(S);
  assert.ok(texts.includes("เหลือ 60%"), "the phone's ChatGPT row is missing");
  assert.equal(texts.includes("เหลือ 7%"), false, "the Mac's ChatGPT row is still shown");
  // The large widget names a row "name · limit", so the checks match the start of the name.
  assert.ok(texts.some((t) => t.startsWith("Claude")), "Claude is missing");
  assert.ok(texts.some((t) => t.startsWith("agy")), "agy is missing");
  assert.equal(texts.filter((t) => t.startsWith("ChatGPT")).length, 1, "the ChatGPT row is shown more than once");
  assertNoSecrets(S);
});

test("without the Mac file, only the phone's ChatGPT row shows: no Claude and no agy", async () => {
  const S = start({
    widget: true,
    family: "medium",
    keychain: { [K.tokens]: tokensJSON(), [K.cache]: cacheJSON({ updated_ms: T0 - 60 * 1000 }) },
  });
  await S.finished;
  const texts = widgetTexts(S);
  assert.ok(texts.includes("ChatGPT"));
  assert.equal(texts.some((t) => t.startsWith("Claude")), false, "Claude was shown without the Mac file");
  assert.equal(texts.includes("agy"), false, "agy was shown without the Mac file");
  assertNoSecrets(S);
});

test("two sources name each source with its age in medium, and small shows the older age", async () => {
  const S = start({
    widget: true,
    family: "medium",
    mac: MAC_SAMPLE,
    keychain: { [K.tokens]: tokensJSON(), [K.cache]: cacheJSON({ updated_ms: T0 }) },
    routes: { [URL.usage]: [ok(USAGE_OK)] },
  });
  await S.finished;
  assert.ok(widgetTexts(S).includes("Mac 8 นาทีก่อน · ChatGPT 1 นาทีก่อน"), "the two-source header is missing");
  const small = start({
    widget: true,
    family: "small",
    mac: MAC_SAMPLE,
    keychain: { [K.tokens]: tokensJSON(), [K.cache]: cacheJSON({ updated_ms: T0 }) },
    routes: { [URL.usage]: [ok(USAGE_OK)] },
  });
  await small.finished;
  const smallTexts = widgetTexts(small);
  assert.ok(smallTexts.includes("8 นาทีก่อน"), "small does not show the older source's age");
  assert.equal(smallTexts.some((t) => t.includes("ChatGPT 1")), false, "small names the sources");
  assertNoSecrets(S);
  assertNoSecrets(small);
});

// -----------------------------------------------------------------------------------------------------------------
// The helper rules, checked without running the script.
// -----------------------------------------------------------------------------------------------------------------

test("plan names and window labels follow the collector", async () => {
  const H = await helpers();
  assert.equal(H.planNameOf("prolite"), "Pro Lite");
  assert.equal(H.planNameOf("PLUS"), "Plus");
  assert.equal(H.planNameOf("pro_lite_x"), "Pro Lite X");
  assert.equal(H.planNameOf("  "), null);
  assert.equal(H.planNameOf(7), null);
  assert.equal(H.windowLabelTH(18000), "5 ชม.");
  assert.equal(H.windowLabelTH(604800), "สัปดาห์");
  assert.equal(H.windowLabelTH(172800), "2 วัน");
  assert.equal(H.windowLabelTH(10800), "3 ชม.");
  assert.equal(H.windowLabelTH(90), "2 นาที");
  assert.equal(H.windowLabelTH(null), "ช่วงเวลา");
});

test("the usage document maps to the collector's account fields", async () => {
  const H = await helpers();
  const parsed = H.parseUsage(USAGE_OK, T0);
  assert.equal(parsed.plan, "Plus");
  assert.deepEqual(parsed.limits.map((l) => [l.key, l.label, l.window_seconds, l.used_percent]), [
    ["primary", "สัปดาห์", 604800, 12.5],
    ["secondary", "5 ชม.", 18000, 40],
  ]);
  assert.equal(parsed.limits[0].resets_at, new Date(T0 + 86400 * 1000).toISOString(), "a reset from reset_after_seconds");
  assert.equal(parsed.limits[1].resets_at, new Date((NOW_S + 3600) * 1000).toISOString(), "a reset from unix seconds");
  assert.deepEqual(parsed.credits, { extra_usage_enabled: true, used_usd: null, limit_usd: null, balance_usd: 3.46 });
  assert.equal(H.parseUsage({}, T0), null);
  assert.equal(H.parseUsage({ rate_limit: { primary_window: { used_percent: "abc" } } }, T0), null);
});

test("the JWT claims read back, including the base64url characters, and the id token gives the account id only", async () => {
  const H = await helpers();
  const claims = H.jwtClaims(jwt({ name: "ü-ö_>?", exp: 1 }));
  assert.equal(claims.name, "ü-ö_>?");
  assert.equal(H.jwtClaims("not-a-jwt"), null);
  const tokens = H.tokensFrom({ access_token: ACCESS, id_token: ID_TOKEN }, { refresh_token: REFRESH, account_id: null });
  assert.equal(tokens.refresh_token, REFRESH, "a refresh with no new refresh token must keep the old one");
  assert.equal(tokens.account_id, ACCOUNT_ID);
  assert.equal(tokens.access_exp_ms, (NOW_S + 3600) * 1000);
  assert.equal(JSON.stringify(tokens).includes(EMAIL), false, "the email reached the stored tokens");
  assert.equal(JSON.stringify(tokens).includes(ID_TOKEN), false, "the id token reached the stored tokens");
});

test("the pending interval has a floor of 5 seconds and accepts text", async () => {
  const H = await helpers();
  assert.equal(H.pendingOf({ device_auth_id: "a", user_code: "b", interval_s: "3", deadline_ms: 1 }).interval_s, 5);
  assert.equal(H.pendingOf({ device_auth_id: "a", user_code: "b", interval_s: "12", deadline_ms: 1 }).interval_s, 12);
  assert.equal(H.pendingOf({ device_auth_id: "a", user_code: "b", deadline_ms: 1 }).interval_s, 5);
  assert.equal(H.pendingOf({ device_auth_id: "a", user_code: "b" }), null, "a pending login with no deadline was accepted");
});

test("the refusals and the status codes map as the Codex CLI returns them", async () => {
  const H = await helpers();
  assert.equal(H.refusedForGood({ status: 401, text: "" }), true);
  assert.equal(H.refusedForGood({ status: 400, text: JSON.stringify({ error: "invalid_grant" }) }), true);
  assert.equal(H.refusedForGood({ status: 400, text: JSON.stringify({ error: { code: "refresh_token_reused" } }) }), true);
  assert.equal(H.refusedForGood({ status: 400, text: JSON.stringify({ error: "other" }) }), false);
  assert.equal(H.refusedForGood({ status: 429, text: "" }), false);
  assert.equal(H.refusedForGood({ status: 500, text: "" }), false);
  assert.equal(H.codeOfStatus(null), "network");
  assert.equal(H.codeOfStatus(429), "rate_limited");
  assert.equal(H.codeOfStatus(503), "server_error");
  assert.equal(H.codeOfStatus(404), "unknown");
});

test("the merge keeps the place of the first codex row, drops the rest, and leaves the Mac copy alone without a login", async () => {
  const H = await helpers();
  const claude = { provider: "claude", id: "claude-main" };
  const codexA = { provider: "codex", id: "codex-main" };
  const codexB = { provider: "codex", id: "codex-2" };
  const agy = { provider: "agy", id: "agy-main" };
  const phone = { provider: "codex", id: "codex-iphone", updated_at: null };
  assert.deepEqual(H.mergeAccounts([claude, codexA, agy], { owns: true, row: phone }), [claude, phone, agy]);
  assert.deepEqual(H.mergeAccounts([claude, codexA, codexB, agy], { owns: true, row: phone }), [claude, phone, agy]);
  assert.deepEqual(H.mergeAccounts([claude, agy], { owns: true, row: phone }), [claude, agy, phone]);
  assert.deepEqual(H.mergeAccounts([claude, codexA, agy], { owns: true, row: null }), [claude, agy]);
  assert.deepEqual(H.mergeAccounts([claude, codexA, agy], { owns: false, row: null }), [claude, codexA, agy]);
});

test("the sources are the Mac copy and the phone row, each with its own time", async () => {
  const H = await helpers();
  const usage = JSON.parse(MAC_SAMPLE);
  const macAccounts = usage.accounts.filter((a) => a.provider !== "codex");
  const phone = { provider: "codex", id: "codex-iphone", updated_at: new Date(T0).toISOString() };
  const both = H.sourcesOf(usage, [...macAccounts, phone], { owns: true, row: phone });
  assert.deepEqual(both.map((s) => s.name), ["mac", "chatgpt"]);
  assert.equal(both[1].at, T0);
  const onlyPhone = H.sourcesOf(null, [phone], { owns: true, row: phone });
  assert.deepEqual(onlyPhone.map((s) => s.name), ["chatgpt"]);
  const macOnly = H.sourcesOf(usage, usage.accounts, { owns: false, row: null });
  assert.deepEqual(macOnly.map((s) => s.name), ["mac"]);
  assert.equal(macOnly[0].at, Date.parse("2026-11-19T04:30:00Z"));
});

test("the exchange body is form encoded, with the verifier and the redirect encoded", async () => {
  const H = await helpers();
  assert.equal(
    H.exchangeBody("AUTH 1", "VER/1"),
    "grant_type=authorization_code&code=AUTH%201&redirect_uri=https%3A%2F%2Fauth.openai.com%2Fdeviceauth%2Fcallback" +
      "&client_id=app_EMoamEEZ73f0CkXaXp7hrann&code_verifier=VER%2F1",
  );
});

test("a pending login whose 15 minutes have already passed opens the timed-out panel at once, with no check", async () => {
  const S = start({
    widget: false,
    family: "medium",
    keychain: { [K.pending]: pendingJSON({ deadline_ms: T0 - 1000 }) },
    routes: { [URL.poll]: [fail(403)] },
  });
  await until(() => hasText(S, TH.done), "the timed-out panel");
  assert.ok(hasText(S, TH.timedOut), "the timed-out line is missing");
  tapRow(currentTable(S), TH.done);
  await S.finished;
  assert.equal(requestsTo(S, URL.poll).length, 0, "a check ran after the deadline");
  assert.equal(S.store.has(K.pending), false, "the expired login was kept");
  assertNoSecrets(S);
});

test("the consent warning is the Mac's direct-mode warning, word for word, as the last paragraph, in both languages", async () => {
  for (const [lang, warning] of [["th", WARNING_TH], ["en", WARNING_EN]]) {
    const S = start({ widget: false, family: "medium", lang, alerts: [-1] });
    await S.finished;
    const message = S.alerts[0].message;
    assert.equal(message.split(warning).length - 1, 1, lang + ": the warning is not shown exactly once");
    assert.ok(message.endsWith("\n\n" + warning), lang + ": the warning is not the last paragraph");
  }
});
