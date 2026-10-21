import QtQuick
import QtQuick.Shapes

// Одна фигура разметки на превью. Координаты — пиксели картинки (родитель масштабирован целиком).
// Геометрия совпадает с Shot::render (C++), чтобы файл выглядел как превью.
Item {
    id: an

    required property var a
    property url pixelUrl
    property real imgW: 0
    property real imgH: 0

    anchors.fill: parent

    readonly property string type: a ? a.type : ""
    readonly property real w: a ? a.width : 1
    readonly property real x1: a ? a.x1 : 0
    readonly property real y1: a ? a.y1 : 0
    readonly property real x2: a ? a.x2 : 0
    readonly property real y2: a ? a.y2 : 0
    readonly property real lx: Math.min(x1, x2)
    readonly property real ty: Math.min(y1, y2)

    // стрелка: наконечник ~4,5 толщины, основание на 0,8 длины от острия
    readonly property real len: Math.hypot(x2 - x1, y2 - y1)
    readonly property real ux: len > 0 ? (x2 - x1) / len : 0
    readonly property real uy: len > 0 ? (y2 - y1) / len : 0
    readonly property real head: Math.max(w * 4.5, 16)
    readonly property real half: head * 0.55
    readonly property point base: Qt.point(x2 - ux * head * 0.8, y2 - uy * head * 0.8)

    function polyline(pts) {
        var out = []
        for (var i = 0; i + 1 < pts.length; i += 2) out.push(Qt.point(pts[i], pts[i + 1]))
        return out
    }

    Loader {
        anchors.fill: parent
        sourceComponent: an.type === "pixel" ? pixelComp : an.type === "step" ? stepComp
                       : an.type === "text" ? textComp : an.type ? shapeComp : null
    }

    Component {
        id: shapeComp
        Shape {
            preferredRendererType: Shape.CurveRenderer   // сглаженные края
            ShapePath {
                strokeColor: an.type === "marker" ? Qt.rgba(Qt.color(an.a.color).r, Qt.color(an.a.color).g, Qt.color(an.a.color).b, 0.38) : an.a.color
                strokeWidth: an.type === "marker" ? an.w * 4 : an.w
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathPolyline {
                    path: an.type === "rect" ? [Qt.point(an.lx, an.ty), Qt.point(an.lx + Math.abs(an.x2 - an.x1), an.ty),
                                                 Qt.point(an.lx + Math.abs(an.x2 - an.x1), an.ty + Math.abs(an.y2 - an.y1)),
                                                 Qt.point(an.lx, an.ty + Math.abs(an.y2 - an.y1)), Qt.point(an.lx, an.ty)]
                        : an.type === "line" ? [Qt.point(an.x1, an.y1), Qt.point(an.x2, an.y2)]
                        : an.type === "arrow" ? [Qt.point(an.x1, an.y1), an.base]
                        : an.type === "pen" || an.type === "marker" ? an.polyline(an.a.points || [])
                        : []
                }
                PathAngleArc {   // эллипс
                    centerX: (an.x1 + an.x2) / 2
                    centerY: (an.y1 + an.y2) / 2
                    radiusX: an.type === "ellipse" ? Math.abs(an.x2 - an.x1) / 2 : 0
                    radiusY: an.type === "ellipse" ? Math.abs(an.y2 - an.y1) / 2 : 0
                    startAngle: 0
                    sweepAngle: an.type === "ellipse" ? 360 : 0
                    moveToStart: true
                }
            }
            ShapePath {   // наконечник стрелки
                strokeWidth: -1
                fillColor: an.type === "arrow" && an.len >= 1 ? an.a.color : "transparent"
                PathPolyline {
                    path: an.type !== "arrow" || an.len < 1 ? [] : [
                        Qt.point(an.x2, an.y2),
                        Qt.point(an.x2 - an.ux * an.head - an.uy * an.half, an.y2 - an.uy * an.head + an.ux * an.half),
                        an.base,
                        Qt.point(an.x2 - an.ux * an.head + an.uy * an.half, an.y2 - an.uy * an.head - an.ux * an.half),
                        Qt.point(an.x2, an.y2)]
                }
            }
        }
    }

    Component {
        id: textComp
        Shape {   // как в C++: тёмная обводка, потом заливка
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: Qt.rgba(0, 0, 0, 150 / 255)
                strokeWidth: Math.max(6, an.a.size) / 7
                fillColor: "transparent"
                joinStyle: ShapePath.RoundJoin
                capStyle: ShapePath.RoundCap
                PathText { x: an.x1; y: an.y1; font.family: "Inter"; font.pixelSize: Math.max(6, an.a.size); font.bold: true; text: an.a.text }
            }
            ShapePath {
                strokeWidth: -1
                fillColor: an.a.color
                PathText { x: an.x1; y: an.y1; font.family: "Inter"; font.pixelSize: Math.max(6, an.a.size); font.bold: true; text: an.a.text }
            }
        }
    }

    Component {
        id: stepComp
        Item {
            readonly property real rad: Math.max(14, an.w * 3.2)
            Rectangle {
                x: an.x1 - parent.rad
                y: an.y1 - parent.rad
                width: parent.rad * 2
                height: width
                radius: width / 2
                color: an.a.color
                border.color: "white"
                border.width: Math.max(2, parent.rad / 7)
                antialiasing: true
                Text {
                    anchors.centerIn: parent
                    text: an.a.n
                    color: "white"
                    font.family: "Inter"
                    font.pixelSize: Math.round(parent.parent.rad * 1.15)
                    font.bold: true
                }
            }
        }
    }

    Component {
        id: pixelComp
        Item {   // окно в заранее «размытую» (пикселями) копию картинки — та же, что пойдёт в файл
            x: an.lx
            y: an.ty
            width: Math.abs(an.x2 - an.x1)
            height: Math.abs(an.y2 - an.y1)
            clip: true
            Image {
                x: -parent.x
                y: -parent.y
                width: an.imgW
                height: an.imgH
                source: an.pixelUrl
                smooth: false
                cache: false
            }
        }
    }
}
