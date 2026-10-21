qt_add_executable(glide-shot
    main.cpp
    shot.h shot.cpp
)

qt_add_qml_module(glide-shot
    URI GlideShot
    VERSION 1.0
    QML_FILES
        Main.qml
        Annotation.qml
)

target_include_directories(glide-shot PRIVATE ${PROJECT_SOURCE_DIR}/common)
target_link_libraries(glide-shot PRIVATE Qt6::Gui Qt6::GuiPrivate Qt6::Quick Qt6::DBus glideuiplugin)

install(TARGETS glide-shot RUNTIME DESTINATION bin)
include(GNUInstallDirs)
configure_file(glide-shot.desktop.in ${CMAKE_CURRENT_BINARY_DIR}/glide-shot.desktop @ONLY)
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/glide-shot.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)

# самотест отрисовки (не устанавливается): build/shot/glide-shot-selftest папка
qt_add_executable(glide-shot-selftest EXCLUDE_FROM_ALL selftest.cpp shot.h shot.cpp)
target_link_libraries(glide-shot-selftest PRIVATE Qt6::Gui Qt6::Qml Qt6::DBus)
