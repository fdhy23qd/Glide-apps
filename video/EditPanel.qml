import QtQuick
import Glide.Ui

// Изменить и сохранить: фрагмент (I/O), формат, качество, размер, без звука, поворот; прогресс экспорта;
// кадр в PNG. Всё делает ffmpeg (Converter), видео при этом можно смотреть дальше.
Rectangle {
    id: panel

    required property var converter
    required property string path
    required property real position
    property var format: (ms) => ""
    property bool open: false

    // ---- выбор пользователя ----
    property real trimStart: 0
    property real trimEnd: 0
    property string fmt: "same"
    property string quality: "copy"
    property int height_: 0          // короткая сторона, 0 — исходная (не «height»: это размер Item)
    property bool mute: false
    property int rotate: 0

    readonly property var info: converter.info
    readonly property bool hasVideo: !!info.hasVideo
    readonly property bool hasAudio: !!info.hasAudio
    readonly property int shortSide: Math.min(info.width || 0, info.height || 0)
    readonly property bool audioFormat: ["mp3", "m4a", "opus", "flac", "wav"].indexOf(fmt) >= 0
                                        || (fmt === "same" && !hasVideo)
    readonly property bool animFormat: fmt === "gif" || fmt === "webp"
    readonly property var opts: ({ input: path, start: trimStart, end: trimEnd, format: fmt, quality: quality,
                                   height: audioFormat ? 0 : height_, mute: mute && !audioFormat,
                                   rotate: audioFormat ? 0 : rotate })
    readonly property bool copyOk: info.ok === true && converter.canCopy(opts)

    function reset() {
        trimStart = 0; trimEnd = 0; fmt = "same"; height_ = 0; mute = false; rotate = 0
        // привязка copyOk в onInfoChanged ещё старая — спрашиваем Converter напрямую
        quality = converter.info.ok === true && converter.canCopy(opts) ? "copy" : "medium"
    }
    // «без перекодирования» невозможно (другой формат, размер, поворот) — переходим на кодирование
    onCopyOkChanged: if (!copyOk && quality === "copy" && info.ok === true) quality = "medium"
    onInfoChanged: reset()

    // копия потоков режет по ключевым кадрам (начало уходит на секунды раньше) — для фрагмента
    // по умолчанию точная обрезка с перекодированием; копию можно выбрать вручную
    function precise() { if (quality === "copy") quality = "high" }
    function setStart(ms) { trimStart = Math.round(ms); if (trimEnd > 0 && trimEnd <= trimStart) trimEnd = 0; precise() }
    function setEnd(ms) { trimEnd = Math.round(ms); if (trimEnd <= trimStart) trimStart = 0; precise() }
    function save() { if (!converter.running && info.ok) converter.start(opts) }

    width: 330
    radius: Theme.radiusLg
    color: Theme.surface
    border.color: Theme.outline
    opacity: open ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: 160 } }
    transform: Translate { x: panel.open ? 0 : 24; Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } } }

    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onWheel: wheel => wheel.accepted = false }

    component Section: Text {
        color: Theme.textMuted
        font.pixelSize: Theme.fs(11)
        font.weight: Font.DemiBold
        topPadding: 6
    }

    Flickable {
        id: flick
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: footer.top
        anchors.margins: 1
        contentHeight: content.implicitHeight + 24
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: content
            x: 20; y: 18
            width: panel.width - 40
            spacing: 10

            Row {
                width: parent.width
                Text {
                    width: parent.width - 32
                    anchors.verticalCenter: parent.verticalCenter
                    text: Tr.t("Изменить и сохранить")
                    color: Theme.text
                    font.pixelSize: Theme.fs(16)
                    font.weight: Font.DemiBold
                }
                IconButton { width: 32; height: 32; glyphSize: 16; glyph: 0xF0156; onClicked: panel.open = false }
            }

            // ---- фрагмент ----
            Section { text: Tr.t("ФРАГМЕНТ") }
            Repeater {
                model: [
                    { label: Tr.t("Начало"), value: panel.trimStart, set: () => panel.setStart(panel.position), clear: () => panel.trimStart = 0 },
                    { label: Tr.t("Конец"), value: panel.trimEnd, set: () => panel.setEnd(panel.position), clear: () => panel.trimEnd = 0 }
                ]
                delegate: Row {
                    required property var modelData
                    width: content.width
                    spacing: 8
                    Text {
                        width: 64
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.label
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fs(13)
                    }
                    Text {
                        width: content.width - 64 - 8 - setBtn.width - 8 - 32
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.value > 0 ? panel.format(modelData.value) : (modelData.label === Tr.t("Начало") ? Tr.t("с начала") : Tr.t("до конца"))
                        color: modelData.value > 0 ? Theme.warning : Theme.textMuted
                        font.pixelSize: Theme.fs(13)
                        font.features: ({ "tnum": 1 })
                    }
                    TextButton { id: setBtn; implicitHeight: 32; text: Tr.t("Сейчас"); onClicked: modelData.set() }
                    IconButton { width: 32; height: 32; glyphSize: 14; glyph: 0xF0156; enabled: modelData.value > 0; onClicked: modelData.clear() }
                }
            }
            Text {
                width: parent.width
                text: Tr.t("Клавиши I и O — начало и конец в текущей точке")
                color: Theme.textMuted
                font.pixelSize: Theme.fs(11)
                wrapMode: Text.Wrap
            }

            // ---- формат ----
            Section { text: Tr.t("ФОРМАТ") }
            Flow {
                width: parent.width
                spacing: 6
                Repeater {
                    model: [
                        { id: "same", text: Tr.t("Как есть"), video: true, audio: true },
                        { id: "mp4", text: "MP4", video: true }, { id: "webm", text: "WebM", video: true },
                        { id: "mkv", text: "MKV", video: true }, { id: "gif", text: "GIF", video: true },
                        { id: "webp", text: "WebP", video: true },
                        { id: "mp3", text: "MP3", audio: true }, { id: "m4a", text: "M4A", audio: true },
                        { id: "opus", text: "Opus", audio: true }, { id: "flac", text: "FLAC", audio: true },
                        { id: "wav", text: "WAV", audio: true }
                    ]
                    delegate: Chip {
                        required property var modelData
                        text: modelData.text
                        selected: panel.fmt === modelData.id
                        enabled: (!!modelData.video && panel.hasVideo) || (!!modelData.audio && panel.hasAudio)
                        onClicked: panel.fmt = modelData.id
                    }
                }
            }

            // ---- качество ----
            Section { text: Tr.t("КАЧЕСТВО") }
            Flow {
                width: parent.width
                spacing: 6
                Chip { text: Tr.t("Без перекодирования"); selected: panel.quality === "copy"; enabled: panel.copyOk; onClicked: panel.quality = "copy" }
                Chip { text: Tr.t("Высокое"); selected: panel.quality === "high"; enabled: panel.fmt !== "wav" && panel.fmt !== "flac"; onClicked: panel.quality = "high" }
                Chip { text: Tr.t("Среднее"); selected: panel.quality === "medium"; enabled: panel.fmt !== "wav" && panel.fmt !== "flac"; onClicked: panel.quality = "medium" }
                Chip { text: Tr.t("Маленький файл"); selected: panel.quality === "small"; enabled: panel.fmt !== "wav" && panel.fmt !== "flac"; onClicked: panel.quality = "small" }
            }

            // ---- размер ----
            Section { text: Tr.t("РАЗМЕР"); visible: panel.hasVideo && !panel.audioFormat }
            Flow {
                visible: panel.hasVideo && !panel.audioFormat
                width: parent.width
                spacing: 6
                Repeater {
                    model: [0, 1080, 720, 480, 360]
                    delegate: Chip {
                        required property int modelData
                        text: modelData === 0 ? (panel.animFormat ? Tr.t("Авто") : Tr.t("Исходный")) : modelData + "p"
                        selected: panel.height_ === modelData
                        enabled: modelData === 0 || modelData < panel.shortSide
                        onClicked: {
                            panel.height_ = modelData
                            if (modelData > 0 && panel.quality === "copy") panel.quality = "high"
                        }
                    }
                }
            }

            // ---- ещё ----
            Section { text: Tr.t("ЕЩЁ"); visible: panel.hasVideo && !panel.audioFormat }
            Toggle {
                visible: panel.hasVideo && !panel.audioFormat && !panel.animFormat
                width: parent.width
                text: Tr.t("Без звука")
                enabled: panel.hasAudio
                checked: panel.mute
                onToggled: on => panel.mute = on
            }
            Row {
                visible: panel.hasVideo && !panel.audioFormat
                width: parent.width
                Text {
                    width: parent.width - rotBtn.width
                    anchors.verticalCenter: parent.verticalCenter
                    text: Tr.t("Повернуть")
                    color: Theme.text
                    font.pixelSize: Theme.fs(13)
                }
                TextButton {
                    id: rotBtn
                    implicitHeight: 32
                    glyph: 0xF0467
                    text: panel.rotate + "°"
                    onClicked: {
                        panel.rotate = (panel.rotate + 90) % 360
                        if (panel.rotate !== 0 && panel.quality === "copy") panel.quality = "high"
                    }
                }
            }

        }
    }

    // ---- итог и сохранение: всегда на виду, прокручиваются только параметры ----
    Column {
        id: footer
        x: 20
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 16
        width: panel.width - 40
        spacing: 10
        Rectangle { width: parent.width; height: 1; color: Theme.divider }
        Text {
            width: parent.width
            text: "→ " + (panel.info.ok ? panel.converter.outputName(panel.opts) : "…")
            color: Theme.textVariant
            font.pixelSize: Theme.fs(12)
            wrapMode: Text.WrapAnywhere
            textFormat: Text.PlainText
        }
        Text {
            width: parent.width
            text: panel.quality === "copy"
                  ? Tr.t("Без перекодирования — за секунды, качество не меняется.")
                    + (panel.trimStart > 0 ? Tr.t(" Начало фрагмента сдвинется к ключевому кадру — бывает на несколько секунд раньше.") : "")
                  : Tr.t("Кодирование: ") + (panel.converter.hardware && !panel.animFormat && !panel.audioFormat && panel.fmt !== "webm"
                                       ? Tr.t("видеокарта (") + panel.converter.hardware + ")" : Tr.t("процессор"))
            color: Theme.textMuted
            font.pixelSize: Theme.fs(11)
            wrapMode: Text.Wrap
        }

        // прогресс или кнопка
        Column {
            visible: panel.converter.running
            width: parent.width
            spacing: 8
            Rectangle {
                width: parent.width; height: 6; radius: 3
                color: Theme.surfaceHigher
                Rectangle {
                    width: parent.width * panel.converter.progress
                    height: parent.height; radius: 3
                    color: Theme.accent
                    Behavior on width { NumberAnimation { duration: 200 } }
                }
            }
            Row {
                width: parent.width
                Text {
                    width: parent.width - cancelBtn.width
                    anchors.verticalCenter: parent.verticalCenter
                    text: Math.round(panel.converter.progress * 100) + "%"
                          + (panel.converter.speed > 0 ? "  ·  ×" + panel.converter.speed.toFixed(1).replace(".", Tr.ru ? "," : ".") : "")
                          + (panel.converter.eta >= 0 ? Tr.t("  ·  осталось ") + (panel.converter.eta < 60 ? panel.converter.eta + Tr.t(" с")
                                 : Math.floor(panel.converter.eta / 60) + Tr.t(" мин ") + panel.converter.eta % 60 + Tr.t(" с")) : "")
                    color: Theme.textVariant
                    font.pixelSize: Theme.fs(12)
                    font.features: ({ "tnum": 1 })
                }
                TextButton { id: cancelBtn; implicitHeight: 32; text: Tr.t("Отмена"); onClicked: panel.converter.cancel() }
            }
        }
        TextButton {
            visible: !panel.converter.running
            width: parent.width
            primary: true
            glyph: 0xF0193
            text: Tr.t("Сохранить")
            enabled: panel.info.ok === true
            onClicked: panel.save()
        }
        TextButton {
            width: parent.width
            glyph: 0xF0100
            text: Tr.t("Сохранить кадр (PNG)")
            enabled: panel.hasVideo
            onClicked: panel.converter.snapshot(panel.path, panel.position)
        }
    }
}
