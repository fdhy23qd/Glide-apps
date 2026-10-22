import QtQuick
import QtQuick.Pdf
import Glide.Ui

// Боковая панель: оглавление документа (если есть) и миниатюры страниц.
Rectangle {
    id: side

    required property var view      // Main
    property bool open: false
    property string tab: hasOutline ? "outline" : "pages"
    readonly property bool hasOutline: tree.rows > 0

    width: open ? 280 : 0
    clip: true
    color: Theme.background
    Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Theme.outline }

    Row {   // вкладки
        id: tabs
        x: 12; y: 10
        spacing: 6
        Chip { text: Tr.t("Оглавление"); visible: side.hasOutline; selected: side.tab === "outline"; onClicked: side.tab = "outline" }
        Chip { text: Tr.t("Страницы"); selected: side.tab === "pages"; onClicked: side.tab = "pages" }
    }

    // ---- оглавление ----
    TreeView {
        id: tree
        visible: side.tab === "outline"
        anchors.top: tabs.bottom
        anchors.topMargin: 8
        anchors.bottom: parent.bottom
        width: 279
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: PdfBookmarkModel { document: side.view.pdf }
        delegate: Rectangle {
            id: node
            Behavior on color { ColorAnimation { duration: 140 } }
            required property TreeView treeView
            required property bool isTreeNode
            required property bool expanded
            required property bool hasChildren
            required property int depth
            required property int row
            required property string title
            required property int page
            required property point location
            readonly property bool here: page === side.view.currentPage
            implicitWidth: 279
            implicitHeight: 36
            radius: Theme.radiusSm
            color: area.pressed ? Theme.surfacePressed : area.containsMouse ? Theme.surfaceHigher : here ? Theme.surfaceLow : "transparent"
            Text {   // раскрыть вложенное
                id: arrow
                x: 8 + node.depth * 16
                anchors.verticalCenter: parent.verticalCenter
                width: 18
                visible: node.hasChildren
                text: Theme.icon(node.expanded ? 0xF0140 : 0xF0142)
                color: Theme.textSecondary
                font.family: Theme.iconFont
                font.pixelSize: Theme.fs(16)
                MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: node.treeView.toggleExpanded(node.row) }
            }
            Text {
                Behavior on color { ColorAnimation { duration: 140 } }
                x: 30 + node.depth * 16
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - x - 44
                text: node.title
                color: node.here ? Theme.accent : Theme.text
                font.pixelSize: Theme.fs(13)
                elide: Text.ElideRight
                textFormat: Text.PlainText
            }
            Text {
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                text: node.page + 1
                color: Theme.textMuted
                font.pixelSize: Theme.fs(11)
                font.features: ({ "tnum": 1 })
            }
            MouseArea {
                id: area
                anchors.fill: parent
                anchors.leftMargin: arrow.visible ? arrow.x + arrow.width : 0
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: side.view.goToLocation(node.page, node.location, true)
            }
        }
    }

    // ---- миниатюры ----
    ListView {
        id: thumbs
        visible: side.tab === "pages"
        anchors.top: tabs.bottom
        anchors.topMargin: 8
        anchors.bottom: parent.bottom
        width: 279
        clip: true
        spacing: 10
        boundsBehavior: Flickable.StopAtBounds
        model: side.open && side.tab === "pages" ? side.view.pdf.pageCount : 0
        currentIndex: side.view.currentPage
        onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
        delegate: Item {
            id: th
            required property int index
            readonly property size pt: side.view.pdf.pagePointSize(index)
            width: 279
            height: img.height + 26
            Rectangle {
                Behavior on border.color { ColorAnimation { duration: 140 } }
                anchors.horizontalCenter: parent.horizontalCenter
                width: img.width + 6
                height: img.height + 6
                radius: 4
                color: "transparent"
                border.width: 2
                border.color: th.index === side.view.currentPage ? Theme.accent : thArea.containsMouse ? Theme.outlineHover : "transparent"
                Rectangle {   // бумага: у страниц PDF прозрачный фон
                    x: img.x; y: img.y; width: img.width; height: img.height
                    color: side.view.night ? "#1a1c20" : "white"
                }
                PdfPageImage {
                    id: img
                    x: 3; y: 3
                    width: 140
                    height: th.pt.width > 0 ? 140 * th.pt.height / th.pt.width : 190
                    document: side.view.pdf
                    currentFrame: th.index
                    asynchronous: true
                    sourceSize: Qt.size(280, 0)
                }
                ShaderEffectSource { id: thumbTex; sourceItem: img; hideSource: side.view.night; visible: false; enabled: side.view.night }
                ShaderEffect {   // ночной режим, как у страниц
                    x: img.x; y: img.y; width: img.width; height: img.height
                    visible: side.view.night
                    property variant source: thumbTex
                    fragmentShader: "qrc:/qt/qml/GlidePdf/night.frag.qsb"
                }
            }
            Text {
                Behavior on color { ColorAnimation { duration: 140 } }
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                text: th.index + 1
                color: th.index === side.view.currentPage ? Theme.accent : Theme.textSecondary
                font.pixelSize: Theme.fs(11)
            }
            MouseArea { id: thArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: side.view.goToPage(th.index, true) }
        }
    }
}
