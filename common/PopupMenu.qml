import QtQuick

// Небольшое меню над кнопкой: items — [{ text, checked, header, run }]; header — подпись раздела.
Rectangle {
    id: menu

    property bool open: false
    property var items: []

    width: 240
    height: col.implicitHeight + 12
    radius: Theme.radiusMd
    color: Theme.surfaceHigh
    border.color: Theme.outline
    opacity: open ? 1 : 0
    visible: opacity > 0
    scale: open ? 1 : 0.96
    transformOrigin: Item.BottomRight
    z: 60
    Behavior on opacity { NumberAnimation { duration: 120 } }
    Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

    MouseArea { anchors.fill: parent }   // щелчки внутри меню не уходят к видео

    Column {
        id: col
        x: 6; y: 6
        width: parent.width - 12
        Repeater {
            model: menu.items
            delegate: Rectangle {
                required property var modelData
                readonly property bool header: !!modelData.header
                width: col.width
                height: header ? 28 : 36
                radius: Theme.radiusSm
                color: !header && itemArea.pressed ? Theme.surfacePressed
                     : !header && itemArea.containsMouse ? Theme.surfaceHigher : "transparent"
                Text {
                    x: parent.header ? 10 : 34
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - x - 10
                    text: parent.modelData.text
                    color: parent.header ? Theme.textMuted : Theme.text
                    font.pixelSize: Theme.fs(parent.header ? 11 : 13)
                    elide: Text.ElideRight
                }
                Text {   // галочка у выбранного
                    visible: !parent.header && !!parent.modelData.checked
                    x: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: Theme.icon(0xF012C)
                    color: Theme.accent
                    font.family: Theme.iconFont
                    font.pixelSize: Theme.fs(16)
                }
                MouseArea {
                    id: itemArea
                    anchors.fill: parent
                    enabled: !parent.header
                    hoverEnabled: true
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: { menu.open = false; parent.modelData.run() }
                }
            }
        }
    }
}
