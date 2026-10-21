import QtQuick
import Glide.Ui

// Поиск по тексту: Enter — следующее, Shift+Enter — предыдущее, Esc — закрыть.
Rectangle {
    id: bar

    required property var search      // PdfSearchModel
    property int count: 0             // число совпадений (считает Main)
    property bool open: false
    signal closed()

    function show() { open = true; field.focusAll() }
    function next() { if (bar.count > 0) search.currentResult = (search.currentResult + 1) % bar.count }
    function prev() { if (bar.count > 0) search.currentResult = (search.currentResult - 1 + bar.count) % bar.count }
    function hide() { open = false; search.searchString = ""; field.text = ""; closed() }

    height: open ? 52 : 0
    clip: true
    color: Theme.background
    Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.outline }

    Timer {   // ищем, когда перестали печатать: на сотнях страниц поиск заметен
        id: debounce
        interval: 250
        onTriggered: bar.search.searchString = field.text
    }

    Row {
        x: 16
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8
        TextField {
            id: field
            width: 300
            glyph: 0xF0349
            placeholder: "Найти в документе"
            onTextChanged: debounce.restart()
            // новый запрос — к первому совпадению, тот же — к следующему
            onAccepted: { debounce.stop(); if (bar.search.searchString !== text) bar.search.searchString = text; else bar.next() }
            onCancelled: bar.hide()
            onShiftAccepted: { debounce.stop(); if (bar.search.searchString !== text) bar.search.searchString = text; else bar.prev() }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: 110
            text: !bar.search.searchString ? "" : bar.count === 0 ? "Не найдено"
                  : (bar.search.currentResult + 1) + " из " + bar.count
            color: bar.search.searchString && bar.count === 0 ? Theme.error : Theme.textSecondary
            font.pixelSize: Theme.fs(13)
            font.features: ({ "tnum": 1 })
        }
        IconButton { anchors.verticalCenter: parent.verticalCenter; glyph: 0xF0143; tip: "Предыдущее  Shift+Enter"; enabled: bar.count > 0; onClicked: bar.prev() }
        IconButton { anchors.verticalCenter: parent.verticalCenter; glyph: 0xF0140; tip: "Следующее  Enter"; enabled: bar.count > 0; onClicked: bar.next() }
    }
    IconButton {
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        glyph: 0xF0156
        tip: "Закрыть  Esc"
        onClicked: bar.hide()
    }
}
