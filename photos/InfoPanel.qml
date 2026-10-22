import QtQuick
import Glide.Ui

// Сведения о файле: карточка справа (клавиша I).
Rectangle {
    id: panel

    required property var gallery
    property bool open: false

    width: 300
    implicitHeight: content.implicitHeight + 36
    radius: Theme.radiusLg
    color: Theme.surface
    border.color: Theme.outline
    opacity: open ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: 160 } }
    transform: Translate { x: panel.open ? 0 : 24; Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } } }

    function sizeText(b) {
        if (b < 1024) return b + Tr.t(" Б")
        if (b < 1048576) return (b / 1024).toFixed(0) + Tr.t(" КБ")
        return (b / 1048576).toFixed(b < 10485760 ? 1 : 0).replace(".", Tr.ru ? "," : ".") + Tr.t(" МБ")
    }
    readonly property var i: gallery.info
    readonly property var rows: !i.name ? [] : [
        [Tr.t("Размер"), i.width + " × " + i.height + Tr.t(" пикс. · ") + (i.width * i.height / 1e6).toFixed(1).replace(".", Tr.ru ? "," : ".") + Tr.t(" Мп")],
        [Tr.t("Файл"), sizeText(i.bytes) + " · " + (i.format || "?") + (i.animated ? Tr.t(" · анимация") : "")],
        [Tr.t("Изменён"), Tr.locale.toString(i.modified, "d MMMM yyyy, HH:mm")],
        [Tr.t("Папка"), gallery.folder],
        [Tr.t("В папке"), (gallery.index + 1) + Tr.t(" из ") + gallery.count]
    ]

    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }   // не пропускать щелчки к фото

    Column {
        id: content
        x: 20; y: 18
        width: parent.width - 40
        spacing: 14

        Row {
            width: parent.width
            Text {
                width: parent.width - 32
                anchors.verticalCenter: parent.verticalCenter
                text: Tr.t("Сведения")
                color: Theme.text
                font.pixelSize: Theme.fs(16)
                font.weight: Font.DemiBold
            }
            IconButton {
                width: 32; height: 32; glyphSize: 16
                glyph: 0xF0156
                onClicked: panel.open = false
            }
        }
        Text {
            width: parent.width
            text: panel.i.name || ""
            color: Theme.textVariant
            font.pixelSize: Theme.fs(13)
            wrapMode: Text.WrapAnywhere
            textFormat: Text.PlainText
        }
        Repeater {
            model: panel.rows
            delegate: Column {
                required property var modelData
                width: parent.width
                spacing: 2
                Text {
                    text: modelData[0]
                    color: Theme.textMuted
                    font.pixelSize: Theme.fs(11)
                }
                Text {
                    width: parent.width
                    text: modelData[1]
                    color: Theme.text
                    font.pixelSize: Theme.fs(13)
                    wrapMode: Text.WrapAnywhere
                    textFormat: Text.PlainText
                }
            }
        }
    }
}
