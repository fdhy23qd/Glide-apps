import QtQuick
import QtQuick.Window
import Glide.Ui

// Просмотр: масштаб и сдвиг текущей картинки, жесты, три слота (предыдущая, текущая, следующая).
// zoom — сколько пикселей экрана на пиксель картинки (1 = 100 %); cx, cy — сдвиг центра.
Item {
    id: viewer

    required property var gallery
    signal activity()            // пользователь что-то делает — показать панели

    readonly property real dpr: Screen.devicePixelRatio
    readonly property int baseSide: Math.max(Screen.width, Screen.height) * dpr
    readonly property var info: gallery.info

    // поворот — только в просмотре, файл не меняется
    property int turnTarget: 0
    property real turn: turnTarget
    Behavior on turn { enabled: viewer.animate; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    readonly property bool sideways: Math.abs(turnTarget % 180) === 90

    readonly property real natW: (sideways ? info.height : info.width) || 0
    readonly property real natH: (sideways ? info.width : info.height) || 0
    // растр крупнее 100 % не растягиваем (мыло); вектор (SVG) вписываем в окно целиком
    function fitFor(w, h, vector) {
        if (!(w > 0 && h > 0 && width > 0)) return 1
        var f = Math.min(width * dpr / w, height * dpr / h)
        return vector ? f * 0.9 : Math.min(1, f)
    }
    readonly property real fitZoom: fitFor(natW, natH, !!info.vector)
    readonly property real maxZoom: 32
    readonly property int percent: Math.round(zoom * 100)

    property bool fitted: true
    property bool animate: true
    property real tz: 1
    property real tcx: 0
    property real tcy: 0
    property real zoom: tz
    property real cx: tcx
    property real cy: tcy
    Behavior on zoom { enabled: viewer.animate; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
    Behavior on cx { enabled: viewer.animate; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
    Behavior on cy { enabled: viewer.animate; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

    // окно поменяло размер или картинку повернули — «по размеру окна» следует за ним
    onFitZoomChanged: if (fitted) { tz = fitZoom; tcx = 0; tcy = 0 }

    readonly property bool zoomedIn: natW * tz / dpr > width + 1 || natH * tz / dpr > height + 1

    function resetView() {
        animate = false
        turnTarget = 0
        fitted = true
        var i = gallery.info
        tz = fitFor(i.width || 0, i.height || 0, !!i.vector)   // из gallery.info: привязка info ещё старая
        tcx = 0
        tcy = 0
        animate = true
    }
    Connections {
        target: viewer.gallery
        function onCurrentChanged() { viewer.resetView() }
    }

    function setPan(x, y) {
        var mx = Math.max(0, (natW * tz / dpr - width) / 2)
        var my = Math.max(0, (natH * tz / dpr - height) / 2)
        tcx = Math.max(-mx, Math.min(mx, x))
        tcy = Math.max(-my, Math.min(my, y))
    }
    // масштаб с точкой (px, py) под курсором на месте
    function zoomTo(z, px, py) {
        z = Math.max(fitZoom, Math.min(maxZoom, z))
        if (px === undefined) { px = width / 2; py = height / 2 }
        var ax = px - width / 2, ay = py - height / 2
        var k = z / tz
        var nx = ax - (ax - tcx) * k, ny = ay - (ay - tcy) * k
        tz = z
        fitted = Math.abs(z - fitZoom) < 1e-4
        setPan(nx, ny)
        activity()
    }
    function zoomIn() { zoomTo(tz * 1.25) }
    function zoomOut() { zoomTo(tz / 1.25) }
    function fit() { zoomTo(fitZoom) }
    function actual(px, py) { zoomTo(1, px, py) }
    // двойной щелчок: по размеру окна ↔ 100 % (маленькие картинки — вдвое)
    function toggleZoom(px, py) {
        if (fitted) zoomTo(fitZoom >= 1 ? 2 : 1, px, py)
        else fit()
    }
    function rotate(d) {
        turnTarget += d
        fitted = true
        tz = fitZoom
        tcx = 0
        tcy = 0
        activity()
    }

    // ---- три слота: у каждого свой номер файла по модулю 3, при листании меняется только один ----
    Repeater {
        id: slots
        model: 3
        delegate: PhotoSlot {
            required property int index
            readonly property int fileIndex: {
                var start = viewer.gallery.index - 1
                return start + (((index - start) % 3) + 3) % 3
            }
            view: viewer
            current: fileIndex === viewer.gallery.index
            url: viewer.gallery.revision >= 0 ? viewer.gallery.urlAt(fileIndex) : ""
            info: viewer.gallery.revision >= 0 && url ? viewer.gallery.infoAt(fileIndex) : ({})
        }
    }

    readonly property var currentSlot: {
        for (var i = 0; i < slots.count; i++) {
            var s = slots.itemAt(i)
            if (s && s.current) return s
        }
        return null
    }
    readonly property int status: currentSlot ? currentSlot.status : Image.Null

    // ---- ввод ----
    property real swipe: 0     // тачпад, два пальца вбок при «по размеру окна» — листание
    Timer { id: swipeReset; interval: 250; onTriggered: viewer.swipe = 0 }

    // не WheelHandler: у него одна ось (по умолчанию вертикальная) — свайп вбок на тачпаде терялся
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        onWheel: event => {
            viewer.activity()
            // у тачпада в Wayland есть фазы жеста (Begin/Update/End), у колеса мыши — нет
            var touchpad = event.phase !== Qt.NoScrollPhase
            if (!touchpad || (event.modifiers & Qt.ControlModifier)) {
                // колесо мыши (или Ctrl) — масштаб под курсором
                var d = touchpad ? event.pixelDelta.y * 2 : event.angleDelta.y
                if (d !== 0) viewer.zoomTo(viewer.tz * Math.pow(2, d / 480), event.x, event.y)
                return
            }
            if (viewer.zoomedIn) {   // тачпад: двигать приближенную картинку
                viewer.animate = false
                viewer.setPan(viewer.tcx + event.pixelDelta.x, viewer.tcy + event.pixelDelta.y)
                viewer.animate = true
                return
            }
            viewer.swipe += event.pixelDelta.x
            swipeReset.restart()
            if (viewer.swipe < -140) { viewer.swipe = -1e6; viewer.gallery.next() }
            else if (viewer.swipe > 140) { viewer.swipe = 1e6; viewer.gallery.prev() }
        }
    }

    PinchHandler {   // щипок на тачпаде или экране
        id: pinch
        target: null
        property real startZoom: 1
        onActiveChanged: if (active) startZoom = viewer.tz
        onActiveScaleChanged: if (active) viewer.zoomTo(startZoom * activeScale, centroid.position.x, centroid.position.y)
    }

    DragHandler {   // перетаскивание приближенной картинки
        id: drag
        target: null
        enabled: viewer.zoomedIn
        cursorShape: active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        property real sx: 0
        property real sy: 0
        onActiveChanged: if (active) { sx = viewer.tcx; sy = viewer.tcy; viewer.animate = false } else viewer.animate = true
        onTranslationChanged: if (active) viewer.setPan(sx + translation.x, sy + translation.y)
    }

    TapHandler {
        acceptedButtons: Qt.LeftButton
        onDoubleTapped: (eventPoint) => viewer.toggleZoom(eventPoint.position.x, eventPoint.position.y)
    }
}
