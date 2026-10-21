import QtQuick

// Одна картинка. Сначала грузится уменьшенная до размера экрана (быстро, ~4–6 МБ памяти), полный
// размер — только когда приблизили сильнее, чем позволяет уменьшенная. Анимация (GIF, WebP) —
// AnimatedImage, векторная (SVG) — перерисовывается под масштаб.
Item {
    id: slot

    required property var view   // Viewer (не «viewer»: в делегате это имя занято id)
    property string url: ""
    property var info: ({})
    property bool current: false

    readonly property bool animated: !!info.animated
    readonly property bool vector: !!info.vector
    readonly property real natW: info.width || 0
    readonly property real natH: info.height || 0
    readonly property int status: !url ? Image.Null : animated ? anim.status : base.status
    readonly property bool hiRes: hi.status === Image.Ready && hi.visible

    anchors.fill: parent
    visible: current

    // для неактивного слота масштаб не важен: он только подгружает картинку заранее
    readonly property real zm: current ? view.zoom : 0.01
    readonly property real dpr: view.dpr

    Item {
        id: frame
        width: slot.natW * slot.zm / slot.dpr
        height: slot.natH * slot.zm / slot.dpr
        x: (slot.width - width) / 2 + (slot.current ? slot.view.cx : 0)
        y: (slot.height - height) / 2 + (slot.current ? slot.view.cy : 0)
        rotation: slot.current ? slot.view.turn : 0   // не viewer.rotation: это поворот самого Item

        // крупные пиксели при сильном приближении — без размытия (пиксель-арт, скриншоты)
        readonly property bool crisp: slot.zm >= 2

        Image {
            id: base
            anchors.fill: parent
            visible: !hi.visible
            source: slot.url && !slot.animated ? slot.url : ""
            asynchronous: true
            autoTransform: true
            retainWhileLoading: slot.vector
            smooth: !frame.crisp
            mipmap: !frame.crisp && slot.zm < 0.5
            // квадрат по большей стороне экрана: при любом повороте снимок не меньше «по размеру окна»
            sourceSize: slot.vector ? Qt.size(vecSize.w, vecSize.h)
                                    : Qt.size(slot.view.baseSide, slot.view.baseSide)
        }

        Image {   // полный размер — по требованию
            id: hi
            anchors.fill: parent
            readonly property bool need: slot.current && !slot.vector && !slot.animated && base.status === Image.Ready
                                         && slot.natW * slot.zm > base.implicitWidth * 1.05
            property bool keep: false   // загрузили — держим, пока картинка текущая
            onNeedChanged: if (need) keep = true
            visible: status === Image.Ready
            source: (need || keep) && slot.current ? slot.url : ""
            asynchronous: true
            autoTransform: true
            cache: false
            smooth: !frame.crisp
            sourceSize: Qt.size(Math.min(8192, slot.natW), Math.min(8192, slot.natH))
        }

        AnimatedImage {
            id: anim
            anchors.fill: parent
            source: slot.url && slot.animated ? slot.url : ""
            asynchronous: true
            playing: slot.current
            smooth: !frame.crisp
        }
    }

    onCurrentChanged: {
        if (!current) hi.keep = false
        else if (vector) vecTimer.restart()
    }
    onUrlChanged: hi.keep = false

    // SVG: перерисовать под новый масштаб, когда масштаб перестал меняться
    QtObject {
        id: vecSize
        property int w: 512
        property int h: 512
    }
    Timer {
        id: vecTimer
        interval: 120
        onTriggered: {
            if (!slot.current) return   // невидимый слот: frame почти нулевой
            vecSize.w = Math.min(8192, Math.max(16, Math.ceil(frame.width * slot.dpr)))
            vecSize.h = Math.min(8192, Math.max(16, Math.ceil(frame.height * slot.dpr)))
        }
    }
    Connections {
        target: frame
        enabled: slot.vector && slot.current
        function onWidthChanged() { vecTimer.restart() }
    }
    onVectorChanged: if (vector) vecTimer.restart()
}
