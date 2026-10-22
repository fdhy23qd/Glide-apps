import QtQuick
import QtQuick.Window
import QtCore
import Glide.Ui
import GlideArchive

// Glide Архивы — открыть архив (папки, размеры, даты), распаковать всё или выбранное — рядом или в папку,
// открыть файл из архива двойным щелчком, создать архив из файлов (zip с паролем, 7z, tar.zst/xz/gz).
// Перетаскивание: архив — открыть, файлы и папки — упаковать.
Window {
    id: win

    property var startFiles: []
    property string startMode: ""      // "" | extract-here | create

    width: 860
    height: 580
    minimumWidth: 520
    minimumHeight: 360
    visible: true
    flags: Qt.Window | Qt.FramelessWindowHint
    color: Theme.background
    title: arc.path ? fileName + Tr.t(" — Архивы") : Tr.t("Архивы")

    Settings {
        id: prefs
        category: "archive"
        property string format: "zip"
    }

    Archive {
        id: arc
        onOpened: {
            win.folder = ""
            win.selected = ({})
            win.current = -1
            if (win.startMode === "extract-here" && !arc.needsPassword) win.extract(false)
        }
        onFailed: message => {
            if (win.startMode === "extract-here") { win.startMode = ""; win.raiseUp() }
            toast.show(message)
        }
        onPasswordRequired: (wrong, forExtract) => {
            if (win.startMode === "extract-here") win.raiseUp()
            password.ask(wrong, forExtract)
        }
        onExtracted: (dest, skipped) => {
            if (win.startMode === "extract-here") { win.nextExtractHere(); return }
            const name = dest.split("/").pop()
            toast.show((skipped ? Tr.t("Распаковано, пропущено небезопасных: ") + skipped : Tr.t("Распаковано: ") + name),
                       Tr.t("Показать"), () => arc.showInFolder(dest))
        }
        onCreated: file => {
            creator.close()
            arc.open(file)
            toast.show(Tr.t("Архив создан: ") + file.split("/").pop(), Tr.t("Показать"), () => arc.showInFolder(file))
        }
        onEntryReady: file => Qt.openUrlExternally("file://" + file)
    }
    readonly property string fileName: arc.path ? arc.path.split("/").pop() : ""

    FilePicker {
        id: picker
        property string purpose: ""     // open | extract | sources | dest
        onPicked: urls => {
            if (!urls.length) return
            if (purpose === "open") win.openArchive(urls[0])
            else if (purpose === "extract") win.extractTo(urls[0])
            else if (purpose === "sources") win.startCreate(urls)
            else if (purpose === "dest") creator.folder = arc.localPath(urls[0])
        }
    }
    function folderOf(p) { return p.substring(0, p.lastIndexOf("/")) || "/" }
    function openDialog() {
        picker.purpose = "open"
        picker.open(Tr.t("Открыть архив"), Tr.t("Архивы"), ["*.zip", "*.7z", "*.rar", "*.tar", "*.tar.*", "*.tgz", "*.txz", "*.tzst",
                     "*.gz", "*.xz", "*.zst", "*.bz2", "*.lz4", "*.iso", "*.cab", "*.jar", "*.cbz", "*.cbr"],
                     arc.path ? folderOf(arc.path) : "")
    }
    function pickSources() {
        picker.purpose = "sources"
        picker.open(Tr.t("Что упаковать"), "", [], arc.path ? folderOf(arc.path) : "", true)
    }

    // ---------- что открыто ----------
    function openArchive(p) {
        password.close()
        arc.open(p)
    }
    function startCreate(urls) {
        const info = arc.sourcesInfo(urls)
        if (!info.count) { toast.show(Tr.t("Нечего упаковывать")); return }
        creator.show(info, arc.suggestName(info.paths, "zip"))
    }
    function raiseUp() { win.visible = true; win.requestActivate() }

    // ---------- папки внутри архива ----------
    property string folder: ""                  // «» — корень
    readonly property var items: {
        const f = folder, out = []
        for (const e of arc.entries) if (e.parent === f) out.push(e)
        return out
    }
    property var selected: ({})                 // путь → true
    property int current: -1                    // строка под клавиатурой
    property int anchorRow: -1                  // откуда тянуть выделение с Shift
    readonly property var selectedPaths: Object.keys(selected)
    readonly property var selectedSize: {
        let s = 0
        for (const e of items) if (selected[e.path]) s += Math.max(0, e.size)
        return s
    }
    function enter(path) { folder = path; selected = ({}); current = items.length ? 0 : -1; list.positionViewAtBeginning() }
    function up() {
        if (!folder) return
        const was = folder
        enter(folder.lastIndexOf("/") > 0 ? folder.substring(0, folder.lastIndexOf("/")) : "")
        for (let i = 0; i < items.length; ++i) if (items[i].path === was) { current = i; list.positionViewAtIndex(i, ListView.Contain) }
    }
    function select(row, mods) {
        const e = items[row]
        if (!e) return
        const s = Object.assign({}, selected)
        if (mods & Qt.ShiftModifier && anchorRow >= 0) {
            const a = Math.min(anchorRow, row), b = Math.max(anchorRow, row)
            if (!(mods & Qt.ControlModifier)) for (const k in s) delete s[k]
            for (let i = a; i <= b; ++i) s[items[i].path] = true
        } else if (mods & Qt.ControlModifier) {
            if (s[e.path]) delete s[e.path]; else s[e.path] = true
            anchorRow = row
        } else {
            for (const k in s) delete s[k]
            s[e.path] = true
            anchorRow = row
        }
        selected = s
        current = row
    }
    function selectAll() {
        const s = {}
        for (const e of items) s[e.path] = true
        selected = s
    }
    function activate(row) {
        const e = items[row]
        if (!e) return
        if (e.dir) enter(e.path)
        else { retry = () => arc.openEntry(e.path); arc.openEntry(e.path) }
    }

    // ---------- распаковка ----------
    property var retry: null                    // что повторить после ввода пароля
    function extract(toFolder) {
        if (!arc.path) return
        if (toFolder) {
            picker.purpose = "extract"
            picker.openFolder(Tr.t("Куда распаковать"), folderOf(arc.path))
            return
        }
        const paths = selectedPaths
        retry = () => arc.extract(paths, "")
        arc.extract(paths, "")
    }
    function extractTo(url) {
        const paths = selectedPaths
        retry = () => arc.extract(paths, url)
        arc.extract(paths, url)
    }
    // --extract-here для нескольких архивов: по очереди, потом выход
    property int extractIndex: 0
    function nextExtractHere() {
        extractIndex += 1
        if (extractIndex < startFiles.length) arc.open(startFiles[extractIndex])
        else Qt.quit()
    }

    Component.onCompleted: {
        if (startMode === "create" && startFiles.length) {
            startCreate(startFiles)
        } else if (startFiles.length) {
            if (startMode === "extract-here") win.visible = false   // окно — только если что-то пойдёт не так
            arc.open(startFiles[0])
        }
    }
    // прогресс --extract-here: показываем окно, если распаковка дольше секунды
    Timer {
        interval: 1000
        running: win.startMode === "extract-here" && arc.busy && !win.visible
        onTriggered: win.visible = true
    }

    // ---------- оформление ----------
    function human(b) {
        if (b < 0) return "—"
        const u = [Tr.t("Б"), Tr.t("КБ"), Tr.t("МБ"), Tr.t("ГБ"), Tr.t("ТБ")]
        let i = 0
        while (b >= 1024 && i < 4) { b /= 1024; ++i }
        return (i === 0 ? String(b) : b.toFixed(b < 10 ? 1 : 0).replace(".", Tr.ru ? "," : ".")) + " " + u[i]
    }
    function plural(n, one, few, many) {
        const m10 = n % 10, m100 = n % 100
        return n + " " + (m10 === 1 && m100 !== 11 ? one : m10 >= 2 && m10 <= 4 && (m100 < 10 || m100 >= 20) ? few : many)
    }
    function glyphFor(e) {
        if (e.dir) return 0xF024B
        const ext = e.name.indexOf(".") > 0 ? e.name.split(".").pop().toLowerCase() : ""
        if (["jpg", "jpeg", "png", "webp", "gif", "bmp", "svg", "avif", "heic", "tif", "tiff", "jxl"].includes(ext)) return 0xF021F
        if (["mp4", "mkv", "webm", "avi", "mov", "m4v"].includes(ext)) return 0xF022B
        if (["mp3", "flac", "ogg", "opus", "wav", "m4a", "aac"].includes(ext)) return 0xF0223
        if (ext === "pdf") return 0xF0226
        if (["zip", "7z", "rar", "tar", "gz", "xz", "zst", "bz2", "tgz", "iso", "jar"].includes(ext)) return 0xF003C
        if (["c", "h", "cpp", "hpp", "py", "js", "ts", "qml", "rs", "go", "java", "sh", "json", "xml", "html", "css", "kdl", "toml", "yaml", "yml"].includes(ext)) return 0xF022E
        if (["txt", "md", "doc", "docx", "odt", "rtf", "csv", "xls", "xlsx", "ods", "ppt", "pptx"].includes(ext)) return 0xF0219
        return 0xF0224
    }

    Rectangle {
        id: header
        width: parent.width
        height: 52
        color: Theme.background
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.outline }
        DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }

        Row {
            id: lead
            x: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            IconButton { glyph: 0xF005D; tip: Tr.t("Наверх  Backspace"); enabled: win.folder !== ""; visible: arc.path !== ""; onClicked: win.up() }
        }
        // путь: архив › папка › папка — каждое звено кликабельно
        ListView {
            id: crumbs
            anchors.left: lead.right
            anchors.leftMargin: 6
            anchors.right: tail.left
            anchors.rightMargin: 12
            height: parent.height
            orientation: ListView.Horizontal
            interactive: contentWidth > width
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: {
                if (!arc.path) return [{ label: Tr.t("Архивы"), path: null }]
                const out = [{ label: win.fileName, path: "" }]
                if (win.folder) {
                    const parts = win.folder.split("/")
                    for (let i = 0; i < parts.length; ++i) out.push({ label: parts[i], path: parts.slice(0, i + 1).join("/") })
                }
                return out
            }
            onCountChanged: positionViewAtEnd()
            delegate: Row {
                id: crumb
                required property var modelData
                required property int index
                readonly property bool last: index === crumbs.count - 1
                height: crumbs.height
                spacing: 2
                Text {
                    visible: crumb.index > 0
                    anchors.verticalCenter: parent.verticalCenter
                    text: Theme.icon(0xF0142)
                    color: Theme.textMuted
                    font.family: Theme.iconFont
                    font.pixelSize: Theme.fs(16)
                }
                Rectangle {
                    Behavior on color { ColorAnimation { duration: 140 } }
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(crumbLabel.implicitWidth + 20, 260)
                    height: 32
                    radius: height / 2
                    color: crumbArea.pressed ? Theme.surfacePressed : crumbArea.containsMouse ? Theme.surfaceHigher : "transparent"
                    scale: crumbArea.pressed ? 0.95 : 1
                    Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
                    Text {
                        id: crumbLabel
                        Behavior on color { ColorAnimation { duration: 140 } }
                        anchors.centerIn: parent
                        width: Math.min(implicitWidth, 240)
                        text: crumb.modelData.label
                        color: crumb.last ? Theme.text : Theme.textSecondary
                        font.pixelSize: Theme.fs(14)
                        font.weight: crumb.last ? Font.DemiBold : Font.Normal
                        elide: Text.ElideMiddle
                        textFormat: Text.PlainText
                    }
                    MouseArea {
                        id: crumbArea
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: !crumb.last && crumb.modelData.path !== null
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: win.enter(crumb.modelData.path)
                    }
                }
            }
        }
        Row {
            id: tail
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            readonly property bool wide: win.width > 700
            TextButton {
                visible: arc.path !== "" && !arc.needsPassword
                anchors.verticalCenter: parent.verticalCenter
                implicitHeight: 36
                primary: true
                glyph: 0xF03D4
                text: win.selectedPaths.length ? (tail.wide ? Tr.t("Распаковать выбранное") : Tr.t("Выбранное")) : Tr.t("Распаковать")
                enabled: !arc.busy
                onClicked: win.extract(false)
            }
            IconButton { visible: arc.path !== "" && !arc.needsPassword; glyph: 0xF0770; tip: Tr.t("Распаковать в папку…  Ctrl+Shift+E"); enabled: !arc.busy; onClicked: win.extract(true) }
            Item { width: 6; height: 1 }
            IconButton { glyph: 0xF0415; tip: Tr.t("Новый архив  Ctrl+N"); enabled: !arc.busy; onClicked: win.pickSources() }
            IconButton { glyph: 0xF003C; tip: Tr.t("Открыть архив  Ctrl+O"); enabled: !arc.busy; onClicked: win.openDialog() }
            IconButton { glyph: 0xF0156; tip: Tr.t("Закрыть  Ctrl+W"); onClicked: win.close() }
        }
    }

    // ---------- пусто: подсказка ----------
    Column {
        opacity: !arc.path && !creator.open ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 160 } }
        anchors.centerIn: parent
        anchors.verticalCenterOffset: 16
        spacing: 14
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 88; height: 88
            radius: Theme.radiusXl
            color: Theme.surface
            border.color: Theme.outline
            Text {
                anchors.centerIn: parent
                text: Theme.icon(0xF003C)
                color: Theme.accent
                font.family: Theme.iconFont
                font.pixelSize: Theme.fs(44)
            }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Tr.t("Перетащите архив — он откроется,\nили файлы и папки — они упакуются")
            horizontalAlignment: Text.AlignHCenter
            color: Theme.textSecondary
            font.pixelSize: Theme.fs(14)
            lineHeight: 1.2
        }
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8
            TextButton { primary: true; glyph: 0xF003C; text: Tr.t("Открыть архив"); onClicked: win.openDialog() }
            TextButton { glyph: 0xF0415; text: Tr.t("Создать архив"); onClicked: win.pickSources() }
        }
    }

    // ---------- архив под паролем, а список ещё не прочитан ----------
    Column {
        opacity: arc.path !== "" && arc.needsPassword && !password.open ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 160 } }
        anchors.centerIn: parent
        spacing: 12
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Theme.icon(0xF033E)
            color: Theme.textSecondary
            font.family: Theme.iconFont
            font.pixelSize: Theme.fs(40)
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Tr.t("Даже список файлов этого архива зашифрован")
            color: Theme.textSecondary
            font.pixelSize: Theme.fs(14)
        }
        TextButton { anchors.horizontalCenter: parent.horizontalCenter; primary: true; text: Tr.t("Ввести пароль"); onClicked: password.ask(false, false) }
    }

    // ---------- список ----------
    Rectangle {   // шапка колонок
        id: columns
        visible: list.visible
        y: header.height
        width: parent.width
        height: 30
        color: Theme.background
        Text { x: 64; anchors.verticalCenter: parent.verticalCenter; text: Tr.t("Имя"); color: Theme.textMuted; font.pixelSize: Theme.fs(12) }
        Text {
            anchors.right: dateHead.left; anchors.rightMargin: 16; anchors.verticalCenter: parent.verticalCenter
            width: 96; horizontalAlignment: Text.AlignRight
            text: Tr.t("Размер"); color: Theme.textMuted; font.pixelSize: Theme.fs(12)
        }
        Text {
            id: dateHead
            visible: win.width > 620
            anchors.right: parent.right; anchors.rightMargin: 24; anchors.verticalCenter: parent.verticalCenter
            width: visible ? 120 : 0
            text: Tr.t("Изменён"); color: Theme.textMuted; font.pixelSize: Theme.fs(12)
        }
    }
    ListView {
        id: list
        visible: arc.path !== "" && !arc.needsPassword
        y: columns.y + columns.height
        width: parent.width
        height: parent.height - y - status.height
        clip: true
        model: win.items
        boundsBehavior: Flickable.StopAtBounds
        focus: true
        keyNavigationEnabled: false
        Keys.onPressed: event => {
            const n = win.items.length
            if (event.key === Qt.Key_Up && event.modifiers & Qt.AltModifier) {
                win.up()
                event.accepted = true
            } else if (event.key === Qt.Key_Down || event.key === Qt.Key_Up) {
                if (!n) return
                const r = Math.max(0, Math.min(n - 1, win.current + (event.key === Qt.Key_Down ? 1 : -1)))
                win.select(r, event.modifiers & Qt.ShiftModifier ? Qt.ShiftModifier : 0)
                list.positionViewAtIndex(r, ListView.Contain)
                event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                if (win.current >= 0) win.activate(win.current)
                event.accepted = true
            } else if (event.key === Qt.Key_Backspace) {
                win.up()
                event.accepted = true
            }
        }
        // пустое место под строками — снять выделение
        MouseArea {
            z: -1
            width: list.width
            height: Math.max(list.height, list.contentHeight)
            onClicked: { win.selected = ({}); list.forceActiveFocus() }
        }
        delegate: Item {
            id: entryRow
            required property var modelData
            required property int index
            readonly property bool on: !!win.selected[modelData.path]
            width: list.width
            height: 44
            Rectangle {   // ListView ставит x делегата сам — отступ у внутреннего прямоугольника
                x: 8
                width: parent.width - 16
                height: parent.height
                radius: Theme.radiusSm
                color: entryRow.on ? (rowArea.pressed ? Theme.accentHover : rowArea.containsMouse ? Qt.lighter(Theme.accentSoft, 1.3) : Theme.accentSoft)
                          : rowArea.pressed ? Theme.surfacePressed : rowArea.containsMouse ? Theme.surface : "transparent"
                border.width: entryRow.index === win.current && list.activeFocus ? 1 : 0
                border.color: Theme.outlineHover
                Behavior on color { ColorAnimation { duration: 90 } }

                Text {
                    id: rowIcon
                    x: 14
                    anchors.verticalCenter: parent.verticalCenter
                    width: 28
                    text: Theme.icon(win.glyphFor(entryRow.modelData))
                    color: entryRow.modelData.dir ? Theme.accent : Theme.textSecondary
                    font.family: Theme.iconFont
                    font.pixelSize: Theme.fs(20)
                }
                Text {
                    anchors.left: rowIcon.right
                    anchors.leftMargin: 14
                    anchors.right: lockIcon.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: entryRow.modelData.name
                    color: Theme.text
                    font.pixelSize: Theme.fs(14)
                    elide: Text.ElideMiddle
                    textFormat: Text.PlainText
                }
                Text {
                    id: lockIcon
                    anchors.right: sizeText.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: entryRow.modelData.enc ? implicitWidth : 0
                    text: entryRow.modelData.enc ? Theme.icon(0xF033E) : ""
                    color: Theme.textMuted
                    font.family: Theme.iconFont
                    font.pixelSize: Theme.fs(14)
                }
                Text {
                    id: sizeText
                    anchors.right: dateText.left
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    width: 96
                    horizontalAlignment: Text.AlignRight
                    text: entryRow.modelData.dir ? win.plural(entryRow.modelData.count || 0, Tr.t("объект"), Tr.t("объекта"), Tr.t("объектов"))
                                                 : entryRow.modelData.link ? Tr.t("ссылка") : win.human(entryRow.modelData.size)
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fs(13)
                }
                Text {
                    id: dateText
                    visible: dateHead.visible
                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    width: visible ? 120 : 0
                    text: entryRow.modelData.mtime > 0 ? Qt.formatDateTime(new Date(entryRow.modelData.mtime), "dd.MM.yyyy  HH:mm") : ""
                    color: Theme.textMuted
                    font.pixelSize: Theme.fs(13)
                }
                MouseArea {
                    id: rowArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    // по выбранной строке без модификаторов — выделение сбрасываем на отпускании (вдруг это двойной щелчок)
                    onPressed: mouse => {
                        list.forceActiveFocus()
                        if (!entryRow.on || mouse.modifiers & (Qt.ControlModifier | Qt.ShiftModifier)) win.select(entryRow.index, mouse.modifiers)
                    }
                    onClicked: mouse => { if (entryRow.on && !(mouse.modifiers & (Qt.ControlModifier | Qt.ShiftModifier))) win.select(entryRow.index, 0) }
                    onDoubleClicked: win.activate(entryRow.index)
                }
            }
        }
        Text {
            visible: list.count === 0 && !arc.busy
            anchors.centerIn: parent
            text: Tr.t("Пусто")
            color: Theme.textMuted
            font.pixelSize: Theme.fs(14)
        }
    }

    // ---------- строка состояния ----------
    Rectangle {
        id: status
        visible: arc.path !== "" && !arc.needsPassword
        anchors.bottom: parent.bottom
        width: parent.width
        height: visible ? 34 : 0
        color: Theme.background
        Rectangle { width: parent.width; height: 1; color: Theme.outline }
        Text {
            x: 16
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 32
            elide: Text.ElideRight
            color: Theme.textSecondary
            font.pixelSize: Theme.fs(12)
            text: {
                if (win.selectedPaths.length)
                    return Tr.t("Выбрано: ") + win.selectedPaths.length + " · " + win.human(win.selectedSize)
                let files = 0, dirs = 0
                for (const e of arc.entries) { if (e.dir) ++dirs; else ++files }
                const parts = [win.plural(files, Tr.t("файл"), Tr.t("файла"), Tr.t("файлов"))]
                if (dirs) parts.push(win.plural(dirs, Tr.t("папка"), Tr.t("папки"), Tr.t("папок")))
                parts.push(win.human(arc.totalSize))
                if (arc.format) parts.push(arc.format)
                if (arc.encrypted) parts.push(Tr.t("зашифрован"))
                return parts.join(" · ")
            }
        }
    }

    // ---------- перетаскивание ----------
    DropArea {
        id: drop
        anchors.fill: parent
        enabled: !arc.busy && !password.open
        onEntered: drag => { if (drag.hasUrls) drag.accept(Qt.CopyAction) }
        onDropped: ev => {
            if (!ev.hasUrls) return
            const urls = ev.urls.map(u => u.toString())
            if (creator.open) creator.add(urls)
            else if (urls.length === 1 && arc.isArchive(urls[0])) win.openArchive(urls[0])
            else win.startCreate(urls)
        }
    }
    Rectangle {   // подсветка, пока несут файлы
        anchors.fill: parent
        anchors.margins: 10
        visible: drop.containsDrag
        radius: Theme.radiusLg
        color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.08)
        border.width: 2
        border.color: Theme.accent
        z: 80
        Text {
            anchors.centerIn: parent
            text: creator.open ? Tr.t("Добавить к упаковке") : Tr.t("Архив — открыть, файлы — упаковать")
            color: Theme.text
            font.pixelSize: Theme.fs(16)
            font.weight: Font.DemiBold
        }
    }

    // ---------- создание ----------
    CreatePanel {
        id: creator
        anchors.fill: parent
        z: 85
        format: prefs.format
        onFormatChanged: prefs.format = format
        working: arc.busy
        onPickFolder: { picker.purpose = "dest"; picker.openFolder(Tr.t("Где сохранить архив"), creator.folder) }
        onAccepted: (out, fmt, pw) => arc.create(creator.info.paths, out, fmt, pw)
        onAddRequested: urls => creator.info = arc.sourcesInfo(creator.info.paths.concat(urls.map(u => arc.localPath(u))))
        onCancelled: { if (win.startMode === "create" && !arc.path) Qt.quit() }
        homeOf: p => arc.homePath(p)
        humanSize: b => win.human(b)
        countText: (f, d) => win.plural(f, Tr.t("файл"), Tr.t("файла"), Tr.t("файлов")) + (d ? ", " + win.plural(d, Tr.t("папка"), Tr.t("папки"), Tr.t("папок")) : "")
    }

    // ---------- пароль ----------
    Item {
        id: password
        property bool open: false
        property bool wrong: false
        property bool forExtract: false
        function ask(w, ext) {
            wrong = w
            forExtract = ext
            open = true
            pwField.text = ""
            pwField.focusAll()
        }
        function close() { open = false; list.forceActiveFocus() }
        function submit() {
            if (!pwField.text) return
            open = false
            if (forExtract) { arc.setPassword(pwField.text); if (win.retry) win.retry() }
            else arc.open(arc.path, pwField.text)
        }
        anchors.fill: parent
        visible: opacity > 0
        opacity: open ? 1 : 0
        z: 90
        Behavior on opacity { NumberAnimation { duration: 140 } }
        Rectangle { anchors.fill: parent; color: Theme.scrim }
        MouseArea { anchors.fill: parent; onClicked: password.close() }
        Rectangle {
            anchors.centerIn: parent
            width: Math.min(380, parent.width - 32)
            height: pwCol.implicitHeight + 40
            radius: Theme.radiusLg
            color: Theme.surface
            border.color: Theme.outline
            scale: password.open ? 1 : 0.96
            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
            MouseArea { anchors.fill: parent }
            Column {
                id: pwCol
                x: 20; y: 20
                width: parent.width - 40
                spacing: 14
                Row {
                    spacing: 10
                    Text { anchors.verticalCenter: parent.verticalCenter; text: Theme.icon(0xF033E); color: password.wrong ? Theme.error : Theme.accent; font.family: Theme.iconFont; font.pixelSize: Theme.fs(22) }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: password.wrong ? Tr.t("Пароль не подошёл") : Tr.t("Архив защищён паролем")
                        color: Theme.text
                        font.pixelSize: Theme.fs(16)
                        font.weight: Font.DemiBold
                    }
                }
                Text {
                    width: parent.width
                    text: win.fileName
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fs(13)
                    elide: Text.ElideMiddle
                    textFormat: Text.PlainText
                }
                TextField {
                    id: pwField
                    width: parent.width
                    password: true
                    glyph: 0xF033E
                    placeholder: Tr.t("Пароль")
                    error: password.wrong && text === ""
                    onAccepted: password.submit()
                    onCancelled: password.close()
                }
                Row {
                    anchors.right: parent.right
                    spacing: 8
                    TextButton { text: Tr.t("Отмена"); flat: true; onClicked: password.close() }
                    TextButton { text: password.forExtract ? Tr.t("Распаковать") : Tr.t("Открыть"); primary: true; enabled: pwField.text !== ""; onClicked: password.submit() }
                }
            }
        }
    }

    // ---------- прогресс ----------
    Item {
        id: progressView
        anchors.fill: parent
        z: 95
        // короткие операции (список, маленький архив) — без мигания карточки
        property bool shown: false
        Timer { interval: 350; running: arc.busy; onTriggered: progressView.shown = true }
        Connections { target: arc; function onBusyChanged() { if (!arc.busy) progressView.shown = false } }
        visible: opacity > 0
        opacity: shown && arc.busy ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 140 } }
        Rectangle { anchors.fill: parent; color: Theme.scrim }
        MouseArea { anchors.fill: parent; hoverEnabled: true }
        Rectangle {
            anchors.centerIn: parent
            width: Math.min(400, parent.width - 32)
            height: 132
            radius: Theme.radiusLg
            color: Theme.surface
            border.color: Theme.outline
            Text {
                x: 20; y: 20
                text: arc.progress > 0 ? Tr.t("Работаю…  ") + Math.round(arc.progress * 100) + "%" : Tr.t("Работаю…")
                color: Theme.text
                font.pixelSize: Theme.fs(15)
                font.weight: Font.DemiBold
            }
            Rectangle {
                x: 20; y: 56
                width: parent.width - 40
                height: 6
                radius: 3
                color: Theme.surfaceHigh
                Rectangle {
                    width: parent.width * Math.max(0.02, arc.progress)
                    height: parent.height
                    radius: 3
                    color: Theme.accent
                    Behavior on width { NumberAnimation { duration: 200 } }
                }
            }
            TextButton {
                anchors.right: parent.right; anchors.rightMargin: 16
                anchors.bottom: parent.bottom; anchors.bottomMargin: 14
                implicitHeight: 34
                flat: true
                text: Tr.t("Отмена")
                onClicked: arc.cancel()
            }
        }
    }

    Toast { id: toast }
    ResizeEdges { window: win }

    // ---------- клавиши ----------
    readonly property bool calm: !password.open && !creator.open && !arc.busy
    Shortcut { sequences: ["Ctrl+W", "Ctrl+Q"]; onActivated: win.close() }
    Shortcut { sequence: "Ctrl+O"; enabled: win.calm; onActivated: win.openDialog() }
    Shortcut { sequence: "Ctrl+N"; enabled: win.calm; onActivated: win.pickSources() }
    Shortcut { sequence: "Ctrl+E"; enabled: win.calm && arc.path !== ""; onActivated: win.extract(false) }
    Shortcut { sequence: "Ctrl+Shift+E"; enabled: win.calm && arc.path !== ""; onActivated: win.extract(true) }
    Shortcut { sequence: "Ctrl+A"; enabled: win.calm && list.visible; onActivated: win.selectAll() }
    Shortcut {
        sequence: "Escape"
        enabled: !password.open && !creator.open
        onActivated: { if (arc.busy) arc.cancel(); else if (win.selectedPaths.length) win.selected = ({}); else win.up() }
    }
    Shortcut { sequence: "F11"; onActivated: win.visibility = win.visibility === Window.FullScreen ? Window.Windowed : Window.FullScreen }
}
