qt_add_executable(glide-disk
    main.cpp
    scanner.h scanner.cpp
)

qt_add_qml_module(glide-disk
    URI GlideDisk
    VERSION 1.0
    QML_FILES
        Main.qml
        Treemap.qml
)

target_include_directories(glide-disk PRIVATE ${PROJECT_SOURCE_DIR}/common)
target_link_libraries(glide-disk PRIVATE Qt6::Gui Qt6::GuiPrivate Qt6::Quick Qt6::DBus glideuiplugin glidetr)

install(TARGETS glide-disk RUNTIME DESTINATION bin)
include(GNUInstallDirs)
configure_file(glide-disk.desktop.in ${CMAKE_CURRENT_BINARY_DIR}/glide-disk.desktop @ONLY)
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/glide-disk.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
