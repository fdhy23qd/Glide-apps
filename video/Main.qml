import QtQuick
import QtQuick.Window
import QtMultimedia
import QtCore
import Glide.Ui
import GlideVideo

// Glide Видео — лёгкий плеер (Qt Multimedia, FFmpeg) с простым редактором: фрагмент, формат,
// размер, качество, кадр в PNG. Продолжает с места остановки, держит экран включённым, MPRIS.
Window {
    id: win

    property string startPath: ""

    width: 1100
    height: 680
    minimumWidth: 480
    minimumHeight: 300
    visible: true
    flags: Qt.Window | Qt.FramelessWindowHint
    color: player.hasVideo ? "black" : Theme.background
    title: playlist.count > 0 ? playlist.name + " — Видео" : "Видео"

    readonly property bool fullscreen: visibility === Window.FullScreen
    function toggleFullscreen() { visibility = fullscreen ? Window.Windowed : Window.FullScreen }
    readonly property bool playing: player.playbackState === MediaPlayer.PlayingState
    readonly property bool hasMedia: playlist.count > 0

    function fmt(ms) {
        var s = Math.max(0, Math.floor(ms / 1000))
        var h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), sec = s % 60
        var ss = (sec < 10 ? "0" : "") + sec
        return h ? h + ":" + (m < 10 ? "0" : "") + m + ":" + ss : m + ":" + ss
    }
    function fmtFine(ms) { return fmt(ms) + "," + Math.floor(ms % 1000 / 100) }   // с десятыми — для обрезки
    function sizeText(b) {
        if (b < 1048576) return Math.round(b / 1024) + " КБ"
        if (b < 1073741824) return (b / 1048576).toFixed(b < 10485760 ? 1 : 0).replace(".", ",") + " МБ"
        return (b / 1073741824).toFixed(1).replace(".", ",") + " ГБ"
    }

    Settings {
        id: prefs
        category: "player"
        property real volume: 0.8
        property bool muted: false
    }

    // ---------- файлы ----------
    Playlist {
        id: playlist
        onError: message => toast.show(message)
        onCurrentChanged: win.load()
    }
    FilePicker {
        id: picker
        onPicked: urls => { if (urls.length) playlist.open(urls[0]) }
    }
    function openDialog() {
        picker.open("Открыть видео", "Видео и аудио",
                    ["*.mp4", "*.m4v", "*.mkv", "*.webm", "*.mov", "*.avi", "*.wmv", "*.flv", "*.ts", "*.mpg",
                     "*.mpeg", "*.3gp", "*.ogv", "*.mp3", "*.flac", "*.ogg", "*.opus", "*.m4a", "*.wav"],
                    playlist.folder)
    }
    Component.onCompleted: if (startPath) playlist.open(startPath)

    // ---------- воспроизведение ----------
    property string currentPath: ""
    property real pendingResume: 0
    property bool ended: false

    function savePosition() {
        if (currentPath && player.duration > 0)
            playlist.savePosition(currentPath, ended ? player.duration : player.position, player.duration)
    }
    function load() {
        savePosition()
        currentPath = playlist.path
        ended = false
        if (!currentPath) { player.source = ""; return }
        conv.probe(currentPath)
        pendingResume = playlist.resumePosition(currentPath)
        player.source = playlist.url
    }
    function toggle() {
        if (!hasMedia) return
        if (ended) { ended = false; player.position = 0; player.play() }
        else if (playing) player.pause()
        else player.play()
        flashIcon.show(playing ? 0xF03E4 : 0xF040A)
    }
    function seekBy(ms) {
        if (!player.seekable) return
        ended = false
        player.position = Math.max(0, Math.min(player.duration, player.position + ms))
        hint.show((ms > 0 ? "+" : "−") + fmt(Math.abs(ms)))
        poke()
    }
    function setVolume(v) {
        prefs.volume = Math.max(0, Math.min(1, v))
        prefs.muted = false
        hint.show("Громкость " + Math.round(prefs.volume * 100) + "%")
    }
    function setRate(r) {
        player.playbackRate = Math.max(0.25, Math.min(4, Math.round(r * 100) / 100))
        hint.show("Скорость ×" + String(player.playbackRate).replace(".", ","))
    }

    MediaPlayer {
        id: player
        audioOutput: AudioOutput {
            id: audio
            volume: prefs.volume
            muted: prefs.muted
        }
        videoOutput: video
        onMediaStatusChanged: {
            if (mediaStatus === MediaPlayer.LoadedMedia) {
                if (win.pendingResume > 0 && win.pendingResume < duration) {
                    position = win.pendingResume
                    toast.show("Продолжено с " + win.fmt(win.pendingResume), "С начала", () => { player.position = 0 })
                }
                win.pendingResume = 0
                play()
            } else if (mediaStatus === MediaPlayer.EndOfMedia) {
                win.ended = true
                win.savePosition()
            }
        }
        onPlaybackStateChanged: if (playbackState !== MediaPlayer.PlayingState) win.savePosition()
        onErrorOccurred: (error, errorString) => toast.show("Не удалось воспроизвести: " + errorString)
    }
    Timer { running: win.playing; interval: 10000; repeat: true; onTriggered: win.savePosition() }
    onClosing: close => {
        if (conv.running && !forceClose) {
            close.accepted = false
            toast.show("Идёт сохранение — закрыть и прервать?", "Закрыть", () => { win.forceClose = true; win.close() })
            return
        }
        savePosition()
    }
    property bool forceClose: false

    Converter {
        id: conv
        onFinished: (ok, output, error) => {
            if (ok) toast.show("Сохранено: " + output.split("/").pop(), "Показать", () => playlist.showInFolder(output))
            else toast.show("Не удалось сохранить: " + error)
        }
        onSnapshotSaved: file => toast.show("Кадр сохранён", "Показать", () => playlist.showInFolder(file))
        onFailed: error => toast.show(error)
    }

    // пульты: медиаклавиши (playerctl), остров Glide Shell
    Mpris {
        id: mpris
        title: playlist.name
        url: playlist.url
        length: player.duration
        position: player.position
        status: !win.hasMedia ? "Stopped" : win.playing ? "Playing" : "Paused"
        canNext: playlist.index < playlist.count - 1
        canPrevious: playlist.index > 0
        volume: prefs.muted ? 0 : prefs.volume
        rate: player.playbackRate
        onPlayRequested: if (!win.playing) win.toggle()
        onPauseRequested: if (win.playing) win.toggle()
        onToggleRequested: win.toggle()
        onStopRequested: player.pause()
        onNextRequested: playlist.next()
        onPreviousRequested: playlist.prev()
        onSeekRequested: ms => { win.ended = false; player.position = ms }
        onVolumeRequested: v => win.setVolume(v)
        onRateRequested: r => win.setRate(r)
        onRaiseRequested: win.requestActivate()
        onQuitRequested: win.close()
    }
    Inhibitor { active: win.playing && player.hasVideo }

    // ---------- панели прячутся через 2,5 с покоя (на паузе — нет) ----------
    property bool awake: true
    readonly property bool chrome: awake || !playing || headerHover.hovered || controlsHover.hovered || edit.open
                                   || speedMenu.open || trackMenu.open || !hasMedia
    Timer { id: sleepTimer; interval: 2500; running: win.awake; onTriggered: win.awake = false }
    function poke() { awake = true; sleepTimer.restart() }

    Item {
        id: stage
        anchors.fill: parent
        HoverHandler {
            onPointChanged: win.poke()
            cursorShape: win.chrome || !win.fullscreen ? Qt.ArrowCursor : Qt.BlankCursor
        }

        VideoOutput {
            id: video
            anchors.fill: parent
            fillMode: VideoOutput.PreserveAspectFit
            TapHandler {   // щелчок — пауза сразу; двойной — во весь экран (и пауза отменяется)
                id: tap
                onTapped: if (tapCount === 1) win.toggle()
                onDoubleTapped: { win.toggle(); win.toggleFullscreen() }
            }
            MouseArea {   // колесо над видео — громкость
                anchors.fill: parent
                acceptedButtons: Qt.NoButton
                onWheel: wheel => {
                    if (wheel.angleDelta.y !== 0) win.setVolume(prefs.volume + (wheel.angleDelta.y > 0 ? 0.05 : -0.05))
                    win.poke()
                }
            }
        }

        // аудио без картинки
        Column {
            anchors.centerIn: parent
            visible: win.hasMedia && !player.hasVideo && player.mediaStatus !== MediaPlayer.LoadingMedia
            spacing: 10
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Theme.icon(0xF075A)
                color: Theme.accent
                font.family: Theme.iconFont
                font.pixelSize: 72
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: player.metaData.stringValue(MediaMetaData.Title) || playlist.name
                color: Theme.text
                font.pixelSize: Theme.fs(18)
                font.weight: Font.DemiBold
                textFormat: Text.PlainText
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: player.metaData.stringValue(MediaMetaData.ContributingArtist)
                      || player.metaData.stringValue(MediaMetaData.AlbumArtist)
                color: Theme.textSecondary
                font.pixelSize: Theme.fs(14)
                textFormat: Text.PlainText
            }
        }

        // пусто
        Column {
            anchors.centerIn: parent
            visible: !win.hasMedia
            spacing: 14
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Theme.icon(0xF0381)
                color: Theme.textMuted
                font.family: Theme.iconFont
                font.pixelSize: 64
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Нет видео"
                color: Theme.text
                font.pixelSize: Theme.fs(18)
                font.weight: Font.DemiBold
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Перетащите файл в окно или откройте его"
                color: Theme.textSecondary
                font.pixelSize: Theme.fs(13)
            }
            Item { width: 1; height: 4 }
            TextButton {
                anchors.horizontalCenter: parent.horizontalCenter
                primary: true
                glyph: 0xF0770
                text: "Открыть…"
                enabled: !picker.busy
                onClicked: win.openDialog()
            }
        }

        // конец видео: сначала или следующее
        Row {
            anchors.centerIn: parent
            visible: win.ended && win.hasMedia
            spacing: 12
            TextButton { glyph: 0xF0459; text: "Сначала"; onClicked: win.toggle() }
            TextButton {
                visible: playlist.index < playlist.count - 1
                primary: true
                glyph: 0xF04AD
                text: "Следующее"
                onClicked: playlist.next()
            }
        }

        // значок паузы/воспроизведения по щелчку
        Rectangle {
            id: flashIcon
            function show(code) { glyphText.text = Theme.icon(code); flashAnim.restart() }
            anchors.centerIn: parent
            width: 84; height: 84; radius: 42
            color: Theme.scrim
            opacity: 0
            Text { id: glyphText; anchors.centerIn: parent; color: Theme.text; font.family: Theme.iconFont; font.pixelSize: 40 }
            ParallelAnimation {
                id: flashAnim
                NumberAnimation { target: flashIcon; property: "opacity"; from: 0.95; to: 0; duration: 600; easing.type: Easing.InQuad }
                NumberAnimation { target: flashIcon; property: "scale"; from: 0.85; to: 1.15; duration: 600; easing.type: Easing.OutCubic }
            }
        }

        // короткая подсказка сверху: громкость, скорость, перемотка
        Rectangle {
            id: hint
            function show(t) { hintText.text = t; opacity = 1; hintTimer.restart() }
            anchors.horizontalCenter: parent.horizontalCenter
            y: 76
            width: hintText.implicitWidth + 28
            height: 34
            radius: height / 2
            color: Theme.scrim
            opacity: 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 160 } }
            Text { id: hintText; anchors.centerIn: parent; color: Theme.text; font.pixelSize: Theme.fs(13); font.features: ({ "tnum": 1 }) }
            Timer { id: hintTimer; interval: 900; onTriggered: hint.opacity = 0 }
        }
    }

    // ---------- шапка ----------
    Item {
        id: header
        width: parent.width
        height: 72
        opacity: win.chrome ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
        HoverHandler { id: headerHover }
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0; color: Theme.scrim }
                GradientStop { position: 1; color: "transparent" }
            }
        }
        DragHandler { target: null; onActiveChanged: if (active) win.startSystemMove() }
        TapHandler { onDoubleTapped: win.toggleFullscreen() }
        Column {
            x: 20; y: 10
            width: header.width - 120
            spacing: 1
            Text {
                width: parent.width
                text: win.hasMedia ? playlist.name : "Видео"
                color: Theme.text
                font.pixelSize: Theme.fs(14)
                font.weight: Font.DemiBold
                elide: Text.ElideMiddle
                textFormat: Text.PlainText
            }
            Text {
                width: parent.width
                visible: win.hasMedia && conv.info.ok === true
                text: [playlist.count > 1 ? (playlist.index + 1) + " из " + playlist.count : "",
                       conv.info.width ? conv.info.width + " × " + conv.info.height : "",
                       (conv.info.vcodec || conv.info.acodec || "").toUpperCase(),
                       conv.info.bytes ? win.sizeText(conv.info.bytes) : ""].filter(x => x).join("  ·  ")
                color: Theme.textSecondary
                font.pixelSize: Theme.fs(12)
                elide: Text.ElideRight
            }
        }
        Row {
            anchors.right: parent.right
            anchors.rightMargin: 12
            y: 8
            spacing: 2
            Rectangle {   // экспорт идёт, а панель закрыта — видно и так
                opacity: conv.running && !edit.open ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 140 } }
                anchors.verticalCenter: parent.verticalCenter
                width: busyText.implicitWidth + 24; height: 30; radius: 15
                color: Theme.accentSoft
                Text { id: busyText; anchors.centerIn: parent; text: "Сохранение " + Math.round(conv.progress * 100) + "%"; color: Theme.text; font.pixelSize: Theme.fs(12) }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: edit.open = true }
            }
            IconButton { glyph: 0xF0156; tip: "Закрыть  Ctrl+W"; onClicked: win.close() }
        }
    }

    // ---------- управление снизу ----------
    Item {
        id: controls
        width: parent.width
        height: 104
        y: parent.height - height
        opacity: win.chrome && win.hasMedia ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
        HoverHandler { id: controlsHover }
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0; color: "transparent" }
                GradientStop { position: 1; color: Theme.scrim }
            }
        }
        MouseArea { anchors.fill: parent; anchors.topMargin: 30 }   // щелчок по панели — не пауза

        SeekBar {
            id: seek
            x: 20
            y: 34
            width: parent.width - 40
            duration: player.duration
            position: player.position
            trimStart: edit.trimStart
            trimEnd: edit.trimEnd
            format: win.fmt
            onSeek: ms => { win.ended = false; player.position = ms; win.poke() }
        }

        Row {
            x: 12
            y: 58
            spacing: 2
            IconButton { visible: playlist.count > 1; glyph: 0xF04AE; tip: "Предыдущее  P"; tipAbove: true; enabled: playlist.index > 0; onClicked: playlist.prev() }
            IconButton { glyph: win.playing ? 0xF03E4 : 0xF040A; glyphSize: 22; tip: win.playing ? "Пауза  Пробел" : "Смотреть  Пробел"; tipAbove: true; onClicked: win.toggle() }
            IconButton { visible: playlist.count > 1; glyph: 0xF04AD; tip: "Следующее  N"; tipAbove: true; enabled: playlist.index < playlist.count - 1; onClicked: playlist.next() }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                leftPadding: 8
                text: win.fmt(player.position) + " / " + win.fmt(player.duration)
                color: Theme.textVariant
                font.pixelSize: Theme.fs(13)
                font.features: ({ "tnum": 1 })
            }
        }

        Row {
            anchors.right: parent.right
            anchors.rightMargin: 12
            y: 58
            spacing: 2
            Rectangle {   // скорость
                id: speedBtn
                Behavior on color { ColorAnimation { duration: 140 } }
                width: 52; height: 36; radius: 18
                anchors.verticalCenter: parent.verticalCenter
                color: speedArea.pressed ? Theme.surfacePressed : speedArea.containsMouse || speedMenu.open ? Theme.surfaceHigher : "transparent"
                scale: speedArea.pressed ? 0.94 : 1
                Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
                Text {
                    Behavior on color { ColorAnimation { duration: 140 } }
                    anchors.centerIn: parent
                    text: "×" + String(player.playbackRate).replace(".", ",")
                    color: player.playbackRate !== 1 ? Theme.accent : Theme.textVariant
                    font.pixelSize: Theme.fs(13)
                    font.weight: Font.DemiBold
                }
                MouseArea { id: speedArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: { trackMenu.open = false; speedMenu.open = !speedMenu.open } }
            }
            IconButton {
                visible: player.audioTracks.length > 1 || player.subtitleTracks.length > 0
                glyph: 0xF0A17; tip: "Звук и субтитры"; tipAbove: true; on: trackMenu.open
                onClicked: { speedMenu.open = false; trackMenu.open = !trackMenu.open }
            }
            IconButton {
                glyph: prefs.muted || prefs.volume === 0 ? 0xF0581 : 0xF057E
                tip: "Без звука  M"; tipAbove: true
                onClicked: prefs.muted = !prefs.muted
            }
            Slider {
                width: 90
                anchors.verticalCenter: parent.verticalCenter
                value: prefs.muted ? 0 : prefs.volume
                onMoved: v => win.setVolume(v)
            }
            Item { width: 6; height: 1 }
            IconButton { glyph: 0xF0190; tip: "Изменить и сохранить  E"; tipAbove: true; on: edit.open; onClicked: edit.open = !edit.open }
            IconButton { glyph: win.fullscreen ? 0xF0294 : 0xF0293; tip: "Во весь экран  F"; tipAbove: true; onClicked: win.toggleFullscreen() }
        }
    }

    // ---------- меню ----------
    MouseArea {   // щелчок мимо меню закрывает его
        anchors.fill: parent
        visible: speedMenu.open || trackMenu.open
        onPressed: { speedMenu.open = false; trackMenu.open = false }
    }
    PopupMenu {
        id: speedMenu
        width: 160
        anchors.right: parent.right
        anchors.rightMargin: 200
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 56
        items: [0.5, 0.75, 1, 1.25, 1.5, 2].map(r => ({ text: "×" + String(r).replace(".", ",") + (r === 1 ? " — обычная" : ""),
                                                       checked: player.playbackRate === r, run: () => win.setRate(r) }))
    }
    PopupMenu {
        id: trackMenu
        width: 260
        anchors.right: parent.right
        anchors.rightMargin: 150
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 56
        function trackName(md, i, word) {
            var t = md.stringValue(MediaMetaData.Title), l = md.stringValue(MediaMetaData.Language)
            return [t, l].filter(x => x).join(" · ") || word + " " + (i + 1)
        }
        items: {
            var out = []
            var a = player.audioTracks, s = player.subtitleTracks
            if (a.length > 1) {
                out.push({ header: true, text: "Звук" })
                for (let i = 0; i < a.length; i++)
                    out.push({ text: trackName(a[i], i, "Дорожка"), checked: player.activeAudioTrack === i, run: () => player.activeAudioTrack = i })
            }
            if (s.length > 0) {
                out.push({ header: true, text: "Субтитры" })
                out.push({ text: "Выключены", checked: player.activeSubtitleTrack < 0, run: () => player.activeSubtitleTrack = -1 })
                for (let j = 0; j < s.length; j++)
                    out.push({ text: trackName(s[j], j, "Субтитры"), checked: player.activeSubtitleTrack === j, run: () => player.activeSubtitleTrack = j })
            }
            return out
        }
    }

    EditPanel {
        id: edit
        converter: conv
        path: playlist.path
        position: player.position
        format: win.fmtFine
        anchors.right: parent.right
        anchors.rightMargin: 16
        y: 72
        height: parent.height - 72 - 112
        onOpenChanged: if (open) conv.detectHardware()
    }

    Toast { id: toast }

    DropArea {
        anchors.fill: parent
        onEntered: drag => drag.accept(Qt.CopyAction)
        onDropped: drop => { if (drop.hasUrls) playlist.open(drop.urls[0]) }
    }

    ResizeEdges { window: win }

    // ---------- клавиши ----------
    Shortcut { sequences: ["Space", "K", "Media Play", "Toggle Media Play/Pause"]; onActivated: win.toggle() }
    Shortcut { sequence: "Left"; onActivated: win.seekBy(-5000) }
    Shortcut { sequence: "Right"; onActivated: win.seekBy(5000) }
    Shortcut { sequence: "J"; onActivated: win.seekBy(-10000) }
    Shortcut { sequence: "L"; onActivated: win.seekBy(10000) }
    Shortcut { sequence: "Shift+Left"; onActivated: win.seekBy(-1000) }
    Shortcut { sequence: "Shift+Right"; onActivated: win.seekBy(1000) }
    Shortcut { sequence: "Ctrl+Left"; onActivated: win.seekBy(-60000) }
    Shortcut { sequence: "Ctrl+Right"; onActivated: win.seekBy(60000) }
    // по кадру (на паузе): длительность кадра из ffprobe
    Shortcut { sequence: ","; onActivated: { player.pause(); win.seekBy(-1000 / (conv.info.fps || 30)) } }
    Shortcut { sequence: "."; onActivated: { player.pause(); win.seekBy(1000 / (conv.info.fps || 30)) } }
    Shortcut { sequence: "Home"; onActivated: { win.ended = false; player.position = 0 } }
    Shortcut { sequence: "Up"; onActivated: win.setVolume(prefs.volume + 0.05) }
    Shortcut { sequence: "Down"; onActivated: win.setVolume(prefs.volume - 0.05) }
    Shortcut { sequence: "M"; onActivated: { prefs.muted = !prefs.muted; hint.show(prefs.muted ? "Без звука" : "Звук включён") } }
    Shortcut { sequence: "]"; onActivated: win.setRate(player.playbackRate + 0.25) }
    Shortcut { sequence: "["; onActivated: win.setRate(player.playbackRate - 0.25) }
    Shortcut { sequence: "Backspace"; onActivated: win.setRate(1) }
    Shortcut { sequences: ["N", "PgDown", "Media Next"]; onActivated: playlist.next() }
    Shortcut { sequences: ["P", "PgUp", "Media Previous"]; onActivated: playlist.prev() }
    Shortcut { sequences: ["F", "F11"]; onActivated: win.toggleFullscreen() }
    Shortcut { sequence: "E"; onActivated: edit.open = !edit.open }
    Shortcut { sequence: "I"; enabled: win.hasMedia; onActivated: { edit.open = true; edit.setStart(player.position) } }
    Shortcut { sequence: "O"; enabled: win.hasMedia; onActivated: { edit.open = true; edit.setEnd(player.position) } }
    Shortcut { sequence: "S"; enabled: player.hasVideo; onActivated: conv.snapshot(playlist.path, player.position) }
    Shortcut { sequence: "Ctrl+S"; enabled: edit.open; onActivated: edit.save() }
    Shortcut { sequence: "Ctrl+O"; onActivated: win.openDialog() }
    Shortcut { sequences: ["Ctrl+W", "Ctrl+Q"]; onActivated: win.close() }
    Shortcut {
        sequence: "Esc"
        onActivated: {
            if (speedMenu.open || trackMenu.open) { speedMenu.open = false; trackMenu.open = false }
            else if (edit.open) edit.open = false
            else if (win.fullscreen) win.toggleFullscreen()
        }
    }
    Repeater {   // 0…9 — перейти на 0…90 %
        model: 10
        delegate: Item {
            required property int index
            Shortcut { sequence: String(index); onActivated: { win.ended = false; player.position = player.duration * index / 10 } }
        }
    }
}
