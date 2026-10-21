import QtQuick
import QtQuick.Window
import Glide.Ui

// Правка: картинка с поворотом и отражением (как получится в файле) и рамка обрезки поверх.
// crop — доли {x, y, w, h} в уже повёрнутом и отражённом изображении; aspect — w/h в пикселях (0 — свободно).
Item {
    id: ev

    required property var info          // gallery.info: размеры после поворота EXIF
    required property string url
    property int rotate: 0
    property bool flipH: false
    property bool flipV: false
    property var crop: ({ x: 0, y: 0, w: 1, h: 1 })
    property real aspect: 0

    readonly property bool sideways: rotate % 180 === 90
    readonly property real natW: (sideways ? info.height : info.width) || 1
    readonly property real natH: (sideways ? info.width : info.height) || 1
    readonly property real k: Math.min((width - 48) / natW, (height - 48) / natH)
    readonly property bool cropped: crop.w < 0.999 || crop.h < 0.999

    // ---- рамка: пропорции в пикселях картинки ----
    function hFor(w) { return w * natW / (natH * aspect) }   // доля высоты для доли ширины при aspect
    function setAspect(a) {
        aspect = a
        if (a <= 0) return
        var w = 1, h = hFor(1)
        if (h > 1) { h = 1; w = a * natH / natW }
        crop = { x: (1 - w) / 2, y: (1 - h) / 2, w: w, h: h }
    }
    function resetCrop() { aspect = 0; crop = { x: 0, y: 0, w: 1, h: 1 } }
    onRotateChanged: { var a = aspect; resetCrop(); if (a > 0) setAspect(1 / a) }   // повернули — рамка заново
    onFlipHChanged: crop = { x: 1 - crop.x - crop.w, y: crop.y, w: crop.w, h: crop.h }
    onFlipVChanged: crop = { x: crop.x, y: 1 - crop.y - crop.h, w: crop.w, h: crop.h }

    readonly property real minSide: 0.04
    function clamp(v, a, b) { return Math.max(a, Math.min(b, v)) }
    // kind: move | l r t b | tl tr bl br; s — рамка в момент нажатия; dx, dy — сдвиг в долях
    function drag(kind, s, dx, dy) {
        if (kind === "move") {
            crop = { x: clamp(s.x + dx, 0, 1 - s.w), y: clamp(s.y + dy, 0, 1 - s.h), w: s.w, h: s.h }
            return
        }
        var l = s.x, r = s.x + s.w, t = s.y, b = s.y + s.h
        if (aspect > 0 && kind.length === 2) {
            // угол при заданных пропорциях: противоположный угол на месте, ширина задаёт высоту
            var ax = kind[1] === "l" ? r : l, ay = kind[0] === "t" ? b : t
            var px = kind[1] === "l" ? l + dx : r + dx
            var sx = kind[1] === "l" ? -1 : 1, sy = kind[0] === "t" ? -1 : 1
            var w = clamp(sx * (px - ax), minSide, sx > 0 ? 1 - ax : ax)
            var h = hFor(w)
            var hMax = sy > 0 ? 1 - ay : ay
            if (h > hMax) { h = hMax; w = h * natH * aspect / natW }
            crop = { x: sx > 0 ? ax : ax - w, y: sy > 0 ? ay : ay - h, w: w, h: h }
            return
        }
        if (kind.indexOf("l") >= 0) l = clamp(l + dx, 0, r - minSide)
        if (kind.indexOf("r") >= 0) r = clamp(r + dx, l + minSide, 1)
        if (kind.indexOf("t") >= 0) t = clamp(t + dy, 0, b - minSide)
        if (kind.indexOf("b") >= 0) b = clamp(b + dy, t + minSide, 1)
        crop = { x: l, y: t, w: r - l, h: b - t }
    }

    // ---- картинка ----
    Item {
        id: box
        width: ev.natW * ev.k
        height: ev.natH * ev.k
        anchors.centerIn: parent
        transform: Scale {
            origin.x: box.width / 2; origin.y: box.height / 2
            xScale: ev.flipH ? -1 : 1; yScale: ev.flipV ? -1 : 1
        }
        Image {
            anchors.centerIn: parent
            width: (ev.info.width || 0) * ev.k
            height: (ev.info.height || 0) * ev.k
            rotation: ev.rotate
            source: ev.url
            asynchronous: true
            autoTransform: true
            smooth: true
            mipmap: true
            sourceSize: Qt.size(Math.max(Screen.width, Screen.height), Math.max(Screen.width, Screen.height))
        }
    }

    // ---- рамка обрезки (вне отражения: доли — в том, что видно) ----
    Item {
        id: ov
        x: box.x; y: box.y
        width: box.width; height: box.height
        readonly property real cx: ev.crop.x * width
        readonly property real cy: ev.crop.y * height
        readonly property real cw: ev.crop.w * width
        readonly property real ch: ev.crop.h * height
        property bool dragging: false
        readonly property color dim: Qt.rgba(0, 0, 0, 0.55)

        Rectangle { x: 0; y: 0; width: parent.width; height: ov.cy; color: ov.dim }
        Rectangle { x: 0; y: ov.cy + ov.ch; width: parent.width; height: parent.height - ov.cy - ov.ch; color: ov.dim }
        Rectangle { x: 0; y: ov.cy; width: ov.cx; height: ov.ch; color: ov.dim }
        Rectangle { x: ov.cx + ov.cw; y: ov.cy; width: parent.width - ov.cx - ov.cw; height: ov.ch; color: ov.dim }

        Rectangle {   // рамка
            x: ov.cx; y: ov.cy; width: ov.cw; height: ov.ch
            color: "transparent"
            border.width: 2
            border.color: "white"
            Repeater {   // трети — пока тянут
                model: 4
                delegate: Rectangle {
                    required property int index
                    readonly property bool vert: index < 2
                    visible: ov.dragging
                    x: vert ? parent.width * (index % 2 + 1) / 3 : 0
                    y: vert ? 0 : parent.height * (index % 2 + 1) / 3
                    width: vert ? 1 : parent.width
                    height: vert ? parent.height : 1
                    color: Qt.rgba(1, 1, 1, 0.5)
                }
            }
        }

        component Handle: MouseArea {
            id: h
            required property string kind
            // inline-компонент не видит id файла — рамка и вид передаются свойствами
            required property Item overlay
            required property Item editor
            property var start: null
            property point p0
            width: kind.length === 2 ? 28 : (kind === "l" || kind === "r" ? 20 : Math.max(20, overlay.cw - 56))
            height: kind.length === 2 ? 28 : (kind === "t" || kind === "b" ? 20 : Math.max(20, overlay.ch - 56))
            x: (kind.indexOf("l") >= 0 ? overlay.cx : kind.indexOf("r") >= 0 ? overlay.cx + overlay.cw : overlay.cx + overlay.cw / 2) - width / 2
            y: (kind.indexOf("t") >= 0 ? overlay.cy : kind.indexOf("b") >= 0 ? overlay.cy + overlay.ch : overlay.cy + overlay.ch / 2) - height / 2
            hoverEnabled: true
            preventStealing: true
            cursorShape: kind === "tl" || kind === "br" ? Qt.SizeFDiagCursor : kind === "tr" || kind === "bl" ? Qt.SizeBDiagCursor
                       : kind === "l" || kind === "r" ? Qt.SizeHorCursor : Qt.SizeVerCursor
            onPressed: mouse => { start = editor.crop; p0 = mapToItem(overlay, mouse.x, mouse.y); overlay.dragging = true }
            onReleased: overlay.dragging = false
            onPositionChanged: mouse => {
                if (!pressed || !start) return
                var p = mapToItem(overlay, mouse.x, mouse.y)
                editor.drag(kind, start, (p.x - p0.x) / overlay.width, (p.y - p0.y) / overlay.height)
            }
            Rectangle {   // уголок
                visible: h.kind.length === 2
                anchors.centerIn: parent
                width: h.pressed ? 16 : h.containsMouse ? 14 : 12
                height: width
                radius: width / 2
                color: "white"
                border.color: Theme.accent
                border.width: h.containsMouse || h.pressed ? 2 : 0
                Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }
            }
            Rectangle {   // середина стороны
                Behavior on opacity { NumberAnimation { duration: 140 } }
                visible: h.kind.length === 1
                anchors.centerIn: parent
                width: h.kind === "t" || h.kind === "b" ? 28 : (h.pressed ? 6 : 4)
                height: h.kind === "l" || h.kind === "r" ? 28 : (h.pressed ? 6 : 4)
                radius: 2
                color: "white"
                opacity: h.containsMouse || h.pressed ? 1 : 0.8
            }
        }

        MouseArea {   // перенести рамку целиком
            x: ov.cx; y: ov.cy; width: ov.cw; height: ov.ch
            cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            preventStealing: true
            property var start: null
            property point p0
            onPressed: mouse => { start = ev.crop; p0 = mapToItem(ov, mouse.x, mouse.y); ov.dragging = true }
            onReleased: ov.dragging = false
            onPositionChanged: mouse => {
                if (!pressed || !start) return
                var p = mapToItem(ov, mouse.x, mouse.y)
                ev.drag("move", start, (p.x - p0.x) / ov.width, (p.y - p0.y) / ov.height)
            }
        }
        // стороны — только при свободных пропорциях
        Handle { overlay: ov; editor: ev; kind: "l"; visible: ev.aspect <= 0 }
        Handle { overlay: ov; editor: ev; kind: "r"; visible: ev.aspect <= 0 }
        Handle { overlay: ov; editor: ev; kind: "t"; visible: ev.aspect <= 0 }
        Handle { overlay: ov; editor: ev; kind: "b"; visible: ev.aspect <= 0 }
        Handle { overlay: ov; editor: ev; kind: "tl" }
        Handle { overlay: ov; editor: ev; kind: "tr" }
        Handle { overlay: ov; editor: ev; kind: "bl" }
        Handle { overlay: ov; editor: ev; kind: "br" }
    }
}
