import QtQuick
import QtQuick.Window
import Glide.Ui
import GlidePhotos

// Glide Фото — лёгкий просмотрщик: папка листается стрелками, колесо — масштаб под курсором,
// тачпад — двигать/листать, щипок — масштаб. Панели прячутся, пока мышь не двигается.
Window {
    id: win

    property string startPath: ""

    width: 1100
    height: 720
    minimumWidth: 420
    minimumHeight: 300
    visible: true
    flags: Qt.Window | Qt.FramelessWindowHint
    color: Theme.background
    title: gallery.count > 0 ? gallery.info.name + Tr.t(" — Фото") : Tr.t("Фото")

    readonly property bool fullscreen: visibility === Window.FullScreen
    function toggleFullscreen() { visibility = fullscreen ? Window.Windowed : Window.FullScreen }

    Gallery {
        id: gallery
        onError: message => toast.show(message)
    }
    FilePicker {
        id: picker
        onPicked: urls => { if (urls.length) gallery.open(urls[0]) }
    }
    function openDialog() {
        picker.open(Tr.t("Открыть изображение"), Tr.t("Изображения"),
                    ["*.jpg", "*.jpeg", "*.jfif", "*.png", "*.webp", "*.gif", "*.svg", "*.svgz", "*.bmp",
                     "*.tif", "*.tiff", "*.tga", "*.ico", "*.avif", "*.heic", "*.jxl"],
                    gallery.folder)
    }
    Component.onCompleted: if (startPath && gallery.open(startPath) && gallery.isDir(startPath)) win.showGrid(true)

    // ---- сетка папки (G) и слайд-шоу (S) ----
    property bool grid: false
    function showGrid(on) {
        if (on && (gallery.count === 0 || editing)) return
        if (on) { stopSlideshow(); info.open = false; menu.open = false }
        grid = on
        if (on) gridPage.focusGrid()
    }
    property bool slideshow: false
    function startSlideshow() {
        if (gallery.count < 2 || editing) return
        showGrid(false); info.open = false; menu.open = false
        slideshow = true; awake = false
        toast.show(Tr.t("Слайд-шоу · любая клавиша — стоп"))
    }
    function stopSlideshow() { if (slideshow) { slideshow = false; toast.show(Tr.t("Слайд-шоу остановлено")) } }
    Timer {
        interval: 4000; repeat: true; running: win.slideshow
        onTriggered: gallery.index = gallery.index < gallery.count - 1 ? gallery.index + 1 : 0
    }

    function trash() {
        var name = gallery.info.name
        if (gallery.trash())
            toast.show("«" + name + Tr.t("» — в корзине"), Tr.t("Отменить"), () => gallery.undoTrash())
    }
    function copyImage() { if (gallery.copyImage()) toast.show(Tr.t("Изображение скопировано")) }
    function copyPath() { gallery.copyPath(); toast.show(Tr.t("Путь скопирован")) }

    // ---- правка: обрезка, поворот, размер, формат, качество ----
    property bool editing: false
    function startEdit() {
        if (gallery.count === 0 || editing) return
        if (gallery.info.animated || gallery.info.vector) { toast.show(Tr.t("Анимацию и SVG править нельзя")); return }
        info.open = false
        menu.open = false
        editPanel.reset()
        editing = true
    }
    function cancelEdit() { editing = false; editor.forget() }
    ImageEditor {
        id: editor
        onSaved: (file, original, inTrash) => {
            win.cancelEdit()
            if (gallery.canShow(file)) gallery.open(file)
            if (inTrash) {
                gallery.recordReplace(original, inTrash, file)
                toast.show(Tr.t("Оригинал — в корзине"), Tr.t("Отменить"), () => gallery.undoTrash())
            } else {
                toast.show(Tr.t("Сохранено: ") + file.split("/").pop(), Tr.t("Показать"), () => gallery.showInFolder())
            }
        }
        onFailed: error => toast.show(Tr.t("Не удалось сохранить: ") + error)
    }

    // ---- панели показываются при движении мыши и прячутся через 2,5 с покоя ----
    property bool awake: true
    readonly property bool chrome: !slideshow && (awake || editing || grid || gallery.count === 0 || headerHover.hovered || info.open
                                   || menu.open || viewer.status === Image.Error)
    Timer { id: sleepTimer; interval: 2500; running: win.awake; onTriggered: win.awake = false }
    function poke() { if (slideshow) return; awake = true; sleepTimer.restart() }

    Viewer {
        id: viewer
        anchors.fill: parent
        visible: !win.editing && !win.grid
        gallery: gallery
        onActivity: win.poke()
        HoverHandler {
            onPointChanged: win.poke()
            cursorShape: win.chrome || !win.fullscreen ? Qt.ArrowCursor : Qt.BlankCursor
        }
    }

    GridPage {
        id: gridPage
        anchors.fill: parent
        visible: win.grid
        gallery: gallery
        onPicked: i => { gallery.index = i; win.showGrid(false) }
    }

    // ---- пусто / ошибка / загрузка ----
    Column {
        anchors.centerIn: parent
        visible: gallery.count === 0
        spacing: 14
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Theme.icon(0xF0976)
            color: Theme.textMuted
            font.family: Theme.iconFont
            font.pixelSize: 64
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Tr.t("Нет изображения")
            color: Theme.text
            font.pixelSize: Theme.fs(18)
            font.weight: Font.DemiBold
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Tr.t("Перетащите картинку в окно или откройте файл")
            color: Theme.textSecondary
            font.pixelSize: Theme.fs(13)
        }
        Item { width: 1; height: 4 }
        TextButton {
            anchors.horizontalCenter: parent.horizontalCenter
            primary: true
            glyph: 0xF0770
            text: Tr.t("Открыть…")
            enabled: !picker.busy
            onClicked: win.openDialog()
        }
    }
    Text {
        anchors.centerIn: parent
        visible: gallery.count > 0 && viewer.status === Image.Error && !win.grid
        text: Tr.t("Не удалось открыть «") + (gallery.info.name || "") + "»"
        color: Theme.textSecondary
        font.pixelSize: Theme.fs(14)
        textFormat: Text.PlainText
    }
    Text {   // большие файлы грузятся заметно — показываем, что работа идёт
        anchors.centerIn: parent
        visible: viewer.status === Image.Loading && loadingDelay.done && !win.grid
        text: Tr.t("Загрузка…")
        color: Theme.textMuted
        font.pixelSize: Theme.fs(13)
        Timer {
            id: loadingDelay
            property bool done: false
            interval: 300
            running: viewer.status === Image.Loading
            onRunningChanged: if (running) done = false
            onTriggered: done = true
        }
    }

    // ---- стрелки по краям ----
    IconButton {
        x: 16
        anchors.verticalCenter: parent.verticalCenter
        width: 44; height: 44; glyphSize: 24
        flat: false
        glyph: 0xF0141
        visible: opacity > 0
        // своя прозрачность затирает «недоступно» у IconButton — перемножаем
        opacity: (win.chrome && !win.editing && !win.grid && gallery.count > 1 ? 1 : 0) * (enabled ? 1 : Theme.disabledOpacity)
        Behavior on opacity { NumberAnimation { duration: 160 } }
        enabled: gallery.index > 0
        onClicked: gallery.prev()
    }
    IconButton {
        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        x: parent.width - width - 16 - (info.open ? info.width + 16 : 0)
        anchors.verticalCenter: parent.verticalCenter
        width: 44; height: 44; glyphSize: 24
        flat: false
        glyph: 0xF0142
        visible: opacity > 0
        opacity: (win.chrome && !win.editing && !win.grid && gallery.count > 1 ? 1 : 0) * (enabled ? 1 : Theme.disabledOpacity)
        Behavior on opacity { NumberAnimation { duration: 160 } }
        enabled: gallery.index < gallery.count - 1
        onClicked: gallery.next()
    }

    // ---- шапка: имя, номер, масштаб, действия; за неё окно перетаскивается ----
    Item {
        id: header
        width: parent.width
        height: 72
        opacity: win.chrome ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 180 } }

        HoverHandler { id: headerHover }
        Rectangle {   // затемнение сверху вниз — фото под шапкой остаётся видно
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0; color: Theme.scrim }
                GradientStop { position: 0.65; color: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 0.45) }
                GradientStop { position: 1; color: "transparent" }
            }
        }
        DragHandler {
            target: null
            onActiveChanged: if (active) win.startSystemMove()
        }
        TapHandler {
            onDoubleTapped: win.toggleFullscreen()
        }

        Column {
            x: 20
            y: 10
            width: header.width - actions.width - 56
            spacing: 1
            Text {
                width: parent.width
                text: win.grid ? Tr.t("Все фото папки") + " · " + gallery.count : gallery.count > 0 ? gallery.info.name : Tr.t("Фото")
                color: Theme.text
                font.pixelSize: Theme.fs(14)
                font.weight: Font.DemiBold
                elide: Text.ElideMiddle
                textFormat: Text.PlainText
            }
            Text {
                width: parent.width
                visible: gallery.count > 0
                text: win.grid ? gallery.folder
                      : (gallery.index + 1) + Tr.t(" из ") + gallery.count
                        + (gallery.info.width ? "  ·  " + gallery.info.width + " × " + gallery.info.height : "")
                        + "  ·  " + info.sizeText(gallery.info.bytes || 0)
                color: Theme.textSecondary
                font.pixelSize: Theme.fs(12)
                elide: Text.ElideRight
            }
        }

        Row {
            id: actions
            visible: !win.editing
            anchors.right: parent.right
            anchors.rightMargin: 12
            y: 8
            spacing: 2
            readonly property bool wideEnough: win.width > 760

            IconButton { glyph: win.grid ? 0xF02E9 : 0xF11D9; tip: win.grid ? Tr.t("К фото  G") : Tr.t("Все фото папки  G"); on: win.grid
                         enabled: gallery.count > 0; onClicked: win.showGrid(!win.grid) }
            Item { width: 8; height: 1 }
            Row {   // действия с одним фото — не в сетке
            visible: !win.grid
            spacing: 2
            IconButton { glyph: 0xF06EC; tip: Tr.t("Уменьшить  −"); enabled: gallery.count > 0 && !viewer.fitted; onClicked: viewer.zoomOut() }
            Rectangle {   // масштаб: щелчок — по размеру окна ↔ 100 %
                Behavior on color { ColorAnimation { duration: 140 } }
                width: 64; height: 36
                radius: height / 2
                color: zoomArea.pressed ? Theme.surfacePressed : zoomArea.containsMouse ? Theme.surfaceHigher : "transparent"
                opacity: gallery.count > 0 ? 1 : Theme.disabledOpacity
                scale: zoomArea.pressed ? 0.94 : 1
                Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
                Text {
                    anchors.centerIn: parent
                    text: viewer.percent + "%"
                    color: Theme.textVariant
                    font.pixelSize: Theme.fs(13)
                    font.features: ({ "tnum": 1 })
                }
                MouseArea {
                    id: zoomArea
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: gallery.count > 0
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: viewer.toggleZoom()
                }
            }
            IconButton { glyph: 0xF06ED; tip: Tr.t("Увеличить  +"); enabled: gallery.count > 0; onClicked: viewer.zoomIn() }
            Item { width: 8; height: 1 }
            IconButton { visible: actions.wideEnough; glyph: 0xF0465; tip: Tr.t("Повернуть влево  Shift+R"); enabled: gallery.count > 0; onClicked: viewer.rotate(-90) }
            IconButton { visible: actions.wideEnough; glyph: 0xF0467; tip: Tr.t("Повернуть вправо  R"); enabled: gallery.count > 0; onClicked: viewer.rotate(90) }
            IconButton { glyph: 0xF03EB; tip: Tr.t("Изменить  E"); enabled: gallery.count > 0; onClicked: win.startEdit() }
            IconButton { glyph: 0xF09E7; tip: Tr.t("В корзину  Delete"); enabled: gallery.count > 0; onClicked: win.trash() }
            IconButton { glyph: 0xF02FD; tip: Tr.t("Сведения  I"); on: info.open; enabled: gallery.count > 0; onClicked: info.open = !info.open }
            }
            IconButton { id: moreBtn; glyph: 0xF01D9; tip: Tr.t("Ещё"); on: menu.open; onClicked: menu.open = !menu.open }
            Item { width: 8; height: 1 }
            IconButton { glyph: win.fullscreen ? 0xF0294 : 0xF0293; tip: win.fullscreen ? Tr.t("Выйти из полноэкранного  F") : Tr.t("Во весь экран  F"); onClicked: win.toggleFullscreen() }
            IconButton { glyph: 0xF0156; tip: Tr.t("Закрыть  Esc"); onClicked: win.close() }
        }
    }

    Row {   // шапка в режиме правки
        visible: win.editing
        anchors.right: parent.right
        anchors.rightMargin: 12
        y: 8
        spacing: 6
        TextButton { implicitHeight: 36; text: Tr.t("Отмена"); onClicked: win.cancelEdit() }
    }
    EditView {
        id: editView
        visible: win.editing
        x: 0
        y: 64
        width: parent.width - editPanel.width - 32
        height: parent.height - 72
        info: gallery.info
        url: gallery.count > 0 && win.editing ? gallery.urlAt(gallery.index) : ""
    }
    EditPanel {
        id: editPanel
        editor: editor
        view: editView
        info: gallery.info
        open: win.editing
        anchors.right: parent.right
        anchors.rightMargin: 16
        y: 64
        height: parent.height - 80
    }

    InfoPanel {
        id: info
        gallery: gallery
        anchors.right: parent.right
        anchors.rightMargin: 16
        y: 72
        height: Math.min(implicitHeight, parent.height - 88)
    }

    // ---- меню «Ещё» ----
    MouseArea {   // щелчок мимо меню закрывает его
        anchors.fill: parent
        visible: menu.open
        onPressed: menu.open = false
    }
    Rectangle {
        id: menu
        property bool open: false
        readonly property var items: [
            { glyph: 0xF018F, text: Tr.t("Копировать изображение"), keys: "Ctrl+C", run: () => win.copyImage(), needImage: true },
            { glyph: 0xF0219, text: Tr.t("Копировать путь"), keys: "Ctrl+Shift+C", run: () => win.copyPath(), needImage: true },
            { glyph: 0xF0256, text: Tr.t("Показать в папке"), keys: "", run: () => gallery.showInFolder(), needImage: true },
            { glyph: 0xF040A, text: Tr.t("Слайд-шоу"), keys: "S", run: () => win.startSlideshow(), needImage: true },
            { glyph: 0xF0770, text: Tr.t("Открыть…"), keys: "Ctrl+O", run: () => win.openDialog(), needImage: false }
        ]
        width: 290
        height: menuCol.implicitHeight + 12
        x: Math.min(parent.width - width - 12, actions.x + moreBtn.x + moreBtn.width - width)   // шапка — в начале окна
        y: 56
        z: 60
        radius: Theme.radiusMd
        color: Theme.surfaceHigh
        border.color: Theme.outline
        opacity: open ? 1 : 0
        visible: opacity > 0
        scale: open ? 1 : 0.96
        transformOrigin: Item.TopRight
        Behavior on opacity { NumberAnimation { duration: 120 } }
        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

        Column {
            id: menuCol
            x: 6; y: 6
            width: parent.width - 12
            Repeater {
                model: menu.items
                delegate: Rectangle {
                    Behavior on color { ColorAnimation { duration: 140 } }
                    required property var modelData
                    readonly property bool usable: !modelData.needImage || gallery.count > 0
                    width: menuCol.width
                    height: 40
                    radius: Theme.radiusSm
                    color: itemArea.pressed && usable ? Theme.surfacePressed : itemArea.containsMouse && usable ? Theme.surfaceHigher : "transparent"
                    opacity: usable ? 1 : Theme.disabledOpacity
                    Text {
                        x: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: Theme.icon(modelData.glyph)
                        color: Theme.textVariant
                        font.family: Theme.iconFont
                        font.pixelSize: Theme.fs(17)
                    }
                    Text {
                        x: 42
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.text
                        color: Theme.text
                        font.pixelSize: Theme.fs(13)
                    }
                    Text {
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.keys
                        color: Theme.textMuted
                        font.pixelSize: Theme.fs(11)
                    }
                    MouseArea {
                        id: itemArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: parent.usable ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: if (parent.usable) { menu.open = false; parent.modelData.run() }
                    }
                }
            }
        }
    }

    Toast { id: toast }

    // ---- перетаскивание файла в окно ----
    DropArea {
        anchors.fill: parent
        onEntered: drag => drag.accept(Qt.CopyAction)
        onDropped: drop => { if (drop.hasUrls && !win.editing) gallery.open(drop.urls[0]) }
    }

    ResizeEdges { window: win }

    // ---- клавиши (просмотр — только вне правки) ----
    readonly property bool viewing: !editing && !grid && !slideshow   // в слайд-шоу клавиши — только «стоп»
    Shortcut { enabled: !win.editing; sequence: "G"; onActivated: win.showGrid(!win.grid) }
    Shortcut { enabled: win.viewing; sequence: "S"; onActivated: win.slideshow ? win.stopSlideshow() : win.startSlideshow() }
    Item {   // слайд-шоу: любая клавиша или движение мыши — стоп
        focus: win.slideshow
        Keys.onPressed: e => { if (win.slideshow) { win.stopSlideshow(); e.accepted = true } }
    }
    Shortcut { enabled: win.viewing; sequences: ["Right", "PgDown", "Space", "N"]; onActivated: gallery.next() }
    Shortcut { enabled: win.viewing; sequences: ["Left", "PgUp", "Backspace", "P"]; onActivated: gallery.prev() }
    Shortcut { enabled: win.viewing; sequence: "Home"; onActivated: gallery.index = 0 }
    Shortcut { enabled: win.viewing; sequence: "End"; onActivated: gallery.index = gallery.count - 1 }
    Shortcut { enabled: win.viewing; sequences: ["+", "=", "Ctrl++", "Ctrl+="]; onActivated: viewer.zoomIn() }
    Shortcut { enabled: win.viewing; sequences: ["-", "Ctrl+-"]; onActivated: viewer.zoomOut() }
    Shortcut { enabled: win.viewing; sequences: ["0", "Ctrl+0"]; onActivated: viewer.fit() }
    Shortcut { enabled: win.viewing; sequence: "1"; onActivated: viewer.actual() }
    Shortcut { sequence: "R"; onActivated: win.editing ? editView.rotate = (editView.rotate + 90) % 360 : viewer.rotate(90) }
    Shortcut { sequence: "Shift+R"; onActivated: win.editing ? editView.rotate = (editView.rotate + 270) % 360 : viewer.rotate(-90) }
    Shortcut { sequences: ["F", "F11"]; onActivated: win.toggleFullscreen() }
    Shortcut { enabled: win.viewing; sequence: "I"; onActivated: if (gallery.count > 0) info.open = !info.open }
    Shortcut { enabled: win.viewing; sequence: "E"; onActivated: win.startEdit() }
    Shortcut { enabled: win.viewing; sequence: "Delete"; onActivated: win.trash() }
    Shortcut { enabled: win.viewing && gallery.canUndo; sequence: "Ctrl+Z"; onActivated: { toast.shown = false; gallery.undoTrash() } }
    Shortcut { enabled: win.viewing; sequence: "Ctrl+C"; onActivated: win.copyImage() }
    Shortcut { enabled: win.viewing; sequence: "Ctrl+Shift+C"; onActivated: win.copyPath() }
    Shortcut { enabled: win.viewing; sequence: "Ctrl+O"; onActivated: win.openDialog() }
    Shortcut { enabled: win.editing && !editor.busy; sequence: "Ctrl+S"; onActivated: editPanel.save("copy") }
    Shortcut { sequences: ["Ctrl+W", "Ctrl+Q"]; onActivated: win.close() }
    Shortcut {
        sequence: "Esc"
        onActivated: {
            if (win.slideshow) win.stopSlideshow()
            else if (win.editing) win.cancelEdit()
            else if (menu.open) menu.open = false
            else if (win.grid && viewer.status !== Image.Null) win.showGrid(false)
            else if (info.open) info.open = false
            else if (win.fullscreen) win.toggleFullscreen()
            else win.close()
        }
    }
}
