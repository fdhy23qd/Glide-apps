import QtQuick
import QtQuick.Window
import QtCore
import QtMultimedia
import Glide.Ui
import GlideCamera

// Glide Камера — фото и видео с веб-камеры. Предпросмотр зеркальный (как в зеркале), снимок — как есть.
// Пробел — снять / начать и остановить запись, V — фото ↔ видео, T — таймер, F — во весь экран.
// Снимки — ~/Изображения/Камера, видео — ~/Видео/Камера; миниатюра последнего открывает его.
Window {
    id: win

    width: 900
    height: 640
    minimumWidth: 480
    minimumHeight: 380
    visible: true
    flags: Qt.Window | Qt.FramelessWindowHint
    color: "#000000"
    title: Tr.t("Камера")
    Component.onCompleted: { Theme.forceDark = true; win.lastPath = Paths.latest() }   // видоискатель — всегда тёмный

    Settings {
        id: prefs
        category: "camera"
        property string mode: "photo"     // photo | video
        property bool mirror: true
        property bool sound: true
        property int timer: 0             // 0 | 3 | 10 с
        property string deviceId: ""
        property string format: ""        // «1280x720@30» — пусто: самое крупное
    }

    // ---- устройство и формат ----
    MediaDevices { id: devices }
    readonly property var device: {
        var list = devices.videoInputs
        for (var i = 0; i < list.length; i++) if (list[i].id == prefs.deviceId) return list[i]
        return devices.defaultVideoInput
    }
    readonly property bool hasCamera: devices.videoInputs.length > 0
    function fmtKey(f) { return f.resolution.width + "x" + f.resolution.height + "@" + Math.round(f.maxFrameRate) }
    // форматы без повторов (одинаковые размер и частота в разных пикселях), крупные — первыми
    readonly property var formats: {
        var seen = {}, out = []
        var list = device ? device.videoFormats : []
        for (var i = 0; i < list.length; i++) {
            var k = fmtKey(list[i])
            if (!seen[k] && list[i].maxFrameRate >= 10) { seen[k] = true; out.push(list[i]) }
        }
        out.sort((a, b) => b.resolution.width * b.resolution.height - a.resolution.width * a.resolution.height
                          || b.maxFrameRate - a.maxFrameRate)
        return out
    }
    readonly property var format: formats.find(f => fmtKey(f) === prefs.format) || formats[0] || null

    property string lastPath: ""
    property string error: ""

    CaptureSession {
        id: session
        camera: Camera {
            id: camera
            cameraDevice: win.device
            cameraFormat: win.format
            active: win.hasCamera && !Paths.cameraOff && win.visibility !== Window.Minimized
            onErrorOccurred: (err, text) => win.error = text
        }
        imageCapture: ImageCapture {
            id: shot
            onImageSaved: (id, path) => { win.lastPath = path; flash.restart() }
            onErrorOccurred: (id, err, text) => toast.show(Tr.t("Не удалось снять: ") + text)
        }
        recorder: MediaRecorder {
            id: recorder
            quality: MediaRecorder.HighQuality
            mediaFormat {
                fileFormat: MediaFormat.MPEG4
                videoCodec: MediaFormat.VideoCodec.H264
                audioCodec: MediaFormat.AudioCodec.AAC
            }
            onRecorderStateChanged: if (recorderState === MediaRecorder.StoppedState && actualLocation.toString())
                                        win.lastPath = decodeURIComponent(actualLocation.toString().replace("file://", ""))
            onErrorOccurred: (err, text) => toast.show(Tr.t("Запись остановлена: ") + text)
        }
        audioInput: AudioInput { muted: !prefs.sound }
        videoOutput: viewfinder
    }
    readonly property bool recording: recorder.recorderState === MediaRecorder.RecordingState

    // ---- спуск: таймер, снимок, запись ----
    property int countdown: 0
    Timer {
        id: tick
        interval: 1000; repeat: true
        onTriggered: if (--win.countdown <= 0) { stop(); win.fire() }
    }
    function shutter() {
        if (!win.hasCamera || !camera.active) return
        if (recording) { recorder.stop(); return }
        if (countdown > 0) { tick.stop(); countdown = 0; return }   // второе нажатие — отменить отсчёт
        if (prefs.timer > 0) { countdown = prefs.timer; tick.restart(); return }
        fire()
    }
    function fire() {
        if (prefs.mode === "photo") shot.captureToFile(Paths.newPhoto())
        else { recorder.outputLocation = "file://" + Paths.newVideo(); recorder.record() }
    }
    function setMode(m) { if (!recording) prefs.mode = m }

    // ---- видоискатель ----
    VideoOutput {
        id: viewfinder
        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectFit
        transform: Scale { origin.x: viewfinder.width / 2; xScale: prefs.mirror ? -1 : 1 }
        TapHandler { onDoubleTapped: win.toggleFullscreen() }
    }
    Rectangle {   // вспышка снимка
        id: flashRect
        anchors.fill: parent
        color: "#ffffff"
        opacity: 0
        SequentialAnimation {
            id: flash
            NumberAnimation { target: flashRect; property: "opacity"; to: 0.75; duration: 40 }
            NumberAnimation { target: flashRect; property: "opacity"; to: 0; duration: 260; easing.type: Easing.OutCubic }
        }
    }
    Text {   // отсчёт таймера
        anchors.centerIn: parent
        visible: win.countdown > 0
        text: win.countdown
        color: "#ffffff"
        font.pixelSize: Math.min(parent.width, parent.height) / 3
        font.weight: Font.Bold
        style: Text.Outline; styleColor: Qt.rgba(0, 0, 0, 0.4)
        scale: tick.running ? 1 : 0.8
    }

    // ---- нет камеры / ошибка / выключена для проверки ----
    Column {
        anchors.centerIn: parent
        visible: !win.hasCamera || !!win.error || Paths.cameraOff
        spacing: 12
        width: Math.min(440, parent.width - 60)
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Theme.icon(win.hasCamera ? 0xF0100 : 0xF0101)
            color: Theme.textMuted; font.family: Theme.iconFont; font.pixelSize: 64
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: !win.hasCamera ? Tr.t("Камера не найдена") : win.error ? Tr.t("Камера не открылась") : Tr.t("Камера выключена")
            color: Theme.text; font.pixelSize: Theme.fs(18); font.weight: Font.DemiBold
        }
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: !win.hasCamera ? Tr.t("Подключите веб-камеру — она появится здесь сама")
                : win.error ? win.error + Tr.t("\nВозможно, камера занята другим приложением.") : "GLIDE_CAMERA_OFF=1"
            color: Theme.textSecondary; font.pixelSize: Theme.fs(13)
        }
    }

    // ---- панели показываются при движении мыши (во время записи — всегда) ----
    property bool awake: true
    readonly property bool chrome: awake || recording || headerHover.hovered || barHover.hovered || menu.open || !camera.active
    Timer { id: sleepTimer; interval: 2500; running: win.awake; onTriggered: win.awake = false }
    HoverHandler { onPointChanged: { win.awake = true; sleepTimer.restart() } }
    readonly property bool fullscreen: visibility === Window.FullScreen
    function toggleFullscreen() { visibility = fullscreen ? Window.Windowed : Window.FullScreen }

    Item {
        id: header
        width: parent.width
        height: 64
        opacity: win.chrome ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 180 } }
        HoverHandler { id: headerHover }
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.55) }
                GradientStop { position: 1; color: "transparent" }
            }
        }
        DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }
        Row {   // идёт запись: точка и время
            anchors.centerIn: parent
            visible: win.recording
            spacing: 8
            Rectangle {
                width: 12; height: 12; radius: 6; color: Theme.error
                anchors.verticalCenter: parent.verticalCenter
                SequentialAnimation on opacity {
                    running: win.recording; loops: Animation.Infinite
                    NumberAnimation { to: 0.3; duration: 600 }
                    NumberAnimation { to: 1; duration: 600 }
                }
            }
            Text {
                text: { var s = Math.floor(recorder.duration / 1000); return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0") }
                color: "#ffffff"; font.pixelSize: Theme.fs(15); font.weight: Font.DemiBold; font.features: ({ "tnum": 1 })
            }
        }
        Row {
            anchors.right: parent.right
            anchors.rightMargin: 12
            y: 10
            spacing: 2
            IconButton { glyph: win.fullscreen ? 0xF0294 : 0xF0293; tip: Tr.t("Во весь экран  F"); onClicked: win.toggleFullscreen() }
            IconButton { glyph: 0xF0156; tip: Tr.t("Закрыть  Esc"); onClicked: win.close() }
        }
    }

    // ---- нижняя панель: последний снимок · режим и спуск · таймер и настройки ----
    Item {
        id: bar
        anchors.bottom: parent.bottom
        width: parent.width
        height: 132
        opacity: win.chrome ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 180 } }
        HoverHandler { id: barHover }
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0; color: "transparent" }
                GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.6) }
            }
        }

        Rectangle {   // последний снимок или видео — открыть
            id: thumb
            x: 24
            anchors.verticalCenter: shutterBtn.verticalCenter
            width: 56; height: 56; radius: Theme.r(14)
            color: Theme.surfaceHigh
            border.color: Qt.rgba(1, 1, 1, 0.5)
            border.width: 2
            visible: win.lastPath !== ""
            clip: true
            scale: thumbArea.pressed ? 0.92 : thumbArea.containsMouse ? 1.05 : 1
            Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
            Image {
                anchors.fill: parent
                anchors.margins: 2
                visible: win.lastPath.endsWith(".jpg")
                source: visible ? "file://" + win.lastPath : ""
                sourceSize.width: 112; sourceSize.height: 112
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
            }
            Text {
                anchors.centerIn: parent
                visible: win.lastPath.endsWith(".mp4")
                text: Theme.icon(0xF0567)
                color: "#ffffff"; font.family: Theme.iconFont; font.pixelSize: 24
            }
            MouseArea {
                id: thumbArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Qt.openUrlExternally("file://" + win.lastPath)
            }
        }

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 16
            spacing: 10
            Row {   // фото | видео
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 4
                opacity: win.recording ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: 150 } }
                Repeater {
                    model: [{ id: "photo", label: Tr.t("Фото") }, { id: "video", label: Tr.t("Видео") }]
                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool on: prefs.mode === modelData.id
                        width: modeText.implicitWidth + 24; height: 28; radius: 14
                        color: on ? Qt.rgba(1, 1, 1, 0.22) : modeArea.containsMouse ? Qt.rgba(1, 1, 1, 0.1) : "transparent"
                        Behavior on color { ColorAnimation { duration: 140 } }
                        Text {
                            id: modeText
                            anchors.centerIn: parent
                            text: modelData.label
                            color: parent.on ? "#ffffff" : Qt.rgba(1, 1, 1, 0.7)
                            font.pixelSize: Theme.fs(13); font.weight: parent.on ? Font.DemiBold : Font.Normal
                        }
                        MouseArea { id: modeArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: win.setMode(modelData.id) }
                    }
                }
            }
            Item {   // кнопка спуска
                id: shutterBtn
                anchors.horizontalCenter: parent.horizontalCenter
                width: 72; height: 72
                opacity: camera.active ? 1 : Theme.disabledOpacity
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: "transparent"
                    border.color: "#ffffff"
                    border.width: 4
                }
                Rectangle {   // фото — белый круг, видео — красный, во время записи — красный квадрат
                    anchors.centerIn: parent
                    readonly property real s: win.recording ? 28 : 56
                    width: s; height: s
                    radius: win.recording ? 8 : s / 2
                    color: prefs.mode === "video" ? Theme.error : "#ffffff"
                    scale: shutterArea.pressed ? 0.88 : shutterArea.containsMouse ? 0.95 : 1
                    Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    Behavior on radius { NumberAnimation { duration: 200 } }
                    Behavior on color { ColorAnimation { duration: 180 } }
                    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
                }
                MouseArea {
                    id: shutterArea
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: camera.active
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: win.shutter()
                }
            }
        }

        Row {
            anchors.right: parent.right
            anchors.rightMargin: 20
            anchors.verticalCenter: shutterBtn.verticalCenter
            spacing: 4
            IconButton {   // таймер: выкл → 3 → 10
                glyph: 0xF13AB
                on: prefs.timer > 0
                tip: prefs.timer > 0 ? Tr.t("Таймер ") + prefs.timer + Tr.t(" с  T") : Tr.t("Таймер выключен  T")
                onClicked: win.nextTimer()
                Text {
                    visible: prefs.timer > 0
                    anchors.right: parent.right; anchors.top: parent.top
                    text: prefs.timer
                    color: Theme.accent; font.pixelSize: Theme.fs(10); font.weight: Font.Bold
                }
            }
            IconButton { id: moreBtn; glyph: 0xF0493; tip: Tr.t("Настройки"); on: menu.open; onClicked: menu.open = !menu.open }
        }
    }
    function nextTimer() { prefs.timer = prefs.timer === 0 ? 3 : prefs.timer === 3 ? 10 : 0 }

    // ---- настройки: камера, разрешение, зеркало, звук ----
    MouseArea { anchors.fill: parent; visible: menu.open; onPressed: menu.open = false; z: 59 }
    PopupMenu {
        id: menu
        width: 280
        anchors.right: parent.right
        anchors.rightMargin: 16
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 124
        items: {
            var out = []
            var cams = devices.videoInputs
            if (cams.length > 1) {
                out.push({ header: true, text: Tr.t("Камера") })
                for (let i = 0; i < cams.length; i++)
                    out.push({ text: cams[i].description, checked: win.device && cams[i].id == win.device.id,
                               run: () => { prefs.deviceId = cams[i].id; prefs.format = "" } })
            }
            if (win.formats.length > 1) {
                out.push({ header: true, text: Tr.t("Разрешение") })
                for (let j = 0; j < Math.min(6, win.formats.length); j++) {
                    let f = win.formats[j]
                    out.push({ text: f.resolution.width + " × " + f.resolution.height + "  ·  " + Math.round(f.maxFrameRate) + Tr.t(" кадр/с"),
                               checked: win.format && win.fmtKey(f) === win.fmtKey(win.format), run: () => prefs.format = win.fmtKey(f) })
                }
            }
            out.push({ header: true, text: Tr.t("Ещё") })
            out.push({ text: Tr.t("Зеркальный предпросмотр  M"), checked: prefs.mirror, run: () => prefs.mirror = !prefs.mirror })
            out.push({ text: Tr.t("Звук в видео"), checked: prefs.sound, run: () => prefs.sound = !prefs.sound })
            out.push({ text: Tr.t("Открыть папку со снимками"), run: () => Qt.openUrlExternally("file://" + Paths.photoFolder()) })
            return out
        }
    }

    Toast { id: toast }
    ResizeEdges { window: win }

    // ---- клавиши ----
    Shortcut { sequences: ["Space", "Return", "Enter"]; onActivated: win.shutter() }
    Shortcut { sequence: "V"; onActivated: win.setMode(prefs.mode === "photo" ? "video" : "photo") }
    Shortcut { sequence: "T"; onActivated: win.nextTimer() }
    Shortcut { sequence: "M"; onActivated: prefs.mirror = !prefs.mirror }
    Shortcut { sequences: ["F", "F11"]; onActivated: win.toggleFullscreen() }
    Shortcut { sequences: ["Ctrl+W", "Ctrl+Q"]; onActivated: win.close() }
    Shortcut {
        sequence: "Esc"
        onActivated: {
            if (menu.open) menu.open = false
            else if (win.countdown > 0) { tick.stop(); win.countdown = 0 }
            else if (win.fullscreen) win.toggleFullscreen()
            else win.close()
        }
    }
    onClosing: if (recording) recorder.stop()   // недописанное видео — сохранить
}
