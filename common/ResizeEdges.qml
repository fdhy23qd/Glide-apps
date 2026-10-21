import QtQuick

// Окна Glide без рамки (niri разрешает клиентские рамки, и Qt нарисовал бы свою): края и углы
// тянут размер через композитор (startSystemResize). В плитке niri размер задаёт он сам.
Item {
    id: edges
    required property var window
    property int margin: 5
    anchors.fill: parent
    z: 1000
    visible: window.visibility === Window.Windowed

    // inline-компонент не видит id файла: окно — свойством
    component Edge: MouseArea {
        property int edge: 0
        property var win: null
        cursorShape: edge === (Qt.LeftEdge | Qt.TopEdge) || edge === (Qt.RightEdge | Qt.BottomEdge) ? Qt.SizeFDiagCursor
                   : edge === (Qt.RightEdge | Qt.TopEdge) || edge === (Qt.LeftEdge | Qt.BottomEdge) ? Qt.SizeBDiagCursor
                   : edge === Qt.LeftEdge || edge === Qt.RightEdge ? Qt.SizeHorCursor : Qt.SizeVerCursor
        onPressed: win.startSystemResize(edge)
    }

    Edge { win: edges.window; edge: Qt.LeftEdge; x: 0; y: edges.margin; width: edges.margin; height: parent.height - 2 * edges.margin }
    Edge { win: edges.window; edge: Qt.RightEdge; x: parent.width - edges.margin; y: edges.margin; width: edges.margin; height: parent.height - 2 * edges.margin }
    Edge { win: edges.window; edge: Qt.TopEdge; x: edges.margin; y: 0; width: parent.width - 2 * edges.margin; height: edges.margin }
    Edge { win: edges.window; edge: Qt.BottomEdge; x: edges.margin; y: parent.height - edges.margin; width: parent.width - 2 * edges.margin; height: edges.margin }
    Edge { win: edges.window; edge: Qt.LeftEdge | Qt.TopEdge; x: 0; y: 0; width: edges.margin * 2; height: edges.margin * 2 }
    Edge { win: edges.window; edge: Qt.RightEdge | Qt.TopEdge; x: parent.width - edges.margin * 2; y: 0; width: edges.margin * 2; height: edges.margin * 2 }
    Edge { win: edges.window; edge: Qt.LeftEdge | Qt.BottomEdge; x: 0; y: parent.height - edges.margin * 2; width: edges.margin * 2; height: edges.margin * 2 }
    Edge { win: edges.window; edge: Qt.RightEdge | Qt.BottomEdge; x: parent.width - edges.margin * 2; y: parent.height - edges.margin * 2; width: edges.margin * 2; height: edges.margin * 2 }
}
