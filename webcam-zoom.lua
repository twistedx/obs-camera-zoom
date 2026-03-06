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

-- ============================================================
-- Description
-- ============================================================
function script_description()
    return [[
<h2>Webcam Zoom</h2>
<p>Zoom into any video source without changing the output frame size.</p>
<p>Starts unzoomed showing your normal camera view. Use the slider or hotkeys to zoom in and pan.</p>
<p>Resize the source to any shape in your scene — it fills by cropping, never squishes.</p>
<p><b>Hotkeys:</b> Settings &rarr; Hotkeys, search "Webcam Zoom".</p>
]]
end

-- ============================================================
-- Find the scene item for our source in the current scene
-- ============================================================
function find_scene_item()
    local current_scene_source = obs.obs_frontend_get_current_scene()
    if current_scene_source == nil then return nil, nil end

    local scene = obs.obs_scene_from_source(current_scene_source)
    if scene == nil then
        obs.obs_source_release(current_scene_source)
        return nil, nil
    end

    local item = obs.obs_scene_find_source(scene, source_name)
    return item, current_scene_source
end

-- ============================================================
-- Apply zoom by setting scene item crop directly
-- No filters — uses OBS built-in scene item cropping
-- ============================================================
function apply_zoom()
    if source_name == "" then return end

    -- Get the source's native resolution
    local source = obs.obs_get_source_by_name(source_name)
    if source == nil then return end

    local native_w = obs.obs_source_get_base_width(source)
    local native_h = obs.obs_source_get_base_height(source)
    obs.obs_source_release(source)

    if native_w == 0 or native_h == 0 then return end

    -- Find the scene item
    local item, scene_source = find_scene_item()
    if item == nil then
        if scene_source then obs.obs_source_release(scene_source) end
        return
    end

    -- Set bounds to SCALE_OUTER so resizing always fills without squishing
    local bounds_type = obs.obs_sceneitem_get_bounds_type(item)
    if bounds_type == obs.OBS_BOUNDS_NONE then
        -- Convert current scale-based size to bounds
        local scale = obs.vec2()
        obs.obs_sceneitem_get_scale(item, scale)
        local bounds = obs.vec2()
        bounds.x = native_w * scale.x
        bounds.y = native_h * scale.y
        obs.obs_sceneitem_set_bounds_type(item, obs.OBS_BOUNDS_SCALE_OUTER)
        obs.obs_sceneitem_set_bounds(item, bounds)
        -- Reset scale since bounds control sizing now
        local unit = obs.vec2()
        unit.x = 1.0
        unit.y = 1.0
        obs.obs_sceneitem_set_scale(item, unit)
    elseif bounds_type ~= obs.OBS_BOUNDS_SCALE_OUTER then
        obs.obs_sceneitem_set_bounds_type(item, obs.OBS_BOUNDS_SCALE_OUTER)
    end

    -- Calculate crop values
    local crop_left = 0
    local crop_right = 0
    local crop_top = 0
    local crop_bottom = 0

    if zoom_factor > 1.0 then
        local visible_w = native_w / zoom_factor
        local visible_h = native_h / zoom_factor
        local crop_total_x = native_w - visible_w
        local crop_total_y = native_h - visible_h

        local px = math.max(0.0, math.min(1.0, pan_x))
        local py = math.max(0.0, math.min(1.0, pan_y))

        crop_left = math.floor(crop_total_x * px)
        crop_right = math.floor(crop_total_x * (1.0 - px))
        crop_top = math.floor(crop_total_y * py)
        crop_bottom = math.floor(crop_total_y * (1.0 - py))
    end

    -- Apply crop directly to the scene item (no filters!)
    local crop = obs.obs_sceneitem_crop()
    crop.left = crop_left
    crop.top = crop_top
    crop.right = crop_right
    crop.bottom = crop_bottom
    obs.obs_sceneitem_set_crop(item, crop)

    obs.obs_source_release(scene_source)
end

-- ============================================================
-- Remove any leftover filters from previous versions
-- ============================================================
function cleanup_old_filters()
    if source_name == "" then return end
    local source = obs.obs_get_source_by_name(source_name)
    if source == nil then return end

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
-- Reset crop to zero (cleanup)
-- ============================================================
function reset_crop()
    local item, scene_source = find_scene_item()
    if item == nil then
        if scene_source then obs.obs_source_release(scene_source) end
        return
    end
    local crop = obs.obs_sceneitem_crop()
    crop.left = 0
    crop.top = 0
    crop.right = 0
    crop.bottom = 0
    obs.obs_sceneitem_set_crop(item, crop)
    obs.obs_source_release(scene_source)
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
-- Script properties (UI)
-- ============================================================
function script_properties()
    local props = obs.obs_properties_create()

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

    obs.obs_properties_add_float_slider(props, "zoom_factor", "Zoom Level", 1.0, max_zoom, 0.25)
    obs.obs_properties_add_float_slider(props, "pan_x", "Pan Horizontal (Left <-> Right)", 0.0, 1.0, 0.01)
    obs.obs_properties_add_float_slider(props, "pan_y", "Pan Vertical (Top <-> Bottom)", 0.0, 1.0, 0.01)
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
end

-- ============================================================
-- Update from UI
-- ============================================================
function script_update(settings)
    local new_source = obs.obs_data_get_string(settings, "source_name")

    if new_source ~= source_name and source_name ~= "" then
        reset_crop()
        cleanup_old_filters()
    end

    source_name = new_source
    zoom_factor = obs.obs_data_get_double(settings, "zoom_factor")
    pan_x = obs.obs_data_get_double(settings, "pan_x")
    pan_y = obs.obs_data_get_double(settings, "pan_y")
    zoom_step = obs.obs_data_get_double(settings, "zoom_step")
    pan_step = obs.obs_data_get_double(settings, "pan_step")

    -- Clean up any leftover filters from previous script versions
    cleanup_old_filters()

    apply_zoom()
end

-- ============================================================
-- Register hotkeys
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
-- Cleanup
-- ============================================================
function script_unload()
    reset_crop()
    cleanup_old_filters()
end
