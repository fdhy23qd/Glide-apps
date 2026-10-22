qt_add_library(glideui STATIC)

set_source_files_properties(Theme.qml Tr.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

qt_add_qml_module(glideui
    URI Glide.Ui
    VERSION 1.0
    QML_FILES
        Theme.qml
        Tr.qml
        IconButton.qml
        TextButton.qml
        Toast.qml
        ResizeEdges.qml
        Chip.qml
        Toggle.qml
        Slider.qml
        TextField.qml
        PopupMenu.qml
    SOURCES
        glidesettings.h glidesettings.cpp
        filepicker.h filepicker.cpp
)

target_link_libraries(glideui PRIVATE Qt6::Quick Qt6::DBus)

# перевод для C++ (glideTr) и словари (:/glide-i18n/en.json) — отдельно: его берут и самотесты
qt_add_library(glidetr STATIC glidetr.h glidetr.cpp)
target_link_libraries(glidetr PUBLIC Qt6::Core)
target_include_directories(glidetr PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
qt_add_resources(glidetr "glide-i18n" PREFIX "/glide-i18n" BASE i18n FILES i18n/en.json)
target_link_libraries(glideui PUBLIC glidetr)
