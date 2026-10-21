import QtQuick

// Ползунок 0…1: тянуть или щёлкнуть; колесо — шаг. moved(значение) — только от пользователя.
Item {
    id: slider

    property real value: 0          // 0…1
    property real step: 0.05
    readonly property bool dragging: area.pressed
    signal moved(real value)

    implicitWidth: 120
    implicitHeight: 24
    opacity: enabled ? 1 : Theme.disabledOpacity

    function setFrom(x) { slider.moved(Math.max(0, Math.min(1, x / width))) }

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: area.containsMouse || area.pressed ? 6 : 4
        radius: height / 2
        color: Theme.surfaceHigher
        Behavior on height { NumberAnimation { duration: 120 } }
        Rectangle {
            width: parent.width * slider.value
            height: parent.height
            radius: parent.radius
            color: Theme.accent
        }
    }
    Rectangle {   // бегунок
        width: area.pressed ? 16 : 12
        height: width
        radius: width / 2
        x: slider.width * slider.value - width / 2
        anchors.verticalCenter: parent.verticalCenter
        color: Theme.text
        opacity: area.containsMouse || area.pressed ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 140 } }
        scale: area.containsMouse || area.pressed ? 1 : 0.4
        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
        Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }
    }
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        enabled: slider.enabled
        cursorShape: slider.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onPressed: mouse => slider.setFrom(mouse.x)
        onPositionChanged: mouse => { if (pressed) slider.setFrom(mouse.x) }
        onWheel: wheel => slider.moved(Math.max(0, Math.min(1, slider.value + (wheel.angleDelta.y > 0 ? slider.step : -slider.step))))
    }
}
