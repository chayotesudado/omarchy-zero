.pragma library

// Pure helpers for the Zero bar plugin, shared with tests/model.test.js.
// The plugin reads `zero today --json`, whose shape is:
//   {"ok": true, "count": 3, "overdue": 1, "today": "2026-11-06",
//    "tasks": [{"id", "content", "priority" (1 = p1), "overdue",
//               "due": {"date", "time", "recurring"} | null,
//               "project": {"name", "inbox"}, "url"}]}
// or, on failure, {"ok": false, "error": "auth"|"network"|"api", "message"}.

var NOT_INSTALLED = 127

function parseResult(text, exitCode) {
  if (exitCode === NOT_INSTALLED)
    return { ok: false, error: "missing", message: "" }
  var raw = String(text || "").trim()
  var data = null
  try { data = raw ? JSON.parse(raw) : null } catch (e) { data = null }
  if (!data || typeof data !== "object")
    return { ok: false, error: "api", message: raw.slice(0, 200) }
  if (data.ok !== true)
    return { ok: false, error: String(data.error || "api"), message: String(data.message || "") }
  var tasks = Array.isArray(data.tasks) ? data.tasks.filter(function (t) { return t && t.id }) : []
  return {
    ok: true,
    tasks: tasks,
    count: tasks.length,
    overdue: tasks.filter(function (t) { return t.overdue === true }).length,
    today: String(data.today || ""),
    task: data.task || null
  }
}

function withoutTask(tasks, id) {
  return (tasks || []).filter(function (t) { return t.id !== id })
}

// Todoist's priority colors (p1 red, p2 orange, p3 blue) in the Omarchy
// theme's shades of them; p4 has none and uses the fallback.
function priorityColor(priority, fallback, palette) {
  var p = palette || {}
  return priority === 1 ? (p.red || "#d1453b")
       : priority === 2 ? (p.orange || "#eb8909")
       : priority === 3 ? (p.blue || "#246fe0")
       : fallback
}

// The `name = "#rrggbb"` entries of the theme's colors.toml.
function parsePalette(text) {
  var palette = {}
  var re = /^\s*([a-z_]+)\s*=\s*["'](#[0-9a-fA-F]{6})["']/gm
  var m
  while ((m = re.exec(String(text || ""))) !== null) palette[m[1]] = m[2]
  return palette
}

// "09:30" for a timed task due today, the date for an overdue one, else "".
function whenKey(task, today) {
  if (!task || !task.due) return { kind: "none", value: "" }
  if (task.due.date && today && task.due.date < today) return { kind: "date", value: task.due.date }
  if (task.due.time) return { kind: "time", value: task.due.time }
  return { kind: "none", value: "" }
}

function clampMinutes(value) {
  var n = Number(value)
  if (!isFinite(n) || n <= 0) return 5
  return Math.max(1, Math.min(120, Math.round(n)))
}

if (typeof module !== "undefined")
  module.exports = { parseResult: parseResult, withoutTask: withoutTask, priorityColor: priorityColor,
                     whenKey: whenKey, parsePalette: parsePalette, clampMinutes: clampMinutes, NOT_INSTALLED: NOT_INSTALLED }
