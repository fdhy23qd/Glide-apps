cmake_minimum_required(VERSION 3.21)
project(glide-apps LANGUAGES CXX)

# Базовые приложения Glide: C++ + QML на системном Qt (тот же, что у Glide Shell — библиотеки
# уже в памяти, запуск быстрый). Общий модуль Glide.Ui — тема из настроек Glide Shell и кнопки.
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()

find_package(Qt6 6.8 REQUIRED COMPONENTS Gui Qml Quick DBus Multimedia Pdf PdfQuick ShaderTools)
set(QT_NO_PRIVATE_MODULE_WARNING ON)
find_package(Qt6 REQUIRED COMPONENTS GuiPrivate)   # testhook.h: события через QPA
qt_standard_project_setup(REQUIRES 6.8)

add_subdirectory(common)
add_subdirectory(photos)
add_subdirectory(video)
add_subdirectory(pdf)
add_subdirectory(shot)
add_subdirectory(archive)
