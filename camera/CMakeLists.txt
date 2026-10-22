qt_add_executable(glide-camera
    main.cpp
    paths.h paths.cpp
)

qt_add_qml_module(glide-camera
    URI GlideCamera
    VERSION 1.0
    QML_FILES
        Main.qml
)

target_include_directories(glide-camera PRIVATE ${PROJECT_SOURCE_DIR}/common)
target_link_libraries(glide-camera PRIVATE Qt6::Gui Qt6::GuiPrivate Qt6::Quick Qt6::DBus Qt6::Multimedia glideuiplugin glidetr)

install(TARGETS glide-camera RUNTIME DESTINATION bin)
include(GNUInstallDirs)
configure_file(glide-camera.desktop.in ${CMAKE_CURRENT_BINARY_DIR}/glide-camera.desktop @ONLY)
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/glide-camera.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
