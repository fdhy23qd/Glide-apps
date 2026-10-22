pragma Singleton
import QtQuick

// Перевод интерфейса — как в Glide Shell: ключ — русская строка, перевод — common/i18n/<язык>.json
// (нет перевода — остаётся русская). Язык — из настроек оболочки (GlideSettings.lang). Tr.t("…") — в каждом
// видимом тексте, Tr.locale — для дат и чисел. В C++ — glideTr("…").
QtObject {
    readonly property bool ru: GlideSettings.lang !== "en"
    readonly property var dict: GlideSettings.dict
    readonly property var locale: Qt.locale(ru ? "ru_RU" : "en_US")
    function t(s) { return ru ? s : (dict[s] !== undefined ? dict[s] : s) }
    function num(x, digits) { var s = Number(x).toFixed(digits); return ru ? s.replace(".", ",") : s }
}
