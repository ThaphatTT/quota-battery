// Runs "AI Usage.js" against sample data with stubbed Scriptable globals.
// The stubs follow the Scriptable docs (docs.scriptable.app): only documented members exist,
// instances are sealed (an unknown property throws), DrawContext strokes use the colour and width set
// before them, dynamic colours are refused inside DrawContext, and addSpacer(0) is not defined (null is
// the flexible spacer). The docs do not say what Device.language() or args.widgetParameter return when
// unset, so the tests cover null, empty, odd and throwing values as well. Layout checks use a rough text
// model (see measure), so they catch gross overflow only. They are not a device check.
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

// Tests ---------------------------------------------------------------------------------------

test("sample fixture: schema 1 with three accounts from the contract", () => {
  const data = JSON.parse(SAMPLE_TEXT);
  assert.equal(data.schema, 1);
  assert.deepEqual(data.accounts.map((a) => a.provider), ["claude", "codex", "agy"]);
});

test("small: three rings show what is left of each account's highest limit, with the label below", async () => {
  const w = homeWidget(await render({ family: "small" }));
  assert.deepEqual(rings(w).map((r) => r.number), ["33", "7", "100"]);
  const t = textValues(w);
  for (const v of ["การใช้งาน AI", "8 นาทีก่อน", "Claude", "ChatGPT", "agy", "สถานะระบบ", "ใกล้หมด 1 รายการ"]) {
    assert.ok(t.includes(v), `small is missing "${v}"`);
  }
  assert.ok(!t.some((v) => v.includes("%")), "small shows bare numbers in the rings");
  assert.ok(!t.includes("ใกล้หมด"), "the pill is for the large widget only");
  assert.equal(sized(w, 5, 5).length, 1, "a green dot: every account is ok");
  assert.equal(hairlines(w).length, 1, "one rule above the footer");
  assertRefresh(w);
});

test("small: the footer counts the rings shown that are yellow or red, and leaves the count out when none is", async () => {
  const none = usageFile([
    account("claude", "Claude", [["5 ชม.", 42]]),
    account("codex", "ChatGPT", [["สัปดาห์", 79.6]]),
    account("agy", "agy", [["Claude", 0]]),
  ]);
  const t = textValues(homeWidget(await render({ family: "small", files: { [FILE]: none } })));
  assert.ok(t.includes("สถานะระบบ"));
  assert.ok(!t.some((v) => v.startsWith("ใกล้หมด")), "no ring is yellow or red, so no almost-out text");

  // A fourth account has a red limit, but it has no ring, so it is not counted.
  const four = usageFile([
    account("claude", "Claude", [["5 ชม.", 42]]),
    account("codex", "ChatGPT", [["สัปดาห์", 10]]),
    account("agy", "agy", [["Claude", 0]]),
    account("agy", "agy 2", [["Claude", 95]]),
  ]);
  const t4 = textValues(homeWidget(await render({ family: "small", files: { [FILE]: four } })));
  assert.ok(!t4.some((v) => v.startsWith("ใกล้หมด")), "the fourth account has no ring");
});

test("small: each arc takes its tier colour (gray, dark yellow or dark red) over a translucent track", async () => {
  const w = homeWidget(await render({ family: "small" }));
  const [claude, gpt, agy] = rings(w).map((r) => r.image);
  assert.equal(hexOf(claude.strokes[1].color), DRAWN.white, "33 left is gray");
  assert.equal(hexOf(gpt.strokes[1].color), DRAWN.yellow, "7 left is dark yellow");
  assert.equal(hexOf(agy.strokes[1].color), DRAWN.white, "100 left is a full gray ring");
  for (const img of [claude, gpt, agy]) {
    const track = img.strokes[0];
    assert.equal(hexOf(track.color), TRACK_HEX);
    assert.equal(track.color.alpha, 0.3);
    assert.equal(track.width, 3.5);
  }
});

test("small: a ring with nothing left has only its track, and 5 left is red", async () => {
  const empty = homeWidget(await render({ family: "small", files: { [FILE]: thresholdFixture([100]) } }));
  assert.equal(rings(empty)[0].image.strokes.length, 1, "0 left: only the track");
  const red = homeWidget(await render({ family: "small", files: { [FILE]: thresholdFixture([95]) } }));
  assert.equal(hexOf(rings(red)[0].image.strokes[1].color), DRAWN.red, "5 left is dark red");
});

test("small: the footer counts the yellow and red rings, and is red only when one of them is red", async () => {
  const yellowOnly = usageFile([
    account("claude", "Claude", [["5 ชม.", 85]]),
    account("codex", "ChatGPT", [["สัปดาห์", 10]]),
  ]);
  const y = homeWidget(await render({ family: "small", files: { [FILE]: yellowOnly } }));
  const yellowFooter = texts(y).find((x) => x.text === "ใกล้หมด 1 รายการ");
  assert.ok(yellowFooter, "one yellow ring is counted");
  assert.deepEqual(pairOf(yellowFooter.textColor), TEXT_PAIR.yellow, "the yellow footer is a light and dark pair");

  const both = usageFile([
    account("claude", "Claude", [["5 ชม.", 85]]),
    account("codex", "ChatGPT", [["สัปดาห์", 96]]),
  ]);
  const b = homeWidget(await render({ family: "small", files: { [FILE]: both } }));
  const redFooter = texts(b).find((x) => x.text === "ใกล้หมด 2 รายการ");
  assert.ok(redFooter, "a yellow and a red ring are both counted");
  assert.deepEqual(pairOf(redFooter.textColor), TEXT_PAIR.red, "the red footer is a light and dark pair");
});

test("small: the arc is a path of short segments that starts at 12 o'clock on the centre line", async () => {
  const D = 36; // LAYOUT.small.ringD
  const c = D / 2;
  const r = (D - 3.5) / 2;
  const full = homeWidget(await render({ family: "small", files: { [FILE]: thresholdFixture([0]) } }));
  const arc = rings(full)[0].image.strokes[1].path;
  const pts = arc.ops.map((o) => o.point);
  assert.ok(pts.length >= 60, `only ${pts.length} points`);
  assert.equal(arc.ops[0].op, "move");
  assert.ok(Math.abs(pts[0].x - c) < 1e-9 && Math.abs(pts[0].y - (c - r)) < 1e-9, "starts at 12 o'clock");
  for (const p of pts) {
    assert.ok(Math.abs(Math.hypot(p.x - c, p.y - c) - r) < 1e-9, "every point is on the centre line");
  }
});

test("small: the arc sweeps the share left, clockwise from 12 o'clock", async () => {
  const c = 18; // half of LAYOUT.small.ringD
  const w = homeWidget(await render({ family: "small" })); // Claude: 33 left
  const pts = rings(w)[0].image.strokes[1].path.ops.map((o) => o.point);
  const last = pts[pts.length - 1];
  const end = Math.atan2(last.y - c, last.x - c);
  assert.ok(Math.abs(end - (-Math.PI / 2 + 2 * Math.PI * 0.33)) < 1e-9, `arc ends at ${end}`);
});

test("small: 79.6 used shows 21 left in gray; 80 used shows 20 left in dark yellow", async () => {
  const gray = homeWidget(await render({ family: "small", files: { [FILE]: thresholdFixture([79.6]) } }));
  assert.equal(rings(gray)[0].number, "21");
  assert.equal(hexOf(rings(gray)[0].image.strokes[1].color), DRAWN.white);
  assert.equal(hexOf(ringNumberColor(gray, 0)), "dynamic", "an ordinary number follows light and dark mode");
  const yellow = homeWidget(await render({ family: "small", files: { [FILE]: thresholdFixture([80]) } }));
  assert.equal(rings(yellow)[0].number, "20");
  assert.equal(hexOf(rings(yellow)[0].image.strokes[1].color), DRAWN.yellow);
  assert.deepEqual(pairOf(ringNumberColor(yellow, 0)), TEXT_PAIR.yellow);
});

test("medium: one row per account with what is left, the used share under it, the reset in brackets, and no credit", async () => {
  const w = homeWidget(await render({ family: "medium" }));
  const t = textValues(w);
  assert.ok(t.includes("การใช้งาน AI"));
  assert.ok(t.includes("อัปเดต 8 นาทีก่อน"));
  for (const v of ["Claude", "ChatGPT", "agy"]) assert.ok(t.includes(v), `medium is missing "${v}"`);
  for (const v of ["สัปดาห์ (รีเซ็ตใน 5 วัน)", "สัปดาห์ (รีเซ็ตใน 22 ชม.)", "Claude (รีเซ็ตใน 5 ชม.)"]) {
    assert.ok(t.includes(v), `medium is missing "${v}"`);
  }
  assert.deepEqual(t.filter((v) => v.startsWith("เหลือ")), ["เหลือ 33%", "เหลือ 7%", "เหลือ 100%"]);
  assert.deepEqual(t.filter((v) => v.startsWith("ใช้ไป")), ["ใช้ไป 67%", "ใช้ไป 93%", "ใช้ไป 0%"]);
  assert.ok(!t.includes("Gemini Flash"), "medium shows one row per account");
  assert.ok(!t.some((v) => v.includes("เครดิต")), "medium has no credit text");
  assert.equal(hairlines(w).length, 3, "a rule under the header and one between each pair of rows");
  assertRefresh(w);
});

test("medium: brand icons are rounded squares with the letters C, G and A in the brand colours", async () => {
  const w = homeWidget(await render({ family: "medium" }));
  assert.deepEqual(icons(w), [
    { letter: "C", hex: "D97757" },
    { letter: "G", hex: "10A37F" },
    { letter: "A", hex: "4285F4" },
  ]);
});

test("gauges: the fill is what is left, gray, dark yellow or dark red by tier", async () => {
  const med = gauges(homeWidget(await render({ family: "medium" })));
  assert.equal(med.length, 3);
  assert.equal(med[0].fill, DRAWN.white, "33 left is gray");
  assert.ok(Math.abs(med[0].width - 19 * 0.33) < 1e-9, `33 left fill is ${med[0].width}`);
  assert.equal(med[1].fill, DRAWN.yellow, "7 left is dark yellow");
  assert.equal(med[1].width, 2, "a 2 pt sliver at least");
  assert.deepEqual(med[2], { fill: DRAWN.white, width: 19 }, "100 left fills the whole gauge");
});

test("gauges: the sliver is at least 2 pt; at 5 left or less the outline and nub turn red", async () => {
  const widths = {};
  for (const used of [32, 85, 95, 99.9]) {
    const w = homeWidget(await render({ family: "medium", files: { [FILE]: thresholdFixture([used]) } }));
    widths[used] = gauges(w)[0].width;
    const edge = used >= 95 ? DRAWN.red : "dynamic";
    assert.deepEqual(gaugeEdges(w), [{ outline: edge, nub: edge }], `${used} used: outline and nub`);
  }
  assert.ok(Math.abs(widths[32] - 19 * 0.68) < 1e-9, `32 used: ${widths[32]}`);
  assert.ok(Math.abs(widths[85] - 19 * 0.15) < 1e-9, `85 used: ${widths[85]}`);
  assert.equal(widths[95], 2, "5 left is 0.95 pt, so the 2 pt sliver applies");
  assert.equal(widths[99.9], 2, "0.1 left is still a visible sliver");
});

test("gauges: a limit above 100 counts as nothing left: an empty gauge with a red outline", async () => {
  const files = { [FILE]: usageFile([account("claude", "Claude", [["5 ชม.", 150]])]) };
  const w = homeWidget(await render({ family: "medium", files }));
  assert.deepEqual(gauges(w), [{ fill: null, width: 0 }]);
  assert.deepEqual(gaugeEdges(w), [{ outline: DRAWN.red, nub: DRAWN.red }]);
});

test("large: five limit rows in file order, with the sample's highest five kept", async () => {
  const w = homeWidget(await render({ family: "large" }));
  const t = textValues(w);
  for (const v of ["Claude · 5 ชม.", "Claude · สัปดาห์", "ChatGPT · สัปดาห์", "agy · Claude", "agy · Gemini Pro"]) {
    assert.ok(t.includes(v), `large is missing "${v}"`);
  }
  assert.ok(!t.includes("agy · Gemini Flash"), "of the three zeros, the tie keeps the first two in file order");
  assert.deepEqual(t.filter((v) => v.startsWith("ใช้ไป")), ["ใช้ไป 42%", "ใช้ไป 67%", "ใช้ไป 93%", "ใช้ไป 0%", "ใช้ไป 0%"]);
  assert.deepEqual(t.filter((v) => v.startsWith("เหลือ")), ["เหลือ 58%", "เหลือ 33%", "เหลือ 7%", "เหลือ 100%", "เหลือ 100%"]);
  assert.equal(hairlines(w).length, 6, "a rule under the header, four between the rows and one above the footer");
  assertRefresh(w);
});

test("large: at most five rows; the highest percentages win and the rows keep file order", async () => {
  const files = {
    [FILE]: usageFile([account("claude", "Claude", [["L0", 10], ["L1", 90], ["L2", 20], ["L3", 80], ["L4", 30], ["L5", 70]])]),
  };
  const t = textValues(homeWidget(await render({ family: "large", files })));
  assert.ok(!t.includes("Claude · L0"), "10% is the lowest and is dropped");
  assert.equal(t.filter((v) => v.startsWith("Claude · L")).length, 5);
  assert.deepEqual(t.filter((v) => v.startsWith("ใช้ไป")), ["ใช้ไป 90%", "ใช้ไป 20%", "ใช้ไป 80%", "ใช้ไป 30%", "ใช้ไป 70%"]);
  assert.deepEqual(t.filter((v) => v.startsWith("เหลือ")), ["เหลือ 10%", "เหลือ 80%", "เหลือ 20%", "เหลือ 70%", "เหลือ 30%"]);
});

test("large: the almost-out pill shows on rows at 20 left or less: yellow from 6 to 20, red at 5 or less", async () => {
  const w = homeWidget(await render({ family: "large", files: { [FILE]: thresholdFixture([79.6, 80, 99.9]) } }));
  const t = textValues(w);
  assert.equal(t.filter((v) => v === "ใกล้หมด").length, 2, "79.6 used (21 left) has no pill");
  assert.deepEqual(t.filter((v) => v.startsWith("ใช้ไป")), ["ใช้ไป 79%", "ใช้ไป 80%", "ใช้ไป 99%"]);
  assert.deepEqual(t.filter((v) => v.startsWith("เหลือ")), ["เหลือ 21%", "เหลือ 20%", "เหลือ 1%"]);
  assert.deepEqual(gauges(w).map((g) => g.fill), [DRAWN.white, DRAWN.yellow, DRAWN.red]);
  const pills = texts(w).filter((x) => x.text === "ใกล้หมด");
  assert.deepEqual(pills.map((x) => pairOf(x.textColor)), [TEXT_PAIR.yellow, TEXT_PAIR.red], "a yellow pill, then a red one");
  assert.deepEqual(pillBackgrounds(w).map((s) => pairOf(s.backgroundColor)), [TEXT_PAIR.yellow, TEXT_PAIR.red], "the pill tints match");
});

test("the figures at 32, 85 and 95 used read as left and used, in Thai and English", async () => {
  const cases = [[32, "68", "32"], [85, "15", "85"], [95, "5", "95"]];
  for (const [used, left, spent] of cases) {
    const files = { [FILE]: thresholdFixture([used]) };
    const th = textValues(homeWidget(await render({ family: "medium", files })));
    assert.ok(th.includes(`เหลือ ${left}%`), `${used} used in Thai: ${th.join(" | ")}`);
    assert.ok(th.includes(`ใช้ไป ${spent}%`), `${used} used in Thai: ${th.join(" | ")}`);
    const en = textValues(homeWidget(await render({ family: "medium", files, deviceLanguage: "en" })));
    assert.ok(en.includes(`${left}% left`), `${used} used in English: ${en.join(" | ")}`);
    assert.ok(en.includes(`${spent}% used`), `${used} used in English: ${en.join(" | ")}`);
  }
});

test("the tiers at 32, 85 and 95 used: gray (68 left), dark yellow (15 left) and dark red (5 left), in every widget and both languages", async () => {
  const cases = [
    { used: 32, left: "68", th: "เหลือ 68%", en: "68% left", fill: DRAWN.white, arc: DRAWN.white, text: "dynamic", edge: "dynamic", pill: null },
    { used: 85, left: "15", th: "เหลือ 15%", en: "15% left", fill: DRAWN.yellow, arc: DRAWN.yellow, text: TEXT_PAIR.yellow, edge: "dynamic", pill: TEXT_PAIR.yellow },
    { used: 95, left: "5", th: "เหลือ 5%", en: "5% left", fill: DRAWN.red, arc: DRAWN.red, text: TEXT_PAIR.red, edge: DRAWN.red, pill: TEXT_PAIR.red },
  ];
  for (const c of cases) {
    const files = { [FILE]: thresholdFixture([c.used]) };
    for (const deviceLanguage of ["th", "en"]) {
      const label = deviceLanguage === "th" ? c.th : c.en;
      const small = homeWidget(await render({ family: "small", files, deviceLanguage }));
      assert.equal(rings(small)[0].number, c.left, `${c.used} used, ${deviceLanguage}: ring number`);
      assertColour(rings(small)[0].image.strokes[1].color, c.arc, `${c.used} used: ring arc`);
      assertColour(ringNumberColor(small, 0), c.text, `${c.used} used: ring number colour`);

      const medium = homeWidget(await render({ family: "medium", files, deviceLanguage }));
      const figure = texts(medium).find((x) => x.text === label);
      assert.ok(figure, `${c.used} used, ${deviceLanguage}: "${label}" is missing`);
      assertColour(figure.textColor, c.text, `${c.used} used: figure colour`);
      assert.equal(gauges(medium)[0].fill, c.fill, `${c.used} used: gauge fill`);
      assert.deepEqual(gaugeEdges(medium), [{ outline: c.edge, nub: c.edge }], `${c.used} used: outline and nub`);

      const large = homeWidget(await render({ family: "large", files, deviceLanguage }));
      const pillText = deviceLanguage === "th" ? "ใกล้หมด" : "Almost out";
      const pill = texts(large).find((x) => x.text === pillText);
      assert.equal(Boolean(pill), c.pill !== null, `${c.used} used, ${deviceLanguage}: pill`);
      if (pill) assertColour(pill.textColor, c.pill, `${c.used} used: pill text colour`);
      assert.deepEqual(
        pillBackgrounds(large).map((s) => pairOf(s.backgroundColor)),
        c.pill ? [c.pill] : [],
        `${c.used} used: pill tint`,
      );
    }
  }
});

test("used rounds down and left rounds up, so the two always add up to 100", async () => {
  const api = (await runScript({ files: {} })).api;
  for (let t = 0; t <= 1000; t++) {
    const used = t / 10;
    assert.equal(api.shownPct(used) + api.shownLeft(used), 100, `used ${used}`);
  }
  const cases = [
    [79.6, 21, 79, "white"],
    [79.99, 21, 79, "white"],
    [80, 20, 80, "yellow"],
    [94.6, 6, 94, "yellow"],
    [94.9, 6, 94, "yellow"],
    [95, 5, 95, "red"],
    [99.99, 1, 99, "red"],
    [100, 0, 100, "red"],
    [0, 100, 0, "white"],
    [150, 0, 100, "red"],
    [-5, 100, 0, "white"],
  ];
  for (const [used, left, spent, tier] of cases) {
    assert.equal(api.shownLeft(used), left, `left of ${used}`);
    assert.equal(api.shownPct(used), spent, `used of ${used}`);
    assert.equal(api.tierOf(used), tier, `tier of ${used}`);
  }
  assert.equal(api.shownLeft(null), null);
  assert.equal(api.tierOf(null), null);
});

test("large: the header, the real-time label, the update footer and the fresh dot", async () => {
  const w = homeWidget(await render({ family: "large" }));
  const t = textValues(w);
  for (const v of ["ขีดจำกัดการใช้งาน AI", "สถานะเรียลไทม์", "อัปเดต 8 นาทีก่อน"]) {
    assert.ok(t.includes(v), `large is missing "${v}"`);
  }
  assert.ok(!t.some((v) => v.includes("วันนี้") || v.includes("Extra usage")), "no token or extra-usage line");
  const dots = sized(w, 5, 5);
  assert.equal(dots.length, 1, "a green dot when every account is ok");
  assert.equal(hexOf(dots[0].backgroundColor), "30D158");
});

test("large: the credit balance follows the reset on its row; the other rows show only the reset", async () => {
  const t = textValues(homeWidget(await render({ family: "large" })));
  assert.ok(t.includes("รีเซ็ตใน 22 ชม. · เครดิต 0"), "ChatGPT's row shows its balance");
  assert.ok(t.includes("รีเซ็ตใน 2 ชม."), "Claude's five-hour row shows only its reset");
  assert.equal(t.filter((v) => v.includes("เครดิต")).length, 1, "only the ChatGPT account has a balance");
});

test("error and stale accounts show their Thai error text: medium on the row, large on the first row", async () => {
  const medium = textValues(homeWidget(await render({ family: "medium", files: { [FILE]: ERROR_FIXTURE } })));
  assert.ok(medium.includes("ล็อกอิน agy หมดอายุ"));
  assert.ok(medium.includes("ล็อกอิน Codex หมดอายุ เปิด codex สักครั้ง"), "a stale account shows its error too");
  assert.ok(medium.includes("อัปเดต 1 นาทีก่อน"), "generated_at is the run time, so the update reads 1 minute");

  const large = textValues(homeWidget(await render({ family: "large", files: { [FILE]: ERROR_FIXTURE } })));
  assert.ok(large.includes("ล็อกอิน agy หมดอายุ"));
  assert.ok(large.includes("ล็อกอิน Codex หมดอายุ เปิด codex สักครั้ง"));
  assert.ok(large.includes("agy"), "an account with no limits keeps its own row");
  assert.ok(large.includes("ChatGPT · สัปดาห์"), "the stale account keeps its limit row");
  assert.ok(!large.includes(NO_LIMIT), "an error replaces the no-limit text");
});

test("large: an error account's green dot is left out", async () => {
  const w = homeWidget(await render({ family: "large", files: { [FILE]: ERROR_FIXTURE } }));
  assert.equal(sized(w, 5, 5).length, 0, "the dot shows only when every account is ok");
});

test("credits follow the reset time with no $ sign: whole numbers without decimals, others up to two", async () => {
  const cases = [[0, "เครดิต 0"], [12, "เครดิต 12"], [12.5, "เครดิต 12.5"], [3.456, "เครดิต 3.46"]];
  for (const [balance, expected] of cases) {
    const files = {
      [FILE]: usageFile([
        account("codex", "ChatGPT", [["สัปดาห์", 10, "2026-11-19T06:38:00Z"]], {
          credits: { extra_usage_enabled: false, used_usd: null, limit_usd: null, balance_usd: balance },
        }),
      ]),
    };
    const t = textValues(homeWidget(await render({ family: "large", files })));
    assert.ok(t.includes("รีเซ็ตใน 2 ชม. · " + expected), `balance ${balance}: ${t.join(" | ")}`);
  }
});

test("credits never appear in small or medium", async () => {
  for (const family of ["small", "medium"]) {
    const t = textValues(homeWidget(await render({ family })));
    assert.ok(!t.some((v) => v.includes("เครดิต")), `${family} has no credit text`);
  }
});

test("a missing data file shows the no-data message in small, medium and large", async () => {
  for (const family of FAMILIES) {
    const s = await render({ family, files: {} });
    assert.ok(textValues(homeWidget(s)).includes(NO_DATA), `${family}: no-data message missing`);
    assert.deepEqual(s.downloads, [FILE], `${family}: download should be attempted first`);
  }
});

test("broken JSON is treated as no data in small, medium and large", async () => {
  for (const family of FAMILIES) {
    const s = await render({ family, files: { [FILE]: "{ not json" } });
    assert.ok(textValues(homeWidget(s)).includes(NO_DATA), `${family}: no-data message missing`);
  }
});

test("a rejected iCloud download still reads an existing local copy", async () => {
  const s = await render({ family: "medium", downloadFails: true });
  assert.ok(textValues(homeWidget(s)).includes("Claude"));
});

test("a rejected iCloud download with no local copy shows the no-data message", async () => {
  const s = await render({ family: "large", downloadFails: true, files: {} });
  assert.ok(textValues(homeWidget(s)).includes(NO_DATA));
});

test("a rendering error shows the failure message and logs the error once", async () => {
  const s = await runScript({ family: "medium", failStacks: true });
  assert.ok(textValues(homeWidget(s)).includes(FAILED));
  assert.deepEqual(s.errors, ["Error: boom"]);
  assert.equal(s.completes, 1);
});

test("the widget background is a light and dark pair, and the message widgets use it too", async () => {
  for (const family of FAMILIES) {
    const bg = homeWidget(await render({ family })).backgroundColor;
    assert.equal(bg.dynamic, true, `${family}: background is not dynamic`);
    assert.equal(bg.light.hex, "E9E9EF", `${family}: light colour`);
    assert.equal(bg.dark.hex, "0A0A0C", `${family}: dark colour`);
  }
  const message = homeWidget(await render({ family: "small", files: {} })).backgroundColor;
  assert.equal(message.dynamic, true, "the no-data widget uses the same panel");
});

test("text colours follow light and dark mode, and every dynamic colour has both halves", async () => {
  const w = homeWidget(await render({ family: "large" }));
  const dynamicTexts = texts(w).filter((t) => hexOf(t.textColor) === "dynamic");
  assert.ok(dynamicTexts.length > 0, "some text must use a dynamic colour");
  assert.ok(dynamicTexts.every((t) => t.textColor.light instanceof Color && t.textColor.dark instanceof Color));
});

test("unknown fields and missing optional fields are ignored", async () => {
  const files = {
    [FILE]: JSON.stringify({
      schema: 1,
      future: "x",
      accounts: [{ id: "x", provider: "claude", label: "Claude", status: "ok", extra: { nested: true } }],
    }),
  };
  for (const family of FAMILIES) {
    const w = homeWidget(await render({ family, files }));
    const t = textValues(w);
    assert.ok(t.includes("Claude"), `${family}: account name missing`);
    if (family === "small") assert.deepEqual(rings(w).map((r) => r.number), ["—"]);
    else assert.ok(t.includes(NO_LIMIT), `${family}: no-limit note missing`);
  }
});

test("non-numeric percentages render as a dash, and values above 100 count as nothing left", async () => {
  const files = { [FILE]: usageFile([account("claude", "Claude", [["5 ชม.", "abc"], ["สัปดาห์", 150]])]) };
  const med = homeWidget(await render({ family: "medium", files }));
  assert.ok(textValues(med).includes("ใช้ไป 100%"), "a used value above 100 is clamped to 100");
  assert.ok(textValues(med).includes("เหลือ 0%"), "so nothing is left");
  assert.deepEqual(gauges(med), [{ fill: null, width: 0 }]);
  const large = homeWidget(await render({ family: "large", files }));
  const figures = textValues(large).filter((v) => v.startsWith("เหลือ") || v.startsWith("ใช้ไป") || v === "—");
  assert.deepEqual(figures, ["—", "เหลือ 0%", "ใช้ไป 100%"], "the row with no number shows a dash and no used line");
  assert.deepEqual(gauges(large).map((g) => g.fill), [null, null]);
});

test("time texts: the update age from the file, the reset countdown, and the no-generated_at fallback", async () => {
  const files = {
    [FILE]: JSON.stringify({
      schema: 1,
      accounts: [{
        id: "claude-main", provider: "claude", label: "Claude", plan: "Max", status: "ok", error: null,
        updated_at: "2026-11-19T04:35:00Z",
        limits: [{ key: "five_hour", label: "5 ชม.", used_percent: 10, resets_at: "2026-11-19T05:23:00Z" }],
        usage: null,
        credits: null,
      }],
    }),
  };
  const t = textValues(homeWidget(await render({ family: "large", files })));
  assert.ok(t.includes("อัปเดต 3 นาทีก่อน"), "no generated_at: the newest account update is used");
  assert.ok(t.includes("รีเซ็ตใน 45 นาที"));
});

test("each limit row shows its own reset, and a reset that has passed shows none", async () => {
  const files = {
    [FILE]: usageFile([
      account("claude", "Claude", [
        ["5 ชม.", 10, "2026-11-19T04:00:00Z"],
        ["สัปดาห์", 20, "2026-11-19T06:38:00Z"],
      ]),
    ]),
  };
  const t = textValues(homeWidget(await render({ family: "large", files })));
  assert.ok(t.includes("รีเซ็ตใน 2 ชม."), "the later, still-future reset is shown on its own row");
  assert.equal(t.filter((v) => v.startsWith("รีเซ็ต")).length, 1, "the passed reset shows no text");
});

test("worst-case fixture renders in every family without errors", async () => {
  for (const family of FAMILIES) {
    const s = await render({ family, files: { [FILE]: WORST_TEXT } });
    const title = family === "large" ? "ขีดจำกัดการใช้งาน AI" : "การใช้งาน AI";
    assert.ok(textValues(homeWidget(s)).includes(title), `${family}: title missing`);
  }
});

test("worst case: the large widget keeps five rows, and the stale agy row keeps its error text", async () => {
  const w = homeWidget(await render({ family: "large", files: { [FILE]: WORST_TEXT } }));
  const t = textValues(w);
  assert.ok(t.includes("ล็อกอิน agy หมดอายุ"));
  assert.deepEqual(t.filter((v) => v.startsWith("ใช้ไป")), ["ใช้ไป 42%", "ใช้ไป 67%", "ใช้ไป 93%", "ใช้ไป 40%", "ใช้ไป 0%"]);
});

test("sample and worst-case layouts fit the smallest frames (estimated, shrinkable text at its smallest)", async () => {
  for (const [name, data] of [["sample", SAMPLE_TEXT], ["worst", WORST_TEXT]]) {
    for (const family of FAMILIES) {
      const w = homeWidget(await render({ family, files: { [FILE]: data } }));
      assertFits(w, MIN_FRAME[family], `${name}/${family}`, { shrink: true });
    }
  }
});

test("worst-case layouts fit the largest frames (estimated, text at full size)", async () => {
  for (const family of FAMILIES) {
    const w = homeWidget(await render({ family, files: { [FILE]: WORST_TEXT } }));
    assertFits(w, MAX_FRAME[family], `worst/${family}`, { shrink: false });
  }
});

test("the English layouts fit the smallest frames (weak evidence: the factor is estimated, not measured)", async () => {
  for (const family of FAMILIES) {
    const v2 = homeWidget(await render({ family, files: { [FILE]: V2_TEXT }, deviceLanguage: "en" }));
    assertFits(v2, MIN_FRAME[family], `v2-en/${family}`, { shrink: true });
    const worst = homeWidget(await render({ family, files: { [FILE]: WORST_TEXT }, deviceLanguage: "en" }));
    assertFits(worst, MIN_FRAME[family], `worst-en/${family}`, { shrink: true });
  }
});

test("the English layouts fit the largest frames (weak evidence, text at full size)", async () => {
  for (const family of FAMILIES) {
    const w = homeWidget(await render({ family, files: { [FILE]: WORST_TEXT }, deviceLanguage: "en" }));
    assertFits(w, MAX_FRAME[family], `worst-en/${family}`, { shrink: false });
  }
});

test("home-screen run sets the widget and previews nothing", async () => {
  const s = await render({ family: "medium", runsInWidget: true });
  homeWidget(s);
  assert.equal(s.made[0].presented, null);
});

test("app run presents a medium preview and sets no home-screen widget", async () => {
  const s = await render({ runsInWidget: false });
  assert.equal(s.setWidgets.length, 0);
  assert.equal(s.made.length, 1);
  assert.equal(s.made[0].presented, "medium");
  assert.ok(textValues(s.made[0]).includes("การใช้งาน AI"));
});

test("an unknown widget family falls back to the medium layout", async () => {
  const t = textValues(homeWidget(await render({ family: "extraLarge" })));
  assert.ok(t.includes("การใช้งาน AI"));
  assert.ok(!t.includes("ขีดจำกัดการใช้งาน AI"));
});

// Language ------------------------------------------------------------------------------------

test("a device language that starts with th gives Thai, whatever follows it", async () => {
  for (const device of ["th", "th-TH", "th_TH", "TH"]) {
    const s = await runScript({ deviceLanguage: device, files: {} });
    assert.equal(s.api.languageOf(), "th", `device "${device}"`);
  }
});

test("any other device language gives English", async () => {
  for (const device of ["en", "en-US", "ja-JP", "fr", "zh-Hans", "ko"]) {
    const s = await runScript({ deviceLanguage: device, files: {} });
    assert.equal(s.api.languageOf(), "en", `device "${device}"`);
  }
});

test("a device language that is empty, not text or unreadable gives English", async () => {
  for (const device of ["", null, undefined, 42]) {
    const s = await runScript({ deviceLanguage: device, files: {} });
    assert.equal(s.api.languageOf(), "en", `device ${String(device)}`);
  }
  const unreadable = await runScript({ deviceLanguageThrows: true, files: {} });
  assert.equal(unreadable.api.languageOf(), "en", "a throwing Device.language() means English");
});

test("the Parameter field decides when it is th or en, in any case and with spaces around it", async () => {
  const cases = [
    [" th ", "en-US", "th"],
    ["EN", "th-TH", "en"],
    ["Th", "en", "th"],
    ["en ", "th", "en"],
  ];
  for (const [parameter, device, lang] of cases) {
    const s = await runScript({ parameter, deviceLanguage: device, files: {} });
    assert.equal(s.api.languageOf(), lang, `parameter "${parameter}" on device "${device}"`);
  }
});

test("any other Parameter is ignored, and so is a Parameter that is not text", async () => {
  const cases = [
    ["ja", "th", "th"],
    ["ja", "en-US", "en"],
    ["thai", "en", "en"], // only the exact words th and en count
    ["", "th", "th"],
    ["", "en", "en"],
    [5, "th", "th"],
    [null, "en", "en"],
  ];
  for (const [parameter, device, lang] of cases) {
    const s = await runScript({ parameter, deviceLanguage: device, files: {} });
    assert.equal(s.api.languageOf(), lang, `parameter ${JSON.stringify(parameter)} on device "${device}"`);
  }
});

test("the Parameter changes what is shown, not only the language value", async () => {
  const forcedEn = textValues(homeWidget(await render({ family: "medium", parameter: "en", deviceLanguage: "th-TH" })));
  assert.ok(forcedEn.includes("AI Usage"));
  assert.ok(!forcedEn.includes("การใช้งาน AI"));
  const forcedTh = textValues(homeWidget(await render({ family: "medium", parameter: "th", deviceLanguage: "en-US" })));
  assert.ok(forcedTh.includes("การใช้งาน AI"));
  assert.ok(!forcedTh.includes("AI Usage"));
});

test("the no-data and failure messages follow the language, even when the device language cannot be read", async () => {
  for (const family of FAMILIES) {
    const en = textValues(homeWidget(await render({ family, files: {}, deviceLanguage: "en" })));
    assert.ok(en.includes(NO_DATA_EN), `${family}: English no-data message`);
    const unreadable = textValues(homeWidget(await render({ family, files: {}, deviceLanguageThrows: true })));
    assert.ok(unreadable.includes(NO_DATA_EN), `${family}: English when the language cannot be read`);
  }
  const failed = await runScript({ family: "medium", failStacks: true, deviceLanguage: "en" });
  assert.ok(textValues(homeWidget(failed)).includes(FAILED_EN));
  assert.deepEqual(failed.errors, ["Error: boom"]);
  const thaiFailed = await runScript({ family: "medium", failStacks: true });
  assert.ok(textValues(homeWidget(thaiFailed)).includes(FAILED));
});

test("English widgets: headers, footers, the almost-out count, and the reset and update texts", async () => {
  const v2 = { [FILE]: V2_TEXT };
  const small = textValues(homeWidget(await render({ family: "small", files: v2, deviceLanguage: "en" })));
  for (const v of ["AI Usage", "8 min ago", "Claude", "ChatGPT", "agy", "System status", "1 almost out"]) {
    assert.ok(small.includes(v), `small is missing "${v}"`);
  }
  const medium = textValues(homeWidget(await render({ family: "medium", files: v2, deviceLanguage: "en" })));
  for (const v of ["AI Usage", "Updated 8 min ago", "Claude", "ChatGPT", "agy", "Week (Resets in 5 d)", "Week (Resets in 22 h)", "Claude (Resets in 5 h)"]) {
    assert.ok(medium.includes(v), `medium is missing "${v}"`);
  }
  assert.deepEqual(medium.filter((v) => v.endsWith("% left")), ["33% left", "7% left", "100% left"]);
  assert.deepEqual(medium.filter((v) => v.endsWith("% used")), ["67% used", "93% used", "0% used"]);
  const large = textValues(homeWidget(await render({ family: "large", files: v2, deviceLanguage: "en" })));
  for (const v of [
    "AI Usage Limits", "Live status", "Updated 8 min ago", "Claude · 5h", "Claude · Week", "ChatGPT · Week",
    "agy · Claude", "agy · Gemini Pro", "Resets in 2 h", "Resets in 5 d", "Resets in 22 h · Credits 0", "Resets in 5 h",
  ]) {
    assert.ok(large.includes(v), `large is missing "${v}"`);
  }
  assert.equal(large.filter((v) => v === "Almost out").length, 1, "one row is almost out");
  assert.deepEqual(large.filter((v) => v.endsWith("% left")), ["58% left", "33% left", "7% left", "100% left", "100% left"]);
  assert.deepEqual(large.filter((v) => v.endsWith("% used")), ["42% used", "67% used", "93% used", "0% used", "0% used"]);
});

test("English mode shows no Thai letters for data with the window_seconds field", async () => {
  for (const family of FAMILIES) {
    const t = textValues(homeWidget(await render({ family, files: { [FILE]: V2_TEXT }, deviceLanguage: "en" })));
    assert.deepEqual(t.filter((v) => THAI_LETTER.test(v)), [], `${family}: Thai text in English mode`);
  }
});

test("English update age: min, h and d, rounded as in Thai", async () => {
  const api = (await runScript({ files: {} })).api;
  const MIN = 60 * 1000;
  const HOUR = 60 * MIN;
  const cases = [
    [0, "Updated 1 min ago"],
    [12 * MIN + 30 * 1000, "Updated 13 min ago"],
    [Math.round(59.5 * MIN), "Updated 1 h ago"],
    [Math.round(3.5 * HOUR), "Updated 4 h ago"],
    [Math.round(23.5 * HOUR), "Updated 1 d ago"],
    [36 * HOUR, "Updated 2 d ago"],
  ];
  for (const [age, expected] of cases) {
    assert.equal(api.ageText(NOW_MS - age, NOW_MS, "en"), expected, `age ${age} ms`);
  }
});

test("English reset text: min, h and d", async () => {
  const api = (await runScript({ files: {} })).api;
  const MIN = 60 * 1000;
  const HOUR = 60 * MIN;
  const cases = [
    [45 * MIN, "Resets in 45 min"],
    [90 * MIN, "Resets in 2 h"],
    [36 * HOUR, "Resets in 2 d"],
  ];
  for (const [offset, expected] of cases) {
    assert.equal(api.resetText(NOW_MS + offset, NOW_MS, "en"), expected, `offset ${offset} ms`);
  }
});

test("the English update and reset units never read 60 min, 24 h or 0 for any span", async () => {
  const api = (await runScript({ files: {} })).api;
  const UNIT_TEXT = /(\d+) (min|h|d)\b/;
  const check = (text, label) => {
    const m = UNIT_TEXT.exec(text);
    assert.ok(m, `${label}: no number and unit in "${text}"`);
    const n = Number(m[1]);
    assert.ok(n >= 1, `${label}: "${text}" reads below 1`);
    if (m[2] === "min") assert.ok(n < 60, `${label}: "${text}" reads 60 minutes or more`);
    if (m[2] === "h") assert.ok(n < 24, `${label}: "${text}" reads 24 hours or more`);
  };
  for (let seconds = 0; seconds <= 2_000_000; seconds += 37) {
    const ms = seconds * 1000;
    check(api.resetText(NOW_MS + ms, NOW_MS, "en"), `reset after ${seconds} s`);
    check(api.ageText(NOW_MS - ms, NOW_MS, "en"), `updated ${seconds} s ago`);
  }
});

// Limit names from window_seconds ------------------------------------------------------------

test("window_seconds builds the limit name: 18000 is 5 ชม. or 5h, 604800 is สัปดาห์ or Week", async () => {
  const th = textValues(homeWidget(await render({ family: "large", files: { [FILE]: V2_TEXT } })));
  assert.ok(th.includes("Claude · 5 ชม.") && th.includes("Claude · สัปดาห์"));
  const en = textValues(homeWidget(await render({ family: "large", files: { [FILE]: V2_TEXT }, deviceLanguage: "en" })));
  assert.ok(en.includes("Claude · 5h") && en.includes("Claude · Week"));
});

test("the built name replaces the file's own label when a window is given", async () => {
  const th = textValues(homeWidget(await render({ family: "large", files: { [FILE]: RELABELLED_TEXT } })));
  assert.ok(th.includes("Claude · 5 ชม."));
  assert.ok(!th.includes("Claude · ห้าชั่วโมง"));
});

test("the Opus and Sonnet keys add (Opus) and (Sonnet) in both languages", async () => {
  const th = textValues(homeWidget(await render({ family: "large", files: { [FILE]: OPUS_SONNET_TEXT } })));
  assert.ok(th.includes("Claude · สัปดาห์ (Opus)") && th.includes("Claude · สัปดาห์ (Sonnet)"));
  const en = textValues(homeWidget(await render({ family: "large", files: { [FILE]: OPUS_SONNET_TEXT }, deviceLanguage: "en" })));
  assert.ok(en.includes("Claude · Week (Opus)") && en.includes("Claude · Week (Sonnet)"));
});

test("other window lengths: whole days, then whole hours, then minutes, in both languages", async () => {
  const cases = [
    [86400, "1 วัน", "1d"],
    [172800, "2 วัน", "2d"],
    [1209600, "14 วัน", "14d"],
    [3600, "1 ชม.", "1h"],
    [1800, "30 นาที", "30min"],
    [5400, "90 นาที", "90min"],
  ];
  for (const [seconds, th, en] of cases) {
    const t = textValues(homeWidget(await render({ family: "large", files: { [FILE]: windowFile(seconds) } })));
    assert.ok(t.includes("Claude · " + th), `${seconds} s in Thai: ${t.join(" | ")}`);
    const e = textValues(homeWidget(await render({ family: "large", files: { [FILE]: windowFile(seconds) }, deviceLanguage: "en" })));
    assert.ok(e.includes("Claude · " + en), `${seconds} s in English: ${e.join(" | ")}`);
  }
});

test("a null window_seconds uses the file's label, which reads the same in both languages", async () => {
  for (const device of ["th", "en"]) {
    const t = textValues(homeWidget(await render({ family: "large", files: { [FILE]: V2_TEXT }, deviceLanguage: device })));
    assert.ok(t.includes("agy · Gemini Pro"), `${device}: model group label`);
  }
});

test("a missing, zero, negative, fractional or text window_seconds falls back to the file's label", async () => {
  for (const windowValue of [undefined, null, 0, -5, 1.5, "abc"]) {
    const en = textValues(homeWidget(await render({ family: "large", files: { [FILE]: windowFile(windowValue) }, deviceLanguage: "en" })));
    assert.ok(en.includes("Claude · 5 ชม."), `window ${String(windowValue)}: ${en.join(" | ")}`);
  }
});

// Error texts from error_code -----------------------------------------------------------------

test("each error_code shows its own text in Thai and in English, and the Thai error does not show", async () => {
  for (const [code, th, en] of ERROR_CODE_TEXTS) {
    const t = textValues(homeWidget(await render({ family: "medium", files: { [FILE]: errorCodeFile(code) } })));
    assert.ok(t.includes(th), `${code} in Thai: ${t.join(" | ")}`);
    assert.ok(!t.includes("ข้อความเดิม"), `${code}: the Thai error must not show`);
    const e = textValues(homeWidget(await render({ family: "medium", files: { [FILE]: errorCodeFile(code) }, deviceLanguage: "en" })));
    assert.ok(e.includes(en), `${code} in English: ${e.join(" | ")}`);
  }
});

test("an error_code also gives the large widget's error row its text in both languages", async () => {
  const th = textValues(homeWidget(await render({ family: "large", files: { [FILE]: errorCodeFile("login_expired") } })));
  assert.ok(th.includes("ล็อกอินหมดอายุ"));
  const en = textValues(homeWidget(await render({ family: "large", files: { [FILE]: errorCodeFile("login_expired") }, deviceLanguage: "en" })));
  assert.ok(en.includes("Sign-in expired"));
});

test("an unrecognised error_code falls back to the Thai error text in both languages", async () => {
  const th = textValues(homeWidget(await render({ family: "medium", files: { [FILE]: errorCodeFile("quota_full") } })));
  assert.ok(th.includes("ข้อความเดิม"));
  const en = textValues(homeWidget(await render({ family: "medium", files: { [FILE]: errorCodeFile("quota_full") }, deviceLanguage: "en" })));
  assert.ok(en.includes("ข้อความเดิม"), "the Thai error stands in");
});

test("a missing error_code falls back to the Thai error text in both languages", async () => {
  const th = textValues(homeWidget(await render({ family: "medium", files: { [FILE]: errorCodeFile(undefined) } })));
  assert.ok(th.includes("ข้อความเดิม"));
  const en = textValues(homeWidget(await render({ family: "medium", files: { [FILE]: errorCodeFile(undefined) }, deviceLanguage: "en" })));
  assert.ok(en.includes("ข้อความเดิม"));
});

test("a recognised error_code wins over the Thai error text", async () => {
  const th = textValues(homeWidget(await render({ family: "medium", files: { [FILE]: errorCodeFile("network") } })));
  assert.ok(th.includes("เชื่อมต่อเครือข่ายไม่ได้"));
  assert.ok(!th.includes("ข้อความเดิม"));
  const en = textValues(homeWidget(await render({ family: "medium", files: { [FILE]: errorCodeFile("network") }, deviceLanguage: "en" })));
  assert.ok(en.includes("No network connection"));
  assert.ok(!en.includes("ข้อความเดิม"));
});

// The old file: the collector has not written the new fields yet ------------------------------

test("an old file with no new fields shows its Thai labels and errors, and English reset texts", async () => {
  const t = textValues(homeWidget(await render({ family: "large", deviceLanguage: "en" })));
  assert.ok(t.includes("Claude · 5 ชม."), "the file's Thai label stands in for the missing window");
  assert.ok(t.includes("Claude · สัปดาห์"));
  assert.ok(t.includes("Resets in 2 h"), "the reset text is still English");
  assert.ok(t.includes("Updated 8 min ago"));
  const errors = textValues(homeWidget(await render({ family: "large", files: { [FILE]: ERROR_FIXTURE }, deviceLanguage: "en" })));
  assert.ok(errors.includes("ล็อกอิน agy หมดอายุ"), "the Thai error stands in for the missing error_code");
});

// Layout helpers, time texts and the reset table (Thai) ----------------------------------------

// Direct checks of the time helpers that the script body returns (a no-data run is enough for them).
async function timeHelpers() {
  return (await runScript({ files: {} })).api;
}

// The reset line of a large widget with one limit, for a reset `offsetMs` after the run.
async function resetLineFor(offsetMs) {
  const resetsAt = new Date(NOW_MS + offsetMs).toISOString();
  const files = { [FILE]: usageFile([account("claude", "Claude", [["5 ชม.", 10, resetsAt]])]) };
  const t = textValues(homeWidget(await render({ family: "large", files })));
  return t.find((v) => v.startsWith("รีเซ็ต")) ?? null;
}

test("reset text picks the unit from the rounded value and never shows 60 นาที or 24 ชม.", async () => {
  const MIN = 60 * 1000;
  const HOUR = 60 * MIN;
  // As on the Mac widget: each unit is rounded from the raw span, and the unit is picked from the rounded minutes and hours.
  const cases = [
    [-MIN, null], // reset already passed: no reset part at all
    [30 * 1000, "รีเซ็ตใน 1 นาที"],
    [45 * MIN, "รีเซ็ตใน 45 นาที"],
    [59 * MIN, "รีเซ็ตใน 59 นาที"],
    [Math.round(59.4 * MIN), "รีเซ็ตใน 59 นาที"],
    [Math.round(59.5 * MIN), "รีเซ็ตใน 1 ชม."],
    [Math.round(59.6 * MIN), "รีเซ็ตใน 1 ชม."],
    [60 * MIN, "รีเซ็ตใน 1 ชม."],
    [Math.round(89.5 * MIN), "รีเซ็ตใน 1 ชม."],
    [90 * MIN, "รีเซ็ตใน 2 ชม."],
    [23 * HOUR, "รีเซ็ตใน 23 ชม."],
    [Math.round(23.4 * HOUR), "รีเซ็ตใน 23 ชม."],
    [Math.round(23.5 * HOUR), "รีเซ็ตใน 1 วัน"],
    [Math.round(23.6 * HOUR), "รีเซ็ตใน 1 วัน"],
    [24 * HOUR, "รีเซ็ตใน 1 วัน"],
    [Math.round(35.5 * HOUR), "รีเซ็ตใน 1 วัน"],
    [36 * HOUR, "รีเซ็ตใน 2 วัน"],
    [5 * 24 * HOUR, "รีเซ็ตใน 5 วัน"],
  ];
  for (const [offset, expected] of cases) {
    assert.equal(await resetLineFor(offset), expected, `offset ${offset} ms`);
  }
});

test("updated text rounds to the nearest unit, picks the unit after rounding, and reads 1 นาที when just updated", async () => {
  const api = await timeHelpers();
  const MIN = 60 * 1000;
  const HOUR = 60 * MIN;
  const cases = [
    [0, "อัปเดต 1 นาทีก่อน"],
    [-5 * MIN, "อัปเดต 1 นาทีก่อน"], // an update time ahead of the clock counts as zero
    [12 * MIN + 30 * 1000, "อัปเดต 13 นาทีก่อน"], // 12.5 minutes rounds up, as on the Mac widget
    [59 * MIN, "อัปเดต 59 นาทีก่อน"],
    [Math.round(59.5 * MIN), "อัปเดต 1 ชม.ก่อน"],
    [60 * MIN, "อัปเดต 1 ชม.ก่อน"],
    [Math.round(3.5 * HOUR), "อัปเดต 4 ชม.ก่อน"],
    [23 * HOUR, "อัปเดต 23 ชม.ก่อน"],
    [Math.round(23.5 * HOUR), "อัปเดต 1 วันก่อน"],
    [36 * HOUR, "อัปเดต 2 วันก่อน"],
  ];
  for (const [age, expected] of cases) {
    assert.equal(api.ageText(NOW_MS - age, NOW_MS, "th"), expected, `age ${age} ms`);
  }
});

test("minute, hour and day texts never read 60 นาที, 24 ชม. or 0 for any span", async () => {
  const api = await timeHelpers();
  const UNIT_TEXT = /(\d+) (นาที|ชม\.|วัน)/;
  const check = (text, label) => {
    const m = UNIT_TEXT.exec(text);
    assert.ok(m, `${label}: no number and unit in "${text}"`);
    const n = Number(m[1]);
    assert.ok(n >= 1, `${label}: "${text}" reads below 1`);
    if (m[2] === "นาที") assert.ok(n < 60, `${label}: "${text}" reads 60 minutes or more`);
    if (m[2] === "ชม.") assert.ok(n < 24, `${label}: "${text}" reads 24 hours or more`);
  };
  for (let seconds = 0; seconds <= 2_000_000; seconds += 37) {
    const ms = seconds * 1000;
    check(api.resetText(NOW_MS + ms, NOW_MS, "th"), `reset after ${seconds} s`);
    check(api.ageText(NOW_MS - ms, NOW_MS, "th"), `updated ${seconds} s ago`);
  }
});

// Several accounts ----------------------------------------------------------------------------------

// The same account with its label replaced. undefined removes the field, so a missing label can be tested.
function relabel(acc, label) {
  const out = { ...acc, label };
  if (label === undefined) delete out.label;
  return out;
}

// Eight accounts in file order, with rising use. The first three are Claude, Claude 2 and Claude 3.
const EIGHT_TEXT = usageFile([
  account("claude", "Claude", [["5 ชม.", 10]], { id: "claude-main" }),
  account("claude", "Claude 2", [["5 ชม.", 20]], { id: "claude-2" }),
  account("claude", "Claude 3", [["5 ชม.", 30]], { id: "claude-3" }),
  account("codex", "ChatGPT", [["สัปดาห์", 40]], { id: "codex-main" }),
  account("codex", "ChatGPT 2", [["สัปดาห์", 50]], { id: "codex-2" }),
  account("codex", "ChatGPT 3", [["สัปดาห์", 60]], { id: "codex-3" }),
  account("agy", "agy", [["Claude", 70]], { id: "agy-main" }),
  account("claude", "Claude 4", [["5 ชม.", 80]], { id: "claude-4" }),
]);

// Eight accounts that each need a row in the large widget: errors with no limits, named Claude 1 to Claude 8.
const EIGHT_ERRORS_TEXT = usageFile(
  Array.from({ length: 8 }, (_, i) =>
    account("claude", "Claude " + (i + 1), [], {
      id: "claude-" + (i + 1),
      status: "error",
      error: "ล็อกอิน Claude หมดอายุ",
      error_code: "login_expired",
      updated_at: null,
    }),
  ),
);

test("several accounts: small and medium show the first three in file order, even when a later one is more used", async () => {
  const files = {
    [FILE]: usageFile([
      account("codex", "ChatGPT", [["สัปดาห์", 50]], { id: "codex-main" }),
      account("claude", "Claude", [["5 ชม.", 90]], { id: "claude-main" }),
      account("agy", "agy", [["5 ชม.", 0]], { id: "agy-main" }),
      account("claude", "Claude 2", [["5 ชม.", 96]], { id: "claude-2" }),
      account("codex", "ChatGPT 2", [["สัปดาห์", 20]], { id: "codex-2" }),
    ]),
  };
  const names = ["ChatGPT", "Claude", "agy", "Claude 2", "ChatGPT 2"];
  const small = homeWidget(await render({ family: "small", files }));
  assert.deepEqual(rings(small).map((r) => r.number), ["50", "10", "100"], "the first three accounts, in file order");
  assert.deepEqual(textValues(small).filter((v) => names.includes(v)), ["ChatGPT", "Claude", "agy"]);
  assert.ok(textValues(small).includes("ใกล้หมด 1 รายการ"), "Claude 2 is red but has no ring, so the footer counts one");
  const medium = homeWidget(await render({ family: "medium", files }));
  assert.deepEqual(textValues(medium).filter((v) => names.includes(v)), ["ChatGPT", "Claude", "agy"]);
  assert.deepEqual(textValues(medium).filter((v) => v.startsWith("ใช้ไป")), ["ใช้ไป 50%", "ใช้ไป 90%", "ใช้ไป 0%"]);
  assertRefresh(medium);
});

test("several accounts: a missing, non-text or blank label shows the provider's short name, in every family", async () => {
  const files = {
    [FILE]: usageFile([
      relabel(account("claude", "Claude", [["5 ชม.", 10]], { id: "claude-main" }), undefined),
      relabel(account("codex", "ChatGPT", [["สัปดาห์", 20]], { id: "codex-main" }), 42),
      relabel(account("agy", "agy", [["5 ชม.", 30]], { id: "agy-main" }), "   "),
    ]),
  };
  const shortNames = ["Claude", "GPT", "agy"];
  const small = homeWidget(await render({ family: "small", files }));
  assert.deepEqual(textValues(small).filter((v) => shortNames.includes(v)), shortNames);
  const medium = homeWidget(await render({ family: "medium", files }));
  assert.deepEqual(textValues(medium).filter((v) => shortNames.includes(v)), shortNames);
  const large = homeWidget(await render({ family: "large", files }));
  assert.deepEqual(textValues(large).filter((v) => v.includes(" · ")), ["Claude · 5 ชม.", "GPT · สัปดาห์", "agy · 5 ชม."]);
});

test("several accounts: a nickname shows trimmed, as the label, in every family", async () => {
  const files = { [FILE]: usageFile([account("claude", " Claude งาน ", [["5 ชม.", 10]], { id: "claude-main" })]) };
  const expected = { small: "Claude งาน", medium: "Claude งาน", large: "Claude งาน · 5 ชม." };
  for (const family of FAMILIES) {
    const t = textValues(homeWidget(await render({ family, files })));
    assert.ok(t.includes(expected[family]), `${family}: "${expected[family]}" is missing`);
  }
});

test("several accounts: two accounts of one provider keep their own labels in every family", async () => {
  const files = {
    [FILE]: usageFile([
      account("claude", "Claude", [["5 ชม.", 30]], { id: "claude-main" }),
      account("claude", "Claude 2", [["5 ชม.", 60]], { id: "claude-2" }),
    ]),
  };
  const small = homeWidget(await render({ family: "small", files }));
  assert.deepEqual(rings(small).map((r) => r.number), ["70", "40"]);
  assert.deepEqual(textValues(small).filter((v) => v.startsWith("Claude")), ["Claude", "Claude 2"]);
  const medium = homeWidget(await render({ family: "medium", files }));
  assert.deepEqual(textValues(medium).filter((v) => v.startsWith("Claude")), ["Claude", "Claude 2"]);
  const large = homeWidget(await render({ family: "large", files }));
  assert.deepEqual(textValues(large).filter((v) => v.startsWith("Claude")), ["Claude · 5 ชม.", "Claude 2 · 5 ชม."]);
});

test("several accounts: no account, or only non-object entries, shows the no-data message; one account fills one row", async () => {
  for (const accounts of [[], [null, 5, "text"]]) {
    for (const family of FAMILIES) {
      const s = await render({ family, files: { [FILE]: usageFile(accounts) } });
      assert.ok(textValues(homeWidget(s)).includes(NO_DATA), `${family}: no-data message missing`);
    }
  }
  const files = { [FILE]: usageFile([account("claude", "Claude", [["5 ชม.", 25]], { id: "claude-main" })]) };
  const small = homeWidget(await render({ family: "small", files }));
  assert.deepEqual(rings(small).map((r) => r.number), ["75"]);
  assert.deepEqual(textValues(small).filter((v) => v === "Claude"), ["Claude"]);
  const medium = homeWidget(await render({ family: "medium", files }));
  assert.deepEqual(textValues(medium).filter((v) => v.startsWith("เหลือ") || v === "Claude"), ["Claude", "เหลือ 75%"]);
  assert.equal(hairlines(medium).length, 1, "a rule under the header and none between rows");
  const large = homeWidget(await render({ family: "large", files }));
  assert.deepEqual(textValues(large).filter((v) => v.includes(" · ")), ["Claude · 5 ชม."]);
  assert.equal(hairlines(large).length, 2, "a rule under the header and one above the footer");
});

test("several accounts: eight accounts show the first three in small and medium, and five rows in large by highest use", async () => {
  const files = { [FILE]: EIGHT_TEXT };
  const small = homeWidget(await render({ family: "small", files }));
  assert.deepEqual(rings(small).map((r) => r.number), ["90", "80", "70"]);
  assert.deepEqual(textValues(small).filter((v) => v.startsWith("Claude")), ["Claude", "Claude 2", "Claude 3"]);
  assert.ok(!textValues(small).some((v) => v.startsWith("ใกล้หมด")), "no ring is almost out");
  const medium = homeWidget(await render({ family: "medium", files }));
  assert.deepEqual(textValues(medium).filter((v) => v.startsWith("Claude")), ["Claude", "Claude 2", "Claude 3"]);
  assert.deepEqual(textValues(medium).filter((v) => v.startsWith("ใช้ไป")), ["ใช้ไป 10%", "ใช้ไป 20%", "ใช้ไป 30%"]);
  const large = homeWidget(await render({ family: "large", files }));
  assert.deepEqual(textValues(large).filter((v) => v.startsWith("ใช้ไป")), ["ใช้ไป 40%", "ใช้ไป 50%", "ใช้ไป 60%", "ใช้ไป 70%", "ใช้ไป 80%"]);
  assert.deepEqual(textValues(large).filter((v) => v.includes(" · ")), [
    "ChatGPT · สัปดาห์", "ChatGPT 2 · สัปดาห์", "ChatGPT 3 · สัปดาห์", "agy · Claude", "Claude 4 · 5 ชม.",
  ]);
  assert.equal(hairlines(large).length, 6, "five rows: a rule under the header, four between the rows and one above the footer");
});

test("several accounts: the large widget keeps five rows when eight accounts each need one", async () => {
  const w = homeWidget(await render({ family: "large", files: { [FILE]: EIGHT_ERRORS_TEXT } }));
  const t = textValues(w);
  assert.deepEqual(t.filter((v) => /^Claude \d$/.test(v)), ["Claude 1", "Claude 2", "Claude 3", "Claude 4", "Claude 5"], "the first five, in file order");
  assert.equal(t.filter((v) => v === "ล็อกอินหมดอายุ").length, 5, "each of the five rows carries its error text");
  assert.equal(hairlines(w).length, 6, "five rows: a rule under the header, four between the rows and one above the footer");
});

test("several accounts: the eight-account and eight-error widgets fit the smallest and largest frames (estimated), in both languages", async () => {
  for (const [name, text] of [["eight", EIGHT_TEXT], ["errors", EIGHT_ERRORS_TEXT]]) {
    for (const deviceLanguage of ["th", "en"]) {
      for (const family of FAMILIES) {
        const w = homeWidget(await render({ family, files: { [FILE]: text }, deviceLanguage }));
        assertFits(w, MIN_FRAME[family], `${name}/${deviceLanguage}/${family} smallest`, { shrink: true });
        assertFits(w, MAX_FRAME[family], `${name}/${deviceLanguage}/${family} largest`, { shrink: false });
      }
    }
  }
});

// Accounts past the first three get a "+N" badge in small and medium. FIVE_ACCOUNTS is in file order: the fourth
// account is red but has no ring, so the footer must not count it, and the fifth is left out as well.
const FIVE_ACCOUNTS = [
  account("claude", "Claude", [["5 ชม.", 42]], { id: "claude-main" }),
  account("claude", "Claude 2", [["5 ชม.", 12]], { id: "claude-2" }),
  account("codex", "ChatGPT", [["สัปดาห์", 85]], { id: "codex-main" }),
  account("codex", "ChatGPT 2", [["สัปดาห์", 100]], { id: "codex-2" }),
  account("agy", "agy", [["Claude", 0]], { id: "agy-main" }),
];
const TWELVE_ACCOUNTS = Array.from({ length: 12 }, (_, i) =>
  account("claude", "Claude " + (i + 1), [["5 ชม.", 10 + i]], { id: "claude-" + (i + 1) }),
);

// The "+N" texts drawn in a widget.
function badges(widget) {
  return textValues(widget).filter((v) => /^\+\d+$/.test(v));
}

test("more accounts: small and medium show a +N badge for the accounts past the first three, and none for three or fewer", async () => {
  for (const family of ["small", "medium"]) {
    const badgesFor = async (accounts) =>
      badges(homeWidget(await render({ family, files: { [FILE]: usageFile(accounts) } })));
    assert.deepEqual(await badgesFor(FIVE_ACCOUNTS.slice(0, 3)), [], `${family}: three accounts`);
    assert.deepEqual(await badgesFor(FIVE_ACCOUNTS.slice(0, 4)), ["+1"], `${family}: four accounts`);
    assert.deepEqual(await badgesFor(FIVE_ACCOUNTS), ["+2"], `${family}: five accounts`);
    assert.deepEqual(await badgesFor(TWELVE_ACCOUNTS), ["+9"], `${family}: twelve accounts`);
  }
  const large = homeWidget(await render({ family: "large", files: { [FILE]: usageFile(FIVE_ACCOUNTS) } }));
  assert.deepEqual(badges(large), [], "the large widget has its own rows and no badge");
});

test("more accounts: the first three keep their rings and rows, and the footer ignores the accounts left out", async () => {
  const files = { [FILE]: usageFile(FIVE_ACCOUNTS) };
  const small = homeWidget(await render({ family: "small", files }));
  assert.deepEqual(rings(small).map((r) => r.number), ["58", "88", "15"]);
  const t = textValues(small);
  assert.ok(t.includes("ใกล้หมด 1 รายการ"), "ChatGPT is yellow; ChatGPT 2 is red but has no ring");
  assert.ok(!t.includes("ใกล้หมด 2 รายการ"), "the red account left out is not counted");
  const medium = homeWidget(await render({ family: "medium", files }));
  assert.deepEqual(
    textValues(medium).filter((v) => ["Claude", "Claude 2", "ChatGPT"].includes(v)),
    ["Claude", "Claude 2", "ChatGPT"],
  );
  assert.deepEqual(textValues(medium).filter((v) => v.startsWith("ใช้ไป")), ["ใช้ไป 42%", "ใช้ไป 12%", "ใช้ไป 85%"]);
});

test("more accounts: the badge is secondary text on a translucent capsule; medium puts it in the header beside the age text, small under it", async () => {
  const badgeOf = (w) => stacks(w).find((s) => s.children.some((c) => c instanceof WidgetText && c.text === "+2"));
  const parentOf = (w, node) => stacks(w).find((s) => s.children.includes(node));
  const checkBadge = (badge, family) => {
    const text = firstText(badge);
    assert.equal(text.text, "+2");
    assert.equal(text.font.size, 10, `${family}: about 10 pt`);
    assert.equal(text.textColor.light.alpha, 0.55, `${family}: secondary text in light mode`);
    assert.equal(text.textColor.dark.alpha, 0.55, `${family}: secondary text in dark mode`);
    assert.equal(badge.cornerRadius, 6.5, `${family}: a capsule`);
    assert.equal(badge.backgroundColor.dynamic, true, `${family}: a light and dark fill`);
    assert.equal(badge.backgroundColor.light.alpha, 0.14);
    assert.equal(badge.backgroundColor.dark.alpha, 0.14);
  };

  // Medium: the title row is the first child. The badge is its last item, after a 6 pt gap, so it sits to the right of the
  // age text and not under the rows.
  const medium = homeWidget(await render({ family: "medium", files: { [FILE]: usageFile(FIVE_ACCOUNTS) } }));
  const header = medium.children[0];
  const mBadge = badgeOf(medium);
  checkBadge(mBadge, "medium");
  assert.equal(parentOf(medium, mBadge), header, "medium: the badge is in the title row");
  assert.equal(header.children[header.children.length - 1], mBadge, "medium: the badge is the last item of the title row");
  assert.deepEqual(header.children[header.children.length - 2], { spacer: true, length: 6 }, "medium: a 6 pt gap before the badge");
  assert.ok(header.children[header.children.length - 3] instanceof WidgetText, "medium: the age text is just before the badge");

  // Small: the title row is the first child, then a 2 pt gap, then the badge row. The badge row is 13 pt high and its
  // flexible spacer pushes the badge to the right edge, under the age text.
  const small = homeWidget(await render({ family: "small", files: { [FILE]: usageFile(FIVE_ACCOUNTS) } }));
  const sBadge = badgeOf(small);
  checkBadge(sBadge, "small");
  const row = parentOf(small, sBadge);
  assert.equal(small.children.indexOf(row), 2, "small: the badge row comes after the title row and a 2 pt gap");
  assert.deepEqual(small.children[1], { spacer: true, length: 2 }, "small: a 2 pt gap under the title row");
  assert.equal(row.size.height, 13, "small: the badge row is 13 pt high");
  assert.equal(row.children.length, 2, "small: nothing else shares the badge's row");
  assert.deepEqual(row.children[0], { spacer: true, length: null }, "small: a flexible spacer pushes the badge to the right edge");
  assert.equal(row.children[1], sBadge);
});

test("more accounts: the medium rows and padding are the same with a badge, since the badge is in the header", async () => {
  const five = homeWidget(await render({ family: "medium", files: { [FILE]: usageFile(FIVE_ACCOUNTS) } }));
  assert.equal(sized(five, 0, 33).length, 3, "three rows at 33 pt");
  assert.equal(sized(five, 0, 31).length, 0, "no tighter rows");
  assert.deepEqual(five.padding, [12, 16, 10, 16]);
  const three = homeWidget(await render({ family: "medium" }));
  assert.equal(sized(three, 0, 33).length, 3, "three rows at 33 pt");
  assert.deepEqual(three.padding, [12, 16, 10, 16]);
});

test("more accounts: the badge layouts fit the smallest and largest frames (estimated), with almost-out text, in both languages", async () => {
  for (const [name, accounts] of [["five", FIVE_ACCOUNTS], ["twelve", TWELVE_ACCOUNTS]]) {
    for (const deviceLanguage of ["th", "en"]) {
      for (const family of ["small", "medium"]) {
        const w = homeWidget(await render({ family, files: { [FILE]: usageFile(accounts) }, deviceLanguage }));
        assertFits(w, MIN_FRAME[family], `${name}/${deviceLanguage}/${family} smallest`, { shrink: true });
        assertFits(w, MAX_FRAME[family], `${name}/${deviceLanguage}/${family} largest`, { shrink: false });
      }
    }
  }
});
