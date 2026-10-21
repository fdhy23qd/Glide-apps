import QtQuick

// Поле ввода Glide: наведение — светлее обводка и курсор I-beam, фокус — акцентная обводка толщиной 2.
// password — точки вместо букв; accepted() — Enter; shiftAccepted() — Shift+Enter; cancelled() — Esc.
Rectangle {
    id: field

    property alias text: input.text
    property alias input: input
    property string placeholder: ""
    property bool password: false
    property int glyph: 0
    property bool error: false
    signal accepted()
    signal shiftAccepted()
    signal cancelled()

    function focusAll() { input.forceActiveFocus(); input.selectAll() }

    implicitWidth: 220
    implicitHeight: 36
    radius: Theme.radiusMd
    color: Theme.surface
    opacity: enabled ? 1 : Theme.disabledOpacity
    border.width: input.activeFocus || error ? 2 : 1
    border.color: error ? Theme.error : input.activeFocus ? Theme.accent : hover.hovered ? Theme.outlineHover : Theme.outline
    Behavior on border.color { ColorAnimation { duration: 140 } }
    HoverHandler { id: hover; cursorShape: Qt.IBeamCursor }

    Text {
        id: icon
        visible: field.glyph !== 0
        x: 12
        anchors.verticalCenter: parent.verticalCenter
        text: field.glyph ? Theme.icon(field.glyph) : ""
        color: Theme.textSecondary
        font.family: Theme.iconFont
        font.pixelSize: Theme.fs(16)
    }
    TextInput {
        id: input
        anchors.left: icon.visible ? icon.right : parent.left
        anchors.leftMargin: icon.visible ? 8 : 14
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        color: Theme.text
        selectionColor: Theme.accent
        selectedTextColor: Theme.accentText
        font.pixelSize: Theme.fs(13)
        clip: true
        echoMode: field.password ? TextInput.Password : TextInput.Normal
        passwordCharacter: "●"
        onAccepted: field.accepted()
        Keys.onEscapePressed: field.cancelled()
        Keys.onPressed: event => {
            if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && (event.modifiers & Qt.ShiftModifier)) {
                field.shiftAccepted()
                event.accepted = true
            }
        }
        Text {
            anchors.fill: parent
            verticalAlignment: Text.AlignVCenter
            visible: !input.text && !input.preeditText
            text: field.placeholder
            color: Theme.textMuted
            font.pixelSize: input.font.pixelSize
            elide: Text.ElideRight
        }
    }
}
