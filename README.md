# LazyConverter

[![macOS](https://img.shields.io/badge/macOS-14.0+-blue.svg)](https://developer.apple.com/macos/)
[![SwiftUI](https://img.shields.io/badge/SwiftUI-5.0+-orange.svg)](https://developer.apple.com/xcode/swiftui/)
[![Downloads](https://img.shields.io/github/downloads/argorar/LazyConverter/total.svg)]()
[![License](https://img.shields.io/github/license/argorar/LazyConverter)](LICENSE)

LazyConverter is a **native macOS app** for fast, simple, and privacy‑friendly video conversion and basic editing. Everything runs locally on your Mac using FFmpeg.

![interface](interface.png)

## ✨ Features

### 🎥 Video Conversion
- Convert videos to **MP4**, **MKV** and other common formats
- Choose output **resolution**: original, 4K, 1080p, 720p, etc.
- Control output **quality** with a percentage slider (1–100%)

### ⏱️ Speed Control & Trimming
- Adjust video **speed** (0.5x → 2x) with intuitive slider
- **Live preview** shows result in real-time
- Set **Trim Start/End** using current playback time
- Displays trim **duration** and progress HUD

### ✂️ Cropping
- Visual **crop overlay** on video preview
- Drag handles to define export region
- Normalized crop coordinates (adapts to any resolution)

### 🔍 Auto-Analysis
Automatically shows:
- Resolution (width × height)
- Duration
- File size
- Frame rate (FPS)

### ▶️ Smart Preview
- Native **AVPlayer** integration
- Live time readout: `current / total (XX%)`
- Crop overlay when enabled

## 🚀 Quick Start

1. **Drag & drop** a video file or click to select
2. **Adjust settings**:
   - Format (MP4/MKV/AV1/WebM)
   - Resolution & quality
   - Speed, trim, crop, color, interpolation
3. **Click Convert**
4. **Success banner** appears when done

## Requirements

To run this app you need to have **FFmpeg** and **FFprobe** installed on your system.

Execute the next commands to install them:

```bash
brew tap homebrew-ffmpeg/ffmpeg
brew install homebrew-ffmpeg/ffmpeg/ffmpeg --with-libvidstab
```

Optional to download videos from internet use yt-dlp:

```bash
brew install yt-dlp
```

## ⬇️ Downloads

- **LazyConverter-Standalone**: Includes FFmpeg and FFprobe inside the app bundle. Works out of the box.
- **LazyConverter**: Smaller app that uses your installed FFmpeg/FFprobe (`/usr/local/bin` or `/opt/homebrew/bin`).


<div align="center">

**Made with ❤️ for macOS users**  
**LazyConverter · Convert videos without effort**

</div>
