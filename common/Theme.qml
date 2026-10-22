pragma Singleton
import QtQuick

// Дизайн Glide — те же токены, что в Theme.qml Glide Shell (тон, акцент, скругления, размер текста
// берутся из настроек оболочки через GlideSettings). Цвета, скругления и шрифты — только отсюда.
QtObject {
    id: theme

    readonly property var tones: ({
        glide:  { background: "#0f1115", surface: "#1b1f26", surfaceLow: "#1f242c", surfaceHigh: "#232831",
                  surfaceHigher: "#2c3340", surfacePressed: "#353d4b", outline: "#2e3a4a", divider: "#334155" },
        amoled: { background: "#000000", surface: "#111216", surfaceLow: "#15171b", surfaceHigh: "#1a1c21",
                  surfaceHigher: "#23262d", surfacePressed: "#2d3139", outline: "#262a31", divider: "#2b3038" },
        soft:   { background: "#161a22", surface: "#212733", surfaceLow: "#262c39", surfaceHigh: "#2a313e",
                  surfaceHigher: "#343c4b", surfacePressed: "#3e4757", outline: "#37445a", divider: "#3d4a5f" }
    })
    // светлая — как в Glide Shell: белые карточки на светло-сером, тёмный текст (те же роли, что у тёмных тонов)
    readonly property var lightTone: ({ background: "#eef0f4", surface: "#ffffff", surfaceLow: "#f6f7f9", surfaceHigh: "#e8ebf0",
                                         surfaceHigher: "#dde2e9", surfacePressed: "#d1d7e0", outline: "#d3d9e2", divider: "#c8d0db" })
    property bool forceDark: false   // плеер и подобное — всегда тёмные (выставляет приложение)
    readonly property bool isLight: GlideSettings.light && !forceDark
    readonly property var t: isLight ? lightTone : (tones[GlideSettings.tone] || tones.glide)

    readonly property color background: t.background
    readonly property color surface: t.surface
    readonly property color surfaceLow: t.surfaceLow
    readonly property color surfaceHigh: t.surfaceHigh
    readonly property color surfaceHigher: t.surfaceHigher
    readonly property color surfacePressed: t.surfacePressed
    readonly property color outline: t.outline
    readonly property color divider: t.divider
    readonly property color outlineHover: textFaint
    // полупрозрачные слои поверх фото и видео
    readonly property color scrim: Qt.rgba(background.r, background.g, background.b, 0.82)

    readonly property real disabledOpacity: 0.38

    readonly property color text: isLight ? "#14171c" : "#f5f7fa"
    readonly property color textVariant: isLight ? "#364050" : "#c3cbd6"
    readonly property color textSecondary: isLight ? "#5a6473" : "#9aa5b5"
    readonly property color textMuted: isLight ? "#7f8999" : "#6b7686"
    readonly property color textFaint: isLight ? "#a3abb8" : "#4b5563"

    readonly property color accent: GlideSettings.accent
    readonly property color accentSoft: Qt.rgba(accent.r, accent.g, accent.b, 0.22)
    readonly property color accentHover: Qt.rgba(accent.r, accent.g, accent.b, 0.42)
    readonly property color accentLight: Qt.lighter(accent, 1.12)
    readonly property color accentPressed: Qt.darker(accent, 1.15)
    readonly property color accentText: 0.299 * accent.r + 0.587 * accent.g + 0.114 * accent.b > 0.62 ? "#0f1115" : "#ffffff"

    readonly property color error: "#ef5b5b"
    readonly property color errorContainer: isLight ? "#fde4e4" : "#3a1f24"
    readonly property color errorHover: isLight ? "#fbd2d2" : "#4a2328"
    readonly property color success: "#34c77b"
    readonly property color warning: "#f5a623"

    function r(n) { return Math.round(n * GlideSettings.radius) }
    readonly property int radiusSm: r(12)
    readonly property int radiusMd: r(16)
    readonly property int radiusLg: r(24)
    readonly property int radiusXl: r(28)

    function fs(n) { return Math.round(n * GlideSettings.font) }

    // значки — JetBrainsMono Nerd Font, коды MDI (проверены рендером)
    readonly property string iconFont: "JetBrainsMono Nerd Font"
    function icon(code) { return String.fromCodePoint(code) }
}
