import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// Todoist in the bar, through the Zero app's command line: Todoist's mark on
// the bar, and a popup that lists what's due today and overdue with a circle to tick
// each one off, and a box at the bottom adds to the Inbox. The app keeps the
// token (~/.config/zero/token); this plugin never sees it.
Panel {
  id: root
  moduleName: "chayotesudado.zero"
  ipcTarget: "chayotesudado.zero"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color urgent: bar ? bar.urgent : Commons.Color.urgent
  readonly property color accent: Commons.Color.accent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property int refreshMinutes: Model.clampMinutes(setting("refreshMinutes", 5))

  // The last good listing stays on screen through a network hiccup.
  property var tasks: []
  property string today: ""
  property bool loaded: false
  property string errorKind: ""
  property string errorMessage: ""
  property string notice: ""
  readonly property int count: tasks.length
  readonly property bool canOpen: errorKind !== "missing"
  readonly property int overdueCount: tasks.filter(function(t) { return t.overdue === true }).length

  property int cursor: -1
  property bool adding: false

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  // The shell's colors have no red, orange, or blue, so the priority circles
  // read them from the theme itself. A theme switch replaces the file, so it
  // reloads whenever the shell's own colors change too.
  property var palette: ({})
  FileView {
    id: themeColors
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"
    watchChanges: true
    printErrors: false
    onLoaded: root.palette = Model.parsePalette(text())
    onFileChanged: reload()
  }
  Connections {
    target: Commons.Color
    function onAccentChanged() { themeColors.reload() }
    function onForegroundChanged() { themeColors.reload() }
  }

  // ---------------------------------------------------------------- zero

  // One run of `zero <args> --json`. Exit 127 means zero isn't on PATH.
  component ZeroCall: Process {
    id: call
    property var args: []
    property int exitCode: -1
    property bool exited: false
    property bool streamDone: false
    signal result(var parsed)

    command: ["sh", "-c", "command -v zero >/dev/null 2>&1 || exit 127; exec zero \"$@\" --json", "zero"].concat(args)
    stdout: StdioCollector {
      id: collector
      waitForEnd: true
      onStreamFinished: { call.streamDone = true; call.settle() }
    }
    onExited: function(code) { call.exitCode = code; call.exited = true; call.settle() }

    // Exit and end-of-output arrive in either order; answer once both have.
    function settle() {
      if (!exited || !streamDone) return
      exited = false
      streamDone = false
      result(Model.parseResult(collector.text, exitCode))
    }

    function start(newArgs) {
      if (running) return false
      args = newArgs
      exited = false
      streamDone = false
      running = true
      return true
    }
  }

  ZeroCall {
    id: listCall
    onResult: function(r) {
      if (r.ok) {
        root.tasks = r.tasks
        root.today = r.today
        root.loaded = true
        root.errorKind = ""
        root.errorMessage = ""
        root.cursor = Math.min(root.cursor, root.tasks.length - 1)
      } else {
        root.errorKind = r.error
        root.errorMessage = r.message
        // Signed out or uninstalled: there's nothing current to show.
        if (r.error === "auth" || r.error === "missing") {
          root.tasks = []
          root.loaded = true
        }
      }
    }
  }

  // Completions queue up, so ticking several quickly works.
  property var doneQueue: []
  ZeroCall {
    id: doneCall
    onResult: function(r) {
      if (!r.ok) {
        root.errorKind = r.error
        root.errorMessage = r.message
      }
      root.nextDone()
      // Recurring tasks move to their next date; a refresh shows that, and
      // brings back anything that failed.
      if (root.doneQueue.length === 0) root.refresh()
    }
  }

  ZeroCall {
    id: addCall
    onResult: function(r) {
      root.adding = false
      if (r.ok) {
        root.notice = strings.t("add.added").arg(r.task ? r.task.content : "")
        noticeTimer.restart()
        var field = root.addField()
        if (field) field.text = ""
        root.refresh()
      } else {
        root.errorKind = r.error
        root.errorMessage = r.message
      }
    }
  }

  function refresh() {
    if (!listCall.start(["today"])) refreshAgain.restart()
  }

  function complete(id) {
    if (!id) return
    tasks = Model.withoutTask(tasks, id)
    cursor = Math.min(cursor, tasks.length - 1)
    doneQueue = doneQueue.concat([id])
    if (!doneCall.running) nextDone()
  }

  function nextDone() {
    if (doneQueue.length === 0) return
    var id = doneQueue[0]
    doneQueue = doneQueue.slice(1)
    doneCall.start(["done", id])
  }

  function add(text) {
    var trimmed = String(text || "").trim()
    if (trimmed === "" || adding) return
    adding = true
    notice = ""
    addCall.start(["add", trimmed])
  }

  function openApp() {
    Quickshell.execDetached(["omarchy-launch-or-focus", "zero"])
    close()
  }

  function addField() {
    return panel.loadedContent ? panel.loadedContent.addField : null
  }

  function focusAdd() {
    var field = addField()
    if (field) field.forceActiveFocus()
  }

  Timer { id: refreshAgain; interval: 1500; onTriggered: root.refresh() }
  Timer { id: noticeTimer; interval: 3000; onTriggered: root.notice = "" }
  Timer {
    interval: root.refreshMinutes * 60000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  Component.onCompleted: refresh()

  onOpenedChanged: if (opened) {
    cursor = -1
    notice = ""
    refresh()
    Qt.callLater(function() { if (panel.loadedContent) panel.loadedContent.forceActiveFocus() })
  }

  // ---------------------------------------------------------------- text

  function metaText() {
    if (errorKind === "auth" || errorKind === "missing") return ""
    if (!loaded) return strings.t("meta.loading")
    if (count === 0) return strings.t("meta.clear")
    if (overdueCount > 0)
      return strings.tn("meta.countOverdue", count).arg(Commons.I18n.formatNumber(count)).arg(Commons.I18n.formatNumber(overdueCount))
    return strings.tn("meta.count", count).arg(Commons.I18n.formatNumber(count))
  }

  function errorText() {
    if (errorKind === "missing") return strings.t("error.missing")
    if (errorKind === "auth") return strings.t("error.auth")
    if (errorKind === "network") return strings.t("error.network")
    if (errorKind !== "") return strings.t("error.api").arg(errorMessage)
    return ""
  }

  function whenText(task) {
    var when = Model.whenKey(task, today)
    var locale = Qt.locale(Commons.I18n.formatLocale)
    if (when.kind === "time") {
      var p = when.value.split(":")
      return new Date(2000, 0, 1, +p[0], +p[1]).toLocaleTimeString(locale, Locale.ShortFormat)
    }
    if (when.kind === "date") {
      var d = when.value.split("-")
      return new Date(+d[0], +d[1] - 1, +d[2]).toLocaleDateString(locale, "d MMM")
    }
    return ""
  }

  // ---------------------------------------------------------------- IPC

  ShellIpc {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.refresh() }
    // Adds to the Inbox (Todoist quick add), e.g. from a Hyprland binding.
    function add(text: string): string {
      if (String(text || "").trim() === "") return "nothing to add"
      root.add(text)
      return "adding"
    }
    function status(): string {
      return root.errorKind !== "" ? root.errorKind : root.count + " due, " + root.overdueCount + " overdue"
    }
  }

  // ---------------------------------------------------------------- bar

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    iconComponent: tickIcon
    slotSize: Style.bar.iconSlot
    tooltipText: root.errorKind === "auth" || root.errorKind === "missing" ? root.errorText()
      : root.count > 0 ? strings.tn("bar.tooltip", root.count).arg(Commons.I18n.formatNumber(root.count))
      : strings.t("bar.tooltipClear")
    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.openApp()
      else root.toggle()
    }
  }

  Component {
    id: tickIcon
    Item {
      ZeroMark {
        size: button.iconSize
        color: button.foreground
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2
      }
    }
  }

  // Todoist's three stacked check-strokes, without the tile, so they sit on
  // the bar like the other icons and head the popup the same way. Drawn, so
  // it needs no icon font.
  component ZeroMark: Canvas {
    id: mark
    property real size: Style.font.display
    property color color: root.foreground
    width: size
    height: size
    implicitWidth: size
    implicitHeight: size
    onSizeChanged: requestPaint()
    onColorChanged: requestPaint()
    onPaint: {
      var ctx = getContext("2d")
      // The strokes span the icon box: 2..62 across, 3..62 down.
      var s = size / 64
      ctx.reset()
      ctx.strokeStyle = color
      ctx.lineWidth = 8.5 * s
      ctx.lineCap = "round"
      ctx.lineJoin = "round"
      // A steep short arm and a long shallow one, so each still reads
      // as a check at bar size.
      var rows = [17, 34, 51]
      for (var i = 0; i < rows.length; i++) {
        var y = rows[i] * s
        ctx.beginPath()
        ctx.moveTo(6 * s, y - 2 * s)
        ctx.lineTo(19 * s, y + 7 * s)
        ctx.lineTo(58 * s, y - 10 * s)
        ctx.stroke()
      }
    }
  }

  // ---------------------------------------------------------------- panel

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight, Style.space(620))

    content: PanelKeyCatcher {
      id: keys
      property alias addField: addField
      implicitHeight: column.implicitHeight
      anchors.fill: parent
      blocked: addField.activeFocus
      onMoveRequested: function(dx, dy) {
        if (dy === 0 || root.tasks.length === 0) return
        root.cursor = Math.max(0, Math.min(root.tasks.length - 1, root.cursor < 0 ? 0 : root.cursor + dy))
      }
      onActivateRequested: if (root.cursor >= 0 && root.cursor < root.tasks.length) root.complete(root.tasks[root.cursor].id)
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t, modifiers) {
        if (t === "a" || t === "n" || t === "i") root.focusAdd()
        else if (t === "o") root.openApp()
        else if (t === "r") root.refresh()
      }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(12)

        PanelHero {
          width: parent.width
          title: strings.t("title")
          meta: root.metaText()
          foreground: root.foreground
          fontFamily: root.fontFamily
          // The count is already in the meta line, so the hero shows the mark.
          iconComponent: Component {
            ZeroMark {
              size: Style.font.display
              color: root.foreground
            }
          }
        }

        Text {
          visible: text !== ""
          width: parent.width
          textFormat: Text.PlainText
          text: root.errorText()
          color: root.errorKind === "network" ? root.dim : root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        PanelSeparator { foreground: root.foreground; visible: root.tasks.length > 0 }

        Flickable {
          id: list
          width: parent.width
          height: Math.min(taskColumn.implicitHeight, Style.space(380))
          visible: root.tasks.length > 0
          contentWidth: width
          contentHeight: taskColumn.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          interactive: contentHeight > height
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

          Column {
            id: taskColumn
            width: list.width
            spacing: Style.space(2)

            Repeater {
              model: root.tasks
              TaskRow {
                required property var modelData
                required property int index
                width: taskColumn.width
                task: modelData
                hasCursor: root.cursor === index
                onHoveredIn: root.cursor = index
              }
            }
          }
        }

        PanelSeparator { foreground: root.foreground }

        TextField {
          id: addField
          width: parent.width
          enabled: !root.adding && root.errorKind !== "auth" && root.errorKind !== "missing"
          placeholderText: root.adding ? strings.t("add.adding") : strings.t("add.placeholder")
          foreground: root.foreground
          font.family: root.fontFamily
          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) {
              addField.text = ""
              if (panel.loadedContent) panel.loadedContent.forceActiveFocus()
              event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              root.add(addField.text)
              event.accepted = true
            }
          }
        }

        // Bound to the condition, not openButton.visible: a child reads as
        // invisible while its parent is hidden, so that never turned back on.
        Item {
          width: parent.width
          visible: root.canOpen || root.notice !== ""
          implicitHeight: openButton.implicitHeight

          Text {
            anchors.left: parent.left
            anchors.right: openButton.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.notice
            elide: Text.ElideRight
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Button {
            id: openButton
            anchors.right: parent.right
            text: strings.t("action.open")
            foreground: root.foreground
            fontFamily: root.fontFamily
            bordered: true
            visible: root.canOpen
            onClicked: root.openApp()
          }
        }
      }
    }
  }

  component TaskRow: CursorSurface {
    id: row
    property var task: ({})
    signal hoveredIn()

    readonly property color ring: Model.priorityColor(task.priority, root.dim, root.palette)
    readonly property string when: root.whenText(task)

    foreground: root.foreground
    implicitHeight: Math.max(contentText.implicitHeight, Style.space(20)) + Style.space(14)

    // A true circle, so it stays round whatever the corner radius.
    Rectangle {
      id: circle
      anchors.left: parent.left
      anchors.leftMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(16)
      height: width
      radius: width / 2
      color: circleMouse.containsMouse ? Qt.rgba(row.ring.r, row.ring.g, row.ring.b, 0.3) : "transparent"
      border.width: Math.max(1, Style.space(2))
      border.color: row.ring

      MouseArea {
        id: circleMouse
        anchors.fill: parent
        anchors.margins: -Style.space(4)
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.complete(row.task.id)
      }
    }

    Text {
      id: contentText
      anchors.left: circle.right
      anchors.leftMargin: Style.space(10)
      anchors.right: meta.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: row.task.content || ""
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
      maximumLineCount: 2
      wrapMode: Text.WordWrap
    }

    Column {
      id: meta
      anchors.right: parent.right
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      Text {
        anchors.right: parent.right
        visible: text !== ""
        textFormat: Text.PlainText
        text: row.when
        color: row.task.overdue ? root.urgent : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
      Text {
        anchors.right: parent.right
        visible: text !== ""
        textFormat: Text.PlainText
        text: row.task.project && !row.task.project.inbox ? row.task.project.name : ""
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
        width: Math.min(implicitWidth, Style.space(110))
      }
    }

    MouseArea {
      anchors.fill: parent
      z: -1
      hoverEnabled: true
      acceptedButtons: Qt.NoButton
      onEntered: row.hoveredIn()
    }

    PanelToolTip {
      visible: circleMouse.containsMouse
      text: strings.t("action.complete")
      fontFamily: root.fontFamily
    }
  }
}
