# OBS Webcam Zoom

An OBS filter plugin that lets you zoom into any video source and pan around the frame. Apply it to as many sources as you want — each gets its own independent zoom and pan controls.

## Features

- **Per-source filter** — Add "Webcam Zoom" as a filter on any video source. Each source gets independent controls
- **GPU-accelerated** — Uses a custom shader for the zoom, runs entirely on the GPU
- **Zoom In/Out** — Smoothly zoom into the feed using sliders or hotkeys
- **Pan** — Move the visible area in any direction while zoomed in
- **Per-source hotkeys** — Each source's filter gets its own hotkey bindings
- **Works with any video source** — Webcams, capture cards, NDI sources, screen captures, etc.

## How It Works

The filter uses a GPU shader that remaps UV coordinates to zoom into the frame. At zoom 1.0 it passes through unchanged (zero overhead). At higher zoom levels the shader samples from a smaller region of the source texture and fills the output, giving you a clean digital zoom with no filter hacks or crop workarounds.

## Installation

1. Open **OBS Studio**
2. Go to **Tools > Scripts**
3. Click the **+** button
4. Select `webcam-zoom.lua`
5. Done — the filter is now available on all sources

## Usage

1. Right-click any video source in your scene
2. Select **Filters**
3. Under "Effect Filters", click **+** and choose **Webcam Zoom**
4. Adjust **Zoom Level** (1.0 = normal, up to 10x)
5. Use **Pan** sliders to move around the zoomed frame

Repeat for as many sources as you need — each filter instance is independent.

## Hotkeys

Go to **Settings > Hotkeys**. Each source with a Webcam Zoom filter gets its own set of hotkeys:

| Action | Description |
|--------|-------------|
| Webcam Zoom: Zoom In | Increase zoom by one step |
| Webcam Zoom: Zoom Out | Decrease zoom by one step |
| Webcam Zoom: Reset | Reset zoom to 1.0 and center pan |
| Webcam Zoom: Pan Left | Shift view left |
| Webcam Zoom: Pan Right | Shift view right |
| Webcam Zoom: Pan Up | Shift view up |
| Webcam Zoom: Pan Down | Shift view down |

## Filter Settings

| Setting | Description |
|---------|-------------|
| Zoom Level | Zoom factor (1.0 = normal, 2.0 = 2x zoom, up to 10x) |
| Pan Horizontal | Horizontal position of the zoom window (0.0 = left, 1.0 = right) |
| Pan Vertical | Vertical position of the zoom window (0.0 = top, 1.0 = bottom) |
| Zoom Step | How much each hotkey press changes the zoom (default: 0.25) |
| Pan Step | How much each hotkey press pans the view (default: 0.05) |

## Resize Without Squishing

To prevent your source from squishing when you resize it to a different aspect ratio:

1. Right-click the source in your scene
2. **Transform > Edit Transform**
3. Set **Bounding Box Type** to **Scale to outer bounds**

This makes OBS fill the frame by cropping overflow instead of stretching.

## Requirements

- OBS Studio 28.0 or later (Lua scripting support)
- Any video source with an active feed

## License

MIT
