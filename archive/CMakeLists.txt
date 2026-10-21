find_package(PkgConfig REQUIRED)
pkg_check_modules(LIBARCHIVE REQUIRED IMPORTED_TARGET libarchive)

qt_add_executable(glide-archive
    main.cpp
    archiver.h archiver.cpp
)

qt_add_qml_module(glide-archive
    URI GlideArchive
    VERSION 1.0
    QML_FILES
        Main.qml
        CreatePanel.qml
)

target_include_directories(glide-archive PRIVATE ${PROJECT_SOURCE_DIR}/common)
target_link_libraries(glide-archive PRIVATE Qt6::Gui Qt6::GuiPrivate Qt6::Quick Qt6::DBus PkgConfig::LIBARCHIVE glideuiplugin)

install(TARGETS glide-archive RUNTIME DESTINATION bin)
include(GNUInstallDirs)
configure_file(glide-archive.desktop.in ${CMAKE_CURRENT_BINARY_DIR}/glide-archive.desktop @ONLY)
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/glide-archive.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)

# самотест движка (не устанавливается): build/archive/glide-archive-selftest папка
add_executable(glide-archive-selftest EXCLUDE_FROM_ALL selftest.cpp archiver.h archiver.cpp)
set_target_properties(glide-archive-selftest PROPERTIES AUTOMOC ON)
target_link_libraries(glide-archive-selftest PRIVATE Qt6::Qml Qt6::DBus PkgConfig::LIBARCHIVE)
