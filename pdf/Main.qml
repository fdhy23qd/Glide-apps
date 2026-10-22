import QtQuick
import QtQuick.Window
import QtQuick.Pdf
import QtCore
import Glide.Ui
import GlidePdf

// Glide PDF — лёгкий просмотрщик: страницы лентой, масштаб (по ширине / страница / проценты), поиск,
// оглавление и миниатюры, ссылки, выделение и копирование текста, ночной режим, пароль,
// продолжение с того места, где остановились.
Window {
    id: win

    property string startPath: ""

    width: 1000
    height: 760
    minimumWidth: 480
    minimumHeight: 360
    visible: true
    flags: Qt.Window | Qt.FramelessWindowHint
    color: Theme.background
    title: path ? fileName + " — PDF" : "PDF"

    readonly property bool fullscreen: visibility === Window.FullScreen
    function toggleFullscreen() { visibility = fullscreen ? Window.Windowed : Window.FullScreen }

    Settings {
        id: prefs
        category: "pdf"
        property bool night: false
        property bool sidebar: false
    }
    Library { id: lib }
    FilePicker {
        id: picker
        onPicked: urls => { if (urls.length) win.openFile(urls[0]) }
    }
    function openDialog() { picker.open(Tr.t("Открыть PDF"), Tr.t("Документы PDF"), ["*.pdf"], path ? lib.fileInfo(path).folder : "") }

    // ---------- документ ----------
    property string path: ""
    readonly property string fileName: path ? path.split("/").pop() : ""
    property bool needPassword: false
    property bool wrongPassword: false
    property bool restored: false

    function openFile(p) {
        savePosition()
        var local = lib.localPath(p)
        if (!local) return
        if (!lib.fileInfo(local).exists) { toast.show(Tr.t("Файл не найден: ") + local.split("/").pop()); return }
        needPassword = false
        wrongPassword = false
        restored = false
        history = []
        search.searchString = ""
        searchBar.open = false
        selectionOwner = null
        path = local
        doc.password = ""
        doc.source = lib.fileUrl(local)
    }
    // документ — после первого кадра: окно появляется сразу, а pdfium (~0,35 с) грузится уже в нём
    property bool started: false
    onFrameSwapped: if (!started) { started = true; if (startPath) Qt.callLater(() => win.openFile(win.startPath)) }

    PdfDocument {
        id: doc
        onPasswordRequired: {
            const wrong = win.needPassword && doc.password !== ""   // уже спрашивали — значит, пароль не подошёл
            passwordField.text = ""          // до флага: очистка поля сбрасывает wrongPassword
            win.needPassword = true
            win.wrongPassword = wrong
            passwordField.focusAll()
        }
        onStatusChanged: {
            if (doc.status === PdfDocument.Ready) {
                win.needPassword = false
                Qt.callLater(win.restorePosition)
            }
        }
    }
    readonly property var pdf: doc            // для делегатов страниц и боковой панели
    readonly property bool ready: doc.status === PdfDocument.Ready && doc.pageCount > 0

    // ---------- масштаб ----------
    property string fit: "width"        // width | page | none
    property real zoom: 1               // логических пикселей на пункт PDF
    property real renderZoom: 1         // в каком разрешении рисуются страницы: догоняет zoom с задержкой
    property int pageRotation: 0
    readonly property bool night: prefs.night
    onZoomChanged: renderTimer.restart()
    Timer { id: renderTimer; interval: 180; onTriggered: win.renderZoom = win.zoom }

    readonly property real maxPageW: (pageRotation % 180 === 90 ? doc.maxPageHeight : doc.maxPageWidth) || 595
    readonly property real pageAreaWidth: Math.max(pages.width, maxPageW * zoom + 32)
    readonly property int percent: Math.round(zoom * 100 * 72 / 96)   // 100 % — как на бумаге (96 точек на дюйм)

    function fitZoom(mode) {
        if (!ready) return zoom
        if (mode === "width") return Math.max(0.1, (pages.width - 40) / maxPageW)
        var s = doc.pagePointSize(currentPage)
        var w = pageRotation % 180 === 90 ? s.height : s.width, h = pageRotation % 180 === 90 ? s.width : s.height
        return Math.max(0.1, Math.min((pages.width - 40) / w, (pages.height - 20) / h))
    }
    // сменить масштаб, не потеряв место: та же точка страницы остаётся в центре окна
    function keepPlace(change) {
        var cy = pages.contentY + pages.height / 2
        var idx = pages.indexAt(pages.contentX + 2, cy)
        var it = idx >= 0 ? pages.itemAtIndex(idx) : null
        var frac = it ? (cy - it.y) / it.height : 0
        var xfrac = pages.contentWidth > pages.width ? (pages.contentX + pages.width / 2) / pages.contentWidth : 0.5
        change()
        if (idx < 0) return
        pages.forceLayout()
        pages.positionViewAtIndex(idx, ListView.Beginning)
        var it2 = pages.itemAtIndex(idx)
        if (it2) pages.contentY = it2.y + frac * it2.height - pages.height / 2
        pages.contentX = Math.max(0, xfrac * pages.contentWidth - pages.width / 2)
        pages.returnToBounds()
    }
    function setZoom(z, mode) {
        keepPlace(() => { win.fit = mode || "none"; win.zoom = Math.max(0.1, Math.min(8, z)) })
        hint.show(mode === "width" ? Tr.t("По ширине") : mode === "page" ? Tr.t("Страница целиком") : percent + "%")
    }
    function zoomBy(k) { setZoom(zoom * k) }
    function refit() { if (fit !== "none" && ready) keepPlace(() => { win.zoom = win.fitZoom(win.fit) }) }
    Connections {
        target: pages
        function onWidthChanged() { win.refit() }
        function onHeightChanged() { if (win.fit === "page") win.refit() }
    }
    function rotate() { keepPlace(() => { win.pageRotation = (win.pageRotation + 90) % 360; if (win.fit !== "none") win.zoom = win.fitZoom(win.fit) }) }

    // ---------- страницы: где мы и куда идём ----------
    property int currentPage: 0
    property var history: []            // откуда переходили по ссылкам и оглавлению — Alt+← вернёт
    function updateCurrent() {
        // докрутили до конца — текущая последняя, даже если она не встала к верху окна
        var atEnd = pages.contentY >= pages.originY + pages.contentHeight - pages.height - 2
        var idx = atEnd && ready ? doc.pageCount - 1 : pages.indexAt(pages.contentX + 2, pages.contentY + pages.height * 0.4)
        if (idx >= 0 && idx !== currentPage) { currentPage = idx; positionSaver.restart() }
    }
    function remember() {
        var h = history.slice()
        h.push({ page: currentPage, y: pages.contentY })
        history = h.slice(-50)
    }
    function back() {
        if (!history.length) return
        var h = history.slice(), e = h.pop()
        history = h
        pages.positionViewAtIndex(e.page, ListView.Beginning)
        pages.contentY = e.y
        pages.returnToBounds()
    }
    function goToPage(n, rememberIt) {
        if (!ready) return
        n = Math.max(0, Math.min(doc.pageCount - 1, n))
        if (rememberIt) remember()
        pages.positionViewAtIndex(n, ListView.Beginning)
        currentPage = n
    }
    // location — точка на странице в пунктах; ставим её на треть высоты окна
    function goToLocation(n, location, rememberIt) {
        goToPage(n, rememberIt)
        var it = pages.itemAtIndex(n)
        if (it && location && location.y > 0) {
            pages.contentY = it.y + 6 + location.y * zoom - pages.height / 3
            pages.returnToBounds()
        }
    }
    function scrollBy(dy) {
        pages.contentY = Math.max(pages.originY, Math.min(pages.originY + pages.contentHeight - pages.height, pages.contentY + dy))
    }
    function openExternal(url) {
        if (/^(https?:|mailto:)/i.test(url)) Qt.openUrlExternally(url)
        else toast.show(Tr.t("Такие ссылки не открываю: ") + url)   // file:, javascript: и прочее — небезопасно
    }

    // ---------- место чтения ----------
    function savePosition() {
        if (!path || !ready) return
        var it = pages.itemAtIndex(currentPage)
        lib.savePosition(path, { page: currentPage, offset: it ? (pages.contentY - it.y) / it.height : 0,
                                 fit: fit, zoom: zoom, rotation: pageRotation })
    }
    Timer { id: positionSaver; interval: 2000; onTriggered: win.savePosition() }
    function restorePosition() {
        var p = lib.position(path)
        pageRotation = p.rotation || 0
        fit = p.fit || "width"
        zoom = fit === "none" && p.zoom > 0 ? p.zoom : fitZoom(fit)
        renderZoom = zoom
        pages.forceLayout()
        if (p.page > 0 || p.offset > 0) {
            goToPage(p.page || 0, false)
            var it = pages.itemAtIndex(p.page || 0)
            if (it) { pages.contentY = it.y + (p.offset || 0) * it.height; pages.returnToBounds() }
            if (p.page > 0) toast.show(Tr.t("Продолжено со страницы ") + (p.page + 1), Tr.t("С начала"), () => win.goToPage(0, false))
        } else {
            pages.positionViewAtBeginning()
        }
        restored = true
        updateCurrent()
    }
    onClosing: savePosition()

    // ---------- поиск и выделение ----------
    PdfSearchModel {
        id: search
        document: doc
        onCurrentResultLinkChanged: {
            var l = currentResultLink
            if (l && l.page >= 0 && searchBar.open) win.goToLocation(l.page, l.location, false)
        }
    }
    // count у PdfSearchModel в этой сборке Qt из QML не виден (ревизия 6.8 не дошла до типа QML) —
    // считаем сами по сигналам модели
    property int resultCount: 0
    function recount() {
        resultCount = search.rowCount()
        searchRev++
        if (resultCount > 0 && (search.currentResult < 0 || search.currentResult >= resultCount)) search.currentResult = 0
    }
    Connections {
        target: search
        function onModelReset() { win.recount() }
        function onRowsInserted() { win.recount() }
        function onRowsRemoved() { win.recount() }
        function onSearchStringChanged() { win.recount() }
        function onLayoutChanged() { win.recount() }
    }
    readonly property var searchModel: search
    property int searchRev: 0
    readonly property bool searchActive: searchBar.open && search.searchString !== ""

    property var selectionOwner: null
    onSelectionOwnerChanged: {   // выделяют на другой странице — прежнее выделение снимаем
        if (lastOwner && lastOwner !== selectionOwner) lastOwner.clear()
        lastOwner = selectionOwner
    }
    property var lastOwner: null
    function copySelection() {
        if (selectionOwner && selectionOwner.text) { selectionOwner.copyToClipboard(); toast.show(Tr.t("Текст скопирован")) }
    }
    function selectAllOnPage() {
        var it = pages.itemAtIndex(currentPage)
        if (it) it.selection.selectAll()
    }
    property string hoverLink: ""

    // ---------- раскладка ----------
    Rectangle {
        id: header
        width: parent.width
        height: win.fullscreen ? 0 : 52
        visible: height > 0
        color: Theme.background
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.outline }
        DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }
        TapHandler { onDoubleTapped: win.toggleFullscreen() }

        Row {
            id: left
            x: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            IconButton { glyph: 0xF0836; tip: Tr.t("Оглавление и страницы  F9"); on: sidebar.open; enabled: win.ready; onClicked: prefs.sidebar = !prefs.sidebar }
            IconButton { visible: win.history.length > 0; glyph: 0xF004D; tip: Tr.t("Назад  Alt+←"); onClicked: win.back() }
        }
        Column {
            anchors.left: left.right
            anchors.leftMargin: 8
            anchors.right: center.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            Text {
                width: parent.width
                text: win.path ? win.fileName : "PDF"
                color: Theme.text
                font.pixelSize: Theme.fs(14)
                font.weight: Font.DemiBold
                elide: Text.ElideMiddle
                textFormat: Text.PlainText
            }
            Text {
                width: parent.width
                visible: win.ready && text !== ""
                text: doc.title && doc.title !== win.fileName ? doc.title : ""
                color: Theme.textSecondary
                font.pixelSize: Theme.fs(11)
                elide: Text.ElideRight
                textFormat: Text.PlainText
            }
        }

        Row {   // страница и масштаб
            id: center
            anchors.right: right.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            visible: win.ready
            TextField {
                id: pageField
                width: 56
                implicitHeight: 32
                anchors.verticalCenter: parent.verticalCenter
                input.horizontalAlignment: TextInput.AlignHCenter
                input.validator: IntValidator { bottom: 1; top: Math.max(1, doc.pageCount) }
                text: win.currentPage + 1
                onAccepted: { win.goToPage(parseInt(text) - 1, true); text = Qt.binding(() => win.currentPage + 1); pages.forceActiveFocus() }
                onCancelled: { text = Qt.binding(() => win.currentPage + 1); pages.forceActiveFocus() }
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Tr.t("из ") + doc.pageCount
                color: Theme.textSecondary
                font.pixelSize: Theme.fs(13)
                rightPadding: 10
            }
            IconButton { anchors.verticalCenter: parent.verticalCenter; glyph: 0xF06EC; tip: Tr.t("Уменьшить  Ctrl+−"); onClicked: win.zoomBy(1 / 1.2) }
            Rectangle {
                id: zoomBtn
                Behavior on color { ColorAnimation { duration: 140 } }
                anchors.verticalCenter: parent.verticalCenter
                width: 64; height: 32; radius: 16
                color: zoomArea.pressed ? Theme.surfacePressed : zoomArea.containsMouse || zoomMenu.open ? Theme.surfaceHigher : "transparent"
                scale: zoomArea.pressed ? 0.94 : 1
                Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
                Text {
                    anchors.centerIn: parent
                    text: win.percent + "%"
                    color: Theme.textVariant
                    font.pixelSize: Theme.fs(13)
                    font.features: ({ "tnum": 1 })
                }
                MouseArea { id: zoomArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: { moreMenu.open = false; zoomMenu.open = !zoomMenu.open } }
            }
            IconButton { anchors.verticalCenter: parent.verticalCenter; glyph: 0xF06ED; tip: Tr.t("Увеличить  Ctrl++"); onClicked: win.zoomBy(1.2) }
        }

        Row {
            id: right
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            readonly property bool wide: win.width > 820
            IconButton { glyph: 0xF0349; tip: Tr.t("Найти  Ctrl+F"); on: searchBar.open; enabled: win.ready; onClicked: searchBar.open ? searchBar.hide() : searchBar.show() }
            IconButton { visible: right.wide; glyph: prefs.night ? 0xF0599 : 0xF0594; tip: prefs.night ? Tr.t("Дневной режим  D") : Tr.t("Ночной режим  D"); on: prefs.night; onClicked: prefs.night = !prefs.night }
            IconButton { visible: right.wide; glyph: 0xF0467; tip: Tr.t("Повернуть  R"); enabled: win.ready; onClicked: win.rotate() }
            IconButton { id: moreBtn; glyph: 0xF01D9; tip: Tr.t("Ещё"); on: moreMenu.open; onClicked: { zoomMenu.open = false; moreMenu.open = !moreMenu.open } }
            IconButton { glyph: win.fullscreen ? 0xF0294 : 0xF0293; tip: Tr.t("Во весь экран  F11"); onClicked: win.toggleFullscreen() }
            IconButton { glyph: 0xF0156; tip: Tr.t("Закрыть  Ctrl+W"); onClicked: win.close() }
        }
    }

    SearchBar {
        id: searchBar
        search: search
        count: win.resultCount
        anchors.top: header.bottom
        width: parent.width
        onClosed: pages.forceActiveFocus()
    }

    Sidebar {
        id: sidebar
        view: win
        open: prefs.sidebar && win.ready && !win.fullscreen
        anchors.top: searchBar.bottom
        anchors.bottom: parent.bottom
    }

    ListView {
        id: pages
        anchors.top: searchBar.bottom
        anchors.bottom: parent.bottom
        anchors.left: sidebar.right
        anchors.right: parent.right
        clip: true
        focus: true
        visible: win.ready
        model: win.ready ? doc.pageCount : 0
        cacheBuffer: Math.max(0, height)        // по экрану сверху и снизу — дальше страницы не держим
        contentWidth: win.pageAreaWidth
        flickableDirection: Flickable.AutoFlickIfNeeded
        boundsBehavior: Flickable.StopAtBounds
        acceptedButtons: Qt.NoButton            // мышь выделяет текст; листают колесо, тачпад, пальцы
        delegate: PageDelegate { view: win }
        onContentYChanged: win.updateCurrent()

        MouseArea {   // Ctrl+колесо — масштаб
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            z: 10
            onWheel: wheel => {
                if (wheel.modifiers & Qt.ControlModifier) {
                    var d = wheel.angleDelta.y || wheel.pixelDelta.y * 2
                    if (d) win.zoomBy(Math.pow(2, d / 600))
                } else wheel.accepted = false
            }
        }
        PinchHandler {
            target: null
            property real startZoom: 1
            onActiveChanged: if (active) startZoom = win.zoom
            onActiveScaleChanged: if (active) win.setZoom(startZoom * activeScale)
        }
    }

    // полоса прокрутки и номер страницы при прокрутке
    Item {
        id: scroller
        anchors.right: parent.right
        anchors.top: pages.top
        anchors.bottom: pages.bottom
        width: 14
        visible: win.ready && pages.visibleArea.heightRatio < 1
        opacity: pages.moving || thumbArea.containsMouse || thumbArea.pressed || fadeDelay.running ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 250 } }
        Timer { id: fadeDelay; interval: 900; running: pages.moving; repeat: false }
        Rectangle {
            id: thumb
            Behavior on color { ColorAnimation { duration: 140 } }
            x: thumbArea.containsMouse || thumbArea.pressed ? 3 : 6
            width: thumbArea.containsMouse || thumbArea.pressed ? 8 : 5
            y: pages.visibleArea.yPosition * parent.height
            height: Math.max(36, pages.visibleArea.heightRatio * parent.height)
            radius: width / 2
            color: thumbArea.pressed ? Theme.accent : Theme.textMuted
            Behavior on width { NumberAnimation { duration: 120 } }
        }
        MouseArea {
            id: thumbArea
            anchors.fill: parent
            hoverEnabled: true
            property real grab: 0
            onPressed: mouse => { grab = mouse.y >= thumb.y && mouse.y <= thumb.y + thumb.height ? mouse.y - thumb.y : thumb.height / 2; move(mouse.y) }
            onPositionChanged: mouse => { if (pressed) move(mouse.y) }
            function move(y) {
                var frac = Math.max(0, Math.min(1, (y - grab) / (height - thumb.height)))
                pages.contentY = pages.originY + frac * (pages.contentHeight - pages.height)
            }
        }
        Rectangle {   // «12 из 40» рядом с ползунком
            opacity: pages.moving || thumbArea.pressed ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 140 } }
            anchors.right: parent.left
            anchors.rightMargin: 6
            y: Math.max(0, Math.min(parent.height - height, thumb.y + thumb.height / 2 - height / 2))
            width: bubbleText.implicitWidth + 20
            height: 26
            radius: 13
            color: Theme.surfaceHigh
            border.color: Theme.outline
            Text { id: bubbleText; anchors.centerIn: parent; text: (win.currentPage + 1) + Tr.t(" из ") + doc.pageCount; color: Theme.text; font.pixelSize: Theme.fs(12); font.features: ({ "tnum": 1 }) }
        }
    }

    // адрес ссылки под курсором
    Rectangle {
        visible: win.hoverLink !== ""
        x: pages.x + 12
        y: parent.height - height - 12
        width: Math.min(linkText.implicitWidth + 20, parent.width / 2)
        height: 26
        radius: 13
        color: Theme.surfaceHigh
        border.color: Theme.outline
        Text { id: linkText; anchors.centerIn: parent; width: parent.width - 20; text: win.hoverLink; color: Theme.textVariant; font.pixelSize: Theme.fs(12); elide: Text.ElideMiddle; textFormat: Text.PlainText }
    }

    // короткая подсказка: масштаб
    Rectangle {
        id: hint
        function show(t) { hintText.text = t; opacity = 1; hintTimer.restart() }
        anchors.horizontalCenter: pages.horizontalCenter
        y: pages.y + 16
        width: hintText.implicitWidth + 28
        height: 34
        radius: 17
        color: Theme.scrim
        opacity: 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 160 } }
        Text { id: hintText; anchors.centerIn: parent; color: Theme.text; font.pixelSize: Theme.fs(13) }
        Timer { id: hintTimer; interval: 900; onTriggered: hint.opacity = 0 }
    }

    // ---------- пусто / пароль / ошибка ----------
    Column {
        anchors.centerIn: parent
        visible: !win.path
        spacing: 14
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: Theme.icon(0xF0219); color: Theme.textMuted; font.family: Theme.iconFont; font.pixelSize: 64 }
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: Tr.t("Нет документа"); color: Theme.text; font.pixelSize: Theme.fs(18); font.weight: Font.DemiBold }
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: Tr.t("Перетащите PDF в окно или откройте файл"); color: Theme.textSecondary; font.pixelSize: Theme.fs(13) }
        Item { width: 1; height: 4 }
        TextButton { anchors.horizontalCenter: parent.horizontalCenter; primary: true; glyph: 0xF0770; text: Tr.t("Открыть…"); enabled: !picker.busy; onClicked: win.openDialog() }
    }
    Rectangle {
        anchors.centerIn: parent
        visible: win.needPassword
        width: 340
        height: pwCol.implicitHeight + 48
        radius: Theme.radiusLg
        color: Theme.surface
        border.color: Theme.outline
        Column {
            id: pwCol
            x: 24; y: 24
            width: parent.width - 48
            spacing: 12
            Text { text: Theme.icon(0xF033E); color: Theme.accent; font.family: Theme.iconFont; font.pixelSize: 32 }
            Text { text: Tr.t("Документ защищён паролем"); color: Theme.text; font.pixelSize: Theme.fs(16); font.weight: Font.DemiBold }
            TextField {
                id: passwordField
                width: parent.width
                password: true
                placeholder: Tr.t("Пароль")
                error: win.wrongPassword
                onAccepted: doc.password = text
                onTextChanged: win.wrongPassword = false
            }
            Text { visible: win.wrongPassword; text: Tr.t("Неверный пароль"); color: Theme.error; font.pixelSize: Theme.fs(12) }
            TextButton { width: parent.width; primary: true; text: Tr.t("Открыть"); enabled: passwordField.text !== ""; onClicked: doc.password = passwordField.text }
        }
    }
    Column {
        anchors.centerIn: parent
        visible: win.path !== "" && doc.status === PdfDocument.Error && !win.needPassword
        spacing: 10
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: Tr.t("Не удалось открыть документ"); color: Theme.text; font.pixelSize: Theme.fs(16) }
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: Tr.t("Файл повреждён или это не PDF"); color: Theme.textSecondary; font.pixelSize: Theme.fs(13) }
    }

    // ---------- меню ----------
    MouseArea {
        anchors.fill: parent
        visible: zoomMenu.open || moreMenu.open || docInfo.open
        onPressed: { zoomMenu.open = false; moreMenu.open = false; docInfo.open = false }
    }
    PopupMenu {
        id: zoomMenu
        width: 200
        transformOrigin: Item.TopRight
        x: Math.min(parent.width - width - 8, center.x + zoomBtn.x + zoomBtn.width - width + 40)
        y: 50
        items: [
            { text: Tr.t("По ширине"), checked: win.fit === "width", run: () => win.setZoom(win.fitZoom("width"), "width") },
            { text: Tr.t("Страница целиком"), checked: win.fit === "page", run: () => win.setZoom(win.fitZoom("page"), "page") }
        ].concat([50, 75, 100, 125, 150, 200, 300].map(p => ({
            text: p + "%", checked: win.fit === "none" && win.percent === p, run: () => win.setZoom(p / 100 * 96 / 72)
        })))
    }
    PopupMenu {
        id: moreMenu
        width: 260
        transformOrigin: Item.TopRight
        x: parent.width - width - 8
        y: 50
        items: [
            { text: Tr.t("Сведения о документе"), run: () => docInfo.open = true },
            { text: Tr.t("Копировать выделенный текст   Ctrl+C"), run: () => win.copySelection() },
            { text: Tr.t("Показать в папке"), run: () => lib.showInFolder(win.path) },
            { text: (prefs.night ? Tr.t("Дневной") : Tr.t("Ночной")) + Tr.t(" режим   D"), run: () => prefs.night = !prefs.night },
            { text: Tr.t("Повернуть   R"), run: () => win.rotate() },
            { text: Tr.t("Открыть…   Ctrl+O"), run: () => win.openDialog() }
        ]
    }
    Rectangle {   // сведения о документе
        id: docInfo
        property bool open: false
        anchors.centerIn: parent
        width: 380
        height: infoCol.implicitHeight + 40
        radius: Theme.radiusLg
        color: Theme.surface
        border.color: Theme.outline
        z: 70
        opacity: open ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 140 } }
        MouseArea { anchors.fill: parent }
        function date(d) { return d && !isNaN(d) ? Tr.locale.toString(d, "d MMMM yyyy, HH:mm") : "" }
        readonly property var size0: win.ready ? doc.pagePointSize(0) : Qt.size(0, 0)
        readonly property var file: win.path ? lib.fileInfo(win.path) : ({})
        readonly property var rows: [
            [Tr.t("Название"), doc.title], [Tr.t("Автор"), doc.author], [Tr.t("Тема"), doc.subject], [Tr.t("Ключевые слова"), doc.keywords],
            [Tr.t("Страниц"), String(doc.pageCount)],
            [Tr.t("Размер страницы"), Math.round(size0.width * 25.4 / 72) + " × " + Math.round(size0.height * 25.4 / 72) + Tr.t(" мм")],
            [Tr.t("Создан"), date(doc.creationDate)], [Tr.t("Изменён"), date(doc.modificationDate)],
            [Tr.t("Программа"), [doc.creator, doc.producer].filter(x => x).join(" · ")],
            [Tr.t("Файл"), file.bytes ? (file.bytes / 1048576).toFixed(1).replace(".", Tr.ru ? "," : ".") + Tr.t(" МБ") : ""], [Tr.t("Папка"), file.folder || ""]
        ].filter(r => r[1])
        Column {
            id: infoCol
            x: 20; y: 20
            width: parent.width - 40
            spacing: 10
            Row {
                width: parent.width
                Text { width: parent.width - 32; anchors.verticalCenter: parent.verticalCenter; text: Tr.t("Сведения"); color: Theme.text; font.pixelSize: Theme.fs(16); font.weight: Font.DemiBold }
                IconButton { width: 32; height: 32; glyphSize: 16; glyph: 0xF0156; onClicked: docInfo.open = false }
            }
            Repeater {
                model: docInfo.rows
                delegate: Column {
                    required property var modelData
                    width: infoCol.width
                    spacing: 2
                    Text { text: modelData[0]; color: Theme.textMuted; font.pixelSize: Theme.fs(11) }
                    Text { width: parent.width; text: modelData[1]; color: Theme.text; font.pixelSize: Theme.fs(13); wrapMode: Text.WrapAnywhere; textFormat: Text.PlainText }
                }
            }
        }
    }

    Toast { id: toast }

    DropArea {
        anchors.fill: parent
        onEntered: drag => drag.accept(Qt.CopyAction)
        onDropped: drop => { if (drop.hasUrls) win.openFile(drop.urls[0]) }
    }

    ResizeEdges { window: win }

    // ---------- клавиши ----------
    Shortcut { sequences: ["PgDown", "Space"]; enabled: win.ready; onActivated: win.scrollBy(pages.height - 48) }
    Shortcut { sequences: ["PgUp", "Shift+Space"]; enabled: win.ready; onActivated: win.scrollBy(-(pages.height - 48)) }
    Shortcut { sequence: "Down"; enabled: win.ready; onActivated: win.scrollBy(60) }
    Shortcut { sequence: "Up"; enabled: win.ready; onActivated: win.scrollBy(-60) }
    Shortcut { sequence: "Right"; enabled: win.ready; onActivated: win.goToPage(win.currentPage + 1, false) }
    Shortcut { sequence: "Left"; enabled: win.ready; onActivated: win.goToPage(win.currentPage - 1, false) }
    Shortcut { sequences: ["Home", "Ctrl+Home"]; enabled: win.ready; onActivated: win.goToPage(0, true) }
    Shortcut { sequences: ["End", "Ctrl+End"]; enabled: win.ready; onActivated: win.goToPage(doc.pageCount - 1, true) }
    Shortcut { sequences: ["Ctrl+G", "G"]; enabled: win.ready; onActivated: pageField.focusAll() }
    Shortcut { sequences: ["Ctrl++", "Ctrl+=", "+", "="]; enabled: win.ready; onActivated: win.zoomBy(1.2) }
    Shortcut { sequences: ["Ctrl+-", "-"]; enabled: win.ready; onActivated: win.zoomBy(1 / 1.2) }
    Shortcut { sequence: "Ctrl+0"; enabled: win.ready; onActivated: win.setZoom(win.fitZoom("width"), "width") }
    Shortcut { sequence: "Ctrl+1"; enabled: win.ready; onActivated: win.setZoom(96 / 72) }
    Shortcut { sequence: "Ctrl+2"; enabled: win.ready; onActivated: win.setZoom(win.fitZoom("page"), "page") }
    Shortcut { sequences: ["Ctrl+F", "/"]; enabled: win.ready; onActivated: searchBar.show() }
    Shortcut { sequence: "F3"; enabled: searchBar.open; onActivated: searchBar.next() }
    Shortcut { sequence: "Shift+F3"; enabled: searchBar.open; onActivated: searchBar.prev() }
    Shortcut { sequence: "Ctrl+C"; onActivated: win.copySelection() }
    Shortcut { sequence: "Ctrl+A"; enabled: win.ready; onActivated: win.selectAllOnPage() }
    Shortcut { sequence: "R"; enabled: win.ready; onActivated: win.rotate() }
    Shortcut { sequence: "D"; onActivated: prefs.night = !prefs.night }
    Shortcut { sequences: ["F9", "Ctrl+B"]; enabled: win.ready; onActivated: prefs.sidebar = !prefs.sidebar }
    Shortcut { sequences: ["Alt+Left", "Backspace"]; enabled: win.history.length > 0; onActivated: win.back() }
    Shortcut { sequences: ["F", "F11"]; onActivated: win.toggleFullscreen() }
    Shortcut { sequence: "Ctrl+O"; onActivated: win.openDialog() }
    Shortcut { sequences: ["Ctrl+W", "Ctrl+Q"]; onActivated: win.close() }
    Shortcut {
        sequence: "Esc"
        onActivated: {
            if (zoomMenu.open || moreMenu.open || docInfo.open) { zoomMenu.open = false; moreMenu.open = false; docInfo.open = false }
            else if (searchBar.open) searchBar.hide()
            else if (win.selectionOwner && win.selectionOwner.text) win.selectionOwner.clear()
            else if (win.fullscreen) win.toggleFullscreen()
        }
    }
}
