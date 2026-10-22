import QtQuick
import QtQuick.Window
import QtQuick.Pdf
import QtQuick.Shapes
import Glide.Ui

// Одна страница: картинка (разрешение — под масштаб, с задержкой), поиск, выделение текста, ссылки.
// Координаты PDF — в пунктах; zoom — логических пикселей на пункт.
Item {
    id: holder

    required property int index
    required property var view          // Main: doc, scale, renderScale, rotation, night, search, goTo…
    readonly property var doc: view.pdf
    readonly property size pt: doc.pagePointSize(index)
    readonly property bool sideways: view.pageRotation % 180 === 90
    readonly property real gap: 12
    property alias selection: selection   // Ctrl+A — выделить всю страницу

    // совпадения поиска на странице — по счётчику, а не привязкой: boundingPolygonsOnPage() трогает
    // модель, и привязка зацикливалась
    readonly property int searchRev: view.searchRev
    readonly property bool searchActive: view.searchActive
    function refreshHits() { hits.paths = searchActive ? view.searchModel.boundingPolygonsOnPage(index) : [] }
    onSearchRevChanged: refreshHits()
    onSearchActiveChanged: refreshHits()
    Component.onCompleted: refreshHits()

    width: view.pageAreaWidth
    height: (sideways ? pt.width : pt.height) * view.zoom + gap

    Rectangle {   // бумага
        id: paper
        anchors.horizontalCenter: parent.horizontalCenter
        y: holder.gap / 2
        width: (holder.sideways ? holder.pt.height : holder.pt.width) * holder.view.zoom
        height: (holder.sideways ? holder.pt.width : holder.pt.height) * holder.view.zoom
        color: holder.view.night ? "#1a1c20" : "white"

        Item {
            id: page
            anchors.centerIn: parent
            width: holder.pt.width * holder.view.zoom
            height: holder.pt.height * holder.view.zoom
            rotation: holder.view.pageRotation
            readonly property real k: holder.view.zoom   // пикселей на пункт

            PdfPageImage {
                id: image
                anchors.fill: parent
                document: holder.doc
                currentFrame: holder.index
                asynchronous: true
                retainWhileLoading: true   // при смене масштаба старая картинка видна, пока рисуется новая
                fillMode: Image.Stretch
                // рисуем в разрешении «после масштаба» — renderScale догоняет scale с задержкой
                sourceSize: Qt.size(Math.round(holder.pt.width * holder.view.renderZoom * Screen.devicePixelRatio),
                                    Math.round(holder.pt.height * holder.view.renderZoom * Screen.devicePixelRatio))
            }

            // ночной режим: снимок страницы → шейдер (яркость наоборот, оттенки те же);
            // layer.effect на PdfPageImage давал пустую страницу
            ShaderEffectSource {
                id: pageTexture
                sourceItem: image
                hideSource: holder.view.night
                live: true
                visible: false
                enabled: holder.view.night
            }
            ShaderEffect {
                anchors.fill: image
                visible: holder.view.night
                property variant source: pageTexture
                fragmentShader: "qrc:/qt/qml/GlidePdf/night.frag.qsb"
            }

            Shape {   // все совпадения поиска на странице и текущее
                anchors.fill: parent
                visible: holder.view.searchActive
                ShapePath {
                    strokeWidth: -1
                    fillColor: Qt.rgba(Theme.warning.r, Theme.warning.g, Theme.warning.b, 0.35)
                    scale: Qt.size(page.k, page.k)
                    PathMultiline { id: hits }
                }
                ShapePath {
                    strokeWidth: 2
                    strokeColor: Theme.accent
                    fillColor: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.25)
                    scale: Qt.size(page.k, page.k)
                    PathMultiline {
                        paths: holder.view.searchModel.currentPage === holder.index ? holder.view.searchModel.currentResultBoundingPolygons : []
                    }
                }
            }

            Shape {   // выделенный текст
                anchors.fill: parent
                ShapePath {
                    strokeWidth: -1
                    fillColor: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35)
                    scale: Qt.size(page.k, page.k)
                    PathMultiline { paths: selection.geometry }
                }
            }

            PdfSelection {
                id: selection
                anchors.fill: parent
                document: holder.doc
                page: holder.index
                renderScale: page.k
                from: textDrag.centroid.pressPosition
                to: textDrag.centroid.position
                hold: !textDrag.active && !tap.pressed
                onTextChanged: if (text) holder.view.selectionOwner = selection
            }
            DragHandler {   // выделить текст мышью (прокрутка — колесом и тачпадом)
                id: textDrag
                acceptedDevices: PointerDevice.Mouse | PointerDevice.Stylus
                target: null
                cursorShape: Qt.IBeamCursor
            }
            HoverHandler { cursorShape: Qt.IBeamCursor }
            TapHandler {
                id: tap
                acceptedDevices: PointerDevice.Mouse | PointerDevice.Stylus
                onTapped: selection.clear()
            }

            Repeater {   // ссылки: внутренние — на страницу, внешние — только http(s) и почта
                model: PdfLinkModel {
                    document: holder.doc
                    page: holder.index
                }
                delegate: MouseArea {
                    required property rect rectangle
                    required property url url
                    required property int page
                    required property point location
                    // «page» здесь — номер страницы ссылки (роль модели), не id страницы выше
                    x: rectangle.x * holder.view.zoom
                    y: rectangle.y * holder.view.zoom
                    width: rectangle.width * holder.view.zoom
                    height: rectangle.height * holder.view.zoom
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onContainsMouseChanged: holder.view.hoverLink = containsMouse
                                            ? (page >= 0 ? Tr.t("Страница ") + (page + 1) : String(url)) : ""
                    onClicked: {
                        if (page >= 0) holder.view.goToLocation(page, location, true)
                        else holder.view.openExternal(String(url))
                    }
                }
            }
        }
    }
}
