import QtQuick
import Glide.Ui

// Полоса перемотки: щелчок или перетаскивание — перейти; при наведении — время под курсором.
// trimStart/trimEnd (мс, 0 — нет) — выделенный для экспорта фрагмент.
Item {
    id: bar

    property real duration: 0
    property real position: 0
    property real trimStart: 0
    property real trimEnd: 0
    property var format: (ms) => ""
    readonly property bool active: area.containsMouse || area.pressed
    signal seek(real ms)

    implicitHeight: 24

    function xFor(ms) { return duration > 0 ? width * Math.max(0, Math.min(1, ms / duration)) : 0 }
    function msAt(x) { return duration * Math.max(0, Math.min(1, x / width)) }

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: bar.active ? 6 : 4
        radius: height / 2
        color: Qt.rgba(1, 1, 1, 0.18)
        Behavior on height { NumberAnimation { duration: 120 } }

        Rectangle {   // просмотрено
            width: bar.xFor(bar.position)
            height: parent.height
            radius: parent.radius
            color: Theme.accent
        }
        Rectangle {   // фрагмент для экспорта — поверх просмотренного, иначе его не видно
            visible: bar.trimStart > 0 || bar.trimEnd > 0
            x: bar.xFor(bar.trimStart)
            width: bar.xFor(bar.trimEnd > 0 ? bar.trimEnd : bar.duration) - x
            height: parent.height
            radius: parent.radius
            color: Qt.rgba(Theme.warning.r, Theme.warning.g, Theme.warning.b, 0.45)
        }
    }
    Repeater {   // маркеры начала и конца фрагмента
        model: [bar.trimStart, bar.trimEnd]
        delegate: Rectangle {
            required property real modelData
            visible: modelData > 0
            x: bar.xFor(modelData) - 1.5
            anchors.verticalCenter: parent.verticalCenter
            width: 3; height: 14; radius: 1.5
            color: Theme.warning
        }
    }
    Rectangle {   // бегунок
        x: bar.xFor(bar.position) - width / 2
        anchors.verticalCenter: parent.verticalCenter
        width: area.pressed ? 16 : 12
        height: width
        radius: width / 2
        color: Theme.text
        opacity: bar.active ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 140 } }
        scale: bar.active ? 1 : 0.4
        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
        Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }
    }
    Rectangle {   // время под курсором
        opacity: area.containsMouse && bar.duration > 0 ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 140 } }
        x: Math.max(0, Math.min(bar.width - width, area.mouseX - width / 2))
        y: -height - 8
        width: tip.implicitWidth + 16
        height: 24
        radius: Theme.r(8)
        color: Theme.surfaceHigh
        border.color: Theme.outline
        Text {
            id: tip
            anchors.centerIn: parent
            text: bar.format(bar.msAt(area.mouseX))
            color: Theme.text
            font.pixelSize: Theme.fs(12)
            font.features: ({ "tnum": 1 })
        }
    }
    MouseArea {
        id: area
        anchors.fill: parent
        anchors.topMargin: -6
        anchors.bottomMargin: -6
        hoverEnabled: true
        enabled: bar.duration > 0
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onPressed: mouse => bar.seek(bar.msAt(mouse.x))
        onPositionChanged: mouse => { if (pressed) bar.seek(bar.msAt(mouse.x)) }
    }
}
