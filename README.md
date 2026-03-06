# OBS Webcam Zoom

A lightweight OBS Lua script that lets you zoom into any webcam or video source and pan around the frame — without changing the output size. When you resize the source in your scene, it automatically crops to fill the new shape instead of squishing the image.

## Features

- **Zoom In/Out** — Smoothly zoom into your webcam feed using sliders or hotkeys
- **Pan** — Move the visible area in any direction while zoomed in
- **Auto-Crop on Resize** — Drag the source to any size or aspect ratio in your scene and the image automatically crops to fill it. No stretching, no squishing, no black bars
- **Hotkey Support** — Bind keys for zoom in, zoom out, pan left/right/up/down, and reset
- **Works with any video source** — Webcams, capture cards, NDI sources, etc.

## How It Works

The script uses OBS's built-in scene item crop to zoom into the frame — no extra filters added to your source. It also sets the scene item to **SCALE_OUTER** bounds mode, which means when you resize the source to any shape, OBS automatically fills it by cropping overflow instead of stretching.

### Example

Your webcam outputs 1920x1080 (16:9). You drag the source into a square in your scene. Instead of squishing:

- The script detects the new aspect ratio
- Crops the left and right edges of the webcam feed
- Scales the center portion to fill the square perfectly
- Use the Pan controls to shift which part of the frame is visible

## Installation

1. Open **OBS Studio**
2. Go to **Tools > Scripts**
3. Click the **+** button
4. Select `webcam-zoom.lua`
5. Done

## Setup

1. In the Scripts window, select `webcam-zoom.lua`
2. Choose your webcam from the **Video Source** dropdown
3. Adjust **Zoom Level** to zoom in (1.0 = no zoom)
4. Use **Pan** sliders to move around the frame
5. Resize the source to any shape — it fills by cropping, never squishes

## Hotkeys

Go to **Settings > Hotkeys** and search for "Webcam Zoom":

| Action | Description |
|--------|-------------|
| Webcam Zoom: Zoom In | Increase zoom by one step |
| Webcam Zoom: Zoom Out | Decrease zoom by one step |
| Webcam Zoom: Reset | Reset zoom to 1.0 and center pan |
| Webcam Zoom: Pan Left | Shift view left |
| Webcam Zoom: Pan Right | Shift view right |
| Webcam Zoom: Pan Up | Shift view up |
| Webcam Zoom: Pan Down | Shift view down |

## Settings

| Setting | Description |
|---------|-------------|
| Video Source | The webcam or video source to control |
| Zoom Level | Manual zoom factor (1.0 = normal, 2.0 = 2x zoom, up to 10x) |
| Pan Horizontal | Horizontal position of the zoom window (0.0 = left, 1.0 = right) |
| Pan Vertical | Vertical position of the zoom window (0.0 = top, 1.0 = bottom) |
| Zoom Step | How much each hotkey press changes the zoom (default: 0.25) |
| Pan Step | How much each hotkey press pans the view (default: 0.05) |

## Requirements

- OBS Studio 28.0 or later (Lua scripting support)
- Any video source with an active feed

## License

MIT
