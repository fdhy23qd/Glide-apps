import QtQuick

// Чип выбора (формат, качество, размер): выбранный — акцентная обводка и мягкий акцентный фон.
Rectangle {
    id: chip
    Behavior on border.color { ColorAnimation { duration: 140 } }

    property string text: ""
    property bool selected: false
    signal clicked()

    implicitWidth: label.implicitWidth + 28
    implicitHeight: 32
    radius: height / 2
    opacity: enabled ? 1 : Theme.disabledOpacity
    color: selected ? (area.pressed ? Theme.accentHover : area.containsMouse ? Qt.lighter(Theme.accentSoft, 1.3) : Theme.accentSoft)
                    : area.pressed ? Theme.surfacePressed : area.containsMouse ? Theme.surfaceHigher : Theme.surfaceHigh
    border.width: 1
    border.color: selected ? Theme.accent : "transparent"
    scale: area.pressed ? 0.95 : 1
    Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
    Behavior on color { ColorAnimation { duration: 120 } }

    Text {
        id: label
        Behavior on color { ColorAnimation { duration: 140 } }
        anchors.centerIn: parent
        text: chip.text
        color: chip.selected ? Theme.text : Theme.textVariant
        font.pixelSize: Theme.fs(13)
        font.weight: chip.selected ? Font.DemiBold : Font.Normal
    }
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        enabled: chip.enabled
        cursorShape: chip.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: chip.clicked()
    }
}
