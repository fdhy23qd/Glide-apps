qt_add_executable(glide-photos
    main.cpp
    gallery.h gallery.cpp
    imageeditor.h imageeditor.cpp
)

qt_add_qml_module(glide-photos
    URI GlidePhotos
    VERSION 1.0
    QML_FILES
        Main.qml
        Viewer.qml
        PhotoSlot.qml
        GridPage.qml
        InfoPanel.qml
        EditView.qml
        EditPanel.qml
)

target_include_directories(glide-photos PRIVATE ${PROJECT_SOURCE_DIR}/common)
target_link_libraries(glide-photos PRIVATE Qt6::Gui Qt6::GuiPrivate Qt6::Quick Qt6::DBus glideuiplugin glidetr)

install(TARGETS glide-photos RUNTIME DESTINATION bin)
# полный путь в Exec: GIO (Nautilus, «Открыть с помощью») прячет приложение, если программы нет в его PATH,
# а ~/.local/bin в PATH графической сессии может не быть
include(GNUInstallDirs)
configure_file(glide-photos.desktop.in ${CMAKE_CURRENT_BINARY_DIR}/glide-photos.desktop @ONLY)
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/glide-photos.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)

# самотест правки (не устанавливается): build/photos/glide-photos-selftest пустая_папка
qt_add_executable(glide-photos-selftest EXCLUDE_FROM_ALL selftest.cpp imageeditor.h imageeditor.cpp gallery.h gallery.cpp)
target_link_libraries(glide-photos-selftest PRIVATE Qt6::Gui Qt6::Qml Qt6::DBus glidetr)
