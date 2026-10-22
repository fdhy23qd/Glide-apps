import QtQuick
import Glide.Ui

// Сетка миниатюр папки: щелчок или Enter — открыть, стрелки — выбор. Миниатюры грузятся в фоне уменьшенными
// (JPEG декодируется сразу в маленьком размере), прокрученные мимо — не держатся в памяти.
Item {
    id: page

    required property var gallery
    signal picked(int index)

    function focusGrid() { grid.forceActiveFocus(); grid.positionViewAtIndex(Math.max(0, gallery.index), GridView.Contain) }

    GridView {
        id: grid
        anchors.fill: parent
        anchors.topMargin: 72
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        readonly property int columns: Math.max(2, Math.floor(width / 190))
        cellWidth: Math.floor(width / columns)
        cellHeight: cellWidth
        model: page.gallery.count
        currentIndex: page.gallery.index
        cacheBuffer: cellHeight * 2
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        highlightMoveDuration: 0
        keyNavigationWraps: false
        onCurrentIndexChanged: if (activeFocus && currentIndex >= 0) page.gallery.index = currentIndex
        Keys.onReturnPressed: page.picked(currentIndex)
        Keys.onEnterPressed: page.picked(currentIndex)

        delegate: Item {
            id: cell
            required property int index
            width: grid.cellWidth
            height: grid.cellHeight
            readonly property bool current: index === page.gallery.index

            Rectangle {
                id: tile
                anchors.fill: parent
                anchors.margins: 5
                radius: Theme.radiusMd
                color: Theme.surface
                border.width: cell.current ? 3 : 0
                border.color: Theme.accent
                scale: tileArea.pressed ? 0.96 : 1
                Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
                clip: true

                Image {
                    id: thumb
                    anchors.fill: parent
                    anchors.margins: cell.current ? 6 : 0
                    // revision — чтобы после переименования/удаления в папке ячейка взяла новый файл
                    source: page.gallery.revision >= 0 ? page.gallery.urlAt(cell.index) : ""
                    sourceSize.width: 360
                    sourceSize.height: 360
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                    opacity: status === Image.Ready ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 160 } }
                }
                Text {   // пока грузится или не открылась
                    anchors.centerIn: parent
                    visible: thumb.status !== Image.Ready
                    text: Theme.icon(thumb.status === Image.Error ? 0xF0976 : 0xF02E9)
                    color: Theme.textFaint
                    font.family: Theme.iconFont
                    font.pixelSize: 28
                }
                Rectangle {   // наведение — светлее
                    anchors.fill: parent
                    radius: parent.radius
                    color: Theme.text
                    opacity: tileArea.containsMouse ? 0.08 : 0
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                }
                MouseArea {
                    id: tileArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: page.picked(cell.index)
                }
            }
        }
    }
}
