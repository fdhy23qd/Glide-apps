qt_add_executable(glide-video
    main.cpp
    playlist.h playlist.cpp
    converter.h converter.cpp
    mpris.h mpris.cpp
    inhibitor.h inhibitor.cpp
)

qt_add_qml_module(glide-video
    URI GlideVideo
    VERSION 1.0
    QML_FILES
        Main.qml
        SeekBar.qml
        EditPanel.qml
)

target_include_directories(glide-video PRIVATE ${PROJECT_SOURCE_DIR}/common)
target_link_libraries(glide-video PRIVATE Qt6::Gui Qt6::GuiPrivate Qt6::Quick Qt6::DBus Qt6::Multimedia glideuiplugin glidetr)

install(TARGETS glide-video RUNTIME DESTINATION bin)
# полный путь в Exec: GIO (Nautilus, «Открыть с помощью») прячет приложение, если программы нет в его PATH,
# а ~/.local/bin в PATH графической сессии может не быть
include(GNUInstallDirs)
configure_file(glide-video.desktop.in ${CMAKE_CURRENT_BINARY_DIR}/glide-video.desktop @ONLY)
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/glide-video.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)

# самотест редактора (не устанавливается): build/video/glide-video-selftest папка_с_тестовыми_файлами
qt_add_executable(glide-video-selftest EXCLUDE_FROM_ALL selftest.cpp converter.h converter.cpp)
target_link_libraries(glide-video-selftest PRIVATE Qt6::Core Qt6::Qml glidetr)
