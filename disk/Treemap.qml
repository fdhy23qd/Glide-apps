import QtQuick
import Glide.Ui

// Карта места: каждая плитка — файл или папка, площадь — размер, цвет — тип (у папки — чего в ней больше). Раскладка «squarified»
// (Bruls и др.): плитки как можно ближе к квадрату — так размеры легче сравнивать на глаз.
// Совсем мелкие (меньше ~0,15 % площади) складываются в одну серую плитку «Остальное».
Item {
    id: map

    property var items: []          // [{name, path, size, dir, kind, small}] по убыванию размера
    property string hoveredPath: ""
    property string selectedPath: ""
    property var human: b => String(b)   // размер по-человечески — даёт окно
    signal activated(var item)      // щелчок: папка — войти, файл — выбрать
    signal menuRequested(var item, real x, real y)

    function kindColor(k) {
        return ({ dir: Theme.accent, video: "#e8615a", image: "#34c77b", audio: "#f5a623", archive: "#4aa3df",
                  doc: "#d9b93c", other: "#8a94a6", small: "#5b6474" })[k] || "#8a94a6"
    }

    readonly property var tiles: {
        var w = width, h = height
        if (w < 10 || h < 10 || !items.length) return []
        var total = 0
        for (var i = 0; i < items.length; i++) total += items[i].size
        if (total <= 0) return []
        // мелкое — в «Остальное»
        var list = [], rest = 0, restN = 0
        for (i = 0; i < items.length; i++) {
            var it = items[i]
            if (it.size <= 0) continue
            if (it.size / total < 0.0015 || list.length >= 120) { rest += it.size; restN++ }
            else list.push(it)
        }
        if (rest > 0) list.push({ name: Tr.t("Остальное: ") + restN, path: "", size: rest, dir: false, kind: "small", small: true })
        var k = w * h / total
        var out = []
        var x = 0, y = 0, rw = w, rh = h
        var row = [], rowArea = 0
        function worst(r, area, side) {
            var mx = 0, mn = Infinity
            for (var j = 0; j < r.length; j++) { mx = Math.max(mx, r[j].a); mn = Math.min(mn, r[j].a) }
            var s2 = side * side, a2 = area * area
            return Math.max(s2 * mx / a2, a2 / (s2 * mn))
        }
        function layout(r, area) {   // уложить ряд вдоль короткой стороны оставшегося прямоугольника
            var horiz = rw >= rh
            var thick = area / (horiz ? rh : rw)
            var off = 0
            for (var j = 0; j < r.length; j++) {
                var len = r[j].a / thick
                out.push(horiz ? { x: x, y: y + off, w: thick, h: len, item: r[j].item }
                               : { x: x + off, y: y, w: len, h: thick, item: r[j].item })
                off += len
            }
            if (horiz) { x += thick; rw -= thick } else { y += thick; rh -= thick }
        }
        for (i = 0; i < list.length; i++) {
            var cell = { a: list[i].size * k, item: list[i] }
            var side = Math.min(rw, rh)
            if (!row.length || worst(row.concat([cell]), rowArea + cell.a, side) <= worst(row, rowArea, side)) {
                row.push(cell); rowArea += cell.a
            } else {
                layout(row, rowArea)
                row = [cell]; rowArea = cell.a
            }
        }
        if (row.length) layout(row, rowArea)
        return out
    }

    Repeater {
        model: map.tiles
        delegate: Rectangle {
            id: tile
            required property var modelData
            readonly property var it: modelData.item
            readonly property bool hot: it.path !== "" && (it.path === map.hoveredPath || it.path === map.selectedPath)
            x: modelData.x + 1.5
            y: modelData.y + 1.5
            width: Math.max(0, modelData.w - 3)
            height: Math.max(0, modelData.h - 3)
            radius: Math.min(Theme.r(10), width / 4, height / 4)
            color: Qt.rgba(baseColor.r, baseColor.g, baseColor.b, tileArea.pressed ? 1 : hot ? 0.95 : 0.78)
            readonly property color baseColor: map.kindColor(it.kind)
            border.width: it.path !== "" && it.path === map.selectedPath ? 2 : 0
            border.color: Theme.text
            scale: tileArea.pressed ? 0.985 : 1
            Behavior on color { ColorAnimation { duration: 120 } }
            Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
            clip: true

            Column {
                visible: tile.width > 64 && tile.height > 34
                x: 8; y: 6
                width: tile.width - 16
                Row {
                    width: parent.width
                    spacing: 4
                    Text {   // папка — значком перед именем
                        id: dirIcon
                        visible: tile.it.dir
                        text: Theme.icon(0xF024B)
                        color: "#ffffff"
                        font.family: Theme.iconFont
                        font.pixelSize: Theme.fs(13)
                    }
                    Text {
                        width: parent.width - (dirIcon.visible ? dirIcon.width + 4 : 0)
                        text: tile.it.name
                        color: "#ffffff"
                        font.pixelSize: Theme.fs(12)
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                        style: Text.Raised; styleColor: Qt.rgba(0, 0, 0, 0.35)
                    }
                }
                Text {
                    visible: tile.height > 52
                    text: map.human(tile.it.size)
                    color: Qt.rgba(1, 1, 1, 0.85)
                    font.pixelSize: Theme.fs(11)
                }
            }
            MouseArea {
                id: tileArea
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: tile.it.path !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
                onEntered: map.hoveredPath = tile.it.path
                onExited: if (map.hoveredPath === tile.it.path) map.hoveredPath = ""
                onClicked: mouse => {
                    if (tile.it.path === "") return
                    if (mouse.button === Qt.RightButton) map.menuRequested(tile.it, mouse.x + tile.x, mouse.y + tile.y)
                    else map.activated(tile.it)
                }
            }
        }
    }
}
