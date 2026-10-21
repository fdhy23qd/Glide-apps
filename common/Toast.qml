import QtQuick

// Всплывающая строка снизу: «Перемещено в корзину · Отменить». show(текст, действие, функция).
Rectangle {
    id: toast

    property string message: ""
    property string actionText: ""
    property var action: null

    function show(msg, actText, fn) {
        message = msg
        actionText = actText || ""
        action = fn || null
        shown = true
        hideTimer.restart()
    }
    property bool shown: false

    anchors.horizontalCenter: parent.horizontalCenter
    y: parent.height - (shown ? height + 24 : 0)
    opacity: shown ? 1 : 0
    visible: opacity > 0
    Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
    Behavior on opacity { NumberAnimation { duration: 180 } }
    z: 50

    width: row.implicitWidth + 32
    height: 48
    radius: height / 2
    color: Theme.surfaceHigh
    border.color: Theme.outline

    HoverHandler { id: hover }
    Timer {
        id: hideTimer
        interval: 5000
        onTriggered: if (hover.hovered) restart(); else toast.shown = false
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 12
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: toast.message
            color: Theme.text
            font.pixelSize: Theme.fs(14)
        }
        TextButton {
            visible: toast.actionText !== ""
            anchors.verticalCenter: parent.verticalCenter
            implicitHeight: 32
            flat: true
            text: toast.actionText
            onClicked: {
                toast.shown = false
                if (toast.action) toast.action()
            }
        }
    }
}
