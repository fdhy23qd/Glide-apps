qt_add_executable(glide-pdf
    main.cpp
    library.h library.cpp
)

qt_add_qml_module(glide-pdf
    URI GlidePdf
    VERSION 1.0
    QML_FILES
        Main.qml
        PageDelegate.qml
        SearchBar.qml
        Sidebar.qml
)

# ночной режим: шейдер компилируется при сборке (qsb)
qt_add_shaders(glide-pdf "glide-pdf-shaders"
    PREFIX "/qt/qml/GlidePdf"
    FILES night.frag
)

target_include_directories(glide-pdf PRIVATE ${PROJECT_SOURCE_DIR}/common)
target_link_libraries(glide-pdf PRIVATE Qt6::Gui Qt6::GuiPrivate Qt6::Quick Qt6::DBus Qt6::Pdf Qt6::PdfQuick glideuiplugin)

install(TARGETS glide-pdf RUNTIME DESTINATION bin)
include(GNUInstallDirs)
configure_file(glide-pdf.desktop.in ${CMAKE_CURRENT_BINARY_DIR}/glide-pdf.desktop @ONLY)
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/glide-pdf.desktop DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
