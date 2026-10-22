# Glide Apps

**English** · [Русский](README.ru.md)

Lightweight everyday apps in the style of [Glide Shell](https://github.com/fdhy23qd/Glide-shell), written in C++ and
QML on the system Qt 6. They are made to go with the shell: they take its theme (tone, accent colour, corner radius,
text size, light or dark mode) and language from `~/.config/glide-shell/config.json` and follow it live. They also work on their own and
on any Wayland compositor, but they are designed for niri. Without Glide Shell they use the default Glide look.

| App | Command | What it does |
|---|---|---|
| Photos | `glide-photos` | Image viewer with a folder grid, slideshow and editing: crop, rotate, resize, convert |
| Video | `glide-video` | Video and audio player with a simple FFmpeg-based editor; MPRIS support |
| PDF | `glide-pdf` | PDF reader: search, outline, thumbnails, text selection, night mode |
| Screenshots | `glide-shot` | Capture with niri's own UI and annotate: arrows, boxes, text, steps, blur |
| Archives | `glide-archive` | Open, extract and create zip, 7z, rar, tar.* and more (libarchive) |

> The interface is in English and Russian, like Glide Shell (`lang` in its settings; without it — by `$LANG`).
> They are a personal project, used daily on Arch Linux with niri.

![Photos](docs/screenshots/photos.png)

| | |
|---|---|
| ![Video](docs/screenshots/video.png) | ![PDF](docs/screenshots/pdf.png) |
| Video: player and editor | PDF |
| ![Screenshots](docs/screenshots/shot.png) | ![Archives](docs/screenshots/archive.png) |
| Screenshots: annotation | Archives |

## Installation

Dependencies (Arch Linux package names):
- `qt6-base`, `qt6-declarative`, `qt6-multimedia`, `qt6-shadertools`;
- `qt6-webengine`, which provides Qt PDF on Arch;
- `libarchive`, `ffmpeg`;
- `cmake` and `ninja` to build.

Optional:
- `kimageformats` for AVIF, HEIC and JPEG XL in Photos;
- `intel-media-driver` for hardware video decoding;
- `7zip` for encrypted 7z and RAR archives.

```sh
git clone https://github.com/fdhy23qd/Glide-apps && cd Glide-apps
sh install.sh        # builds (cmake + ninja) and installs to ~/.local: bin, applications, icons
```

The installer does not change your file associations. To make the apps your defaults:

```sh
xdg-mime default glide-photos.desktop image/jpeg image/png image/webp image/gif image/svg+xml
xdg-mime default glide-video.desktop video/mp4 video/x-matroska video/webm video/quicktime
xdg-mime default glide-archive.desktop application/zip application/x-7z-compressed application/vnd.rar application/x-tar
```

The `.desktop` files use full paths in `Exec`, so the apps also appear in "Open with" when `~/.local/bin` is not in
the session's `PATH`.

## Highlights

- **Photos** opens in about 0.3 s and uses 30–45 MB of its own memory. Neighbouring images are preloaded, so
  browsing has no delay. It understands EXIF rotation and plays animated GIFs.
  - Edit mode (E): crop with aspect presets, rotate and flip, resize, and convert to JPEG, PNG, WebP, AVIF or JPEG XL
    with a live estimate of the file size. It saves a copy next to the original, or replaces the original and keeps
    it in the trash, so Ctrl+Z works.
- **Video** resumes where you stopped, keeps the screen awake while playing, and exposes MPRIS. Media keys work,
  and the Glide Shell island shows the video as playing.
  - Editor (E): trim (exactly, or "without re-encoding" in seconds), convert to MP4, WebM, MKV, GIF, WebP, MP3,
    M4A, Opus, FLAC or WAV, change the quality and resolution, remove the sound, rotate.
- **PDF** renders only the visible pages, at the resolution of the current zoom. It has search, an outline and
  thumbnails (F9), and a night mode (D). It opens password-protected files and follows only http(s) and mail links.
- **Screenshots:** `glide-shot --capture region|window|screen` captures with niri's own selection UI and opens the
  editor right away.
  - Tools: arrow, box, oval, line, pen, marker, text, numbered steps, blur (pixelate numbers, e-mails, passwords),
    crop.
  - Ctrl+C copies the result and Ctrl+S saves it.
  - In Glide Shell, the screenshot plugin and the Print keys use it when it is installed.
- **Archives:**
  - Extraction never overwrites files, and paths that would escape the target folder are skipped.
  - Old Windows zips with Cyrillic names (CP866) are detected automatically.
  - Zip archives can be created with an AES-256 password.
  - An archive is written to `name.part` and renamed only when complete, so a half-written archive never remains.

Each app has a self-test target (`*-selftest`) and a UI test hook that works without a mouse or a screen. See the
"Разработка" (development) section of the [Russian README](README.ru.md).

## License

[GPL-3.0-or-later](LICENSE), the same as Glide Shell.
