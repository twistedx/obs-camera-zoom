obs = obslua

-- ============================================================
-- GPU shader for zoom (remaps UV coordinates)
-- ============================================================
local EFFECT_CODE = [[
uniform float4x4 ViewProj;
uniform texture2d image;

uniform float zoom_factor;
uniform float offset_x;
uniform float offset_y;

sampler_state texSampler {
    Filter   = Linear;
    AddressU = Clamp;
    AddressV = Clamp;
};

struct VertData {
    float4 pos : POSITION;
    float2 uv  : TEXCOORD0;
};

VertData VSDefault(VertData v_in)
{
    VertData v_out;
    v_out.pos = mul(float4(v_in.pos.xyz, 1.0), ViewProj);
    v_out.uv  = v_in.uv;
    return v_out;
}

float4 PSZoom(VertData v_in) : TARGET
{
    float inv_zoom = 1.0 / zoom_factor;
    float2 uv;
    uv.x = v_in.uv.x * inv_zoom + offset_x;
    uv.y = v_in.uv.y * inv_zoom + offset_y;
    return image.Sample(texSampler, uv);
}

technique Draw
{
    pass
    {
        vertex_shader = VSDefault(v_in);
        pixel_shader  = PSZoom(v_in);
    }
};
]]

-- ============================================================
-- Filter source definition
-- ============================================================
local source_info = {}
source_info.id = "webcam_zoom_filter"
source_info.type = obs.OBS_SOURCE_TYPE_FILTER
source_info.output_flags = bit.bor(obs.OBS_SOURCE_VIDEO)

-- ============================================================
-- Filter name (shown in Add Filter menu)
-- ============================================================
source_info.get_name = function()
    return "Webcam Zoom"
end

-- ============================================================
-- Create filter instance
-- ============================================================
source_info.create = function(settings, source)
    local data = {}
    data.source = source
    data.zoom_factor = 1.0
    data.pan_x = 0.5
    data.pan_y = 0.5
    data.zoom_step = 0.25
    data.pan_step = 0.05

    -- Compile the shader
    obs.obs_enter_graphics()
    local err = ""
    data.effect = obs.gs_effect_create(EFFECT_CODE, nil, err)
    obs.obs_leave_graphics()

    if data.effect then
        data.params = {
            zoom_factor = obs.gs_effect_get_param_by_name(data.effect, "zoom_factor"),
            offset_x = obs.gs_effect_get_param_by_name(data.effect, "offset_x"),
            offset_y = obs.gs_effect_get_param_by_name(data.effect, "offset_y"),
        }
    end

    -- Register per-source hotkeys
    data.hotkey_zoom_in = obs.obs_hotkey_register_source(source,
        "webcam_zoom_in", "Webcam Zoom: Zoom In",
        function(pressed)
            if not pressed then return end
            data.zoom_factor = math.min(data.zoom_factor + data.zoom_step, 10.0)
            update_settings_from_data(data)
        end)

    data.hotkey_zoom_out = obs.obs_hotkey_register_source(source,
        "webcam_zoom_out", "Webcam Zoom: Zoom Out",
        function(pressed)
            if not pressed then return end
            data.zoom_factor = math.max(data.zoom_factor - data.zoom_step, 1.0)
            if data.zoom_factor <= 1.0 then
                data.pan_x = 0.5
                data.pan_y = 0.5
            end
            update_settings_from_data(data)
        end)

    data.hotkey_reset = obs.obs_hotkey_register_source(source,
        "webcam_zoom_reset", "Webcam Zoom: Reset",
        function(pressed)
            if not pressed then return end
            data.zoom_factor = 1.0
            data.pan_x = 0.5
            data.pan_y = 0.5
            update_settings_from_data(data)
        end)

    data.hotkey_pan_left = obs.obs_hotkey_register_source(source,
        "webcam_zoom_pan_left", "Webcam Zoom: Pan Left",
        function(pressed)
            if not pressed then return end
            data.pan_x = math.max(data.pan_x - data.pan_step, 0.0)
            update_settings_from_data(data)
        end)

    data.hotkey_pan_right = obs.obs_hotkey_register_source(source,
        "webcam_zoom_pan_right", "Webcam Zoom: Pan Right",
        function(pressed)
            if not pressed then return end
            data.pan_x = math.min(data.pan_x + data.pan_step, 1.0)
            update_settings_from_data(data)
        end)

    data.hotkey_pan_up = obs.obs_hotkey_register_source(source,
        "webcam_zoom_pan_up", "Webcam Zoom: Pan Up",
        function(pressed)
            if not pressed then return end
            data.pan_y = math.max(data.pan_y - data.pan_step, 0.0)
            update_settings_from_data(data)
        end)

    data.hotkey_pan_down = obs.obs_hotkey_register_source(source,
        "webcam_zoom_pan_down", "Webcam Zoom: Pan Down",
        function(pressed)
            if not pressed then return end
            data.pan_y = math.min(data.pan_y + data.pan_step, 1.0)
            update_settings_from_data(data)
        end)

    source_info.update(data, settings)
    return data
end

-- ============================================================
-- Push data values back to OBS settings (so sliders update)
-- ============================================================
function update_settings_from_data(data)
    local s = obs.obs_source_get_settings(data.source)
    obs.obs_data_set_double(s, "zoom_factor", data.zoom_factor)
    obs.obs_data_set_double(s, "pan_x", data.pan_x)
    obs.obs_data_set_double(s, "pan_y", data.pan_y)
    obs.obs_source_update(data.source, s)
    obs.obs_data_release(s)
end

-- ============================================================
-- Destroy filter instance
-- ============================================================
source_info.destroy = function(data)
    if data.effect then
        obs.obs_enter_graphics()
        obs.gs_effect_destroy(data.effect)
        obs.obs_leave_graphics()
    end
end

-- ============================================================
-- Update from settings (sliders changed)
-- ============================================================
source_info.update = function(data, settings)
    data.zoom_factor = obs.obs_data_get_double(settings, "zoom_factor")
    data.pan_x = obs.obs_data_get_double(settings, "pan_x")
    data.pan_y = obs.obs_data_get_double(settings, "pan_y")
    data.zoom_step = obs.obs_data_get_double(settings, "zoom_step")
    data.pan_step = obs.obs_data_get_double(settings, "pan_step")
end

-- ============================================================
-- Render the zoomed frame (runs on GPU every frame)
-- ============================================================
source_info.video_render = function(data, effect)
    if not data.effect then
        obs.obs_source_skip_video_filter(data.source)
        return
    end

    -- Get parent source dimensions
    local target = obs.obs_filter_get_target(data.source)
    if target == nil then
        obs.obs_source_skip_video_filter(data.source)
        return
    end

    local width = obs.obs_source_get_base_width(target)
    local height = obs.obs_source_get_base_height(target)

    if width == 0 or height == 0 then
        obs.obs_source_skip_video_filter(data.source)
        return
    end

    -- Calculate UV offsets from zoom + pan
    local inv_zoom = 1.0 / data.zoom_factor
    local ox = data.pan_x * (1.0 - inv_zoom)
    local oy = data.pan_y * (1.0 - inv_zoom)

    -- Render source to texture
    if not obs.obs_source_process_filter_begin(data.source, obs.GS_RGBA, obs.OBS_NO_DIRECT_RENDERING) then
        return
    end

    -- Set shader parameters
    obs.gs_effect_set_float(data.params.zoom_factor, data.zoom_factor)
    obs.gs_effect_set_float(data.params.offset_x, ox)
    obs.gs_effect_set_float(data.params.offset_y, oy)

    -- Draw with zoom shader
    obs.obs_source_process_filter_end(data.source, data.effect, width, height)
end

-- ============================================================
-- Output dimensions (same as input — zoom doesn't change size)
-- ============================================================
source_info.get_width = function(data)
    local target = obs.obs_filter_get_target(data.source)
    if target == nil then return 0 end
    return obs.obs_source_get_base_width(target)
end

source_info.get_height = function(data)
    local target = obs.obs_filter_get_target(data.source)
    if target == nil then return 0 end
    return obs.obs_source_get_base_height(target)
end

-- ============================================================
-- Filter properties (shown in filter settings UI)
-- ============================================================
source_info.get_properties = function(data)
    local props = obs.obs_properties_create()
    obs.obs_properties_add_float_slider(props, "zoom_factor", "Zoom Level", 1.0, 10.0, 0.25)
    obs.obs_properties_add_float_slider(props, "pan_x", "Pan Horizontal (Left <-> Right)", 0.0, 1.0, 0.01)
    obs.obs_properties_add_float_slider(props, "pan_y", "Pan Vertical (Top <-> Bottom)", 0.0, 1.0, 0.01)
    obs.obs_properties_add_float_slider(props, "zoom_step", "Zoom Step (per hotkey press)", 0.05, 1.0, 0.05)
    obs.obs_properties_add_float_slider(props, "pan_step", "Pan Step (per hotkey press)", 0.01, 0.2, 0.01)
    return props
end

-- ============================================================
-- Default settings
-- ============================================================
source_info.get_defaults = function(settings)
    obs.obs_data_set_default_double(settings, "zoom_factor", 1.0)
    obs.obs_data_set_default_double(settings, "pan_x", 0.5)
    obs.obs_data_set_default_double(settings, "pan_y", 0.5)
    obs.obs_data_set_default_double(settings, "zoom_step", 0.25)
    obs.obs_data_set_default_double(settings, "pan_step", 0.05)
end

-- ============================================================
-- Script description
-- ============================================================
function script_description()
    return [[
<h2>Webcam Zoom Filter</h2>
<p>Adds a <b>Webcam Zoom</b> filter you can apply to any video source.</p>
<p>Right-click a source &rarr; Filters &rarr; + &rarr; Webcam Zoom</p>
<p>Each source gets its own independent zoom and pan controls.</p>
<p>Hotkeys are registered per-source in Settings &rarr; Hotkeys.</p>
]]
end

-- ============================================================
-- Register the filter when script loads
-- ============================================================
function script_load(settings)
    obs.obs_register_source(source_info)
end
