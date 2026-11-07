const test = require("node:test")
const assert = require("node:assert")
const fs = require("node:fs")
const path = require("node:path")

// Model.js starts with `.pragma library`, which QML needs and Node can't
// parse, so it's loaded with that line stripped.
const source = fs.readFileSync(path.join(__dirname, "..", "Model.js"), "utf8").replace(/^\.pragma library\s*/, "")
const mod = { exports: {} }
new Function("module", source)(mod)
const Model = mod.exports

test("reads a successful listing", () => {
  const r = Model.parseResult(JSON.stringify({
    ok: true, today: "2026-11-06",
    tasks: [{ id: "1", content: "a", overdue: true }, { id: "2", content: "b", overdue: false }, { content: "no id" }]
  }), 0)
  assert.equal(r.ok, true)
  assert.equal(r.count, 2)
  assert.equal(r.overdue, 1)
  assert.equal(r.today, "2026-11-06")
})

test("reports failures by kind", () => {
  assert.equal(Model.parseResult("", 127).error, "missing")
  const auth = Model.parseResult('{"ok":false,"error":"auth","message":"Not signed in."}', 1)
  assert.equal(auth.ok, false)
  assert.equal(auth.error, "auth")
  assert.equal(Model.parseResult("garbage", 1).error, "api")
  assert.equal(Model.parseResult("", 1).ok, false)
})

test("removes a completed task", () => {
  assert.deepEqual(Model.withoutTask([{ id: "1" }, { id: "2" }], "1"), [{ id: "2" }])
})

test("shows a time today and a date when overdue", () => {
  assert.deepEqual(Model.whenKey({ due: { date: "2026-11-05", time: null } }, "2026-11-06"), { kind: "date", value: "2026-11-05" })
  assert.deepEqual(Model.whenKey({ due: { date: "2026-11-06", time: "09:30" } }, "2026-11-06"), { kind: "time", value: "09:30" })
  assert.deepEqual(Model.whenKey({ due: null }, "2026-11-06"), { kind: "none", value: "" })
})

test("keeps the refresh interval sane", () => {
  assert.equal(Model.clampMinutes("x"), 5)
  assert.equal(Model.clampMinutes(0), 5)
  assert.equal(Model.clampMinutes(1000), 120)
  assert.equal(Model.clampMinutes(3), 3)
})

test("every string the panel uses is in en.json", () => {
  const panel = fs.readFileSync(path.join(__dirname, "..", "Panel.qml"), "utf8")
  const catalog = JSON.parse(fs.readFileSync(path.join(__dirname, "..", "i18n", "en.json"), "utf8"))
  const keys = [...panel.matchAll(/strings\.tn?\("([^"]+)"/g)].map(m => m[1])
  assert.ok(keys.length > 0)
  for (const key of keys) assert.ok(key in catalog, `missing ${key}`)
})

test("uses the theme's red, orange, and blue for priorities", () => {
  const palette = Model.parsePalette('accent = "#7daea3"\nred = "#ea6962"\norange = "#e1875c"\nblue = "#7daea3"\n')
  assert.equal(palette.red, "#ea6962")
  assert.equal(Model.priorityColor(1, "x", palette), "#ea6962")
  assert.equal(Model.priorityColor(2, "x", palette), "#e1875c")
  assert.equal(Model.priorityColor(4, "x", palette), "x")
  assert.equal(Model.priorityColor(1, "x", {}), "#d1453b")
})
