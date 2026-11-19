// AI Usage widget for iPhone (Scriptable).
// Reads ai-usage.json from the Scriptable folder in iCloud Drive. The Mac collector writes it.
// Data contract: docs/usage-json.md (schema 1).
// Language: Thai when the device language starts with "th", English otherwise. The widget's
// Parameter field can force "th" or "en".

const FILE_NAME = "ai-usage.json";
const REFRESH_MINUTES = 5;
// The battery tiers, on the share left (see tierOf): more than LOW_LEFT is white, RED_LEFT or less is red.
const LOW_LEFT = 20;
const RED_LEFT = 5;
const OTHER_HEX = "8E8E93";
const PROVIDERS = {
  claude: { short: "Claude", letter: "C", hex: "D97757" },
  codex: { short: "GPT", letter: "G", hex: "10A37F" },
  agy: { short: "agy", letter: "A", hex: "4285F4" },
};

// Every string the widget shows, by language. The Thai text is the original. The English texts are plain
// wording choices.
const TEXT = {
  th: {
    usageTitle: "การใช้งาน AI",
    limitsTitle: "ขีดจำกัดการใช้งาน AI",
    liveStatus: "สถานะเรียลไทม์",
    systemStatus: "สถานะระบบ",
    almostOut: "ใกล้หมด",
    almostOutCount: (n) => "ใกล้หมด " + n + " รายการ",
    left: (n) => "เหลือ " + n + "%",
    used: (n) => "ใช้ไป " + n + "%",
    noLimit: "ไม่มีข้อมูล",
    noData: "ยังไม่มีข้อมูล เปิด Mac ไว้",
    failed: "แสดงผลไม่ได้",
    account: "บัญชี",
    week: "สัปดาห์",
    credits: (n) => "เครดิต " + n,
    updated: (ago) => "อัปเดต " + ago,
    ago: (v, u) => v + " " + { minute: "นาทีก่อน", hour: "ชม.ก่อน", day: "วันก่อน" }[u],
    resetIn: (v, u) => "รีเซ็ตใน " + v + " " + { minute: "นาที", hour: "ชม.", day: "วัน" }[u],
    windowLabel: (v, u) => v + " " + { minute: "นาที", hour: "ชม.", day: "วัน" }[u],
    errors: {
      login_expired: "ล็อกอินหมดอายุ",
      relogin_needed: "ต้องล็อกอินใหม่",
      not_set_up: "ยังไม่มีโปรเจกต์",
      network: "เชื่อมต่อเครือข่ายไม่ได้",
      rate_limited: "ถูกจำกัดการเรียกชั่วคราว",
      server_error: "เซิร์ฟเวอร์มีปัญหา",
      unknown: "เกิดข้อผิดพลาดที่ไม่ทราบสาเหตุ",
    },
    chatgpt: {
      title: "เชื่อม ChatGPT",
      consentBody: "ดึงโควตา ChatGPT จาก iPhone เครื่องนี้โดยตรง ไม่ต้องเปิด Mac\nClaude และ agy ยังมาจาก Mac ตามเดิม\nโทเค็นเก็บไว้เฉพาะใน Keychain ของ Scriptable บน iPhone เครื่องนี้",
      consentWarning: "นี่เป็นช่องทางที่ไม่เป็นทางการ อาจใช้งานไม่ได้ หรือขัดกับข้อกำหนดของผู้ให้บริการ คุณใช้บัญชีด้วยความเสี่ยงของตนเอง",
      accept: "ยินยอมและเชื่อมต่อ",
      later: "ไว้ทีหลัง",
      reconnect: "การเชื่อมต่อหมดอายุ ต้องเชื่อมต่อใหม่",
      startFailed: "เริ่มการเชื่อมต่อไม่สำเร็จ ลองอีกครั้ง",
      codeHint: "เปิดหน้า OpenAI กรอกรหัสนี้ แล้วกลับมาที่นี่ ระบบจะตรวจให้เอง",
      waiting: "กำลังรอการอนุมัติ",
      copied: "คัดลอกรหัสแล้ว",
      checkFailed: "ตรวจสอบยังไม่ได้ ระบบจะลองอีกครั้ง",
      expiresIn: (n) => "หมดอายุใน " + n + " นาที",
      openPage: "เปิดหน้า OpenAI",
      copyCode: "คัดลอกรหัส",
      connected: "เชื่อม ChatGPT แล้ว",
      plan: (p) => "แผน " + p,
      done: "เสร็จ",
      disconnect: "ยกเลิกการเชื่อมต่อ",
      timedOut: "หมดเวลาแล้ว เปิดแอปอีกครั้งเพื่อเริ่มใหม่",
    },
  },
  en: {
    usageTitle: "AI Usage",
    limitsTitle: "AI Usage Limits",
    liveStatus: "Live status",
    systemStatus: "System status",
    almostOut: "Almost out",
    almostOutCount: (n) => n + " almost out",
    left: (n) => n + "% left",
    used: (n) => n + "% used",
    noLimit: "No data",
    noData: "No data yet. Keep your Mac on.",
    failed: "Can't show the data",
    account: "Account",
    week: "Week",
    credits: (n) => "Credits " + n,
    updated: (ago) => "Updated " + ago,
    ago: (v, u) => v + " " + { minute: "min ago", hour: "h ago", day: "d ago" }[u],
    resetIn: (v, u) => "Resets in " + v + " " + { minute: "min", hour: "h", day: "d" }[u],
    windowLabel: (v, u) => v + { minute: "min", hour: "h", day: "d" }[u],
    errors: {
      login_expired: "Sign-in expired",
      relogin_needed: "Sign in again",
      not_set_up: "No project yet",
      network: "No network connection",
      rate_limited: "Rate limited for now",
      server_error: "Server error",
      unknown: "Unknown error",
    },
    chatgpt: {
      title: "Connect ChatGPT",
      consentBody: "Get your ChatGPT usage directly from this iPhone, without the Mac.\nClaude and agy still come from the Mac.\nThe token is stored only in Scriptable's Keychain on this iPhone.",
      consentWarning: "This is an unofficial channel. It may stop working or conflict with the provider's terms. You use your account at your own risk.",
      accept: "Consent and connect",
      later: "Not now",
      reconnect: "The connection has expired. Connect again.",
      startFailed: "Could not start the connection. Try again.",
      codeHint: "Open the OpenAI page, enter this code, then come back here. The check runs by itself.",
      waiting: "Waiting for approval",
      copied: "Code copied",
      checkFailed: "Could not check yet. It will try again.",
      expiresIn: (n) => "Expires in " + n + " min",
      openPage: "Open the OpenAI page",
      copyCode: "Copy code",
      connected: "ChatGPT connected",
      plan: (p) => "Plan " + p,
      done: "Done",
      disconnect: "Disconnect",
      timedOut: "Timed out. Open the app again to start over.",
    },
  },
};

// Colours. Color.dynamic takes the light colour first, then the dark colour.
const PANEL = Color.dynamic(new Color("E9E9EF", 0.9), new Color("0A0A0C", 0.85));
const TEXT_PRIMARY = Color.dynamic(new Color("1C1C1E"), new Color("FFFFFF"));
const TEXT_MUTED = Color.dynamic(new Color("000000", 0.55), new Color("FFFFFF", 0.55));
const HAIRLINE = Color.dynamic(new Color("000000", 0.12), new Color("FFFFFF", 0.16));
const GAUGE_EDGE = Color.dynamic(new Color("000000", 0.45), new Color("FFFFFF", 0.5));
const GREEN = new Color("30D158");
const WHITE = new Color("FFFFFF");
// Battery colours. Gauges and rings are drawn with one fixed colour per tier, the same in light
// and dark mode: gray for white, dark yellow and dark red. Text and pills take a light/dark pair: the dark colour on
// the light panel, the bright one on the dark panel.
const DRAWN = { white: new Color(OTHER_HEX), yellow: new Color("B58900"), red: new Color("D93025") };
const TEXT_YELLOW = Color.dynamic(new Color("B58900"), new Color("FFD60A"));
const TEXT_RED = Color.dynamic(new Color("D93025"), new Color("FF5F57"));
const PILL_YELLOW = Color.dynamic(new Color("B58900", 0.22), new Color("FFD60A", 0.22));
const PILL_RED = Color.dynamic(new Color("D93025", 0.22), new Color("FF5F57", 0.22));
// DrawContext ignores dynamic colours, so the ring track is a fixed translucent neutral.
const TRACK = new Color(OTHER_HEX, 0.3);

// Sizes in points. The real frames depend on the device (see the test file).
const GAP = 8;
const ICON = { size: 20, radius: 5, font: 12 };
const INDENT = ICON.size + GAP;
const GAUGE = { w: 24, h: 11, nubW: 1.5, nubH: 4.5, border: 1, pad: 1.5, radius: 3, minFill: 2 };
// Small and medium show the first three accounts in file order (maxRings, maxRows). The collector has already put
// them in the chosen order. Large shows as many rows as fit (maxRows).
const LAYOUT = {
  small: { pad: [14, 14, 12, 14], ringD: 36, ringStroke: 3.5, ringFont: 13, labelFont: 10, maxRings: 3 },
  medium: {
    pad: [12, 16, 10, 16], titleFont: 13, metaFont: 10, nameFont: 13, subFont: 11, pctFont: 14,
    rowH: 33, pctW: 78, usedFont: 10, maxRows: 3,
  },
  large: {
    pad: [12, 16, 10, 16], titleFont: 13, metaFont: 10, nameFont: 13, subFont: 10, pctFont: 14,
    rowH: 40, pctW: 78, usedFont: 10, maxRows: 5,
  },
};

// The "+N" badge for the accounts past the first three (small and medium): a quiet capsule, secondary text on a
// translucent fill. It sits beside the age text in the medium header, and under the age text in small.
const MORE = { font: 10, h: 13, padX: 6, fill: Color.dynamic(new Color("000000", 0.14), new Color("FFFFFF", 0.14)) };

function isObject(v) {
  return v !== null && typeof v === "object" && !Array.isArray(v);
}

function cleanText(v) {
  return typeof v === "string" && v.trim() !== "" ? v.trim() : null;
}

function numOrNull(v) {
  const n = typeof v === "string" && v.trim() !== "" ? Number(v) : v;
  return typeof n === "number" && isFinite(n) ? n : null;
}

function timeOf(v) {
  if (typeof v !== "string") return null;
  const ms = Date.parse(v);
  return isNaN(ms) ? null : ms;
}

// Used, rounded down: 79.6 shows 79. The text "ใช้ไป N%" shows it.
function shownPct(p) {
  return Math.floor(Math.min(100, Math.max(0, p)));
}

// What is left, from 0 to 100: 100 minus used, with used clamped to 0 to 100. Null when there is no number.
function leftOf(p) {
  if (p === null) return null;
  return 100 - Math.min(100, Math.max(0, p));
}

// What is left as the widget shows it, rounded UP: used 94.6 shows 6 left, and used 79.6 shows 21 left. Used
// rounded down and left rounded up always add up to 100.
function shownLeft(p) {
  const left = leftOf(p);
  return left === null ? null : Math.ceil(left);
}

// The battery tier from the shown left: white above 20, yellow from 6 to 20, red at 5 or less. Null for no number.
function tierOf(p) {
  const left = shownLeft(p);
  if (left === null) return null;
  if (left <= RED_LEFT) return "red";
  if (left <= LOW_LEFT) return "yellow";
  return "white";
}

// A row is almost out when its tier is yellow or red. The pill and the small-widget footer count these rows.
function isAlmostOut(p) {
  const tier = tierOf(p);
  return tier === "yellow" || tier === "red";
}

// The ring centre shows the bare number of left, as the tiny widgets must.
function ringText(p) {
  const left = shownLeft(p);
  return left === null ? "—" : String(left);
}

function providerOf(acc) {
  return Object.prototype.hasOwnProperty.call(PROVIDERS, acc.provider) ? PROVIDERS[acc.provider] : null;
}

// The short name of a provider, or the account's own label, or "Account" / "บัญชี" when there is neither.
function shortName(acc, lang) {
  const p = providerOf(acc);
  return p ? p.short : cleanText(acc.label) || TEXT[lang].account;
}

// Brand letter and colour. An unknown provider gets a neutral grey square with the label's first letter.
function brandOf(acc, lang) {
  const p = providerOf(acc);
  if (p) return p;
  const name = cleanText(acc.label) || TEXT[lang].account;
  return { short: name, letter: name.charAt(0).toUpperCase(), hex: OTHER_HEX };
}

// window_seconds: a positive whole number of seconds. Anything else (null, missing, text) means no window.
function windowOf(v) {
  const n = numOrNull(v);
  return n !== null && Number.isInteger(n) && n > 0 ? n : null;
}

// A window length as a count and a unit: whole days, else whole hours, else minutes (at least one minute).
function windowSpan(seconds) {
  if (seconds % 86400 === 0) return { value: seconds / 86400, unit: "day" };
  if (seconds % 3600 === 0) return { value: seconds / 3600, unit: "hour" };
  return { value: Math.max(1, Math.round(seconds / 60)), unit: "minute" };
}

// A limit's name in the given language. A window length builds it: 604800 seconds is the week, and any
// other length is its count and unit. The Opus and Sonnet keys add " (Opus)" or " (Sonnet)" in both
// languages. Without a window, the file's label is used, then the key. A model group such as "Gemini Pro"
// reads the same in both languages.
function limitNameOf(limit, lang) {
  if (limit.windowSeconds === null) return cleanText(limit.label) || cleanText(limit.key) || "";
  const t = TEXT[lang];
  let base;
  if (limit.windowSeconds === 604800) base = t.week;
  else {
    const span = windowSpan(limit.windowSeconds);
    base = t.windowLabel(span.value, span.unit);
  }
  const key = limit.key || "";
  if (/(^|_)opus$/i.test(key)) return base + " (Opus)";
  if (/(^|_)sonnet$/i.test(key)) return base + " (Sonnet)";
  return base;
}

function limitsOf(acc, lang) {
  const list = Array.isArray(acc.limits) ? acc.limits : [];
  return list.filter(isObject).map((l) => {
    const key = cleanText(l.key) || "";
    return {
      key,
      label: limitNameOf({ key, label: cleanText(l.label), windowSeconds: windowOf(l.window_seconds) }, lang),
      pct: numOrNull(l.used_percent),
      resetsAt: timeOf(l.resets_at),
    };
  });
}

// The limit with the highest percentage (the first one on a tie). With no number at all, the first limit.
function topLimit(limits) {
  let best = null;
  for (const l of limits) {
    if (l.pct !== null && (best === null || l.pct > best.pct)) best = l;
  }
  return best !== null ? best : limits[0] || null;
}

// Picks the unit and the whole number for a span of time, the same way as the Mac widget (timeSpan in
// UsagePresentation.swift). Each candidate is rounded to the nearest whole number from the raw span, and
// the unit is chosen from the rounded minutes and hours, so the text never reads "60 นาที" or "24 ชม.".
// The minimum is 1, and a negative span (a clock that is behind) counts as zero.
function timeSpan(ms) {
  const seconds = Math.max(0, ms) / 1000;
  const minutes = Math.round(seconds / 60);
  if (minutes < 60) return { value: Math.max(1, minutes), unit: "minute" };
  const hours = Math.round(seconds / 3600);
  if (hours < 24) return { value: Math.max(1, hours), unit: "hour" };
  return { value: Math.max(1, Math.round(seconds / 86400)), unit: "day" };
}

// The time since an update, without the "updated" prefix: "2 นาทีก่อน" or "2 min ago".
function agoText(updatedAt, now, lang) {
  const span = timeSpan(now - updatedAt);
  return TEXT[lang].ago(span.value, span.unit);
}

// "อัปเดต 8 นาทีก่อน" or "Updated 8 min ago", counted from the last update.
function ageText(updatedAt, now, lang) {
  return TEXT[lang].updated(agoText(updatedAt, now, lang));
}

// "รีเซ็ตใน 2 ชม." or "Resets in 2 h".
function resetText(resetsAt, now, lang) {
  const span = timeSpan(resetsAt - now);
  return TEXT[lang].resetIn(span.value, span.unit);
}

// The reset text of a limit whose reset is still ahead; null when there is none.
function futureReset(limit, now, lang) {
  return limit.resetsAt !== null && limit.resetsAt > now ? resetText(limit.resetsAt, now, lang) : null;
}

// Whole numbers without decimals; otherwise up to two decimals with trailing zeros removed. No $ sign.
function creditText(n) {
  return Number.isInteger(n) ? String(n) : String(Number(n.toFixed(2)));
}

// The file's generated_at, or the newest account update when that is missing.
function updatedAtOf(usage, accounts) {
  const generated = timeOf(usage.generated_at);
  if (generated !== null) return generated;
  let latest = null;
  accounts.forEach((acc) => {
    const t = timeOf(acc.updated_at);
    if (t !== null && (latest === null || t > latest)) latest = t;
  });
  return latest;
}

// The text for a recognised error_code, in the given language. A missing or unrecognised code uses the
// collector's Thai error text, in both languages.
function errorTextOf(acc, lang) {
  const code = cleanText(acc.error_code);
  const texts = TEXT[lang].errors;
  if (code !== null && Object.prototype.hasOwnProperty.call(texts, code)) return texts[code];
  return cleanText(acc.error);
}

// Everything a row needs about one account, in the given language.
function modelOf(acc, lang) {
  const limits = limitsOf(acc, lang);
  const top = topLimit(limits);
  const credits = isObject(acc.credits) ? acc.credits : null;
  return {
    name: cleanText(acc.label) || shortName(acc, lang),
    brand: brandOf(acc, lang),
    limits,
    top,
    pct: top ? top.pct : null,
    errorText: errorTextOf(acc, lang),
    credit: credits ? numOrNull(credits.balance_usd) : null,
  };
}

// Figures take their tier's colour: the primary text colour above 20 left, and the yellow or red text pair below.
// With no number, the text is muted.
function pctColor(p) {
  const tier = tierOf(p);
  if (tier === "red") return TEXT_RED;
  if (tier === "yellow") return TEXT_YELLOW;
  return tier === "white" ? TEXT_PRIMARY : TEXT_MUTED;
}

// Rows of the large widget: one per limit, and one per account with no limits. The row that carries an
// account's error text is kept, as are the no-limit rows, up to the rows that fit (the first in file order).
// The other limits fill the remaining rows by highest percentage (a tie keeps file order), and the shown rows
// go back into file order.
function largeEntries(accounts, lang) {
  const entries = [];
  accounts.forEach((acc) => {
    const m = modelOf(acc, lang);
    if (m.limits.length === 0) {
      entries.push({ m, lim: null, keep: true });
      return;
    }
    m.limits.forEach((lim, j) => entries.push({ m, lim, keep: j === 0 && m.errorText !== null }));
  });
  const sortKey = (p) => (p === null ? -1 : p);
  // Eight accounts that each need a row must not overflow the widget, so the kept rows stop at the row limit.
  const kept = entries.filter((e) => e.keep).slice(0, LAYOUT.large.maxRows);
  const rest = entries
    .filter((e) => !e.keep)
    .sort((a, b) => (sortKey(b.lim.pct) - sortKey(a.lim.pct)) || (entries.indexOf(a) - entries.indexOf(b)));
  const room = Math.max(0, LAYOUT.large.maxRows - kept.length);
  const chosen = new Set(kept.concat(rest.slice(0, room)));
  const shown = entries.filter((e) => chosen.has(e));
  // The first shown row of each account carries its error text.
  const seen = new Set();
  shown.forEach((e) => {
    e.first = !seen.has(e.m);
    seen.add(e.m);
  });
  return shown;
}

// The widget's language. The Parameter field wins when it is "th" or "en" (any case, spaces ignored).
// Otherwise Thai when the device language starts with "th", and English for anything else, including a
// device language that is missing or cannot be read. This never throws.
function languageOf() {
  try {
    const parameter = args.widgetParameter;
    if (typeof parameter === "string") {
      const value = parameter.trim().toLowerCase();
      if (value === "th" || value === "en") return value;
    }
  } catch (e) {
    // No usable Parameter: the device language decides.
  }
  try {
    const device = Device.language();
    if (typeof device === "string" && device.trim().toLowerCase().startsWith("th")) return "th";
  } catch (e) {
    // No readable device language: English.
  }
  return "en";
}

function style(text, font, color, lines) {
  text.font = font;
  text.textColor = color;
  text.lineLimit = lines;
  text.minimumScaleFactor = 0.7;
  return text;
}

// A horizontal row. A height, when given, fixes the row's height and leaves its width automatic.
function addRow(parent, height) {
  const row = parent.addStack();
  row.layoutHorizontally();
  row.centerAlignContent();
  if (height) row.size = new Size(0, height);
  return row;
}

// The ring: a translucent track, then an arc from 12 o'clock clockwise whose length is the share left. The arc
// is a path of many short line segments. DrawContext cannot take dynamic colours, so the arc colour is fixed.
function ringImage(left, color, size, stroke) {
  const dc = new DrawContext();
  dc.size = new Size(size, size);
  dc.respectScreenScale = true;
  dc.opaque = false;
  const inset = stroke / 2;
  dc.setLineWidth(stroke);
  dc.setStrokeColor(TRACK);
  dc.strokeEllipse(new Rect(inset, inset, size - stroke, size - stroke));
  if (left !== null && left > 0) {
    const frac = Math.min(left, 100) / 100;
    const r = (size - stroke) / 2;
    const c = size / 2;
    const steps = Math.max(2, Math.ceil(120 * frac));
    const arc = new Path();
    for (let i = 0; i <= steps; i++) {
      const a = -Math.PI / 2 + (2 * Math.PI * frac * i) / steps;
      const p = new Point(c + r * Math.cos(a), c + r * Math.sin(a));
      if (i === 0) arc.move(p);
      else arc.addLine(p);
    }
    dc.setStrokeColor(color);
    dc.addPath(arc);
    dc.strokePath();
  }
  return dc.getImage();
}

function addIcon(parent, brand) {
  const icon = parent.addStack();
  icon.size = new Size(ICON.size, ICON.size);
  icon.cornerRadius = ICON.radius;
  icon.backgroundColor = new Color(brand.hex);
  icon.centerAlignContent();
  icon.addSpacer(null);
  style(icon.addText(brand.letter), Font.boldSystemFont(ICON.font), WHITE, 1);
  icon.addSpacer(null);
}

// A hairline: a 0.5 pt stack with an automatic width, so it runs across its row (the flexible spacer
// inside keeps it open). An indent leaves room for the brand icon.
function addHairline(parent, indent) {
  const row = parent.addStack();
  row.size = new Size(0, 0.5);
  if (indent > 0) row.addSpacer(indent);
  const line = row.addStack();
  line.size = new Size(0, 0.5);
  line.backgroundColor = HAIRLINE;
  line.addSpacer(null);
}

// The battery capsule: a 24 x 11 outline with a nub on the right. The fill is what is left: its width is the
// share left, at least a 2 pt sliver while anything is left. Its colour is the tier's drawn colour (gray, dark yellow
// or dark red), the same in light and dark mode. At the red tier the outline and nub turn red too. An empty gauge
// shows only the outline.
function addGauge(parent, p) {
  const left = leftOf(p);
  const tier = tierOf(p);
  const edge = tier === "red" ? DRAWN.red : GAUGE_EDGE;
  const cap = parent.addStack();
  cap.size = new Size(GAUGE.w, GAUGE.h);
  cap.cornerRadius = GAUGE.radius;
  cap.borderWidth = GAUGE.border;
  cap.borderColor = edge;
  cap.setPadding(GAUGE.pad, GAUGE.pad, GAUGE.pad, GAUGE.pad);
  cap.centerAlignContent();
  if (left !== null && left > 0) {
    const innerW = GAUGE.w - 2 * (GAUGE.border + GAUGE.pad);
    const innerH = GAUGE.h - 2 * (GAUGE.border + GAUGE.pad);
    const fillW = Math.min(innerW, Math.max(GAUGE.minFill, (innerW * left) / 100));
    const fill = cap.addStack();
    fill.size = new Size(fillW, innerH);
    fill.cornerRadius = Math.min(fillW, innerH) / 2;
    fill.backgroundColor = DRAWN[tier];
  }
  const nub = parent.addStack();
  nub.size = new Size(GAUGE.nubW, GAUGE.nubH);
  nub.cornerRadius = GAUGE.nubW / 2;
  nub.backgroundColor = edge;
}

// The battery figure in a fixed-width cell: "เหลือ 33%" in the tier colour, with "ใช้ไป 67%" under it in muted
// text. With no number, the cell shows a dash alone.
function addLeftCell(parent, p, lang, L) {
  const t = TEXT[lang];
  const left = shownLeft(p);
  const cell = parent.addStack();
  cell.size = new Size(L.pctW, 0);
  cell.layoutVertically();
  style(cell.addText(left === null ? "—" : t.left(left)), Font.boldSystemFont(L.pctFont), pctColor(p), 1).rightAlignText();
  if (p !== null) {
    style(cell.addText(t.used(shownPct(p))), Font.mediumSystemFont(L.usedFont), TEXT_MUTED, 1).rightAlignText();
  }
}

function addDot(parent) {
  const dot = parent.addStack();
  dot.size = new Size(5, 5);
  dot.cornerRadius = 2.5;
  dot.backgroundColor = GREEN;
}

// The almost-out pill on a large-widget row: yellow from 6 to 20 left, red at 5 or less. Its tint and its text take
// the tier's light/dark pair.
function addPill(parent, text, tier) {
  const pill = parent.addStack();
  pill.backgroundColor = tier === "red" ? PILL_RED : PILL_YELLOW;
  pill.cornerRadius = 4;
  pill.setPadding(1, 5, 1, 5);
  style(pill.addText(text), Font.semiboldSystemFont(9), tier === "red" ? TEXT_RED : TEXT_YELLOW, 1);
}

// A line of text centred in a fixed-width row, with a flexible spacer on each side (as the brand icon does).
function addCentred(parent, width, text, font, color) {
  const row = parent.addStack();
  row.size = new Size(width, 0);
  row.layoutHorizontally();
  row.centerAlignContent();
  row.addSpacer(null);
  style(row.addText(text), font, color, 1);
  row.addSpacer(null);
}

// The arc colour of a ring by tier: gray, dark yellow or dark red. DrawContext takes one fixed colour, so it is the
// same in light and dark mode.
function ringColorOf(tier) {
  return DRAWN[tier] || DRAWN.white;
}

// One ring of the small widget: the account's highest limit as the share left, the number left in the centre and
// its label below (the provider name when the label is missing). The label turns red at the red tier. Brand colours
// are for the icons only.
function addRing(parent, m) {
  const L = LAYOUT.small;
  const tier = tierOf(m.pct);
  const cell = parent.addStack();
  cell.layoutVertically();
  const ring = cell.addStack();
  ring.size = new Size(L.ringD, L.ringD);
  ring.backgroundImage = ringImage(leftOf(m.pct), ringColorOf(tier), L.ringD, L.ringStroke);
  ring.layoutVertically();
  ring.addSpacer(null);
  addCentred(ring, L.ringD, ringText(m.pct), Font.boldSystemFont(L.ringFont), pctColor(m.pct));
  ring.addSpacer(null);
  cell.addSpacer(4);
  addCentred(cell, L.ringD, m.name, Font.mediumSystemFont(L.labelFont), tier === "red" ? TEXT_RED : TEXT_MUTED);
}

// The "+N" badge: a quiet capsule holding the count. The caller adds it to a row: in medium, beside the age text in the
// title row; in small, on a row of its own under the age text, at the right. So it covers no ring or row.
function addMoreBadge(parent, count) {
  const badge = parent.addStack();
  badge.cornerRadius = MORE.h / 2;
  badge.backgroundColor = MORE.fill;
  badge.setPadding(0, MORE.padX, 0, MORE.padX);
  badge.centerAlignContent();
  style(badge.addText("+" + count), Font.mediumSystemFont(MORE.font), TEXT_MUTED, 1);
}

// Small: a title row, the first three accounts as rings in file order, a hairline and the footer.
function buildSmall(widget, accounts, info) {
  const L = LAYOUT.small;
  const t = TEXT[info.lang];
  widget.setPadding(...L.pad);
  const head = addRow(widget);
  style(head.addText(t.usageTitle), Font.semiboldSystemFont(13), TEXT_PRIMARY, 1);
  head.addSpacer(null);
  if (info.allOk) {
    addDot(head);
    head.addSpacer(4);
  }
  if (info.updated !== null) {
    style(head.addText(agoText(info.updated, info.now, info.lang)), Font.mediumSystemFont(L.labelFont), TEXT_MUTED, 1);
  }
  // The "+N" badge sits under the age text, at the right edge, on a row of its own. The title row has no room beside it.
  const hidden = accounts.length - L.maxRings;
  if (hidden > 0) {
    widget.addSpacer(2);
    const more = addRow(widget, MORE.h);
    more.addSpacer(null);
    addMoreBadge(more, hidden);
  }
  widget.addSpacer(null);
  const models = accounts.slice(0, L.maxRings).map((acc) => modelOf(acc, info.lang));
  const rings = addRow(widget);
  rings.addSpacer(null);
  models.forEach((m) => {
    addRing(rings, m);
    rings.addSpacer(null);
  });
  widget.addSpacer(null);
  addHairline(widget, 0);
  widget.addSpacer(6);
  const foot = addRow(widget);
  style(foot.addText(t.systemStatus), Font.mediumSystemFont(L.labelFont), TEXT_MUTED, 1);
  foot.addSpacer(null);
  // Counts the rings that are yellow or red, so the footer and the rings always agree. The colour is red when any
  // of them is red, otherwise yellow.
  const low = models.filter((m) => isAlmostOut(m.pct));
  if (low.length > 0) {
    const worst = low.some((m) => tierOf(m.pct) === "red") ? TEXT_RED : TEXT_YELLOW;
    style(foot.addText(t.almostOutCount(low.length)), Font.mediumSystemFont(L.labelFont), worst, 1);
  }
}

// The subtitle of a medium row: the error text when the account has one, else the highest limit's name
// with its reset in brackets.
function mediumSub(m, info) {
  if (m.errorText) return m.errorText;
  if (!m.top) return TEXT[info.lang].noLimit;
  const reset = futureReset(m.top, info.now, info.lang);
  const label = m.top.label;
  if (reset) return label ? label + " (" + reset + ")" : "(" + reset + ")";
  return label || null;
}

function addMediumRow(widget, m, info, rowH) {
  const L = LAYOUT.medium;
  const row = addRow(widget, rowH);
  addIcon(row, m.brand);
  row.addSpacer(GAP);
  style(row.addText(m.name), Font.semiboldSystemFont(L.nameFont), TEXT_PRIMARY, 1);
  const sub = mediumSub(m, info);
  if (sub) {
    row.addSpacer(6);
    style(row.addText(sub), Font.systemFont(L.subFont), TEXT_MUTED, 1);
  }
  row.addSpacer(null);
  addLeftCell(row, m.pct, info.lang, L);
  row.addSpacer(GAP);
  addGauge(row, m.pct);
}

// Medium: a title row with the age text on the right and, past three accounts, the "+N" badge beside it. Then one row per
// account for the first three in file order (each with its highest limit), with hairlines between them.
function buildMedium(widget, accounts, info) {
  const L = LAYOUT.medium;
  const t = TEXT[info.lang];
  const hidden = accounts.length - L.maxRows;
  widget.setPadding(...L.pad);
  const head = addRow(widget);
  style(head.addText(t.usageTitle), Font.semiboldSystemFont(L.titleFont), TEXT_PRIMARY, 1);
  head.addSpacer(null);
  if (info.updated !== null) {
    style(head.addText(agesText(info)), Font.mediumSystemFont(L.metaFont), TEXT_MUTED, 1);
  }
  if (hidden > 0) {
    head.addSpacer(6);
    addMoreBadge(head, hidden);
  }
  widget.addSpacer(6);
  addHairline(widget, 0);
  accounts.slice(0, L.maxRows).forEach((acc, i) => {
    if (i > 0) addHairline(widget, INDENT);
    addMediumRow(widget, modelOf(acc, info.lang), info, L.rowH);
  });
}

// The subtitle of a large row: the reset (or the error text on the account's first row, or the no-limit
// text), then the credit balance when the account has one.
function largeSub(e, info) {
  const t = TEXT[info.lang];
  const parts = [];
  if (e.first && e.m.errorText) parts.push(e.m.errorText);
  else if (e.lim) {
    const reset = futureReset(e.lim, info.now, info.lang);
    if (reset) parts.push(reset);
  } else parts.push(t.noLimit);
  if (e.m.credit !== null) parts.push(t.credits(creditText(e.m.credit)));
  return parts.length > 0 ? parts.join(" · ") : null;
}

function addLargeRow(widget, e, info) {
  const L = LAYOUT.large;
  const m = e.m;
  const lim = e.lim;
  const pct = lim ? lim.pct : null;
  const row = addRow(widget, L.rowH);
  addIcon(row, m.brand);
  row.addSpacer(GAP);
  const group = row.addStack();
  group.layoutVertically();
  const titleLine = addRow(group);
  const title = lim && lim.label ? m.name + " · " + lim.label : m.name;
  style(titleLine.addText(title), Font.semiboldSystemFont(L.nameFont), TEXT_PRIMARY, 1);
  if (isAlmostOut(pct)) {
    titleLine.addSpacer(5);
    addPill(titleLine, TEXT[info.lang].almostOut, tierOf(pct));
  }
  const sub = largeSub(e, info);
  if (sub) {
    group.addSpacer(1);
    style(group.addText(sub), Font.systemFont(L.subFont), TEXT_MUTED, 1);
  }
  row.addSpacer(null);
  addLeftCell(row, pct, info.lang, L);
  row.addSpacer(GAP);
  addGauge(row, pct);
}

// Large: a title row, the limit rows (at most five), a hairline and the footer.
function buildLarge(widget, accounts, info) {
  const L = LAYOUT.large;
  const t = TEXT[info.lang];
  widget.setPadding(...L.pad);
  const head = addRow(widget);
  style(head.addText(t.limitsTitle), Font.semiboldSystemFont(L.titleFont), TEXT_PRIMARY, 1);
  head.addSpacer(null);
  style(head.addText(t.liveStatus), Font.mediumSystemFont(L.metaFont), TEXT_MUTED, 1);
  widget.addSpacer(6);
  addHairline(widget, 0);
  largeEntries(accounts, info.lang).forEach((e, i) => {
    if (i > 0) addHairline(widget, INDENT);
    addLargeRow(widget, e, info);
  });
  widget.addSpacer(null);
  addHairline(widget, 0);
  const foot = addRow(widget);
  if (info.updated !== null) {
    style(foot.addText(agesText(info)), Font.mediumSystemFont(L.metaFont), TEXT_MUTED, 1);
  }
  foot.addSpacer(null);
  if (info.allOk) addDot(foot);
}

function buildUsageWidget(accounts, sources, family, now, lang) {
  const widget = new ListWidget();
  widget.backgroundColor = PANEL;
  const info = {
    lang,
    now,
    // The oldest source. The small widget shows it, and with one source it is the whole header text.
    updated: sources.length > 0 ? Math.min(...sources.map((s) => s.at)) : null,
    sources,
    // The green dot means fresh data: it shows only when every account is ok.
    allOk: accounts.every((acc) => acc.status === "ok"),
  };
  if (family === "small") buildSmall(widget, accounts, info);
  else if (family === "large") buildLarge(widget, accounts, info);
  else buildMedium(widget, accounts, info);
  return widget;
}

// A message widget. The key is "noData" or "failed", and the text comes from the same language table.
function buildMessageWidget(family, lang, key) {
  const widget = new ListWidget();
  widget.backgroundColor = PANEL;
  widget.setPadding(12, 12, 12, 12);
  widget.addSpacer(null);
  const msg = widget.addText(TEXT[lang][key]);
  style(msg, Font.systemFont(family === "small" ? 13 : 15), TEXT_MUTED, 3);
  msg.centerAlignText();
  widget.addSpacer(null);
  return widget;
}

async function loadUsage() {
  try {
    const fm = FileManager.iCloud();
    const path = fm.joinPath(fm.documentsDirectory(), FILE_NAME);
    try {
      // Downloads the file from iCloud when needed. Resolves at once for a file that is not in iCloud.
      await fm.downloadFileFromiCloud(path);
    } catch (e) {
      // Offline or not downloadable: use the local copy if there is one.
    }
    if (!fm.fileExists(path)) return null;
    const text = fm.readString(path);
    if (typeof text !== "string") return null;
    const data = JSON.parse(text);
    return isObject(data) && Array.isArray(data.accounts) ? data : null;
  } catch (e) {
    return null;
  }
}

// ---------------------------------------------------------------------------------------------------------------
// ChatGPT on this iPhone, without the Mac. The login is the Codex CLI's device code login.
// The endpoints and fields are those of the Codex CLI's login and usage calls (see the CHATGPT table). The tokens
// stay in this iPhone's Keychain. The app shows the panel (consent, device code, connected). A widget run never
// shows anything: it reads the Keychain, refreshes the token when it must, and reads the usage.
// ---------------------------------------------------------------------------------------------------------------
const CHATGPT = {
  clientId: "app_EMoamEEZ73f0CkXaXp7hrann",
  usercodeUrl: "https://auth.openai.com/api/accounts/deviceauth/usercode",
  pollUrl: "https://auth.openai.com/api/accounts/deviceauth/token",
  tokenUrl: "https://auth.openai.com/oauth/token",
  devicePageUrl: "https://auth.openai.com/codex/device",
  redirectUri: "https://auth.openai.com/deviceauth/callback",
  usageUrl: "https://chatgpt.com/backend-api/wham/usage",
  accountClaim: "https://api.openai.com/auth",
  deviceTimeoutMs: 15 * 60 * 1000,
  minPollSeconds: 5,
  requestTimeoutSeconds: 12,
  expiryMarginMs: 60 * 1000,
  widgetCacheMs: 5 * 60 * 1000,
  liveGapMs: 30 * 1000,
  rateBackoffMs: 5 * 60 * 1000,
  lockMs: 30 * 1000,
};
const KEY = {
  tokens: "ai-usage.chatgpt.tokens",
  pending: "ai-usage.chatgpt.pending",
  cache: "ai-usage.chatgpt.cache",
  status: "ai-usage.chatgpt.status",
  lock: "ai-usage.chatgpt.lock",
};
const JSON_HEADERS = { "Content-Type": "application/json", Accept: "application/json" };
const FORM_HEADERS = { "Content-Type": "application/x-www-form-urlencoded", Accept: "application/json" };
// The answers that mean the refresh token is refused for good.
const REFUSED_CODES = ["invalid_grant", "refresh_token_expired", "refresh_token_reused", "refresh_token_invalidated"];
const B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
// Plan names as the collector shows them (CODEX_PLANS in collector/ai_usage_collect.py).
const CODEX_PLAN_NAMES = {
  prolite: "Pro Lite", pro: "Pro", plus: "Plus", team: "Team", business: "Business",
  enterprise: "Enterprise", free: "Free", go: "Go",
};
// The names of the "Updated" sources, used when the header names both.
const SOURCE_NAME = { mac: "Mac", chatgpt: "ChatGPT" };

// Parses JSON text. Anything else gives null, and the parser's own message is never kept, because it can quote the text.
function parseJSONText(text) {
  if (typeof text !== "string") return null;
  try {
    return JSON.parse(text);
  } catch (e) {
    return null;
  }
}

function base64UrlBytes(text) {
  const s = text.replace(/-/g, "+").replace(/_/g, "/").replace(/=+$/, "");
  const bytes = [];
  let buf = 0;
  let bits = 0;
  for (let i = 0; i < s.length; i++) {
    const v = B64.indexOf(s.charAt(i));
    if (v < 0) return null;
    buf = ((buf << 6) | v) & 0xffffff;
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      bytes.push((buf >> bits) & 0xff);
    }
  }
  return bytes;
}

function utf8Text(bytes) {
  if (bytes === null) return null;
  let pct = "";
  for (let i = 0; i < bytes.length; i++) pct += "%" + (bytes[i] < 16 ? "0" : "") + bytes[i].toString(16);
  try {
    return decodeURIComponent(pct);
  } catch (e) {
    return null;
  }
}

// The claims of a JWT's payload, or null. They are read, not verified: the tokens come from the provider over HTTPS.
function jwtClaims(token) {
  if (typeof token !== "string") return null;
  const parts = token.split(".");
  if (parts.length < 3) return null;
  const claims = parseJSONText(utf8Text(base64UrlBytes(parts[1])));
  return isObject(claims) ? claims : null;
}

// The expiry of an access token in ms (its JWT exp claim), or null when it has none.
function expiryOf(token) {
  const claims = jwtClaims(token);
  const exp = claims ? numOrNull(claims.exp) : null;
  return exp !== null ? exp * 1000 : null;
}

// The account id from the id token's OpenAI claim. The id token itself is never kept: it holds the email.
function accountIdOf(idToken) {
  const claims = jwtClaims(idToken);
  const auth = claims && isObject(claims[CHATGPT.accountClaim]) ? claims[CHATGPT.accountClaim] : null;
  return auth ? cleanText(auth.chatgpt_account_id) : null;
}

// The Keychain never throws into the script: a missing key, or a Keychain that cannot be read (a locked iPhone),
// reads as no value. Values are plain strings; JSON is written and read as text.
function keyRead(key) {
  try {
    if (!Keychain.contains(key)) return null;
    const value = Keychain.get(key);
    return typeof value === "string" ? value : null;
  } catch (e) {
    return null;
  }
}

function keyWrite(key, value) {
  try {
    Keychain.set(key, value);
    return true;
  } catch (e) {
    return false;
  }
}

function keyRemove(key) {
  try {
    if (Keychain.contains(key)) Keychain.remove(key);
  } catch (e) {
    // Nothing to remove, or the Keychain is locked. The value stays, and the next run tries again.
  }
}

function objRead(key) {
  const parsed = parseJSONText(keyRead(key));
  return isObject(parsed) ? parsed : null;
}

function objWrite(key, obj) {
  return keyWrite(key, JSON.stringify(obj));
}

// Only the fields the script uses are read back, and each one is checked.
function tokensOf(v) {
  if (!isObject(v) || typeof v.access_token !== "string" || typeof v.refresh_token !== "string") return null;
  return {
    access_token: v.access_token,
    refresh_token: v.refresh_token,
    account_id: typeof v.account_id === "string" ? v.account_id : null,
    access_exp_ms: numOrNull(v.access_exp_ms),
  };
}

function pendingOf(v) {
  if (!isObject(v) || typeof v.device_auth_id !== "string" || typeof v.user_code !== "string") return null;
  const deadline = numOrNull(v.deadline_ms);
  if (deadline === null) return null;
  const interval = numOrNull(v.interval_s);
  return {
    device_auth_id: v.device_auth_id,
    user_code: v.user_code,
    interval_s: interval !== null && interval >= CHATGPT.minPollSeconds ? interval : CHATGPT.minPollSeconds,
    deadline_ms: deadline,
  };
}

function cacheOf(v) {
  if (!isObject(v)) return null;
  return {
    updated_ms: numOrNull(v.updated_ms),
    plan: cleanText(v.plan),
    limits: Array.isArray(v.limits) ? v.limits : [],
    credits: isObject(v.credits) ? v.credits : null,
    next_try_ms: numOrNull(v.next_try_ms),
  };
}

// The state of this iPhone's ChatGPT login: "connected" (tokens are stored), "reconnect" (the login was refused for
// good), "pending" (a device code is waiting for approval) or "none". The usage cache holds no secret.
function chatgptState() {
  const tokens = tokensOf(objRead(KEY.tokens));
  const cache = cacheOf(objRead(KEY.cache));
  if (tokens) return { kind: "connected", tokens, cache, pending: null };
  if (keyRead(KEY.status) === "reconnect") return { kind: "reconnect", tokens: null, cache, pending: null };
  const pending = pendingOf(objRead(KEY.pending));
  if (pending) return { kind: "pending", tokens: null, cache: null, pending };
  return { kind: "none", tokens: null, cache: null, pending: null };
}

function tokensWrite(tokens) {
  if (!objWrite(KEY.tokens, tokens)) return false;
  keyRemove(KEY.status);
  return true;
}

function cacheWrite(cache) {
  objWrite(KEY.cache, cache);
}

// A refused login is removed only while the stored refresh token is still the one that was refused. Another run may
// have rotated it already; then nothing is removed. Returns true when the login was removed.
function reconnectIfStill(refreshToken) {
  const stored = tokensOf(objRead(KEY.tokens));
  if (stored !== null && stored.refresh_token !== refreshToken) return false;
  keyRemove(KEY.tokens);
  keyRemove(KEY.pending);
  keyRemove(KEY.cache);
  keyWrite(KEY.status, "reconnect");
  return true;
}

// Disconnect removes this iPhone's copy only. The provider is not told: its revoke request format was not read.
function chatgptDisconnect() {
  [KEY.tokens, KEY.pending, KEY.cache, KEY.status, KEY.lock].forEach((key) => keyRemove(key));
}

// A best-effort lock, so that two runs do not refresh the same refresh token at once. It is not atomic, which is why a
// refused refresh is checked again against the Keychain (see refreshTokens).
function lockTake(now) {
  const held = numOrNull(keyRead(KEY.lock));
  if (held !== null && now - held < CHATGPT.lockMs) return false;
  return keyWrite(KEY.lock, String(now));
}

function lockDrop() {
  keyRemove(KEY.lock);
}

// One HTTP call. It gives the status (null when the call did not finish) and the body text. It never throws, and a
// body is never put into an error, so nothing secret can reach a log.
async function httpCall(method, url, headers, body) {
  const req = new Request(url);
  req.method = method;
  req.headers = headers;
  if (body !== undefined) req.body = body;
  req.timeoutInterval = CHATGPT.requestTimeoutSeconds;
  let text = null;
  try {
    text = await req.loadString();
  } catch (e) {
    text = null;
  }
  const response = req.response;
  const status = response && typeof response.statusCode === "number" ? response.statusCode : null;
  return { status, text: typeof text === "string" ? text : null };
}

// Asks for a device code. Null when that fails. The device id is kept for polling and is never shown.
async function deviceStart(now) {
  const r = await httpCall("POST", CHATGPT.usercodeUrl, JSON_HEADERS, JSON.stringify({ client_id: CHATGPT.clientId }));
  const d = r.status === 200 ? parseJSONText(r.text) : null;
  if (!isObject(d) || cleanText(d.device_auth_id) === null || cleanText(d.user_code) === null) return null;
  return pendingOf({
    device_auth_id: cleanText(d.device_auth_id),
    user_code: cleanText(d.user_code),
    interval_s: numOrNull(d.interval),
    deadline_ms: now + CHATGPT.deviceTimeoutMs,
  });
}

// One poll of the device login: "pending" while the user has not approved it (HTTP 403 or 404), "approved" with the
// code and its verifier, or "error".
async function devicePoll(pending) {
  const body = JSON.stringify({ device_auth_id: pending.device_auth_id, user_code: pending.user_code });
  const r = await httpCall("POST", CHATGPT.pollUrl, JSON_HEADERS, body);
  if (r.status === 403 || r.status === 404) return { result: "pending" };
  const d = r.status === 200 ? parseJSONText(r.text) : null;
  if (!isObject(d) || typeof d.authorization_code !== "string" || typeof d.code_verifier !== "string") {
    return { result: "error" };
  }
  return { result: "approved", code: d.authorization_code, verifier: d.code_verifier };
}

// The body of the token exchange for a device code: form encoded, as the Codex CLI sends it. The field list comes
// from the Codex source. The binary has grant_type, authorization_code,
// code_verifier and the /deviceauth/callback redirect; the full field list is pinned by a test.
function exchangeBody(code, verifier) {
  return "grant_type=authorization_code" +
    "&code=" + encodeURIComponent(code) +
    "&redirect_uri=" + encodeURIComponent(CHATGPT.redirectUri) +
    "&client_id=" + encodeURIComponent(CHATGPT.clientId) +
    "&code_verifier=" + encodeURIComponent(verifier);
}

// The token set from a token response. A refresh that returns no new refresh token keeps the old one. The id token is
// read for the account id only.
function tokensFrom(d, previous) {
  const access = cleanText(d.access_token);
  const refresh = cleanText(d.refresh_token) || (previous !== null ? previous.refresh_token : null);
  if (access === null || refresh === null) return null;
  const accountId = accountIdOf(d.id_token) || (previous !== null ? previous.account_id : null);
  const exp = expiryOf(access);
  const seconds = numOrNull(d.expires_in);
  let expMs = null;
  if (exp !== null) expMs = exp;
  else if (seconds !== null) expMs = Date.now() + seconds * 1000;
  return { access_token: access, refresh_token: refresh, account_id: accountId || null, access_exp_ms: expMs };
}

// Exchanges an approved device code for tokens and saves them. Returns the token set, or null.
async function deviceExchange(approved) {
  const r = await httpCall("POST", CHATGPT.tokenUrl, FORM_HEADERS, exchangeBody(approved.code, approved.verifier));
  const d = r.status === 200 ? parseJSONText(r.text) : null;
  const tokens = isObject(d) ? tokensFrom(d, null) : null;
  return tokens !== null && tokensWrite(tokens) ? tokens : null;
}

// True when the refusal is for good: HTTP 401, or a 400 that names one of REFUSED_CODES.
function refusedForGood(r) {
  if (r.status === 401) return true;
  if (r.status !== 400) return false;
  const d = parseJSONText(r.text);
  if (!isObject(d)) return false;
  let code = null;
  if (typeof d.error === "string") code = d.error;
  else if (isObject(d.error) && typeof d.error.code === "string") code = d.error.code;
  return code !== null && REFUSED_CODES.indexOf(code) >= 0;
}

// The error code for a status that the provider did not accept (the same mapping as the collector's http_error_code).
function codeOfStatus(status) {
  if (status === null) return "network";
  if (status === 429) return "rate_limited";
  if (status >= 500) return "server_error";
  return "unknown";
}

// Refreshes the token set. Returns { tokens } (saved), { relogin: true } (refused for good), { locked: true } (another
// run is refreshing now) or { failed: code } for a failure that keeps the stored login.
async function refreshTokens(tokens, now) {
  if (!lockTake(now)) return { locked: true };
  try {
    const body = JSON.stringify({ grant_type: "refresh_token", client_id: CHATGPT.clientId, refresh_token: tokens.refresh_token });
    const r = await httpCall("POST", CHATGPT.tokenUrl, JSON_HEADERS, body);
    if (r.status === 200) {
      const d = parseJSONText(r.text);
      const next = isObject(d) ? tokensFrom(d, tokens) : null;
      if (next !== null && tokensWrite(next)) return { tokens: next };
      return { failed: "unknown" };
    }
    if (refusedForGood(r)) {
      const stored = tokensOf(objRead(KEY.tokens));
      // Another run rotated the token while this one was waiting. Its tokens are the good ones.
      if (stored !== null && stored.refresh_token !== tokens.refresh_token) return { tokens: stored };
      return reconnectIfStill(tokens.refresh_token) ? { relogin: true } : { failed: "unknown" };
    }
    return { failed: codeOfStatus(r.status) };
  } finally {
    lockDrop();
  }
}

// The token set to use now. It is refreshed first when the access token ends within the margin. An unknown expiry is
// not refreshed here: a refused usage call refreshes it instead.
async function usableTokens(tokens, now) {
  const exp = tokens.access_exp_ms;
  if (exp === null || exp - now >= CHATGPT.expiryMarginMs) return { tokens };
  return refreshTokens(tokens, now);
}

// One call to the usage endpoint: the status, and on 200 the parsed document.
async function usageCall(tokens) {
  const headers = { Authorization: "Bearer " + tokens.access_token, Accept: "application/json", "User-Agent": "codex_cli_rs" };
  if (tokens.account_id) headers["ChatGPT-Account-Id"] = tokens.account_id;
  const r = await httpCall("GET", CHATGPT.usageUrl, headers, undefined);
  return { status: r.status, doc: r.status === 200 ? parseJSONText(r.text) : null };
}

// The plan's name, as the collector shows it.
function planNameOf(raw) {
  if (typeof raw !== "string" || raw.trim() === "") return null;
  const key = raw.trim().toLowerCase();
  if (Object.prototype.hasOwnProperty.call(CODEX_PLAN_NAMES, key)) return CODEX_PLAN_NAMES[key];
  return raw.trim().replace(/_/g, " ").split(" ").map((w) => (w ? w.charAt(0).toUpperCase() + w.slice(1).toLowerCase() : w)).join(" ");
}

// The Thai window label that the collector writes (window_label). The widget builds its own label from window_seconds.
function windowLabelTH(seconds) {
  if (seconds === null || seconds <= 0) return "ช่วงเวลา";
  if (seconds === 18000) return "5 ชม.";
  if (seconds === 604800) return "สัปดาห์";
  if (seconds % 86400 === 0) return seconds / 86400 + " วัน";
  if (seconds % 3600 === 0) return seconds / 3600 + " ชม.";
  return Math.round(seconds / 60) + " นาที";
}

// A reset time in ms: an ISO text, or unix seconds (unix milliseconds when the number is large).
function resetMsOf(v) {
  if (typeof v === "number" && isFinite(v)) return Math.abs(v) > 1e11 ? v : v * 1000;
  return timeOf(v);
}

function isoOf(ms) {
  try {
    return new Date(ms).toISOString();
  } catch (e) {
    return null;
  }
}

// The limits, credits and plan of a wham/usage document (a port of parse_codex_usage in the collector). Null when the
// document has no limit.
function parseUsage(doc, now) {
  if (!isObject(doc)) return null;
  const rate = isObject(doc.rate_limit) ? doc.rate_limit : {};
  const limits = [];
  [["primary_window", "primary"], ["secondary_window", "secondary"]].forEach((pair) => {
    const w = rate[pair[0]];
    if (!isObject(w)) return;
    const used = numOrNull(w.used_percent);
    if (used === null) return;
    let reset = resetMsOf(w.reset_at);
    if (reset === null) {
      const after = numOrNull(w.reset_after_seconds);
      if (after !== null) reset = now + after * 1000;
    }
    const len = numOrNull(w.limit_window_seconds);
    const seconds = len !== null && len > 0 ? Math.floor(len) : null;
    limits.push({
      key: pair[1],
      label: windowLabelTH(seconds),
      used_percent: Math.min(100, Math.max(0, used)),
      resets_at: reset !== null ? isoOf(reset) : null,
      window_seconds: seconds,
    });
  });
  if (limits.length === 0) return null;
  let credits = null;
  if (isObject(doc.credits)) {
    const balance = numOrNull(doc.credits.balance);
    credits = {
      extra_usage_enabled: !!doc.credits.has_credits,
      used_usd: null,
      limit_usd: null,
      balance_usd: balance !== null ? Math.round(balance * 100) / 100 : null,
    };
  }
  return { plan: planNameOf(doc.plan_type), limits, credits };
}

// A schema-1 account for this iPhone's ChatGPT login. The status and error_code values are the collector's.
function chatgptAccount(parts) {
  const code = parts.errorCode || null;
  return {
    id: "codex-iphone",
    provider: "codex",
    label: "ChatGPT",
    plan: parts.plan || null,
    status: parts.status,
    error: code ? (TEXT.th.errors[code] || null) : null,
    error_code: code,
    updated_at: typeof parts.updatedMs === "number" ? isoOf(parts.updatedMs) : null,
    limits: parts.limits || [],
    usage: null,
    credits: parts.credits || null,
  };
}

// The row for fresh data, from the cache.
function rowFromCache(cache) {
  return chatgptAccount({
    plan: cache.plan,
    limits: cache.limits,
    credits: cache.credits,
    updatedMs: cache.updated_ms,
    status: "ok",
    errorCode: null,
  });
}

// The row for a failed run: the last good data as stale when there is any, else an error row with no limits.
function staleRow(cache, errorCode) {
  if (cache === null || cache.updated_ms === null) {
    return chatgptAccount({ plan: null, limits: [], credits: null, updatedMs: null, status: "error", errorCode });
  }
  return chatgptAccount({
    plan: cache.plan,
    limits: cache.limits,
    credits: cache.credits,
    updatedMs: cache.updated_ms,
    status: "stale",
    errorCode,
  });
}

// The row from a usage call: fresh data is cached, a rate limit waits before the next call, anything else keeps the
// last good data.
function rowFromCall(call, cache, now) {
  if (call.status === 200) {
    const parsed = parseUsage(call.doc, now);
    if (parsed === null) return staleRow(cache, "unknown");
    cacheWrite({ updated_ms: now, plan: parsed.plan, limits: parsed.limits, credits: parsed.credits, next_try_ms: null });
    return rowFromCache({ updated_ms: now, plan: parsed.plan, limits: parsed.limits, credits: parsed.credits });
  }
  if (call.status === 429) {
    const base = cache || { updated_ms: null, plan: null, limits: [], credits: null, next_try_ms: null };
    cacheWrite(Object.assign({}, base, { next_try_ms: now + CHATGPT.rateBackoffMs }));
    return staleRow(cache, "rate_limited");
  }
  return staleRow(cache, codeOfStatus(call.status));
}

// The ChatGPT row of a connected login. Widget runs use the cache when it is fresh and wait after a rate limit. App runs
// are live. A refused login becomes the reconnect row.
async function connectedRow(state, mode, now) {
  const cache = state.cache;
  const hasData = cache !== null && cache.updated_ms !== null;
  const gap = mode === "widget" ? CHATGPT.widgetCacheMs : CHATGPT.liveGapMs;
  if (hasData && now - cache.updated_ms < gap) return rowFromCache(cache);
  if (cache !== null && cache.next_try_ms !== null && now < cache.next_try_ms) return staleRow(cache, "rate_limited");
  const first = await usableTokens(state.tokens, now);
  if (first.relogin) return staleRow(null, "relogin_needed");
  if (first.locked) return hasData ? rowFromCache(cache) : null;
  if (first.failed) return staleRow(cache, first.failed);
  let tokens = first.tokens;
  let call = await usageCall(tokens);
  if (call.status === 401) {
    const again = await refreshTokens(tokens, now);
    if (again.relogin) return staleRow(null, "relogin_needed");
    if (again.locked) return hasData ? rowFromCache(cache) : null;
    if (again.failed) return staleRow(cache, again.failed);
    tokens = again.tokens;
    call = await usageCall(tokens);
    if (call.status === 401) {
      return reconnectIfStill(tokens.refresh_token) ? staleRow(null, "relogin_needed") : staleRow(cache, "unknown");
    }
  }
  return rowFromCall(call, cache, now);
}

// This run's ChatGPT part. It never throws. owns is true when this iPhone's login stands in for the Mac's ChatGPT rows.
async function chatgptPart(mode, now) {
  const state = chatgptState();
  if (state.kind === "none" || state.kind === "pending") return { owns: false, row: null };
  if (state.kind === "reconnect") return { owns: true, row: staleRow(null, "relogin_needed") };
  try {
    return { owns: true, row: await connectedRow(state, mode, now) };
  } catch (e) {
    return { owns: true, row: staleRow(state.cache, "unknown") };
  }
}

// The accounts to show. The phone's ChatGPT row takes the place of the Mac copy's codex rows (at the first of them, or at
// the end). Claude and agy still come from the Mac copy. Without a login, the Mac copy is shown as it is.
function mergeAccounts(macAccounts, part) {
  if (!part.owns) return macAccounts.slice();
  const out = [];
  let placed = false;
  macAccounts.forEach((acc) => {
    if (acc.provider !== "codex") {
      out.push(acc);
      return;
    }
    if (!placed && part.row !== null) out.push(part.row);
    placed = true;
  });
  if (!placed && part.row !== null) out.push(part.row);
  return out;
}

// The "Updated" sources: the Mac copy when it still contributes accounts, and the phone's ChatGPT row when it has a time.
function sourcesOf(usage, accounts, part) {
  const out = [];
  const macAccounts = accounts.filter((acc) => acc !== part.row);
  if (usage && macAccounts.length > 0) {
    const at = updatedAtOf(usage, macAccounts);
    if (at !== null) out.push({ name: "mac", at });
  }
  if (part.row !== null && part.row.updated_at) {
    const at = timeOf(part.row.updated_at);
    if (at !== null) out.push({ name: "chatgpt", at });
  }
  return out;
}

// The age text of the header and the footer. One source reads as before; two sources name each one.
function agesText(info) {
  if (info.sources.length > 1) {
    return info.sources.map((s) => SOURCE_NAME[s.name] + " " + agoText(s.at, info.now, info.lang)).join(" · ");
  }
  return ageText(info.updated, info.now, info.lang);
}

function errorNameOf(e) {
  return e && typeof e.name === "string" ? e.name : "Error";
}

// Waits without a visible screen. Timer.schedule fires once when the time is up.
function waitMs(ms) {
  return new Promise((resolve) => {
    Timer.schedule(ms, false, resolve);
  });
}

// A text row of the ChatGPT table. The options: header (a highlighted row), font, center.
function textRow(table, title, opts) {
  const o = opts || {};
  const row = new UITableRow();
  const cell = row.addText(title);
  if (o.font) cell.titleFont = o.font;
  if (o.center) cell.centerAligned();
  row.isHeader = o.header === true;
  table.addRow(row);
}

// A button row of the ChatGPT table. It closes the table only when dismiss is true.
function buttonRow(table, title, onTap, dismiss, color) {
  const row = new UITableRow();
  const cell = row.addButton(title);
  cell.onTap = onTap;
  cell.dismissOnTap = dismiss === true;
  if (color) cell.titleColor = color;
  table.addRow(row);
}

// A row that closes the table when it is tapped (dismissOnSelect is true by default).
function doneRow(table, title) {
  const row = new UITableRow();
  row.addText(title);
  row.dismissOnSelect = true;
  row.onSelect = () => {};
  table.addRow(row);
}

// The first alert: consent. Resolves true for "Consent and connect". The reconnect line and the start-failed line are
// one line each, added above the text. The warning comes last.
async function consentAlert(lang, reconnect, note) {
  const t = TEXT[lang].chatgpt;
  const alert = new Alert();
  alert.title = t.title;
  const body = [reconnect ? t.reconnect : null, note === "start" ? t.startFailed : null, t.consentBody]
    .filter((line) => line !== null)
    .join("\n");
  // The Mac's direct-mode warning, word for word. It comes last, after a blank line.
  alert.message = body + "\n\n" + t.consentWarning;
  alert.addAction(t.accept);
  alert.addCancelAction(t.later);
  const index = await alert.present();
  return index === 0;
}

// Draws the table for the panel's phase: "code" (the device code), "connected" or "timeout".
function renderView(table, view) {
  const t = TEXT[view.lang].chatgpt;
  table.removeAllRows();
  if (view.phase === "code") {
    const code = view.pending.user_code;
    const minutes = Math.max(0, Math.ceil((view.pending.deadline_ms - Date.now()) / 60000));
    textRow(table, t.title, { header: true });
    textRow(table, code, { font: Font.boldSystemFont(30), center: true });
    textRow(table, t.codeHint);
    textRow(table, view.note === "failed" ? t.checkFailed : view.note === "copied" ? t.copied : t.waiting);
    textRow(table, t.expiresIn(minutes));
    buttonRow(table, t.openPage, () => {
      Safari.open(CHATGPT.devicePageUrl);
    }, false, null);
    buttonRow(table, t.copyCode, () => {
      Pasteboard.copyString(code);
      view.note = "copied";
      renderView(table, view);
    }, false, null);
  } else if (view.phase === "connected") {
    textRow(table, t.connected, { header: true });
    if (view.plan) textRow(table, t.plan(view.plan));
    doneRow(table, t.done);
    buttonRow(table, t.disconnect, () => {
      chatgptDisconnect();
    }, true, DRAWN.red);
  } else {
    textRow(table, t.title, { header: true });
    textRow(table, t.timedOut);
    doneRow(table, t.done);
  }
  table.reload();
}

// Polls the device login while the panel is open. The first poll comes one interval after the panel opens. The loop
// stops when the table closes, when the login is approved and connected, or when the code times out.
async function pollLoop(table, view) {
  while (!view.closed && view.phase === "code") {
    await waitMs(view.pending.interval_s * 1000);
    if (view.closed || view.phase !== "code") return;
    if (Date.now() >= view.pending.deadline_ms) {
      keyRemove(KEY.pending);
      view.phase = "timeout";
      renderView(table, view);
      return;
    }
    const outcome = await devicePoll(view.pending);
    if (outcome.result === "approved") {
      const tokens = await deviceExchange(outcome);
      if (tokens === null) {
        view.note = "failed";
      } else {
        keyRemove(KEY.pending);
        view.phase = "connected";
        const call = await usageCall(tokens);
        const parsed = call.status === 200 ? parseUsage(call.doc, Date.now()) : null;
        if (parsed !== null) {
          cacheWrite({ updated_ms: Date.now(), plan: parsed.plan, limits: parsed.limits, credits: parsed.credits, next_try_ms: null });
        }
        view.plan = parsed !== null ? parsed.plan : null;
      }
    } else {
      view.note = outcome.result === "pending" ? null : "failed";
    }
    if (!view.closed) renderView(table, view);
  }
}

// Screen 2, the device code. One table: the code, the status, the time left and the two buttons.
// It polls by itself while it is open. Closing the table stops the polling; the pending login stays for the next run.
async function codePanel(lang, pending, startNote) {
  const table = new UITable();
  const view = { lang, phase: "code", pending, note: startNote, plan: null, closed: false };
  const closed = table.present(false).then(() => {
    view.closed = true;
  });
  if (Date.now() >= pending.deadline_ms) {
    keyRemove(KEY.pending);
    view.phase = "timeout";
  }
  renderView(table, view);
  pollLoop(table, view).catch(() => {
    view.note = "failed";
    if (!view.closed) renderView(table, view);
  });
  await closed;
}

// Screen 3, connected: the plan, Done and the red Disconnect. The plan is the one from the last good usage call.
async function connectedPanel(lang, cache) {
  const table = new UITable();
  const view = {
    lang,
    phase: "connected",
    pending: null,
    note: null,
    plan: cache !== null && cache.plan ? cache.plan : null,
    closed: false,
  };
  const closed = table.present(false).then(() => {
    view.closed = true;
  });
  renderView(table, view);
  await closed;
}

// The ChatGPT menu. It runs in the app only, never in a widget run. A stored login opens the connected panel, a pending
// code opens the code panel again, and otherwise the consent alert comes first.
async function openChatGPTMenu(lang) {
  const state = chatgptState();
  if (state.kind === "connected") return connectedPanel(lang, state.cache);
  if (state.kind === "pending") return codePanel(lang, state.pending, null);
  const reconnect = state.kind === "reconnect";
  let note = null;
  for (;;) {
    const accepted = await consentAlert(lang, reconnect, note);
    if (!accepted) return;
    const pending = await deviceStart(Date.now());
    if (pending !== null && objWrite(KEY.pending, pending)) {
      keyRemove(KEY.status);
      return codePanel(lang, pending, null);
    }
    note = "start";
  }
}

function familyFor(cfg) {
  if (!cfg.runsInWidget) return "medium";
  return cfg.widgetFamily === "small" || cfg.widgetFamily === "large" ? cfg.widgetFamily : "medium";
}

async function main() {
  const family = familyFor(config);
  // Resolved before the try, and it cannot throw, so the no-data and failure widgets have a language too.
  const lang = languageOf();
  let widget;
  // The app shows the ChatGPT menu first. A widget run never does: it has no screen to show a prompt on.
  if (config.runsInApp === true) {
    try {
      await openChatGPTMenu(lang);
    } catch (e) {
      // A failing menu must not stop the preview. Only the error's name is logged, never its text.
      console.error("ChatGPT menu: " + errorNameOf(e));
    }
  }
  try {
    const usage = await loadUsage();
    const part = await chatgptPart(config.runsInApp === true ? "app" : "widget", Date.now());
    const macAccounts = usage ? usage.accounts.filter(isObject) : [];
    const accounts = mergeAccounts(macAccounts, part);
    widget = accounts.length > 0
      ? buildUsageWidget(accounts, sourcesOf(usage, accounts, part), family, Date.now(), lang)
      : buildMessageWidget(family, lang, "noData");
  } catch (e) {
    console.error(String(e));
    widget = buildMessageWidget(family, lang, "failed");
  }
  widget.refreshAfterDate = new Date(Date.now() + REFRESH_MINUTES * 60 * 1000);
  if (config.runsInWidget) {
    Script.setWidget(widget);
  } else {
    await widget.presentMedium();
  }
  Script.complete();
}

try {
  await main();
} catch (e) {
  console.error(String(e));
  Script.complete();
}
