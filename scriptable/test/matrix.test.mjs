// The iPhone matrix: the three families, Thai and English, 0, 1, 3 and 5 accounts, the three tiers (white, yellow and red)
// and the three states (ok, stale and error), each checked at the smallest and the largest frame. Five accounts is the
// badge case: small and medium show the first three and a "+2" badge.
//
// The stubs cannot switch appearance, so the appearance check is that every text colour has a light and a dark half. The
// layout is the same in both appearances. The harness below is a copy of the stubs and helpers in render.test.mjs (its
// lines 8 to 703); keep the two copies in step. The fit checks are the rough text model of render.test.mjs, not a device.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { createContext, runInContext } from "node:vm";

const here = dirname(fileURLToPath(import.meta.url));
const SCRIPT_SRC = readFileSync(join(here, "..", "AI Usage.js"), "utf8");
const SAMPLE_TEXT = readFileSync(join(here, "usage.sample.json"), "utf8");

const FILE = "/icloud/Documents/ai-usage.json";
const NOW_ISO = "2026-11-19T04:38:00Z";
const NOW_MS = Date.parse(NOW_ISO);
const NO_DATA = "ยังไม่มีข้อมูล เปิด Mac ไว้";
const NO_DATA_EN = "No data yet. Keep your Mac on.";
const FAILED = "แสดงผลไม่ได้";
const FAILED_EN = "Can't show the data";
const NO_LIMIT = "ไม่มีข้อมูล";
// Battery colours. Drawn gauges and rings take one fixed colour per tier; text and pills take a light/dark pair.
const DRAWN = { white: "8E8E93", yellow: "B58900", red: "D93025" };
const TEXT_PAIR = { yellow: ["B58900", "FFD60A"], red: ["D93025", "FF5F57"] };
const TRACK_HEX = "8E8E93";
const THAI_LETTER = /[฀-๿]/;
const FAMILIES = ["small", "medium", "large"];
// Frames the layouts are checked against. These are ASSUMPTIONS, not measured values, and must be
// confirmed on a device. The minimum medium and large frames are from memory of Apple's widget sizes,
// the small frame is a guess, and the maximum frames are assumed for the largest iPhones.
const MIN_FRAME = { small: { w: 141, h: 141 }, medium: { w: 321, h: 148 }, large: { w: 321, h: 324 } };
const MAX_FRAME = { small: { w: 170, h: 170 }, medium: { w: 364, h: 170 }, large: { w: 364, h: 382 } };

let S = null; // state of the current run, read by the stubs

class FixedDate extends Date {
  constructor(...args) {
    if (args.length === 0) super(NOW_MS);
    else super(...args);
  }
  static now() {
    return NOW_MS;
  }
}

class Size {
  constructor(width, height) {
    if (typeof width !== "number" || typeof height !== "number") throw new TypeError("Size needs numbers");
    this.width = width;
    this.height = height;
    Object.freeze(this);
  }
}

class Rect {
  constructor(x, y, width, height) {
    for (const v of [x, y, width, height]) {
      if (typeof v !== "number") throw new TypeError("Rect needs numbers");
    }
    Object.assign(this, { x, y, width, height });
    Object.freeze(this);
  }
}

class Point {
  constructor(x, y) {
    if (typeof x !== "number" || typeof y !== "number") throw new TypeError("Point needs numbers");
    this.x = x;
    this.y = y;
    Object.freeze(this);
  }
}

class Color {
  constructor(hex, alpha = 1) {
    if (typeof hex !== "string") throw new TypeError("Color needs a hex string");
    this.hex = hex.replace(/^#/, "").toUpperCase();
    this.alpha = alpha;
    Object.freeze(this);
  }
  static dynamic(light, dark) {
    if (!(light instanceof Color) || !(dark instanceof Color)) throw new TypeError("dynamic needs two Colors");
    return { dynamic: true, light, dark };
  }
}

class Font {
  constructor(size, weight) {
    if (typeof size !== "number") throw new TypeError("Font needs a size");
    this.size = size;
    this.weight = weight;
    Object.freeze(this);
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
  constructor() {
    this.ops = [];
    Object.seal(this);
  }
  move(point) {
    if (!(point instanceof Point)) throw new TypeError("move needs a Point");
    this.ops.push({ op: "move", point });
  }
  addLine(point) {
    if (!(point instanceof Point)) throw new TypeError("addLine needs a Point");
    if (this.ops.length === 0) throw new Error("addLine called before move");
    this.ops.push({ op: "line", point });
  }
}

class DrawContext {
  constructor() {
    this.size = null;
    this.respectScreenScale = false;
    this.opaque = true;
    this.strokeColor = null;
    this.lineWidth = 1;
    this.lastPath = null;
    this.strokes = [];
    Object.seal(this);
  }
  setStrokeColor(color) {
    if (!(color instanceof Color)) throw new TypeError("setStrokeColor needs a Color (dynamic colors are not supported)");
    this.strokeColor = color;
  }
  setLineWidth(width) {
    if (typeof width !== "number" || !(width > 0)) throw new TypeError("setLineWidth needs a positive number");
    this.lineWidth = width;
  }
  addPath(path) {
    if (!(path instanceof Path)) throw new TypeError("addPath needs a Path");
    this.lastPath = path;
  }
  strokePath(...args) {
    if (args.length > 0) throw new TypeError("strokePath takes no arguments: it strokes the path added last");
    if (this.lastPath === null) throw new Error("strokePath called before addPath");
    if (this.strokeColor === null) throw new Error("strokePath called before setStrokeColor");
    this.strokes.push({ color: this.strokeColor, width: this.lineWidth, path: this.lastPath });
  }
  strokeEllipse(rect) {
    if (!(rect instanceof Rect)) throw new TypeError("strokeEllipse needs a Rect");
    if (this.strokeColor === null) throw new Error("strokeEllipse called before setStrokeColor");
    this.strokes.push({ color: this.strokeColor, width: this.lineWidth, ellipse: rect });
  }
  getImage() {
    if (!(this.size instanceof Size)) throw new Error("DrawContext.size must be set");
    return {
      kind: "image",
      size: this.size,
      respectScreenScale: this.respectScreenScale,
      opaque: this.opaque,
      strokes: this.strokes.slice(),
    };
  }
}

function addChild(parent, child) {
  parent.children.push(child);
  return child;
}

// The docs define a flexible spacer as null (or no argument). Zero is not defined, so it throws here.
function spacerOf(length) {
  if (length === 0) throw new Error("addSpacer(0) is not defined by the docs; use null for a flexible spacer");
  return { spacer: true, length: length === undefined ? null : length };
}

class WidgetText {
  constructor(text) {
    if (typeof text !== "string") throw new TypeError("addText expects a string, got " + typeof text);
    this.text = text;
    this.font = null;
    this.textColor = null;
    this.textOpacity = 1;
    this.lineLimit = 0;
    this.minimumScaleFactor = 1;
    this.alignment = "left";
    this.url = null;
    Object.seal(this);
  }
  leftAlignText() {
    this.alignment = "left";
  }
  centerAlignText() {
    this.alignment = "center";
  }
  rightAlignText() {
    this.alignment = "right";
  }
}

class WidgetStack {
  constructor() {
    this.children = [];
    this.padding = [0, 0, 0, 0];
    this.direction = "horizontal";
    this.alignment = null;
    this.size = null;
    this.spacing = 0;
    this.url = null;
    this.backgroundColor = null;
    this.backgroundImage = null;
    this.backgroundGradient = null;
    this.cornerRadius = 0;
    this.borderWidth = 0;
    this.borderColor = null;
    Object.seal(this);
  }
  addText(text) {
    return addChild(this, new WidgetText(text));
  }
  addStack() {
    if (S.failStacks) throw new Error("boom");
    return addChild(this, new WidgetStack());
  }
  addSpacer(length) {
    this.children.push(spacerOf(length));
  }
  setPadding(top, leading, bottom, trailing) {
    this.padding = [top, leading, bottom, trailing];
  }
  useDefaultPadding() {
    this.padding = [0, 0, 0, 0];
  }
  topAlignContent() {
    this.alignment = "top";
  }
  centerAlignContent() {
    this.alignment = "center";
  }
  bottomAlignContent() {
    this.alignment = "bottom";
  }
  layoutHorizontally() {
    this.direction = "horizontal";
  }
  layoutVertically() {
    this.direction = "vertical";
  }
}

class ListWidget {
  constructor() {
    this.children = [];
    this.padding = [0, 0, 0, 0];
    this.direction = "vertical";
    this.backgroundColor = null;
    this.backgroundImage = null;
    this.backgroundGradient = null;
    this.addAccessoryWidgetBackground = false;
    this.spacing = 0;
    this.url = null;
    this.refreshAfterDate = null;
    this.presented = null;
    Object.seal(this);
    S.made.push(this);
  }
  addText(text) {
    return addChild(this, new WidgetText(text));
  }
  addStack() {
    if (S.failStacks) throw new Error("boom");
    return addChild(this, new WidgetStack());
  }
  addSpacer(length) {
    this.children.push(spacerOf(length));
  }
  setPadding(top, leading, bottom, trailing) {
    this.padding = [top, leading, bottom, trailing];
  }
  useDefaultPadding() {
    this.padding = [0, 0, 0, 0];
  }
  presentSmall() {
    this.presented = "small";
    return Promise.resolve();
  }
  presentMedium() {
    this.presented = "medium";
    return Promise.resolve();
  }
  presentLarge() {
    this.presented = "large";
    return Promise.resolve();
  }
}

const FileManager = {
  iCloud() {
    return {
      documentsDirectory() {
        return "/icloud/Documents";
      },
      joinPath(lhs, rhs) {
        return lhs + "/" + rhs;
      },
      fileExists(path) {
        return Object.prototype.hasOwnProperty.call(S.files, path);
      },
      downloadFileFromiCloud(path) {
        S.downloads.push(path);
        // Per the docs: resolves at once for a file that is not in iCloud. A failure is forced by tests.
        if (S.downloadFails) return Promise.reject(new Error("iCloud download failed"));
        return Promise.resolve();
      },
      readString(path) {
        return Object.prototype.hasOwnProperty.call(S.files, path) ? S.files[path] : null;
      },
    };
  },
};

const Script = {
  setWidget(widget) {
    S.setWidgets.push(widget);
  },
  complete() {
    S.completes += 1;
  },
};

// The ChatGPT code in AI Usage.js reads the Keychain, and the app shows its menu. These stubs keep every test here
// offline: the Keychain starts empty, the Alert answers -1 ("Not now"), and any request fails. What they record is in S.
const Keychain = {
  set(key, value) {
    S.store.set(key, value);
  },
  get(key) {
    if (!S.store.has(key)) throw new Error("no such key");
    return S.store.get(key);
  },
  contains(key) {
    return S.store.has(key);
  },
  remove(key) {
    if (!S.store.has(key)) throw new Error("no such key");
    S.store.delete(key);
  },
};
class Alert {
  constructor() {
    this.title = "";
    this.message = "";
    this.actions = [];
  }
  addAction(title) {
    this.actions.push(title);
  }
  addCancelAction(title) {
    this.actions.push(title);
  }
  addDestructiveAction(title) {
    this.actions.push(title);
  }
  present() {
    S.alerts.push(this.title);
    return Promise.resolve(-1);
  }
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
  loadString() {
    S.requests.push(this.url);
    return Promise.reject(new Error("no network in these tests"));
  }
}
const Safari = {
  open(url) {
    S.opened.push(url);
  },
};
const Pasteboard = {
  copyString(text) {
    S.pasted.push(text);
  },
};
const Timer = {
  schedule(ms, repeats, callback) {
    S.timers.push(ms);
    Promise.resolve().then(callback);
    return { invalidate() {} };
  },
};
class UITableRow {
  constructor() {
    this.cells = [];
  }
  addText() {
    const cell = {};
    this.cells.push(cell);
    return cell;
  }
  addButton() {
    const cell = {};
    this.cells.push(cell);
    return cell;
  }
}
class UITable {
  constructor() {
    this.rows = [];
  }
  addRow(row) {
    this.rows.push(row);
  }
  removeAllRows() {
    this.rows = [];
  }
  reload() {}
  present() {
    return Promise.resolve();
  }
}

function withTimeout(promise, ms) {
  let timer;
  const timeout = new Promise((_, reject) => {
    timer = setTimeout(() => reject(new Error("script did not finish")), ms);
  });
  return Promise.race([promise, timeout]).finally(() => clearTimeout(timer));
}

// Options: family, runsInWidget, files, downloadFails, failStacks, deviceLanguage (default "th"),
// deviceLanguageThrows, parameter (the widget's Parameter, default null).
async function runScript(options = {}) {
  S = {
    family: options.family ?? "medium",
    runsInWidget: options.runsInWidget ?? true,
    files: options.files !== undefined ? options.files : { [FILE]: SAMPLE_TEXT },
    downloadFails: options.downloadFails ?? false,
    failStacks: options.failStacks ?? false,
    deviceLanguage: "deviceLanguage" in options ? options.deviceLanguage : "th",
    deviceLanguageThrows: options.deviceLanguageThrows ?? false,
    parameter: "parameter" in options ? options.parameter : null,
    made: [],
    setWidgets: [],
    completes: 0,
    errors: [],
    downloads: [],
    store: new Map(),
    alerts: [],
    requests: [],
    opened: [],
    pasted: [],
    timers: [],
  };
  const sandbox = {
    ListWidget, WidgetStack, WidgetText, Color, Font, Size, Rect, Point, Path, DrawContext,
    FileManager, Script, Keychain, Alert, Request, Safari, Pasteboard, Timer, UITable, UITableRow,
    Device: {
      language() {
        if (S.deviceLanguageThrows) throw new Error("no device language");
        return S.deviceLanguage;
      },
    },
    args: { widgetParameter: S.parameter },
    config: { runsInWidget: S.runsInWidget, runsInApp: !S.runsInWidget, widgetFamily: S.runsInWidget ? S.family : undefined },
    console: { log() {}, warn() {}, error: (...args) => S.errors.push(args.map(String).join(" ")) },
    Date: FixedDate,
  };
  const context = createContext(sandbox);
  // The script body also returns its helpers, so tests can check them directly.
  const body = `(async () => {\n"use strict";\n${SCRIPT_SRC}\nreturn { timeSpan, ageText, resetText, languageOf, shownPct, shownLeft, tierOf, leftOf };\n})()`;
  S.api = await withTimeout(runInContext(body, context, { filename: "AI Usage.js" }), 3000);
  return S;
}

// Runs the script and checks that it logged nothing and completed exactly once.
async function render(options) {
  const s = await runScript(options);
  assert.deepEqual(s.errors, [], "the script logged errors");
  assert.equal(s.completes, 1, "Script.complete must run exactly once");
  return s;
}

function homeWidget(s) {
  assert.equal(s.setWidgets.length, 1, "expected exactly one Script.setWidget call");
  return s.setWidgets[0];
}

function assertRefresh(widget) {
  assert.equal(widget.refreshAfterDate.getTime() - NOW_MS, 5 * 60 * 1000, "refresh five minutes after the run");
}

function visit(node, fn) {
  fn(node);
  for (const child of node.children ?? []) {
    if (!child.spacer) visit(child, fn);
  }
}

function texts(widget) {
  const out = [];
  visit(widget, (node) => {
    if (node instanceof WidgetText) out.push(node);
  });
  return out;
}

function textValues(widget) {
  return texts(widget).map((t) => t.text);
}

// Colour of a fill, stroke or text: the hex of a plain colour, "dynamic" for a light and dark pair.
function hexOf(color) {
  if (color instanceof Color) return color.hex;
  return color && color.dynamic === true ? "dynamic" : null;
}

function stacks(widget) {
  const out = [];
  visit(widget, (node) => {
    if (node instanceof WidgetStack) out.push(node);
  });
  return out;
}

function sized(widget, width, height) {
  return stacks(widget).filter((s) => s.size && s.size.width === width && s.size.height === height);
}

// Gauges: the 24 x 11 capsules. The fill is the capsule's only stack child; none when the gauge is empty.
function gauges(widget) {
  return sized(widget, 24, 11).map((cap) => {
    const fill = cap.children.find((c) => c instanceof WidgetStack);
    return fill ? { fill: hexOf(fill.backgroundColor), width: fill.size.width } : { fill: null, width: 0 };
  });
}

// Brand icons: the 20 x 20 rounded squares, with their letter and colour.
function icons(widget) {
  return sized(widget, 20, 20).map((s) => ({
    letter: s.children.find((c) => c instanceof WidgetText).text,
    hex: hexOf(s.backgroundColor),
  }));
}

// The first text inside a node, at any depth (the ring number sits in a centring row inside the ring).
function firstText(node) {
  return texts(node)[0];
}

// Rings: the stacks that carry a ring drawing as their background, with the number drawn on top.
function rings(widget) {
  return stacks(widget)
    .filter((s) => s.backgroundImage !== null)
    .map((s) => ({ number: firstText(s).text, image: s.backgroundImage }));
}

function ringNumberColor(widget, index) {
  const ring = stacks(widget).filter((s) => s.backgroundImage !== null)[index];
  return firstText(ring).textColor;
}

// Hairlines: the 0.5 pt rules that have a colour (their wrapper rows have none).
function hairlines(widget) {
  return stacks(widget).filter((s) => s.size && s.size.height === 0.5 && s.backgroundColor !== null);
}

// The outline and the nub colour of each gauge, in order.
function gaugeEdges(widget) {
  const caps = sized(widget, 24, 11);
  const nubs = sized(widget, 1.5, 4.5);
  return caps.map((cap, i) => ({ outline: hexOf(cap.borderColor), nub: hexOf(nubs[i].backgroundColor) }));
}

// The two hex values of a light and dark pair, or null for a plain colour.
function pairOf(color) {
  return color && color.dynamic === true ? [color.light.hex, color.dark.hex] : null;
}

// The pill tints: the stacks whose background is a light and dark pair with a 22% alpha.
function pillBackgrounds(widget) {
  return stacks(widget).filter(
    (s) => s.backgroundColor && s.backgroundColor.dynamic === true && s.backgroundColor.light.alpha === 0.22,
  );
}

// A plain colour is checked by its hex, and a light and dark pair by its two hexes.
function assertColour(actual, expected, message) {
  if (Array.isArray(expected)) assert.deepEqual(pairOf(actual), expected, message);
  else assert.equal(hexOf(actual), expected, message);
}

// Fixtures ------------------------------------------------------------------------------------

function usageFile(accounts, extra = {}) {
  return JSON.stringify({ schema: 1, generated_at: NOW_ISO, accounts, ...extra });
}

// limits: [label, used_percent, resets_at?]
function account(provider, label, limits, extra = {}) {
  return {
    id: provider + "-main",
    provider,
    label,
    plan: "Max",
    status: "ok",
    error: null,
    updated_at: NOW_ISO,
    limits: limits.map(([name, pct, resetsAt], i) => ({
      key: "k" + i,
      label: name,
      used_percent: pct,
      resets_at: resetsAt ?? null,
    })),
    usage: null,
    credits: null,
    ...extra,
  };
}

function thresholdFixture(values) {
  return usageFile([
    account("claude", "Claude", values.map((v, i) => ["L" + i, v])),
  ]);
}

const ERROR_FIXTURE = JSON.stringify({
  schema: 1,
  generated_at: NOW_ISO,
  accounts: [
    {
      id: "agy-main", provider: "agy", label: "agy", plan: "free-tier", status: "error",
      error: "ล็อกอิน agy หมดอายุ", updated_at: null, limits: [], usage: null, credits: null,
    },
    {
      id: "codex-main", provider: "codex", label: "ChatGPT", plan: "Pro Lite", status: "stale",
      error: "ล็อกอิน Codex หมดอายุ เปิด codex สักครั้ง", updated_at: "2026-11-19T03:38:00Z",
      limits: [{ key: "primary", label: "สัปดาห์", used_percent: 93, resets_at: "2026-11-20T02:35:51Z" }],
      usage: null,
      credits: null,
    },
  ],
});

// Worst case: Claude 4 limits, Codex 2, agy 4 with a stale error, and credits.
const WORST = {
  schema: 1,
  generated_at: NOW_ISO,
  accounts: [
    {
      id: "claude-main", provider: "claude", label: "Claude", plan: "Max", status: "ok", error: null,
      updated_at: "2026-11-19T04:30:00Z",
      limits: [
        { key: "five_hour", label: "5 ชม.", used_percent: 42, resets_at: "2026-11-19T06:40:00Z" },
        { key: "seven_day", label: "สัปดาห์", used_percent: 67, resets_at: "2026-11-24T02:00:00Z" },
        { key: "seven_day_opus", label: "Opus", used_percent: 12, resets_at: "2026-11-24T02:00:00Z" },
        { key: "seven_day_sonnet", label: "Sonnet", used_percent: 5, resets_at: "2026-11-24T02:00:00Z" },
      ],
      usage: { today: { tokens: 1200000, cost_usd: 18.4 }, month: { tokens: 35000000, cost_usd: 512 } },
      credits: { extra_usage_enabled: true, used_usd: 0, limit_usd: 50, balance_usd: null },
    },
    {
      id: "codex-main", provider: "codex", label: "ChatGPT", plan: "Pro Lite", status: "ok", error: null,
      updated_at: "2026-11-19T04:30:00Z",
      limits: [
        { key: "primary", label: "5 ชม.", used_percent: 93, resets_at: "2026-11-19T09:00:00Z" },
        { key: "secondary", label: "สัปดาห์", used_percent: 40, resets_at: "2026-11-20T02:35:51Z" },
      ],
      usage: { today: { tokens: 640000, cost_usd: null }, month: { tokens: 9000000, cost_usd: null } },
      credits: { extra_usage_enabled: false, used_usd: null, limit_usd: null, balance_usd: 0 },
    },
    {
      id: "agy-main", provider: "agy", label: "agy", plan: "free-tier", status: "stale",
      error: "ล็อกอิน agy หมดอายุ", updated_at: "2026-11-19T02:30:00Z",
      limits: [
        { key: "claude", label: "Claude", used_percent: 0, resets_at: "2026-11-19T09:21:41Z" },
        { key: "gemini_pro", label: "Gemini Pro", used_percent: 0, resets_at: "2026-11-19T09:21:41Z" },
        { key: "gemini_flash", label: "Gemini Flash", used_percent: 0, resets_at: "2026-11-19T09:21:41Z" },
        { key: "gpt_oss", label: "GPT-OSS", used_percent: 0, resets_at: "2026-11-19T09:21:41Z" },
      ],
      usage: null,
      credits: null,
    },
  ],
};
const WORST_TEXT = JSON.stringify(WORST);

// The sample with the window_seconds field on every limit. agy's model groups have no window.
function v2Sample() {
  const data = JSON.parse(SAMPLE_TEXT);
  data.accounts[0].limits[0].window_seconds = 18000; // Claude five_hour
  data.accounts[0].limits[1].window_seconds = 604800; // Claude seven_day
  data.accounts[1].limits[0].window_seconds = 604800; // ChatGPT primary, a week
  for (const l of data.accounts[2].limits) l.window_seconds = null; // agy model groups
  return JSON.stringify(data);
}
const V2_TEXT = v2Sample();

// One Claude account with one limit: the window_seconds under test (undefined leaves the field out).
function windowFile(windowSeconds, key = "five_hour") {
  const limit = { key, label: "5 ชม.", used_percent: 10, resets_at: "2026-11-19T06:38:00Z" };
  if (windowSeconds !== undefined) limit.window_seconds = windowSeconds;
  return usageFile([{
    id: "claude-main", provider: "claude", label: "Claude", plan: "Max", status: "ok", error: null,
    updated_at: NOW_ISO, limits: [limit], usage: null, credits: null,
  }]);
}

// One Claude account with the file's own label "ห้าชั่วโมง" and a 5-hour window: the built name must win.
const RELABELLED_TEXT = usageFile([{
  id: "claude-main", provider: "claude", label: "Claude", plan: "Max", status: "ok", error: null,
  updated_at: NOW_ISO,
  limits: [{ key: "five_hour", label: "ห้าชั่วโมง", used_percent: 10, resets_at: "2026-11-19T06:38:00Z", window_seconds: 18000 }],
  usage: null, credits: null,
}]);

// Claude's Opus and Sonnet week limits, as the collector writes them.
const OPUS_SONNET_TEXT = usageFile([{
  id: "claude-main", provider: "claude", label: "Claude", plan: "Max", status: "ok", error: null,
  updated_at: NOW_ISO,
  limits: [
    { key: "seven_day_opus", label: "สัปดาห์ (Opus)", used_percent: 12, resets_at: "2026-11-24T02:00:00Z", window_seconds: 604800 },
    { key: "seven_day_sonnet", label: "สัปดาห์ (Sonnet)", used_percent: 5, resets_at: "2026-11-24T02:00:00Z", window_seconds: 604800 },
  ],
  usage: null, credits: null,
}]);

// One account with an error, its error_code (undefined leaves the field out) and a Thai error text.
function errorCodeFile(code) {
  const acc = {
    id: "claude-main", provider: "claude", label: "Claude", plan: "Max", status: "error",
    error: "ข้อความเดิม", updated_at: null, limits: [], usage: null, credits: null,
  };
  if (code !== undefined) acc.error_code = code;
  return usageFile([acc]);
}

// The seven error codes, with their Thai and English texts.
const ERROR_CODE_TEXTS = [
  ["login_expired", "ล็อกอินหมดอายุ", "Sign-in expired"],
  ["relogin_needed", "ต้องล็อกอินใหม่", "Sign in again"],
  ["not_set_up", "ยังไม่มีโปรเจกต์", "No project yet"],
  ["network", "เชื่อมต่อเครือข่ายไม่ได้", "No network connection"],
  ["rate_limited", "ถูกจำกัดการเรียกชั่วคราว", "Rate limited for now"],
  ["server_error", "เซิร์ฟเวอร์มีปัญหา", "Server error"],
  ["unknown", "เกิดข้อผิดพลาดที่ไม่ทราบสาเหตุ", "Unknown error"],
];

// Rough layout model: text height = lines x size x 1.3. One-line text width = characters x size x em.
// em is 0.5 for both languages. A Thai header measures at about 0.4 to 0.45 em, and a rough glyph
// estimate for SF Pro English gives about 0.48 em. Neither is measured on a device. A text that may wrap
// (lineLimit above 1) takes its container's width, so it adds no width here. Fixed sizes win, flexible
// spacers take no room. With `shrink`, a one-line text takes the smallest width its minimumScaleFactor
// allows, because Scriptable shrinks such text before it truncates.
function measure(node, opts) {
  if (node instanceof WidgetText) {
    const lines = node.lineLimit > 0 ? node.lineLimit : 1;
    const scale = opts.shrink ? node.minimumScaleFactor : 1;
    const oneLineWidth = lines > 1 ? 0 : [...node.text].length * node.font.size * opts.em * scale;
    return { w: oneLineWidth, h: lines * node.font.size * 1.3 };
  }
  const horizontal = node.direction === "horizontal";
  let w = 0;
  let h = 0;
  for (const child of node.children) {
    if (child.spacer) {
      const len = child.length ?? 0;
      if (horizontal) w += len;
      else h += len;
      continue;
    }
    const m = measure(child, opts);
    if (horizontal) {
      w += m.w;
      h = Math.max(h, m.h);
    } else {
      w = Math.max(w, m.w);
      h += m.h;
    }
  }
  if (node.size && node.size.width > 0) w = node.size.width;
  if (node.size && node.size.height > 0) h = node.size.height;
  const [top, left, bottom, right] = node.padding;
  return { w: w + left + right, h: h + top + bottom };
}

function assertFits(widget, frame, label, { shrink = false, em = 0.5 } = {}) {
  const m = measure(widget, { shrink, em });
  assert.ok(m.h <= frame.h, `${label}: estimated height ${m.h.toFixed(1)} exceeds ${frame.h}`);
  assert.ok(m.w <= frame.w, `${label}: estimated width ${m.w.toFixed(1)} exceeds ${frame.w}`);
}


// The matrix ----------------------------------------------------------------------------------------------------------

// The accounts of each count, in file order. Five is two Claude, two ChatGPT and one agy.
const MATRIX_ACCOUNTS = {
  1: [["claude", "Claude"]],
  3: [["claude", "Claude"], ["codex", "ChatGPT"], ["agy", "agy"]],
  5: [["claude", "Claude 1"], ["claude", "Claude 2"], ["codex", "ChatGPT 1"], ["codex", "ChatGPT 2"], ["agy", "agy"]],
};
// Every limit at one used share: white (32), yellow (85) and red (95).
const MATRIX_TIERS = { white: 32, yellow: 85, red: 95 };
const MATRIX_ERROR_TEXT = {
  claude: "ล็อกอิน Claude หมดอายุ เปิด Claude Code สักครั้ง",
  codex: "ล็อกอิน Codex หมดอายุ เปิด codex สักครั้ง",
  agy: "ล็อกอิน agy หมดอายุ",
};
// Small and medium show the first three accounts (see maxRings and maxRows in AI Usage.js).
const MATRIX_SHOWN = 3;

function matrixLimits(provider, used) {
  if (provider === "claude") return [["5 ชม.", used, "2026-11-19T06:40:00Z"], ["สัปดาห์", used, "2026-11-24T02:00:00Z"]];
  if (provider === "codex") return [["สัปดาห์", used, "2026-11-20T02:00:00Z"]];
  return [["Claude", used, "2026-11-19T09:00:00Z"], ["Gemini Pro", used, "2026-11-19T09:00:00Z"]];
}

// ok: fresh data. stale: the last run failed and the old limits stay. error: no data yet, so there are no limits.
function matrixFile(count, tier, state) {
  const accounts = (MATRIX_ACCOUNTS[count] ?? []).map(([provider, label]) => {
    if (state === "ok") return account(provider, label, matrixLimits(provider, MATRIX_TIERS[tier]));
    const failed = { error: MATRIX_ERROR_TEXT[provider], error_code: "login_expired" };
    if (state === "stale") {
      return account(provider, label, matrixLimits(provider, MATRIX_TIERS[tier]), {
        ...failed,
        status: "stale",
        updated_at: "2026-11-19T01:30:00Z",
      });
    }
    return account(provider, label, [], { ...failed, status: "error", updated_at: null });
  });
  return usageFile(accounts);
}

// Zero accounts has no tier or state, and the error state has no limits, so those cases are written once each.
function matrixCases() {
  const cases = [{ count: 0, tier: "na", state: "na" }];
  for (const count of [1, 3, 5]) {
    for (const state of ["ok", "stale"]) {
      for (const tier of Object.keys(MATRIX_TIERS)) cases.push({ count, tier, state });
    }
    cases.push({ count, tier: "na", state: "error" });
  }
  return cases;
}

// Reported, not fixed. Medium with five accounts in the ok state has reset text. At the assumed 364 pt frame its text at
// full size is 2 to 4 % too wide (376.5 pt in Thai, 371 pt in English). Every medium text goes through style(), which lets
// it shrink to 0.7 (AI Usage.js), so it fits by shrinking on a device. The full-size check stays strict: these six cases
// are listed here, any other overflow fails, and a listed case that stops overflowing also fails until the list is updated.
const KNOWN_OVERFLOW = [
  "medium/th/5 accounts/white/ok largest", "medium/th/5 accounts/yellow/ok largest", "medium/th/5 accounts/red/ok largest",
  "medium/en/5 accounts/white/ok largest", "medium/en/5 accounts/yellow/ok largest", "medium/en/5 accounts/red/ok largest",
  // The small Thai header "Quota Battery" (owner decision: keep the size): about 1.5 pt wide by estimate at the largest
  // frame. It shrinks about 1% through minimumScaleFactor on a device.
  "small/th/1 accounts/white/ok largest", "small/th/1 accounts/yellow/ok largest", "small/th/1 accounts/red/ok largest",
  "small/th/3 accounts/white/ok largest", "small/th/3 accounts/yellow/ok largest", "small/th/3 accounts/red/ok largest",
  "small/th/5 accounts/white/ok largest", "small/th/5 accounts/yellow/ok largest", "small/th/5 accounts/red/ok largest",
];

// Both halves of every dynamic text colour must be a six-digit hex, so both appearances have a colour.
function assertColourHalves(widget, label) {
  for (const t of texts(widget)) {
    const c = t.textColor;
    if (c && c.dynamic === true) {
      for (const half of [c.light, c.dark]) assert.match(half.hex, /^[0-9A-F]{6}$/, `${label}: colour ${half.hex}`);
    }
  }
}

for (const family of FAMILIES) {
  for (const deviceLanguage of ["th", "en"]) {
    test(`matrix ${family} ${deviceLanguage}: 0, 1, 3 and 5 accounts, three tiers and three states fit both frames`, async () => {
      const cases = matrixCases();
      const problems = [];
      for (const c of cases) {
        const label = `${family}/${deviceLanguage}/${c.count} accounts/${c.tier}/${c.state}`;
        const text = c.count === 0 ? usageFile([]) : matrixFile(c.count, c.tier, c.state);
        const w = homeWidget(await render({ family, files: { [FILE]: text }, deviceLanguage }));
        const values = textValues(w);
        if (c.count === 0) {
          assert.ok(values.includes(deviceLanguage === "th" ? NO_DATA : NO_DATA_EN), `${label}: no-data message`);
        }
        if (family !== "large") {
          const hidden = Math.max(0, c.count - MATRIX_SHOWN);
          if (hidden > 0) assert.ok(values.includes("+" + hidden), `${label}: the "+${hidden}" badge is missing`);
          else assert.ok(!values.some((v) => /^\+\d+$/.test(v)), `${label}: a badge shows with no accounts left out`);
        }
        assertColourHalves(w, label);
        for (const [frame, name, shrink] of [[MIN_FRAME[family], "smallest", true], [MAX_FRAME[family], "largest", false]]) {
          try {
            assertFits(w, frame, `${label} ${name}`, { shrink });
          } catch (error) {
            problems.push(error.message);
          }
        }
      }
      assert.equal(cases.length, 22);
      const found = problems.map((p) => p.slice(0, p.indexOf(": estimated")));
      const known = KNOWN_OVERFLOW.filter((l) => l.startsWith(`${family}/${deviceLanguage}/`));
      assert.deepEqual(found.filter((l) => !known.includes(l)), [], "fit problems that are not known:\n" + problems.join("\n"));
      assert.deepEqual(known.filter((l) => !found.includes(l)), [], "a known overflow no longer shows: update KNOWN_OVERFLOW");
    });
  }
}
