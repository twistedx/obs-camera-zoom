obs = obslua

-- Script settings
local source_name = ""
local zoom_factor = 1.0
local pan_x = 0.5
local pan_y = 0.5
local hotkey_zoom_in = obs.OBS_INVALID_HOTKEY_ID
local hotkey_zoom_out = obs.OBS_INVALID_HOTKEY_ID
local hotkey_reset = obs.OBS_INVALID_HOTKEY_ID
local hotkey_pan_left = obs.OBS_INVALID_HOTKEY_ID
local hotkey_pan_right = obs.OBS_INVALID_HOTKEY_ID
local hotkey_pan_up = obs.OBS_INVALID_HOTKEY_ID
local hotkey_pan_down = obs.OBS_INVALID_HOTKEY_ID
local zoom_step = 0.25
local pan_step = 0.05
local max_zoom = 10.0
local auto_crop = true

-- Tracking for auto-crop on resize
local last_item_w = 0
local last_item_h = 0

-- ============================================================
-- Description
-- ============================================================
function script_description()
    return [[
<h2>Webcam Zoom</h2>
<p>Zoom into any video source (webcam, capture card, etc.) without changing the output frame size.</p>
<p><b>How it works:</b> Applies a crop filter to zoom in and lets you pan around the frame.</p>
<p><b>Auto-Crop on Resize:</b> When you resize the source in your scene, the image automatically
crops to fill the new shape instead of squishing. The perspective stays correct no matter
what size or aspect ratio you drag it to.</p>
<p><b>Hotkeys:</b> Set hotkeys in OBS Settings &rarr; Hotkeys for zoom in/out, pan, and reset.</p>
]]
end

-- ============================================================
-- Get the scene item for our source in the current scene
-- ============================================================
function get_scene_item()
    local current_scene_source = obs.obs_frontend_get_current_scene()
    if current_scene_source == nil then return nil, nil end

    local scene = obs.obs_scene_from_source(current_scene_source)
    if scene == nil then
        obs.obs_source_release(current_scene_source)
        return nil, nil
    end

    local item = obs.obs_scene_find_source(scene, source_name)
    -- Return both so we can release the scene source later
    return item, current_scene_source
end

-- ============================================================
-- Get the scene item's display size (what the user dragged it to)
-- ============================================================
function get_item_display_size()
    local item, scene_source = get_scene_item()
    if item == nil then
        if scene_source then obs.obs_source_release(scene_source) end
        return 0, 0
    end

    local bounds_type = obs.obs_sceneitem_get_bounds_type(item)
    local w, h

    if bounds_type ~= obs.OBS_BOUNDS_NONE then
        -- Item uses bounding box
        local bounds = obs.vec2()
        obs.obs_sceneitem_get_bounds(item, bounds)
        w = bounds.x
        h = bounds.y
    else
        -- Item uses scale transform
        local scale = obs.vec2()
        obs.obs_sceneitem_get_scale(item, scale)

        local source = obs.obs_get_source_by_name(source_name)
        if source == nil then
            obs.obs_source_release(scene_source)
            return 0, 0
        end
        local base_w = obs.obs_source_get_base_width(source)
        local base_h = obs.obs_source_get_base_height(source)
        obs.obs_source_release(source)

        w = base_w * scale.x
        h = base_h * scale.y
    end

    obs.obs_source_release(scene_source)
    return math.floor(w + 0.5), math.floor(h + 0.5)
end

-- ============================================================
-- Apply the crop/zoom to the source
-- Called both manually (hotkeys/sliders) and by the auto-resize timer
-- ============================================================
function apply_zoom()
    local source = obs.obs_get_source_by_name(source_name)
    if source == nil then
        return
    end

    local base_width = obs.obs_source_get_base_width(source)
    local base_height = obs.obs_source_get_base_height(source)

    if base_width == 0 or base_height == 0 then
        obs.obs_source_release(source)
        return
    end

    -- Start with the user's manual zoom
    local effective_zoom = zoom_factor
    local effective_pan_x = pan_x
    local effective_pan_y = pan_y

    -- Auto-crop: if the scene item has been resized to a different aspect ratio,
    -- add extra cropping so the image fills the new shape without squishing
    local item_w, item_h = get_item_display_size()
    if auto_crop and item_w > 0 and item_h > 0 then
        local src_aspect = base_width / base_height
        local item_aspect = item_w / item_h

        if math.abs(src_aspect - item_aspect) > 0.01 then
            -- Aspects differ — we need to crop to fill
            -- Calculate how much extra zoom is needed to fill the item shape
            if item_aspect > src_aspect then
                -- Item is wider than source — crop top/bottom to fill width
                local aspect_zoom = item_aspect / src_aspect
                effective_zoom = zoom_factor * aspect_zoom
            else
                -- Item is taller than source — crop left/right to fill height
                local aspect_zoom = src_aspect / item_aspect
                effective_zoom = zoom_factor * aspect_zoom
            end
        end
    end

    -- Clamp effective zoom
    if effective_zoom > max_zoom then effective_zoom = max_zoom end
    if effective_zoom < 1.0 then effective_zoom = 1.0 end

    -- Calculate crop amounts from the effective zoom
    local visible_w = base_width / effective_zoom
    local visible_h = base_height / effective_zoom
    local crop_total_x = base_width - visible_w
    local crop_total_y = base_height - visible_h

    -- Clamp pan values
    if effective_pan_x < 0.0 then effective_pan_x = 0.0 end
    if effective_pan_x > 1.0 then effective_pan_x = 1.0 end
    if effective_pan_y < 0.0 then effective_pan_y = 0.0 end
    if effective_pan_y > 1.0 then effective_pan_y = 1.0 end

    local crop_left = math.floor(crop_total_x * effective_pan_x)
    local crop_right = math.floor(crop_total_x * (1.0 - effective_pan_x))
    local crop_top = math.floor(crop_total_y * effective_pan_y)
    local crop_bottom = math.floor(crop_total_y * (1.0 - effective_pan_y))

    -- Apply crop filter
    local filter = obs.obs_source_get_filter_by_name(source, "WebcamZoom_Crop")
    if filter == nil then
        local settings = obs.obs_data_create()
        obs.obs_data_set_int(settings, "left", crop_left)
        obs.obs_data_set_int(settings, "right", crop_right)
        obs.obs_data_set_int(settings, "top", crop_top)
        obs.obs_data_set_int(settings, "bottom", crop_bottom)
        obs.obs_data_set_bool(settings, "relative", false)

        filter = obs.obs_source_create_private("crop_filter", "WebcamZoom_Crop", settings)
        obs.obs_source_filter_add(source, filter)
        obs.obs_data_release(settings)
    else
        local settings = obs.obs_source_get_settings(filter)
        obs.obs_data_set_int(settings, "left", crop_left)
        obs.obs_data_set_int(settings, "right", crop_right)
        obs.obs_data_set_int(settings, "top", crop_top)
        obs.obs_data_set_int(settings, "bottom", crop_bottom)
        obs.obs_data_set_bool(settings, "relative", false)
        obs.obs_source_update(filter, settings)
        obs.obs_data_release(settings)
    end

    -- Apply scale filter: scale cropped result to fill the item display size
    local scale_filter = obs.obs_source_get_filter_by_name(source, "WebcamZoom_Scale")
    local target_w = item_w
    local target_h = item_h

    -- If no valid item size, fall back to source native resolution
    if target_w <= 0 or target_h <= 0 then
        target_w = base_width
        target_h = base_height
    end

    local need_scale = (effective_zoom > 1.0)
    if need_scale then
        local res_str = tostring(target_w) .. "x" .. tostring(target_h)
        if scale_filter == nil then
            local s_settings = obs.obs_data_create()
            obs.obs_data_set_string(s_settings, "resolution", res_str)
            obs.obs_data_set_int(s_settings, "sampling", 2) -- Bicubic
            scale_filter = obs.obs_source_create_private("scale_filter", "WebcamZoom_Scale", s_settings)
            obs.obs_source_filter_add(source, scale_filter)
            obs.obs_data_release(s_settings)
        else
            local s_settings = obs.obs_source_get_settings(scale_filter)
            obs.obs_data_set_string(s_settings, "resolution", res_str)
            obs.obs_source_update(scale_filter, s_settings)
            obs.obs_data_release(s_settings)
        end
    else
        if scale_filter ~= nil then
            obs.obs_source_filter_remove(source, scale_filter)
        end
    end

    if scale_filter ~= nil then
        obs.obs_source_release(scale_filter)
    end
    obs.obs_source_release(filter)
    obs.obs_source_release(source)
end

-- ============================================================
-- Timer: polls the scene item size and re-crops if it changed
-- ============================================================
function check_resize()
    if source_name == "" or not auto_crop then return end

    local w, h = get_item_display_size()
    if w <= 0 or h <= 0 then return end

    if w ~= last_item_w or h ~= last_item_h then
        last_item_w = w
        last_item_h = h
        apply_zoom()
    end
end

-- ============================================================
-- Remove filters when cleaning up
-- ============================================================
function remove_filters()
    local source = obs.obs_get_source_by_name(source_name)
    if source == nil then
        return
    end

    local filter = obs.obs_source_get_filter_by_name(source, "WebcamZoom_Crop")
    if filter ~= nil then
        obs.obs_source_filter_remove(source, filter)
        obs.obs_source_release(filter)
    end

    local scale_filter = obs.obs_source_get_filter_by_name(source, "WebcamZoom_Scale")
    if scale_filter ~= nil then
        obs.obs_source_filter_remove(source, scale_filter)
        obs.obs_source_release(scale_filter)
    end

    obs.obs_source_release(source)
end

-- ============================================================
-- Hotkey callbacks
-- ============================================================
function on_zoom_in(pressed)
    if not pressed then return end
    zoom_factor = math.min(zoom_factor + zoom_step, max_zoom)
    apply_zoom()
end

function on_zoom_out(pressed)
    if not pressed then return end
    zoom_factor = math.max(zoom_factor - zoom_step, 1.0)
    if zoom_factor <= 1.0 then
        pan_x = 0.5
        pan_y = 0.5
    end
    apply_zoom()
end

function on_reset(pressed)
    if not pressed then return end
    zoom_factor = 1.0
    pan_x = 0.5
    pan_y = 0.5
    apply_zoom()
end

function on_pan_left(pressed)
    if not pressed then return end
    pan_x = math.max(pan_x - pan_step, 0.0)
    apply_zoom()
end

function on_pan_right(pressed)
    if not pressed then return end
    pan_x = math.min(pan_x + pan_step, 1.0)
    apply_zoom()
end

function on_pan_up(pressed)
    if not pressed then return end
    pan_y = math.max(pan_y - pan_step, 0.0)
    apply_zoom()
end

function on_pan_down(pressed)
    if not pressed then return end
    pan_y = math.min(pan_y + pan_step, 1.0)
    apply_zoom()
end

-- ============================================================
-- Script properties (UI in OBS Tools -> Scripts)
-- ============================================================
function script_properties()
    local props = obs.obs_properties_create()

    -- Source selector (only video sources)
    local source_list = obs.obs_properties_add_list(
        props, "source_name", "Video Source",
        obs.OBS_COMBO_TYPE_LIST, obs.OBS_COMBO_FORMAT_STRING
    )
    obs.obs_property_list_add_string(source_list, "-- Select Source --", "")

    local sources = obs.obs_enum_sources()
    if sources ~= nil then
        for _, source in ipairs(sources) do
            local flags = obs.obs_source_get_output_flags(source)
            if bit.band(flags, obs.OBS_SOURCE_VIDEO) ~= 0 then
                local name = obs.obs_source_get_name(source)
                obs.obs_property_list_add_string(source_list, name, name)
            end
        end
        obs.source_list_release(sources)
    end

    -- Auto-crop toggle
    obs.obs_properties_add_bool(props, "auto_crop",
        "Auto-Crop on Resize (zoom to fill instead of squishing)")

    -- Zoom controls
    obs.obs_properties_add_float_slider(props, "zoom_factor", "Zoom Level", 1.0, max_zoom, 0.25)
    obs.obs_properties_add_float_slider(props, "pan_x", "Pan Horizontal (Left <-> Right)", 0.0, 1.0, 0.01)
    obs.obs_properties_add_float_slider(props, "pan_y", "Pan Vertical (Top <-> Bottom)", 0.0, 1.0, 0.01)

    -- Step size settings
    obs.obs_properties_add_float_slider(props, "zoom_step", "Zoom Step (per hotkey press)", 0.05, 1.0, 0.05)
    obs.obs_properties_add_float_slider(props, "pan_step", "Pan Step (per hotkey press)", 0.01, 0.2, 0.01)

    return props
end

-- ============================================================
-- Default settings
-- ============================================================
function script_defaults(settings)
    obs.obs_data_set_default_double(settings, "zoom_factor", 1.0)
    obs.obs_data_set_default_double(settings, "pan_x", 0.5)
    obs.obs_data_set_default_double(settings, "pan_y", 0.5)
    obs.obs_data_set_default_double(settings, "zoom_step", 0.25)
    obs.obs_data_set_default_double(settings, "pan_step", 0.05)
    obs.obs_data_set_default_bool(settings, "auto_crop", true)
end

-- ============================================================
-- Update settings from UI
-- ============================================================
function script_update(settings)
    local new_source = obs.obs_data_get_string(settings, "source_name")

    -- If source changed, remove old filters first
    if new_source ~= source_name and source_name ~= "" then
        remove_filters()
    end

    source_name = new_source
    zoom_factor = obs.obs_data_get_double(settings, "zoom_factor")
    pan_x = obs.obs_data_get_double(settings, "pan_x")
    pan_y = obs.obs_data_get_double(settings, "pan_y")
    zoom_step = obs.obs_data_get_double(settings, "zoom_step")
    pan_step = obs.obs_data_get_double(settings, "pan_step")
    auto_crop = obs.obs_data_get_bool(settings, "auto_crop")

    -- Reset tracking so next timer tick picks up fresh
    last_item_w = 0
    last_item_h = 0

    apply_zoom()
end

-- ============================================================
-- Register hotkeys and start resize monitor timer
-- ============================================================
function script_load(settings)
    hotkey_zoom_in = obs.obs_hotkey_register_frontend("webcam_zoom_in", "Webcam Zoom: Zoom In", on_zoom_in)
    local save_array = obs.obs_data_get_array(settings, "webcam_zoom_in")
    obs.obs_hotkey_load(hotkey_zoom_in, save_array)
    obs.obs_data_array_release(save_array)

    hotkey_zoom_out = obs.obs_hotkey_register_frontend("webcam_zoom_out", "Webcam Zoom: Zoom Out", on_zoom_out)
    save_array = obs.obs_data_get_array(settings, "webcam_zoom_out")
    obs.obs_hotkey_load(hotkey_zoom_out, save_array)
    obs.obs_data_array_release(save_array)

    hotkey_reset = obs.obs_hotkey_register_frontend("webcam_zoom_reset", "Webcam Zoom: Reset", on_reset)
    save_array = obs.obs_data_get_array(settings, "webcam_zoom_reset")
    obs.obs_hotkey_load(hotkey_reset, save_array)
    obs.obs_data_array_release(save_array)

    hotkey_pan_left = obs.obs_hotkey_register_frontend("webcam_zoom_pan_left", "Webcam Zoom: Pan Left", on_pan_left)
    save_array = obs.obs_data_get_array(settings, "webcam_zoom_pan_left")
    obs.obs_hotkey_load(hotkey_pan_left, save_array)
    obs.obs_data_array_release(save_array)

    hotkey_pan_right = obs.obs_hotkey_register_frontend("webcam_zoom_pan_right", "Webcam Zoom: Pan Right", on_pan_right)
    save_array = obs.obs_data_get_array(settings, "webcam_zoom_pan_right")
    obs.obs_hotkey_load(hotkey_pan_right, save_array)
    obs.obs_data_array_release(save_array)

    hotkey_pan_up = obs.obs_hotkey_register_frontend("webcam_zoom_pan_up", "Webcam Zoom: Pan Up", on_pan_up)
    save_array = obs.obs_data_get_array(settings, "webcam_zoom_pan_up")
    obs.obs_hotkey_load(hotkey_pan_up, save_array)
    obs.obs_data_array_release(save_array)

    hotkey_pan_down = obs.obs_hotkey_register_frontend("webcam_zoom_pan_down", "Webcam Zoom: Pan Down", on_pan_down)
    save_array = obs.obs_data_get_array(settings, "webcam_zoom_pan_down")
    obs.obs_hotkey_load(hotkey_pan_down, save_array)
    obs.obs_data_array_release(save_array)

    pan_x = 0.5
    pan_y = 0.5

    -- Start a timer that checks every 200ms if the item was resized
    obs.timer_add(check_resize, 200)
end

-- ============================================================
-- Save hotkeys
-- ============================================================
function script_save(settings)
    local save_array = obs.obs_hotkey_save(hotkey_zoom_in)
    obs.obs_data_set_array(settings, "webcam_zoom_in", save_array)
    obs.obs_data_array_release(save_array)

    save_array = obs.obs_hotkey_save(hotkey_zoom_out)
    obs.obs_data_set_array(settings, "webcam_zoom_out", save_array)
    obs.obs_data_array_release(save_array)

    save_array = obs.obs_hotkey_save(hotkey_reset)
    obs.obs_data_set_array(settings, "webcam_zoom_reset", save_array)
    obs.obs_data_array_release(save_array)

    save_array = obs.obs_hotkey_save(hotkey_pan_left)
    obs.obs_data_set_array(settings, "webcam_zoom_pan_left", save_array)
    obs.obs_data_array_release(save_array)

    save_array = obs.obs_hotkey_save(hotkey_pan_right)
    obs.obs_data_set_array(settings, "webcam_zoom_pan_right", save_array)
    obs.obs_data_array_release(save_array)

    save_array = obs.obs_hotkey_save(hotkey_pan_up)
    obs.obs_data_set_array(settings, "webcam_zoom_pan_up", save_array)
    obs.obs_data_array_release(save_array)

    save_array = obs.obs_hotkey_save(hotkey_pan_down)
    obs.obs_data_set_array(settings, "webcam_zoom_pan_down", save_array)
    obs.obs_data_array_release(save_array)
end

-- ============================================================
-- Cleanup on unload
-- ============================================================
function script_unload()
    obs.timer_remove(check_resize)
    remove_filters()
end
