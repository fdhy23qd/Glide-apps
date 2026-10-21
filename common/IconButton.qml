import QtQuick

// Круглая кнопка-значок Glide: наведение светлее, нажатие темнее и чуть меньше (OutBack),
// недоступна — полупрозрачна; on — выбранное состояние (акцентный фон). tip — подсказка снизу.
Rectangle {
    id: btn

    property int glyph: 0
    property int glyphSize: 18
    property bool on: false
    property bool flat: true          // без фона в покое (на панели); false — фон surfaceHigh
    property string tip: ""
    property bool tipAbove: false
    signal clicked()

    implicitWidth: 36
    implicitHeight: 36
    radius: height / 2
    opacity: enabled ? 1 : Theme.disabledOpacity
    color: on ? (area.pressed ? Theme.accentPressed : area.containsMouse ? Theme.accentLight : Theme.accent)
              : area.pressed ? Theme.surfacePressed
              : area.containsMouse ? Theme.surfaceHigher
              : flat ? "transparent" : Theme.surfaceHigh
    scale: area.pressed ? 0.92 : 1
    Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
    Behavior on color { ColorAnimation { duration: 120 } }

    Text {
        Behavior on color { ColorAnimation { duration: 140 } }
        anchors.centerIn: parent
        text: btn.glyph ? Theme.icon(btn.glyph) : ""
        color: btn.on ? Theme.accentText : Theme.text
        font.family: Theme.iconFont
        font.pixelSize: Theme.fs(btn.glyphSize)
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        enabled: btn.enabled
        cursorShape: btn.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: btn.clicked()
    }

    Rectangle {   // подсказка: появляется, если курсор задержался
        id: tipBox
        visible: opacity > 0
        opacity: btn.tip && area.containsMouse && !area.pressed && tipDelay.done ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 120 } }
        anchors.horizontalCenter: parent.horizontalCenter
        y: btn.tipAbove ? -height - 8 : parent.height + 8
        z: 100
        width: tipText.implicitWidth + 20
        height: tipText.implicitHeight + 10
        radius: Theme.r(10)
        color: Theme.surfaceHigh
        border.color: Theme.outline
        Text {
            id: tipText
            anchors.centerIn: parent
            text: btn.tip
            color: Theme.textVariant
            font.pixelSize: Theme.fs(12)
        }
    }
    Timer {
        id: tipDelay
        property bool done: false
        interval: 550
        running: area.containsMouse
        onRunningChanged: if (!running) done = false
        onTriggered: done = true
    }
}
