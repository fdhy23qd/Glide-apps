qt_add_library(glideui STATIC)

set_source_files_properties(Theme.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

qt_add_qml_module(glideui
    URI Glide.Ui
    VERSION 1.0
    QML_FILES
        Theme.qml
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
