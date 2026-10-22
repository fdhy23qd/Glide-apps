import QtQuick
import QtQuick.Window
import Glide.Ui
import GlideShot

// Glide Скриншоты: снимок (область, экран, окно — интерфейсом niri) и разметка: стрелки, рамки,
// текст, номера шагов, маркер, размытие, обрезка. Копировать в буфер или сохранить.
Window {
    id: win

    property string startPath: ""
    property string startCapture: ""     // region | screen | window — снять сразу при запуске

    width: 1100
    height: 720
    minimumWidth: 640
    minimumHeight: 420
    // пока снимаем, окна нет — иначе оно попадёт на скриншот
    visible: !hiding
    property bool hiding: startCapture !== ""
    flags: Qt.Window | Qt.FramelessWindowHint
    color: Theme.background
    title: shot.ready ? shot.path.split("/").pop() + Tr.t(" — Скриншоты") : Tr.t("Скриншоты")

    Shot {
        id: shot
        onLoaded: { win.resetEdits(); win.hiding = false; if (win.startCapture) win.requestActivate() }
        onFailed: message => { win.hiding = false; toast.show(message) }
        onCaptureGaveUp: { if (!shot.ready) Qt.quit(); else win.hiding = false }
    }
    function capture(mode) { hiding = true; shot.capture(mode) }
    FilePicker {
        id: picker
        onPicked: urls => {
            if (!urls.length) return
            if (win.saveAsPending) { win.saveAsPending = false; win.saveTo(shot.localPath(urls[0])) }
            else shot.load(urls[0])
        }
    }
    property bool saveAsPending: false
    Component.onCompleted: {
        if (startCapture) Qt.callLater(() => shot.capture(win.startCapture))
        else if (startPath) shot.load(startPath)
    }

    // ---------- разметка ----------
    property var items: []                 // готовые фигуры
    property var current: null             // рисуемая сейчас
    property var crop: null                // {x, y, w, h} в пикселях картинки
    property var undoStack: []
    property var redoStack: []
    property bool dirty: false             // есть несохранённые и нескопированные изменения

    property string tool: "arrow"
    readonly property var inks: ["#ef5b5b", "#f5a623", "#34c77b", "#3d8bfd", "#7b61ff", "#ffffff", "#111111"]
    property color penColor: inks[0]
    property int sizeIndex: 1
    // толщина — в пикселях картинки: на 4K снимке линии пропорционально толще
    readonly property real k: Math.max(1, Math.round(Math.max(shot.size.width, shot.size.height) / 1600 * 10) / 10)
    readonly property real strokeW: [3, 5, 9][sizeIndex] * k
    readonly property real textSize: [20, 30, 46][sizeIndex] * k

    function resetEdits() { items = []; current = null; crop = null; undoStack = []; redoStack = []; dirty = false }
    function snapshot() { return { items: items.slice(), crop: crop } }
    function push(changeFn) {
        var u = undoStack.slice(); u.push(snapshot()); undoStack = u.slice(-200)
        redoStack = []
        changeFn()
        dirty = true
    }
    function undo() {
        if (!undoStack.length) return
        var u = undoStack.slice(), s = u.pop()
        var r = redoStack.slice(); r.push(snapshot()); redoStack = r
        undoStack = u; items = s.items; crop = s.crop; dirty = true
    }
    function redo() {
        if (!redoStack.length) return
        var r = redoStack.slice(), s = r.pop()
        var u = undoStack.slice(); u.push(snapshot()); undoStack = u
        redoStack = r; items = s.items; crop = s.crop; dirty = true
    }
    function addItem(a) { push(() => { var l = items.slice(); l.push(a); win.items = l }) }
    function nextStep() { var n = 1; for (var a of items) if (a.type === "step") n++; return n }

    // ---------- итог ----------
    function cropMap() { return crop && crop.w > 1 && crop.h > 1 ? crop : ({}) }
    function copy() {
        commitText()
        if (shot.copy(items, cropMap())) { dirty = false; toast.show(Tr.t("Скопировано в буфер")) }
    }
    function saveTo(file) {
        commitText()
        if (shot.save(items, cropMap(), file)) {
            dirty = false
            toast.show(Tr.t("Сохранено: ") + file.split("/").pop(), Tr.t("Показать"), () => shot.showInFolder(file))
        }
    }
    function save() { if (shot.ready) saveTo(shot.savePath()) }
    function saveAs() {
        if (!shot.ready) return
        saveAsPending = true
        picker.save(Tr.t("Сохранить скриншот"), shot.savePath().split("/").pop(), shot.folder)
    }
    onClosing: close => {
        if (dirty && !forceClose) {
            close.accepted = false
            toast.show(Tr.t("Изменения не сохранены и не скопированы"), Tr.t("Закрыть"), () => { win.forceClose = true; win.close() })
        }
    }
    property bool forceClose: false

    // ---------- шапка ----------
    Rectangle {
        id: header
        width: parent.width
        height: 52
        color: Theme.background
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.outline }
        DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }
        Column {
            x: 16
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - actions.width - 40
            Text {
                width: parent.width
                text: shot.ready ? shot.path.split("/").pop() : Tr.t("Скриншоты")
                color: Theme.text
                font.pixelSize: Theme.fs(14)
                font.weight: Font.DemiBold
                elide: Text.ElideMiddle
                textFormat: Text.PlainText
            }
            Text {
                visible: shot.ready
                text: (win.crop ? Math.round(win.crop.w) + " × " + Math.round(win.crop.h) + Tr.t(" (обрезано из ") : "")
                      + shot.size.width + " × " + shot.size.height + (win.crop ? ")" : "")
                color: Theme.textSecondary
                font.pixelSize: Theme.fs(11)
            }
        }
        Row {
            id: actions
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            IconButton { glyph: 0xF0100; tip: Tr.t("Новый снимок"); on: newMenu.open; onClicked: newMenu.open = !newMenu.open }
            Item { width: 6; height: 1 }
            TextButton { anchors.verticalCenter: parent.verticalCenter; implicitHeight: 36; text: Tr.t("Сохранить как…"); flat: true; enabled: shot.ready; onClicked: win.saveAs() }
            TextButton { anchors.verticalCenter: parent.verticalCenter; implicitHeight: 36; glyph: 0xF0193; text: Tr.t("Сохранить"); enabled: shot.ready; onClicked: win.save() }
            TextButton { anchors.verticalCenter: parent.verticalCenter; implicitHeight: 36; glyph: 0xF018F; text: Tr.t("Копировать"); primary: true; enabled: shot.ready; onClicked: win.copy() }
            Item { width: 6; height: 1 }
            IconButton { glyph: 0xF0156; tip: Tr.t("Закрыть  Esc"); onClicked: win.close() }
        }
    }

    // ---------- холст ----------
    Item {
        id: stage
        anchors.top: header.bottom
        anchors.bottom: toolbar.top
        anchors.bottomMargin: 8
        width: parent.width
        clip: true

        readonly property real s: shot.ready ? Math.min(1, (width - 32) / shot.size.width, (height - 24) / shot.size.height) : 1

        Item {
            id: paper
            visible: shot.ready
            width: shot.size.width
            height: shot.size.height
            x: Math.round((stage.width - width * stage.s) / 2)
            y: Math.round((stage.height - height * stage.s) / 2)
            transform: Scale { xScale: stage.s; yScale: stage.s }

            Image {
                anchors.fill: parent
                source: shot.ready ? shot.url : ""
                smooth: true
                mipmap: true
                cache: false
            }
            Repeater {
                model: win.items
                delegate: Annotation {
                    required property var modelData
                    a: modelData
                    pixelUrl: shot.pixelUrl
                    imgW: paper.width
                    imgH: paper.height
                }
            }
            Annotation {
                a: win.current
                visible: !!win.current
                pixelUrl: shot.pixelUrl
                imgW: paper.width
                imgH: paper.height
            }

            // обрезка: снаружи — затемнение
            Item {
                anchors.fill: parent
                readonly property var c: win.current && win.current.type === "crop" ? win.current
                                        : win.crop ? ({ x1: win.crop.x, y1: win.crop.y, x2: win.crop.x + win.crop.w, y2: win.crop.y + win.crop.h }) : null
                visible: !!c
                readonly property real l: c ? Math.min(c.x1, c.x2) : 0
                readonly property real t: c ? Math.min(c.y1, c.y2) : 0
                readonly property real r: c ? Math.max(c.x1, c.x2) : 0
                readonly property real b: c ? Math.max(c.y1, c.y2) : 0
                readonly property color dim: Qt.rgba(0, 0, 0, 0.6)
                Rectangle { x: 0; y: 0; width: parent.width; height: parent.t; color: parent.dim }
                Rectangle { x: 0; y: parent.b; width: parent.width; height: parent.height - parent.b; color: parent.dim }
                Rectangle { x: 0; y: parent.t; width: parent.l; height: parent.b - parent.t; color: parent.dim }
                Rectangle { x: parent.r; y: parent.t; width: parent.width - parent.r; height: parent.b - parent.t; color: parent.dim }
                Rectangle {
                    x: parent.l; y: parent.t; width: parent.r - parent.l; height: parent.b - parent.t
                    color: "transparent"
                    border.color: "white"
                    border.width: 2 / stage.s
                }
            }

            // ввод текста прямо на картинке
            TextInput {
                id: textEdit
                property bool active: false
                visible: active
                font.family: "Inter"
                font.pixelSize: win.textSize
                font.bold: true
                color: win.penColor
                selectionColor: Theme.accent
                cursorVisible: active
                onAccepted: win.commitText()
                Keys.onEscapePressed: { active = false; text = ""; stage.forceActiveFocus() }
                Rectangle {   // рамка поля, чтобы было видно, куда печатаем
                    anchors.fill: parent
                    anchors.margins: -4 / stage.s
                    color: "transparent"
                    border.color: Theme.accent
                    border.width: 1.5 / stage.s
                    radius: 4 / stage.s
                }
            }
        }

        // ---- рисование ----
        MouseArea {
            id: draw
            anchors.fill: parent
            enabled: shot.ready
            cursorShape: win.tool === "text" ? Qt.IBeamCursor : Qt.CrossCursor
            property point start
            function img(mx, my) {
                var q = paper.mapFromItem(draw, mx, my)
                return Qt.point(Math.max(0, Math.min(paper.width, q.x)), Math.max(0, Math.min(paper.height, q.y)))
            }
            // Shift: линии и стрелки — по 45°, рамки — квадратные
            function constrain(p, mods) {
                if (!(mods & Qt.ShiftModifier)) return p
                var dx = p.x - start.x, dy = p.y - start.y
                if (win.tool === "line" || win.tool === "arrow") {
                    var ang = Math.round(Math.atan2(dy, dx) / (Math.PI / 4)) * Math.PI / 4, len = Math.hypot(dx, dy)
                    return Qt.point(start.x + Math.cos(ang) * len, start.y + Math.sin(ang) * len)
                }
                var m = Math.max(Math.abs(dx), Math.abs(dy))
                return Qt.point(start.x + (dx < 0 ? -m : m), start.y + (dy < 0 ? -m : m))
            }
            onPressed: mouse => {
                win.commitText()
                var p = img(mouse.x, mouse.y)
                start = p
                if (win.tool === "text") { win.startText(p); return }
                if (win.tool === "step") { win.addItem({ type: "step", color: String(win.penColor), width: win.strokeW, x1: p.x, y1: p.y, x2: p.x, y2: p.y, n: win.nextStep() }); return }
                if (win.tool === "pixel") shot.preparePixels()
                win.current = { type: win.tool, color: String(win.penColor), width: win.strokeW,
                                x1: p.x, y1: p.y, x2: p.x, y2: p.y, points: [p.x, p.y] }
            }
            onPositionChanged: mouse => {
                if (!pressed || !win.current) return
                var p = constrain(img(mouse.x, mouse.y), mouse.modifiers)
                var c = Object.assign({}, win.current)
                if (c.type === "pen" || c.type === "marker") {
                    var pts = c.points, lx = pts[pts.length - 2], ly = pts[pts.length - 1]
                    if (Math.hypot(p.x - lx, p.y - ly) * stage.s < 2) return   // не копим точки чаще 2 пикселей экрана
                    c.points = pts.concat([p.x, p.y])
                }
                c.x2 = p.x; c.y2 = p.y
                win.current = c
            }
            onReleased: {
                var c = win.current
                win.current = null
                if (!c) return
                var big = Math.hypot(c.x2 - c.x1, c.y2 - c.y1) * stage.s > 4 || (c.points && c.points.length > 4)
                if (!big) return
                if (c.type === "crop") {
                    win.push(() => { win.crop = { x: Math.min(c.x1, c.x2), y: Math.min(c.y1, c.y2), w: Math.abs(c.x2 - c.x1), h: Math.abs(c.y2 - c.y1) } })
                    return
                }
                win.addItem(c)
            }
        }

        // пусто: чем снять
        Column {
            anchors.centerIn: parent
            visible: !shot.ready && !shot.capturing
            spacing: 14
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: Theme.icon(0xF0100); color: Theme.textMuted; font.family: Theme.iconFont; font.pixelSize: 64 }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: Tr.t("Новый скриншот"); color: Theme.text; font.pixelSize: Theme.fs(18); font.weight: Font.DemiBold }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8
                TextButton { primary: true; text: Tr.t("Область"); onClicked: win.capture("region") }
                TextButton { text: Tr.t("Окно"); onClicked: win.capture("window") }
                TextButton { text: Tr.t("Весь экран"); onClicked: win.capture("screen") }
            }
            TextButton { anchors.horizontalCenter: parent.horizontalCenter; flat: true; text: Tr.t("Открыть картинку…"); onClicked: picker.open(Tr.t("Открыть картинку"), Tr.t("Изображения"), ["*.png", "*.jpg", "*.jpeg", "*.webp", "*.bmp"], shot.folder) }
        }
    }

    function startText(p) {
        textEdit.x = p.x
        textEdit.y = p.y
        textEdit.text = ""
        textEdit.active = true
        textEdit.forceActiveFocus()
    }
    function commitText() {
        if (!textEdit.active) return
        textEdit.active = false
        stage.forceActiveFocus()   // иначе клавиши (инструменты A, R, N…) уходят в невидимое поле
        if (textEdit.text.trim())
            addItem({ type: "text", color: String(penColor), width: strokeW, size: textSize, text: textEdit.text,
                      x1: textEdit.x, y1: textEdit.y, x2: textEdit.x, y2: textEdit.y })
        textEdit.text = ""
    }

    // ---------- панель инструментов ----------
    Rectangle {
        id: toolbar
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 12
        // в узком окне (плитка niri) — в два ряда
        width: tools.width + 16
        height: tools.implicitHeight + 12
        radius: Math.min(26, height / 2)
        color: Theme.surface
        border.color: Theme.outline
        visible: shot.ready
        Flow {
            id: tools
            anchors.centerIn: parent
            // ширина — по самим кнопкам (раньше 800 px: последняя переносилась и в широком окне)
            readonly property real rowW: { var w = 0; for (var i = 0; i < children.length; i++) if (children[i].visible && children[i].width > 0) w += children[i].width + spacing; return w - spacing }
            width: Math.min(rowW, win.width - 40)
            spacing: 2
            Repeater {
                model: [
                    { id: "arrow", glyph: 0xF005C, tip: Tr.t("Стрелка  A") }, { id: "rect", glyph: 0xF0E5F, tip: Tr.t("Рамка  R") },
                    { id: "ellipse", glyph: 0xF0766, tip: Tr.t("Овал  O") }, { id: "line", glyph: 0xF0374, tip: Tr.t("Линия  L") },
                    { id: "pen", glyph: 0xF03EB, tip: Tr.t("Карандаш  P") }, { id: "marker", glyph: 0xF0652, tip: Tr.t("Маркер  M") },
                    { id: "text", glyph: 0xF0284, tip: Tr.t("Текст  T") }, { id: "step", glyph: 0xF0CA0, tip: Tr.t("Номер шага  N") },
                    { id: "pixel", glyph: 0xF00B5, tip: Tr.t("Размыть  B") }, { id: "crop", glyph: 0xF019E, tip: Tr.t("Обрезать  C") }
                ]
                delegate: IconButton {
                    required property var modelData
                    glyph: modelData.glyph
                    tip: modelData.tip
                    tipAbove: true
                    on: win.tool === modelData.id
                    onClicked: { win.commitText(); win.tool = modelData.id }
                }
            }
            Item { width: 9; height: 36; Rectangle { anchors.centerIn: parent; width: 1; height: 28; color: Theme.outline } }
            Repeater {   // цвета
                model: win.inks
                delegate: Item {
                    required property string modelData
                    width: 32; height: 36
                    Rectangle {   // кольцо у выбранного
                        anchors.centerIn: parent
                        width: 30; height: 30; radius: 15
                        color: "transparent"
                        border.width: Qt.colorEqual(win.penColor, parent.modelData) ? 2 : 0
                        border.color: Theme.text
                    }
                    Rectangle {
                        anchors.centerIn: parent
                        width: dotArea.containsMouse ? 22 : 18; height: width; radius: width / 2
                        color: parent.modelData
                        border.color: Theme.outline
                        Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }
                    }
                    MouseArea { id: dotArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.penColor = parent.modelData }
                }
            }
            Item { width: 9; height: 36; Rectangle { anchors.centerIn: parent; width: 1; height: 28; color: Theme.outline } }
            Repeater {   // толщина
                model: 3
                delegate: Rectangle {
                    Behavior on color { ColorAnimation { duration: 140 } }
                    required property int index
                    width: 32; height: 36; radius: 16
                    color: sizeArea.pressed ? Theme.surfacePressed : sizeArea.containsMouse ? Theme.surfaceHigher
                         : win.sizeIndex === index ? Theme.accentSoft : "transparent"
                    Rectangle { anchors.centerIn: parent; width: [5, 9, 14][parent.index]; height: width; radius: width / 2; color: Theme.text }
                    MouseArea { id: sizeArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: win.sizeIndex = parent.index }
                }
            }
            Item { width: 9; height: 36; Rectangle { anchors.centerIn: parent; width: 1; height: 28; color: Theme.outline } }
            IconButton { glyph: 0xF054C; tip: Tr.t("Отменить  Ctrl+Z"); tipAbove: true; enabled: win.undoStack.length > 0; onClicked: win.undo() }
            IconButton { glyph: 0xF044E; tip: Tr.t("Повторить  Ctrl+Shift+Z"); tipAbove: true; enabled: win.redoStack.length > 0; onClicked: win.redo() }
        }
    }

    // ---------- меню «Новый снимок» ----------
    MouseArea { anchors.fill: parent; visible: newMenu.open; onPressed: newMenu.open = false }
    PopupMenu {
        id: newMenu
        width: 230
        transformOrigin: Item.TopRight
        x: parent.width - width - 300
        y: 50
        items: [
            { text: Tr.t("Область"), run: () => win.capture("region") },
            { text: Tr.t("Окно"), run: () => win.capture("window") },
            { text: Tr.t("Весь экран"), run: () => win.capture("screen") },
            { text: Tr.t("Открыть картинку…"), run: () => picker.open(Tr.t("Открыть картинку"), Tr.t("Изображения"), ["*.png", "*.jpg", "*.jpeg", "*.webp", "*.bmp"], shot.folder) }
        ]
    }

    Toast { id: toast }
    DropArea {
        anchors.fill: parent
        onEntered: drag => drag.accept(Qt.CopyAction)
        onDropped: drop => { if (drop.hasUrls) shot.load(drop.urls[0]) }
    }
    ResizeEdges { window: win }

    // ---------- клавиши (не во время ввода текста) ----------
    readonly property bool keysOn: !textEdit.active
    Shortcut { enabled: win.keysOn; sequence: "A"; onActivated: win.tool = "arrow" }
    Shortcut { enabled: win.keysOn; sequence: "R"; onActivated: win.tool = "rect" }
    Shortcut { enabled: win.keysOn; sequence: "O"; onActivated: win.tool = "ellipse" }
    Shortcut { enabled: win.keysOn; sequence: "L"; onActivated: win.tool = "line" }
    Shortcut { enabled: win.keysOn; sequence: "P"; onActivated: win.tool = "pen" }
    Shortcut { enabled: win.keysOn; sequence: "M"; onActivated: win.tool = "marker" }
    Shortcut { enabled: win.keysOn; sequence: "T"; onActivated: win.tool = "text" }
    Shortcut { enabled: win.keysOn; sequence: "N"; onActivated: win.tool = "step" }
    Shortcut { enabled: win.keysOn; sequence: "B"; onActivated: win.tool = "pixel" }
    Shortcut { enabled: win.keysOn; sequence: "C"; onActivated: win.tool = "crop" }
    Shortcut { enabled: win.keysOn; sequence: "1"; onActivated: win.sizeIndex = 0 }
    Shortcut { enabled: win.keysOn; sequence: "2"; onActivated: win.sizeIndex = 1 }
    Shortcut { enabled: win.keysOn; sequence: "3"; onActivated: win.sizeIndex = 2 }
    Shortcut { enabled: win.keysOn; sequence: "Ctrl+Z"; onActivated: win.undo() }
    Shortcut { enabled: win.keysOn; sequences: ["Ctrl+Shift+Z", "Ctrl+Y"]; onActivated: win.redo() }
    Shortcut { sequence: "Ctrl+C"; enabled: win.keysOn && shot.ready; onActivated: win.copy() }
    Shortcut { sequence: "Ctrl+S"; enabled: shot.ready; onActivated: win.save() }
    Shortcut { sequence: "Ctrl+Shift+S"; enabled: shot.ready; onActivated: win.saveAs() }
    Shortcut { sequence: "Ctrl+O"; onActivated: picker.open(Tr.t("Открыть картинку"), Tr.t("Изображения"), ["*.png", "*.jpg", "*.jpeg", "*.webp", "*.bmp"], shot.folder) }
    Shortcut { sequences: ["Ctrl+W", "Ctrl+Q"]; onActivated: win.close() }
    Shortcut {
        sequence: "Esc"
        enabled: win.keysOn
        onActivated: { if (newMenu.open) newMenu.open = false; else win.close() }
    }
}
