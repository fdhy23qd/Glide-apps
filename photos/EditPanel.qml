import QtQuick
import Glide.Ui
import GlidePhotos

// Правка фото: обрезка (пропорции), поворот и отражение, размер, формат, качество; оценка размера файла;
// «Сохранить копию» или «Заменить оригинал» (оригинал — в корзину, Ctrl+Z вернёт).
Rectangle {
    id: panel

    required property var editor        // ImageEditor
    required property var view          // EditView
    required property var info          // gallery.info
    property bool open: false

    property int longSide: 0
    property string fmt: "same"
    property int quality: 85

    readonly property var opts: ({
        path: info.path || "", rotate: view.rotate, flipH: view.flipH, flipV: view.flipV,
        crop: view.cropped ? view.crop : ({}), longSide: longSide, format: fmt, quality: quality
    })
    readonly property string ext: editor.outputExt(opts)
    readonly property bool lossy: ["jpg", "webp", "avif", "jxl"].indexOf(ext) >= 0
    readonly property real cropLong: Math.max(view.natW * view.crop.w, view.natH * view.crop.h)

    function reset() { longSide = 0; fmt = "same"; quality = 85; view.rotate = 0; view.flipH = false; view.flipV = false; view.resetCrop() }
    function save(mode) {
        var o = Object.assign({}, opts)
        o.mode = mode
        editor.save(o)
    }
    function sizeText(b) {
        if (b < 1024) return b + " Б"
        if (b < 1048576) return Math.round(b / 1024) + " КБ"
        return (b / 1048576).toFixed(1).replace(".", ",") + " МБ"
    }

    // оценка размера — после того как перестали менять
    onOptsChanged: if (open) estimateTimer.restart()
    onOpenChanged: if (open) estimateTimer.restart()
    Timer { id: estimateTimer; interval: 300; onTriggered: panel.editor.requestEstimate(panel.opts) }

    width: 330
    radius: Theme.radiusLg
    color: Theme.surface
    border.color: Theme.outline
    opacity: open ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: 160 } }
    transform: Translate { x: panel.open ? 0 : 24; Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } } }

    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

    component Section: Text {
        color: Theme.textMuted
        font.pixelSize: Theme.fs(11)
        font.weight: Font.DemiBold
        topPadding: 6
    }

    Flickable {
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

            Text {
                text: "Правка"
                color: Theme.text
                font.pixelSize: Theme.fs(16)
                font.weight: Font.DemiBold
            }

            Section { text: "ОБРЕЗКА" }
            Flow {
                width: parent.width
                spacing: 6
                Repeater {
                    model: [
                        { text: "Свободно", a: 0 }, { text: "Исходные", a: -1 }, { text: "1:1", a: 1 },
                        { text: "4:3", a: 4 / 3 }, { text: "3:4", a: 3 / 4 }, { text: "16:9", a: 16 / 9 }, { text: "9:16", a: 9 / 16 }
                    ]
                    delegate: Chip {
                        required property var modelData
                        readonly property real value: modelData.a < 0 ? panel.view.natW / panel.view.natH : modelData.a
                        text: modelData.text
                        selected: Math.abs(panel.view.aspect - value) < 1e-3
                        onClicked: panel.view.setAspect(value)
                    }
                }
            }
            TextButton {
                implicitHeight: 32
                text: "Без обрезки"
                enabled: panel.view.cropped
                onClicked: panel.view.resetCrop()
            }

            Section { text: "ПОВОРОТ И ОТРАЖЕНИЕ" }
            Row {
                spacing: 6
                IconButton { flat: false; glyph: 0xF0465; tip: "Влево  Shift+R"; onClicked: panel.view.rotate = (panel.view.rotate + 270) % 360 }
                IconButton { flat: false; glyph: 0xF0467; tip: "Вправо  R"; onClicked: panel.view.rotate = (panel.view.rotate + 90) % 360 }
                IconButton { flat: false; glyph: 0xF0A0E; tip: "Отразить по горизонтали"; on: panel.view.flipH; onClicked: panel.view.flipH = !panel.view.flipH }
                IconButton { flat: false; glyph: 0xF0A0F; tip: "Отразить по вертикали"; on: panel.view.flipV; onClicked: panel.view.flipV = !panel.view.flipV }
            }

            Section { text: "РАЗМЕР (длинная сторона)" }
            Flow {
                width: parent.width
                spacing: 6
                Repeater {
                    model: [0, 3840, 2560, 1920, 1280, 800]
                    delegate: Chip {
                        required property int modelData
                        text: modelData === 0 ? "Исходный" : modelData + " px"
                        selected: panel.longSide === modelData
                        enabled: modelData === 0 || modelData < panel.cropLong
                        onClicked: panel.longSide = modelData
                    }
                }
            }

            Section { text: "ФОРМАТ" }
            Flow {
                width: parent.width
                spacing: 6
                Repeater {
                    model: [{ id: "same", text: "Как есть" }, { id: "jpg", text: "JPEG" }, { id: "png", text: "PNG" },
                            { id: "webp", text: "WebP" }, { id: "avif", text: "AVIF" }, { id: "jxl", text: "JPEG XL" }]
                    delegate: Chip {
                        required property var modelData
                        text: modelData.text
                        selected: panel.fmt === modelData.id
                        onClicked: panel.fmt = modelData.id
                    }
                }
            }

            Section { text: "КАЧЕСТВО"; visible: panel.lossy }
            Row {
                visible: panel.lossy
                width: parent.width
                spacing: 12
                Slider {
                    width: parent.width - qText.width - 12
                    anchors.verticalCenter: parent.verticalCenter
                    value: (panel.quality - 1) / 99
                    step: 0.05
                    onMoved: v => panel.quality = Math.round(1 + v * 99)
                }
                Text {
                    id: qText
                    width: 32
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignRight
                    text: panel.quality
                    color: Theme.text
                    font.pixelSize: Theme.fs(13)
                    font.features: ({ "tnum": 1 })
                }
            }
            Text {
                visible: panel.lossy
                width: parent.width
                text: "Меньше — легче файл. 80–90 — на глаз как оригинал."
                color: Theme.textMuted
                font.pixelSize: Theme.fs(11)
                wrapMode: Text.Wrap
            }
        }
    }

    // ---- итог и сохранение ----
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
            text: (panel.editor.outputSize.width > 0 ? panel.editor.outputSize.width + " × " + panel.editor.outputSize.height + "  ·  " : "")
                  + panel.ext.toUpperCase().replace("JPG", "JPEG").replace("JXL", "JPEG XL")
                  + (panel.editor.estimate > 0 ? "  ·  ≈ " + panel.sizeText(panel.editor.estimate) : "")
                  + (panel.info.bytes ? "  (было " + panel.sizeText(panel.info.bytes) + ")" : "")
            color: Theme.textVariant
            font.pixelSize: Theme.fs(12)
            wrapMode: Text.Wrap
        }
        Text {
            width: parent.width
            text: "Сведения EXIF (камера, место съёмки) в новый файл не попадают."
                  + (panel.ext === "avif" || panel.ext === "jxl" ? " Открыть AVIF и JPEG XL в Фото можно после установки kimageformats." : "")
            color: Theme.textMuted
            font.pixelSize: Theme.fs(11)
            wrapMode: Text.Wrap
        }
        TextButton {
            width: parent.width
            primary: true
            glyph: 0xF0193
            text: panel.editor.busy ? "Сохранение…" : "Сохранить копию"
            enabled: !panel.editor.busy
            onClicked: panel.save("copy")
        }
        TextButton {
            width: parent.width
            text: "Заменить оригинал"
            enabled: !panel.editor.busy
            onClicked: panel.save("replace")
        }
    }
}
