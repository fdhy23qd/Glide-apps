import QtQuick
import QtQuick.Window
import Glide.Ui
import GlideDisk

// Glide Диск — что занимает место. Начало: диски и домашняя папка; дальше карта-плитки (площадь — размер,
// цвет — тип) и список по убыванию. Папка — войти, Backspace — выше; файл — открыть, показать в папке,
// в корзину (с отменой). Перетащенная в окно папка проверяется сразу.
Window {
    id: win

    property string startPath: ""

    width: 1040
    height: 680
    minimumWidth: 640
    minimumHeight: 420
    visible: true
    flags: Qt.Window | Qt.FramelessWindowHint
    color: Theme.background
    title: scanner.root ? folderName(cur) + Tr.t(" — Диск") : Tr.t("Диск")

    Scanner {
        id: scanner
        onError: message => toast.show(message)
        onTreeChanged: if (!win.cur || !scanner.info(win.cur).size && win.cur !== scanner.root) win.cur = scanner.root
    }
    Component.onCompleted: if (startPath) win.start(startPath)

    // ---- состояние ----
    property string cur: ""                     // открытая папка (внутри проверенной)
    property string selected: ""
    property var volumes: scanner.volumes()
    readonly property bool hasTree: scanner.root !== "" && !scanner.scanning
    readonly property var items: hasTree && scanner.revision >= 0 ? scanner.children(cur) : []
    readonly property var curInfo: hasTree && scanner.revision >= 0 ? scanner.info(cur) : ({})
    readonly property var selItem: items.find(x => x.path !== "" && x.path === selected) || null

    function start(path) { selected = ""; cur = ""; scanner.scan(path) }
    function home() { if (scanner.scanning) scanner.cancel(); volumes = scanner.volumes(); showStart = true }
    property bool showStart: true
    Connections { target: scanner; function onScanningChanged() { if (scanner.scanning) win.showStart = false } }
    function enter(it) {
        if (!it || it.path === "") return
        if (it.dir) { cur = it.path; selected = "" }
        else selected = it.path
    }
    function up() {
        if (!hasTree || cur === scanner.root) return
        selected = cur
        cur = cur.substring(0, cur.lastIndexOf("/"))
    }
    function trash(it) {
        if (!it || it.path === "") return
        if (scanner.trash(it.path)) {
            if (selected === it.path) selected = ""
            toast.show("«" + it.name + Tr.t("» — в корзине, освобождено ") + human(it.size), Tr.t("Отменить"), () => scanner.undoTrash())
        }
    }

    function folderName(p) {
        if (p === scanner.home()) return Tr.t("Домашняя папка")
        if (p === "/") return Tr.t("Система")
        return p.substring(p.lastIndexOf("/") + 1) || p
    }
    function human(b) {
        var u = [Tr.t("Б"), Tr.t("КБ"), Tr.t("МБ"), Tr.t("ГБ"), Tr.t("ТБ")], i = 0
        while (b >= 1024 && i < u.length - 1) { b /= 1024; i++ }
        return (i === 0 ? String(b) : b.toFixed(b < 10 ? 1 : 0).replace(".", Tr.ru ? "," : ".")) + " " + u[i]
    }
    function count(n) { return Number(n).toLocaleString(Tr.locale, "f", 0) }
    function files(n) {   // «1 файл, 2 файла, 5 файлов»
        var m10 = n % 10, m100 = n % 100
        var w = m10 === 1 && m100 !== 11 ? Tr.t("файл") : m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14) ? Tr.t("файла") : Tr.t("файлов")
        return count(n) + " " + w
    }
    readonly property var kindNames: ({ dir: Tr.t("Папки"), video: Tr.t("Видео"), image: Tr.t("Картинки"), audio: Tr.t("Музыка"),
                                        archive: Tr.t("Архивы и образы"), doc: Tr.t("Документы"), other: Tr.t("Другое"),
                                        small: Tr.t("Мелкие файлы") })
    function kindGlyph(k) {
        return ({ dir: 0xF024B, video: 0xF0567, image: 0xF02E9, audio: 0xF075A, archive: 0xF05C4, doc: 0xF0219,
                  other: 0xF0214, small: 0xF0222 })[k] || 0xF0214
    }

    // ---- шапка ----
    Item {
        id: header
        width: parent.width
        height: 60
        DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }
        TapHandler { onDoubleTapped: win.visibility = win.visibility === Window.Maximized ? Window.Windowed : Window.Maximized }

        Row {
            x: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            IconButton {
                visible: !win.showStart
                glyph: 0xF0141
                tip: Tr.t("Выше  Backspace")
                enabled: win.hasTree && win.cur !== scanner.root
                onClicked: win.up()
            }
            IconButton {
                visible: !win.showStart
                glyph: 0xF02DC
                tip: Tr.t("Диски и папки")
                onClicked: win.home()
            }
        }
        // «хлебные крошки» от проверенной папки
        Flickable {
            id: crumbs
            x: win.showStart ? 20 : 104
            width: parent.width - x - tools.width - 24
            height: parent.height
            contentWidth: crumbRow.width
            clip: true
            interactive: contentWidth > width
            onContentWidthChanged: contentX = Math.max(0, contentWidth - width)
            Row {
                id: crumbRow
                height: parent.height
                spacing: 2
                Text {
                    visible: win.showStart
                    anchors.verticalCenter: parent.verticalCenter
                    text: Tr.t("Диск")
                    color: Theme.text; font.pixelSize: Theme.fs(15); font.weight: Font.DemiBold
                }
                Repeater {
                    model: {
                        if (!win.hasTree || win.showStart) return []
                        var root = scanner.root, out = [{ name: win.folderName(root), path: root }]
                        var rest = win.cur.substring(root.length).split("/").filter(x => x)
                        var p = root
                        for (var i = 0; i < rest.length; i++) { p += "/" + rest[i]; out.push({ name: rest[i], path: p }) }
                        return out
                    }
                    delegate: Row {
                        required property var modelData
                        required property int index
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Text {
                            visible: index > 0
                            anchors.verticalCenter: parent.verticalCenter
                            text: Theme.icon(0xF0142); color: Theme.textMuted
                            font.family: Theme.iconFont; font.pixelSize: Theme.fs(16)
                        }
                        Rectangle {
                            readonly property bool last: modelData.path === win.cur
                            width: crumbText.implicitWidth + 16; height: 30; radius: 15
                            color: crumbArea.pressed ? Theme.surfacePressed : crumbArea.containsMouse && !last ? Theme.surfaceHigher : "transparent"
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Text {
                                id: crumbText
                                anchors.centerIn: parent
                                text: modelData.name
                                color: parent.last ? Theme.text : Theme.textSecondary
                                font.pixelSize: Theme.fs(14)
                                font.weight: parent.last ? Font.DemiBold : Font.Normal
                                textFormat: Text.PlainText
                            }
                            MouseArea {
                                id: crumbArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: parent.last ? Qt.ArrowCursor : Qt.PointingHandCursor
                                onClicked: { win.cur = modelData.path; win.selected = "" }
                            }
                        }
                    }
                }
            }
        }
        Row {
            id: tools
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            IconButton {
                visible: win.hasTree && !win.showStart
                glyph: 0xF0450
                tip: Tr.t("Проверить заново  F5")
                onClicked: win.start(scanner.root)
            }
            IconButton {
                glyph: win.visibility === Window.FullScreen ? 0xF0294 : 0xF0293
                tip: Tr.t("Во весь экран  F11")
                onClicked: win.visibility = win.visibility === Window.FullScreen ? Window.Windowed : Window.FullScreen
            }
            IconButton { glyph: 0xF0156; tip: Tr.t("Закрыть  Esc"); onClicked: win.close() }
        }
    }

    // ---- начало: диски и домашняя папка ----
    Flickable {
        id: startPage
        visible: win.showStart && !scanner.scanning
        anchors.fill: parent
        anchors.topMargin: header.height
        contentHeight: startCol.implicitHeight + 40
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        Column {
            id: startCol
            x: Math.max(20, (parent.width - width) / 2)
            width: Math.min(720, startPage.width - 40)
            spacing: 12
            Text {
                text: Tr.t("Что занимает место?")
                color: Theme.text; font.pixelSize: Theme.fs(22); font.weight: Font.DemiBold
            }
            Text {
                width: parent.width
                text: Tr.t("Выберите, что проверить, или перетащите папку в окно. Файлы при проверке не меняются.")
                color: Theme.textSecondary; font.pixelSize: Theme.fs(13); wrapMode: Text.WordWrap
            }
            Item { width: 1; height: 4 }
            Repeater {
                model: [{ name: Tr.t("Домашняя папка"), path: scanner.home(), home: true }].concat(win.volumes)
                delegate: Rectangle {
                    id: vol
                    required property var modelData
                    readonly property real part: modelData.total ? modelData.used / modelData.total : 0
                    width: startCol.width
                    height: 76
                    radius: Theme.radiusLg
                    color: volArea.pressed ? Theme.surfacePressed : volArea.containsMouse ? Theme.surfaceHigh : Theme.surface
                    border.color: volArea.containsMouse ? Theme.outlineHover : Theme.outline
                    scale: volArea.pressed ? 0.985 : 1
                    Behavior on color { ColorAnimation { duration: 140 } }
                    Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
                    Rectangle {
                        x: 16; anchors.verticalCenter: parent.verticalCenter
                        width: 44; height: 44; radius: 22
                        color: Theme.accentSoft
                        Text {
                            anchors.centerIn: parent
                            text: Theme.icon(vol.modelData.home ? 0xF02DC : 0xF02CA)
                            color: Theme.accent; font.family: Theme.iconFont; font.pixelSize: 22
                        }
                    }
                    Column {
                        x: 76; anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - x - 20
                        spacing: 6
                        Row {
                            width: parent.width
                            Text {
                                width: parent.width - usedText.width
                                text: vol.modelData.name + (vol.modelData.home ? "" : "  ·  " + vol.modelData.path)
                                color: Theme.text; font.pixelSize: Theme.fs(14); font.weight: Font.DemiBold
                                elide: Text.ElideRight; textFormat: Text.PlainText
                            }
                            Text {
                                id: usedText
                                text: vol.modelData.total ? win.human(vol.modelData.used) + Tr.t(" из ") + win.human(vol.modelData.total)
                                                          : vol.modelData.path.replace(scanner.home(), "~")
                                color: Theme.textSecondary; font.pixelSize: Theme.fs(12)
                            }
                        }
                        Rectangle {   // заполненность
                            visible: !!vol.modelData.total
                            width: parent.width; height: 8; radius: 4
                            color: Theme.surfaceHigher
                            Rectangle {
                                width: parent.width * vol.part; height: parent.height; radius: parent.radius
                                color: vol.part > 0.9 ? Theme.error : vol.part > 0.75 ? Theme.warning : Theme.accent
                            }
                        }
                        Text {
                            visible: !!vol.modelData.total
                            text: Tr.t("Свободно ") + win.human(vol.modelData.total - vol.modelData.used) + "  ·  " + vol.modelData.fs
                            color: Theme.textMuted; font.pixelSize: Theme.fs(11)
                        }
                    }
                    MouseArea {
                        id: volArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: win.start(vol.modelData.path)
                    }
                }
            }
            TextButton {
                visible: scanner.root !== ""
                glyph: 0xF024B
                text: Tr.t("Вернуться к результату: ") + win.folderName(scanner.root)
                onClicked: win.showStart = false
            }
        }
    }

    // ---- идёт проверка ----
    Column {
        visible: scanner.scanning
        anchors.centerIn: parent
        width: Math.min(520, parent.width - 60)
        spacing: 12
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Tr.t("Считаю…")
            color: Theme.text; font.pixelSize: Theme.fs(20); font.weight: Font.DemiBold
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: win.files(scanner.progressFiles) + "  ·  " + win.human(scanner.progressBytes)
            color: Theme.textSecondary; font.pixelSize: Theme.fs(14); font.features: ({ "tnum": 1 })
        }
        Rectangle {   // бегущая полоска — ждём, сколько всего, заранее не знаем
            width: parent.width; height: 6; radius: 3
            color: Theme.surfaceHigher
            clip: true
            Rectangle {
                width: parent.width * 0.3; height: parent.height; radius: 3
                color: Theme.accent
                NumberAnimation on x { from: -width; to: parent.width; duration: 1400; loops: Animation.Infinite; running: scanner.scanning }
            }
        }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: scanner.progressPath.replace(scanner.home(), "~")
            color: Theme.textMuted; font.pixelSize: Theme.fs(11)
            elide: Text.ElideMiddle; textFormat: Text.PlainText
        }
        Item { width: 1; height: 4 }
        Column {   // уже досчитанные папки — видно, куда ушло место, пока считается остальное
            visible: scanner.partial.length > 0
            width: parent.width
            spacing: 6
            Text { text: Tr.t("Уже посчитано"); color: Theme.textMuted; font.pixelSize: Theme.fs(11); font.weight: Font.DemiBold }
            Repeater {
                model: scanner.partial
                delegate: Row {
                    required property var modelData
                    width: parent.width
                    Text {
                        width: parent.width - partSize.width
                        text: modelData.name; color: Theme.text; font.pixelSize: Theme.fs(13)
                        elide: Text.ElideMiddle; textFormat: Text.PlainText
                    }
                    Text { id: partSize; text: win.human(modelData.size); color: Theme.textSecondary; font.pixelSize: Theme.fs(13) }
                }
            }
        }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: Tr.t("На обычном жёстком диске первая проверка большой папки занимает несколько минут, повторная — быстрее")
            color: Theme.textMuted; font.pixelSize: Theme.fs(11); wrapMode: Text.WordWrap
        }
        TextButton { anchors.horizontalCenter: parent.horizontalCenter; text: Tr.t("Отмена"); onClicked: win.home() }
    }

    // ---- результат: карта и список ----
    Item {
        id: result
        visible: win.hasTree && !win.showStart
        anchors.fill: parent
        anchors.topMargin: header.height
        anchors.margins: 12

        Treemap {
            id: treemap
            x: 0; y: 0
            width: parent.width - side.width - 12
            height: parent.height - legend.height - 8
            items: win.items
            human: win.human
            selectedPath: win.selected
            hoveredPath: list.hoveredPath
            onActivated: it => win.enter(it)
            onMenuRequested: (it, mx, my) => win.openMenu(it, treemap.mapToItem(win.contentItem, mx, my))
        }
        Flow {   // обозначения цветов: только те типы, что есть в папке
            id: legend
            anchors.bottom: parent.bottom
            width: treemap.width
            spacing: 14
            Repeater {
                model: (win.curInfo.kinds || []).map(x => x.kind).concat(win.items.some(x => x.small) ? ["small"] : [])
                delegate: Row {
                    required property string modelData
                    spacing: 6
                    Rectangle { width: 10; height: 10; radius: 3; anchors.verticalCenter: parent.verticalCenter; color: treemap.kindColor(modelData) }
                    Text { text: win.kindNames[modelData] || modelData; color: Theme.textSecondary; font.pixelSize: Theme.fs(11) }
                }
            }
        }

        Rectangle {
            id: side
            anchors.right: parent.right
            width: Math.min(380, parent.width * 0.42)
            height: parent.height
            radius: Theme.radiusLg
            color: Theme.surface
            border.color: Theme.outline

            Column {   // итог по открытой папке
                id: summary
                x: 16; y: 14
                width: parent.width - 32
                spacing: 2
                Text {
                    width: parent.width
                    text: win.folderName(win.cur)
                    color: Theme.text; font.pixelSize: Theme.fs(15); font.weight: Font.DemiBold
                    elide: Text.ElideMiddle; textFormat: Text.PlainText
                }
                Text {
                    text: win.human(win.curInfo.size || 0) + "  ·  " + win.files(win.curInfo.files || 0)
                          + (win.curInfo.denied ? Tr.t("  ·  часть папок закрыта") : "")
                    color: Theme.textSecondary; font.pixelSize: Theme.fs(12)
                }
                Item { width: 1; height: 8 }
                Row {   // из чего состоит папка — полоса по типам
                    id: mix
                    width: parent.width
                    height: 10
                    spacing: 2
                    readonly property var parts: win.curInfo.kinds || []
                    readonly property real total: parts.reduce((a, x) => a + x.size, 0)
                    Repeater {
                        model: mix.parts
                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            width: Math.max(3, (mix.width - 2 * (mix.parts.length - 1)) * modelData.size / mix.total)
                            height: mix.height
                            radius: 3
                            color: treemap.kindColor(modelData.kind)
                        }
                    }
                }
                Item { width: 1; height: 4 }
                Text {
                    width: parent.width
                    text: (win.curInfo.kinds || []).slice(0, 3).map(x => (win.kindNames[x.kind] || x.kind) + " " + win.human(x.size)).join("  ·  ")
                    color: Theme.textMuted; font.pixelSize: Theme.fs(11); elide: Text.ElideRight
                }
            }
            ListView {
                id: list
                property string hoveredPath: ""
                anchors.top: summary.bottom
                anchors.topMargin: 10
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 8
                x: 8
                width: parent.width - 16
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: win.items
                delegate: Rectangle {
                    id: row
                    required property var modelData
                    readonly property var it: modelData
                    readonly property bool sel: it.path !== "" && it.path === win.selected
                    readonly property bool hot: it.path !== "" && it.path === treemap.hoveredPath
                    readonly property real part: win.curInfo.size ? it.size / win.curInfo.size : 0
                    width: list.width
                    height: 52
                    radius: Theme.radiusSm
                    color: rowArea.pressed ? Theme.surfacePressed : sel ? Theme.accentSoft : rowArea.containsMouse || hot ? Theme.surfaceHigh : "transparent"
                    Behavior on color { ColorAnimation { duration: 120 } }
                    HoverHandler { id: rowHover }   // и над кнопкой «⋮» — строка остаётся «под курсором»
                    Text {
                        x: 10; anchors.verticalCenter: parent.verticalCenter
                        text: Theme.icon(row.it.dir ? 0xF024B : win.kindGlyph(row.it.kind))
                        color: treemap.kindColor(row.it.kind)
                        font.family: Theme.iconFont; font.pixelSize: 20
                    }
                    Column {
                        x: 40; anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - x - (moreBtn.visible ? 44 : 12)
                        spacing: 4
                        Row {
                            width: parent.width
                            Text {
                                width: parent.width - sizeText.width - 8
                                text: row.it.name
                                color: row.it.small ? Theme.textSecondary : Theme.text
                                font.pixelSize: Theme.fs(13)
                                elide: Text.ElideMiddle; textFormat: Text.PlainText
                            }
                            Text {
                                id: sizeText
                                text: win.human(row.it.size)
                                color: Theme.textSecondary; font.pixelSize: Theme.fs(12); font.features: ({ "tnum": 1 })
                            }
                        }
                        Rectangle {   // доля в открытой папке
                            width: parent.width; height: 4; radius: 2
                            color: Theme.surfaceHigher
                            Rectangle {
                                width: Math.max(2, parent.width * row.part); height: parent.height; radius: 2
                                color: treemap.kindColor(row.it.kind)
                            }
                        }
                    }
                    MouseArea {
                        id: rowArea
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: row.it.path !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onEntered: list.hoveredPath = row.it.path
                        onExited: if (list.hoveredPath === row.it.path) list.hoveredPath = ""
                        onClicked: mouse => {
                            if (row.it.path === "") return
                            if (mouse.button === Qt.RightButton) win.openMenu(row.it, rowArea.mapToItem(win.contentItem, mouse.x, mouse.y))
                            else win.enter(row.it)
                        }
                        onDoubleClicked: if (!row.it.dir && row.it.path !== "") scanner.open(row.it.path)
                    }
                    IconButton {
                        id: moreBtn
                        visible: row.it.path !== "" && (rowHover.hovered || row.sel)
                        anchors.right: parent.right; anchors.rightMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        glyph: 0xF01D9
                        tip: Tr.t("Действия")
                        onClicked: win.openMenu(row.it, moreBtn.mapToItem(win.contentItem, 0, height))
                    }
                }
            }
            Text {
                visible: win.items.length === 0
                anchors.centerIn: parent
                text: Tr.t("Пустая папка")
                color: Theme.textMuted; font.pixelSize: Theme.fs(13)
            }
        }
    }

    // ---- меню действий ----
    property var menuItem: null
    function openMenu(it, pt) {
        menuItem = it
        selected = it.path
        menu.x = Math.min(pt.x, width - menu.width - 8)
        menu.y = Math.min(pt.y, height - menu.height - 8)
        menu.open = true
    }
    MouseArea { anchors.fill: parent; visible: menu.open; onPressed: menu.open = false; z: 59 }
    PopupMenu {
        id: menu
        transformOrigin: Item.TopLeft
        items: !win.menuItem ? [] : [
            win.menuItem.dir ? { text: Tr.t("Открыть здесь"), run: () => win.enter(win.menuItem) }
                             : { text: Tr.t("Открыть"), run: () => scanner.open(win.menuItem.path) },
            { text: Tr.t("Показать в папке"), run: () => scanner.showInFolder(win.menuItem.path) },
            { text: win.menuItem.dir ? Tr.t("Проверить только эту папку") : "", run: () => win.start(win.menuItem.path) },
            { text: Tr.t("В корзину  Delete"), run: () => win.trash(win.menuItem) }
        ].filter(x => x.text)
    }

    Toast { id: toast }

    DropArea {
        anchors.fill: parent
        onEntered: drag => drag.accept(Qt.CopyAction)
        onDropped: drop => { if (drop.hasUrls) win.start(drop.urls[0]) }
    }
    ResizeEdges { window: win }

    // ---- клавиши ----
    Shortcut { sequences: ["Backspace", "Alt+Left"]; enabled: win.hasTree && !win.showStart; onActivated: win.up() }
    Shortcut { sequence: "F5"; enabled: win.hasTree; onActivated: win.start(scanner.root) }
    Shortcut { sequence: "Delete"; enabled: !!win.selItem; onActivated: win.trash(win.selItem) }
    Shortcut { sequence: "Return"; enabled: !!win.selItem; onActivated: win.selItem.dir ? win.enter(win.selItem) : scanner.open(win.selItem.path) }
    Shortcut { sequence: "Ctrl+Z"; enabled: scanner.canUndo; onActivated: { toast.shown = false; scanner.undoTrash() } }
    Shortcut { sequence: "F11"; onActivated: win.visibility = win.visibility === Window.FullScreen ? Window.Windowed : Window.FullScreen }
    Shortcut { sequences: ["Ctrl+W", "Ctrl+Q"]; onActivated: win.close() }
    Shortcut {
        sequence: "Esc"
        onActivated: {
            if (menu.open) menu.open = false
            else if (scanner.scanning) win.home()
            else if (win.selected) win.selected = ""
            else if (win.visibility === Window.FullScreen) win.visibility = Window.Windowed
            else win.close()
        }
    }
}
