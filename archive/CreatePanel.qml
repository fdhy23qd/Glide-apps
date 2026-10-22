import QtQuick
import Glide.Ui

// Окно «Новый архив»: что пакуем, имя, формат, куда сохранить, пароль (только zip — AES-256).
// Значения снаружи — свойствами: inline-компоненты и чужие id отсюда не видны.
Item {
    id: panel

    property bool open: false
    property var info: ({ count: 0, files: 0, dirs: 0, size: 0, names: [], paths: [], folder: "" })
    property string folder: ""
    property string format: "zip"
    property bool working: false
    property var homeOf: p => p
    property var humanSize: b => b + Tr.t(" Б")
    property var countText: (f, d) => f + ""

    signal accepted(string out, string format, string password)
    signal pickFolder()
    signal addRequested(var urls)
    signal cancelled()

    readonly property var formats: [
        { id: "zip", hint: Tr.t("Открывается везде, можно поставить пароль") },
        { id: "7z", hint: Tr.t("Сильнее сжимает; открывают 7-Zip, WinRAR и Linux") },
        { id: "tar.zst", hint: Tr.t("Быстро и хорошо сжимает — для Linux") },
        { id: "tar.xz", hint: Tr.t("Компактнее всех, но медленнее — для Linux") },
        { id: "tar.gz", hint: Tr.t("Старый совместимый формат для Linux и macOS") }
    ]
    readonly property bool passwordAllowed: format === "zip"

    function show(i, suggested) {
        info = i
        folder = i.folder
        let n = suggested ? suggested.split("/").pop() : (i.names[0] || Tr.t("Архив"))
        if (n.endsWith(".zip")) n = n.substring(0, n.length - 4)
        nameField.text = n
        protect.checked = false
        pwField.text = ""
        open = true
        nameField.focusAll()
    }
    function close() { open = false }
    function add(urls) { addRequested(urls) }
    function submit() {
        const n = nameField.text.trim().replace(/\//g, "_")
        if (!n || working) return
        if (protect.checked && passwordAllowed && !pwField.text) { pwField.focusAll(); return }
        accepted(folder + "/" + n + "." + format, format, protect.checked && passwordAllowed ? pwField.text : "")
    }

    visible: opacity > 0
    opacity: open ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 140 } }

    Rectangle { anchors.fill: parent; color: Theme.scrim }
    MouseArea { anchors.fill: parent; onClicked: { panel.close(); panel.cancelled() } }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(500, parent.width - 32)
        height: Math.min(col.implicitHeight + 44 + 58, parent.height - 32)
        radius: Theme.radiusLg
        color: Theme.surface
        border.color: Theme.outline
        clip: true
        scale: panel.open ? 1 : 0.96
        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        MouseArea { anchors.fill: parent }

        Flickable {
            id: flick
            anchors.fill: parent
            anchors.margins: 22
            anchors.bottomMargin: 22 + 58
            contentHeight: col.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            clip: true

            Column {
                id: col
                width: parent.width
                spacing: 14

                Text {
                    text: Tr.t("Новый архив")
                    color: Theme.text
                    font.pixelSize: Theme.fs(18)
                    font.weight: Font.DemiBold
                }

                // что пакуем
                Rectangle {
                    width: parent.width
                    height: what.implicitHeight + 24
                    radius: Theme.radiusMd
                    color: Theme.surfaceLow
                    border.color: Theme.outline
                    Column {
                        id: what
                        x: 14; y: 12
                        width: parent.width - 28
                        spacing: 4
                        Text {
                            width: parent.width
                            text: panel.countText(panel.info.files, panel.info.dirs) + " · " + panel.humanSize(panel.info.size)
                            color: Theme.text
                            font.pixelSize: Theme.fs(14)
                            font.weight: Font.DemiBold
                        }
                        Text {
                            width: parent.width
                            text: panel.info.names.slice(0, 4).join(", ") + (panel.info.names.length > 4 ? Tr.t(" и ещё ") + (panel.info.names.length - 4) : "")
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fs(12)
                            elide: Text.ElideRight
                            textFormat: Text.PlainText
                        }
                        Text {
                            text: Tr.t("Перетащите сюда ещё файлы, чтобы добавить")
                            color: Theme.textMuted
                            font.pixelSize: Theme.fs(12)
                        }
                    }
                }

                // имя
                Column {
                    width: parent.width
                    spacing: 6
                    Text { text: Tr.t("Имя"); color: Theme.textSecondary; font.pixelSize: Theme.fs(12) }
                    Row {
                        width: parent.width
                        spacing: 8
                        TextField {
                            id: nameField
                            width: parent.width - ext.width - 8
                            placeholder: Tr.t("Имя архива")
                            onAccepted: panel.submit()
                            onCancelled: { panel.close(); panel.cancelled() }
                        }
                        Text {
                            id: ext
                            anchors.verticalCenter: parent.verticalCenter
                            text: "." + panel.format
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fs(14)
                        }
                    }
                }

                // формат
                Column {
                    width: parent.width
                    spacing: 8
                    Text { text: Tr.t("Формат"); color: Theme.textSecondary; font.pixelSize: Theme.fs(12) }
                    Flow {
                        width: parent.width
                        spacing: 8
                        Repeater {
                            model: panel.formats
                            delegate: Chip {
                                required property var modelData
                                text: modelData.id
                                selected: panel.format === modelData.id
                                onClicked: panel.format = modelData.id
                            }
                        }
                    }
                    Text {
                        width: parent.width
                        text: (panel.formats.find(f => f.id === panel.format) || {}).hint || ""
                        color: Theme.textMuted
                        font.pixelSize: Theme.fs(12)
                        wrapMode: Text.WordWrap
                    }
                }

                // куда
                Column {
                    width: parent.width
                    spacing: 6
                    Text { text: Tr.t("Куда"); color: Theme.textSecondary; font.pixelSize: Theme.fs(12) }
                    Row {
                        width: parent.width
                        spacing: 8
                        Rectangle {
                            width: parent.width - change.width - 8
                            height: 36
                            radius: Theme.radiusMd
                            color: Theme.surfaceLow
                            border.color: Theme.outline
                            Text {
                                x: 12
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 24
                                text: panel.homeOf(panel.folder)
                                color: Theme.text
                                font.pixelSize: Theme.fs(13)
                                elide: Text.ElideMiddle
                                textFormat: Text.PlainText
                            }
                        }
                        TextButton { id: change; implicitHeight: 36; text: Tr.t("Изменить"); onClicked: panel.pickFolder() }
                    }
                }

                // пароль
                Column {
                    width: parent.width
                    spacing: 8
                    Toggle {
                        id: protect
                        width: parent.width
                        text: panel.passwordAllowed ? Tr.t("Защитить паролем") : Tr.t("Пароль — только для zip")
                        enabled: panel.passwordAllowed
                        onToggled: c => {
                            checked = c
                            if (!c) return
                            pwField.focusAll()
                            // поле пароля ниже края — докрутить
                            Qt.callLater(() => flick.contentY = Math.max(0, flick.contentHeight - flick.height))
                        }
                    }
                    Row {
                        opacity: protect.checked && panel.passwordAllowed ? 1 : 0
                        visible: opacity > 0
                        Behavior on opacity { NumberAnimation { duration: 160 } }
                        width: parent.width
                        spacing: 4
                        TextField {
                            id: pwField
                            width: parent.width - eye.width - 4
                            password: !eye.on
                            glyph: 0xF033E
                            placeholder: Tr.t("Пароль")
                            onAccepted: panel.submit()
                            onCancelled: { panel.close(); panel.cancelled() }
                        }
                        IconButton { id: eye; anchors.verticalCenter: parent.verticalCenter; glyph: 0xF0208; tip: on ? Tr.t("Скрыть") : Tr.t("Показать"); onClicked: on = !on }
                    }
                    Text {
                        opacity: protect.checked && panel.passwordAllowed ? 1 : 0
                        visible: opacity > 0
                        Behavior on opacity { NumberAnimation { duration: 160 } }
                        width: parent.width
                        text: Tr.t("Шифрование AES-256: имена файлов видны, содержимое — нет. Забытый пароль не восстановить.")
                        color: Theme.textMuted
                        font.pixelSize: Theme.fs(12)
                        wrapMode: Text.WordWrap
                    }
                }

            }
        }

        Row {   // кнопки всегда видны: если полей больше, чем влезает, прокручиваются только поля
            id: actions
            anchors.right: parent.right
            anchors.rightMargin: 22
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 18
            spacing: 8
            TextButton { text: Tr.t("Отмена"); flat: true; onClicked: { panel.close(); panel.cancelled() } }
            TextButton {
                primary: true
                glyph: 0xF003C
                text: Tr.t("Создать")
                enabled: nameField.text.trim() !== "" && !panel.working && panel.info.count > 0
                         && (!protect.checked || !panel.passwordAllowed || pwField.text !== "")
                onClicked: panel.submit()
            }
        }
    }
}
