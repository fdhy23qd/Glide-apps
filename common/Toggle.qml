import QtQuick

// Строка с переключателем (MD3): вся строка кликабельна, бегунок пружинит.
Item {
    id: row

    property string text: ""
    property bool checked: false
    signal toggled(bool checked)

    implicitWidth: 240
    implicitHeight: 36
    opacity: enabled ? 1 : Theme.disabledOpacity

    Text {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - track.width - 12
        text: row.text
        color: Theme.text
        font.pixelSize: Theme.fs(13)
        elide: Text.ElideRight
    }
    Rectangle {
        id: track
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: 44; height: 24
        radius: height / 2
        color: row.checked ? (area.containsMouse ? Theme.accentLight : Theme.accent)
                           : (area.containsMouse ? Theme.surfaceHigher : Theme.surfaceHigh)
        border.width: row.checked ? 0 : 1
        border.color: Theme.outline
        Behavior on color { ColorAnimation { duration: 140 } }
        Rectangle {
            Behavior on color { ColorAnimation { duration: 140 } }
            width: area.pressed ? 22 : 18
            height: 18
            radius: 9
            y: 3
            x: row.checked ? parent.width - width - 3 : 3
            color: row.checked ? Theme.accentText : Theme.textSecondary
            Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
            Behavior on width { NumberAnimation { duration: 120 } }
        }
    }
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        enabled: row.enabled
        cursorShape: row.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: row.toggled(!row.checked)
    }
}
