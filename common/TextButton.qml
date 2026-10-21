import QtQuick

// Кнопка-надпись Glide: primary — залита акцентом, иначе — поверхность. Состояния как у IconButton.
Rectangle {
    id: btn

    property string text: ""
    property int glyph: 0
    property bool primary: false
    property bool flat: false
    signal clicked()

    implicitWidth: row.implicitWidth + 32
    implicitHeight: 40
    radius: height / 2
    opacity: enabled ? 1 : Theme.disabledOpacity
    color: primary ? (area.pressed ? Theme.accentPressed : area.containsMouse ? Theme.accentLight : Theme.accent)
                   : area.pressed ? Theme.surfacePressed
                   : area.containsMouse ? Theme.surfaceHigher
                   : flat ? "transparent" : Theme.surfaceHigh
    scale: area.pressed ? 0.95 : 1
    Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
    Behavior on color { ColorAnimation { duration: 120 } }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 8
        Text {
            visible: btn.glyph !== 0
            anchors.verticalCenter: parent.verticalCenter
            text: btn.glyph ? Theme.icon(btn.glyph) : ""
            color: btn.primary ? Theme.accentText : Theme.text
            font.family: Theme.iconFont
            font.pixelSize: Theme.fs(17)
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: btn.text
            color: btn.primary ? Theme.accentText : btn.flat ? Theme.accent : Theme.text
            font.pixelSize: Theme.fs(14)
            font.weight: Font.DemiBold
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        enabled: btn.enabled
        cursorShape: btn.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: btn.clicked()
    }
}
