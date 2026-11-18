local cmd = require("cmd")
local json = require("json")
local shell_command = require("shell_command")

local M = {}

---@alias HerdrPlatform "linux"|"macos"|"windows"

---@class HerdrBuildStep
---@field command string[]
---@field platforms HerdrPlatform[]|nil

---@class HerdrPlugin
---@field plugin_id string
---@field plugin_root string
---@field enabled boolean
---@field platforms HerdrPlatform[]|nil
---@field build HerdrBuildStep[]
---@field source_kind string

--- @param value any
--- @param context string
--- @return string
local function expect_string(value, context)
    if type(value) ~= "string" then
        error("unexpected herdr output: " .. context .. " is not a string")
    end
    return value
end

--- @param value any
--- @param context string
--- @return string[]
local function expect_string_list(value, context)
    if type(value) ~= "table" then
        error("unexpected herdr output: " .. context .. " is not a list")
    end
    local items = {}
    for index, item in ipairs(value) do
        table.insert(items, expect_string(item, context .. "[" .. index .. "]"))
    end
    return items
end

--- @param value any
--- @param context string
--- @return HerdrPlatform[]|nil
local function optional_platforms(value, context)
    if type(value) ~= "table" then
        return nil
    end
    local platforms = {}
    for index, name in ipairs(expect_string_list(value, context)) do
        if name ~= "linux" and name ~= "macos" and name ~= "windows" then
            error("unexpected herdr output: " .. context .. "[" .. index .. "] is not a known platform")
        end
        table.insert(platforms, name)
    end
    return platforms
end

--- @param value any
--- @return HerdrPlugin
local function decode_plugin(value)
    if type(value) ~= "table" then
        error("unexpected herdr output: plugin is not an object")
    end
    local build = {}
    if type(value.build) == "table" then
        for index, step in ipairs(value.build) do
            local context = "build[" .. index .. "]"
            if type(step) ~= "table" then
                error("unexpected herdr output: " .. context .. " is not an object")
            end
            table.insert(build, {
                command = expect_string_list(step.command, context .. ".command"),
                platforms = optional_platforms(step.platforms, context .. ".platforms"),
            })
        end
    end
    if type(value.enabled) ~= "boolean" then
        error("unexpected herdr output: enabled is not a boolean")
    end
    local source_kind = "local"
    if type(value.source) == "table" then
        source_kind = expect_string(value.source.kind, "source.kind")
    end
    return {
        plugin_id = expect_string(value.plugin_id, "plugin_id"),
        plugin_root = expect_string(value.plugin_root, "plugin_root"),
        enabled = value.enabled,
        platforms = optional_platforms(value.platforms, "platforms"),
        build = build,
        source_kind = source_kind,
    }
end

--- Runs a herdr command and returns the `result` object of its JSON response.
--- @param command string
--- @return table
local function request(command)
    local ok, output = pcall(shell_command.exec, command)
    if not ok then
        error("herdr command failed: " .. tostring(output))
    end
    local decoded_ok, response = pcall(json.decode, output)
    if not decoded_ok or type(response) ~= "table" then
        error("unexpected herdr output: " .. output)
    end
    if type(response.error) == "table" then
        error("herdr command failed: " .. tostring(response.error.message))
    end
    if type(response.result) ~= "table" then
        error("unexpected herdr output: " .. output)
    end
    return response.result
end

--- @return HerdrPlatform
function M.current_platform()
    if RUNTIME.osType == "darwin" then
        return "macos"
    elseif RUNTIME.osType == "linux" then
        return "linux"
    end
    error("unsupported operating system: " .. RUNTIME.osType .. " (supported: macOS, Linux)")
end

--- Validates a plugin manifest by linking it into a throwaway herdr configuration.
--- @param plugin_dir string
--- The throwaway configuration lives in a short temporary path, because herdr derives a Unix socket path from it.
--- @return HerdrPlugin
function M.read_manifest(plugin_dir)
    local scratch_dir = shell_command.make_temp_dir()
    local command = shell_command.unset_herdr_runtime_env()
        .. "XDG_CONFIG_HOME="
        .. shell_command.quote(scratch_dir)
        .. " XDG_STATE_HOME="
        .. shell_command.quote(scratch_dir .. "/state")
        .. " "
        .. shell_command.join({ "herdr", "plugin", "link", plugin_dir, "--disabled" })
    local ok, result = pcall(request, command)
    shell_command.remove_dir(scratch_dir)
    if not ok then
        error("invalid herdr plugin at " .. plugin_dir .. ": " .. tostring(result))
    end
    return decode_plugin(result.plugin)
end

--- @param plugin HerdrPlugin
--- @return HerdrBuildStep[]
function M.applicable_build_steps(plugin)
    local platform = M.current_platform()
    local steps = {}
    for _, step in ipairs(plugin.build) do
        local platforms = step.platforms or plugin.platforms
        local applies = platforms == nil
        for _, candidate in ipairs(platforms or {}) do
            if candidate == platform then
                applies = true
            end
        end
        if applies then
            table.insert(steps, step)
        end
    end
    return steps
end

--- Runs the build steps of a plugin that apply to the current platform.
--- @param plugin HerdrPlugin
--- @param plugin_dir string
function M.run_build_steps(plugin, plugin_dir)
    local steps = M.applicable_build_steps(plugin)
    for index, step in ipairs(steps) do
        local command_line = shell_command.join(step.command)
        print(string.format("%s: build %d/%d: %s", plugin.plugin_id, index, #steps, command_line))
        local ok, err =
            pcall(shell_command.exec, shell_command.unset_herdr_runtime_env() .. command_line, { cwd = plugin_dir })
        if not ok then
            error(string.format("%s: build %d/%d failed: %s", plugin.plugin_id, index, #steps, tostring(err)))
        end
    end
end

--- Looks up a plugin in the herdr plugin registry.
--- @param plugin_id string
--- @return HerdrPlugin|nil
function M.find_registered(plugin_id)
    local result = request(shell_command.join({ "herdr", "plugin", "list", "--json", "--plugin", plugin_id }))
    if type(result.plugins) ~= "table" then
        error("unexpected herdr output: plugins is not a list")
    end
    for _, value in ipairs(result.plugins) do
        local plugin = decode_plugin(value)
        if plugin.plugin_id == plugin_id then
            return plugin
        end
    end
    return nil
end

--- Registers a local plugin directory with herdr.
--- @param plugin_dir string
--- @param enabled boolean
--- @return HerdrPlugin
function M.link(plugin_dir, enabled)
    local argv = { "herdr", "plugin", "link", plugin_dir, enabled and "--enabled" or "--disabled" }
    return decode_plugin(request(shell_command.join(argv)).plugin)
end

--- Removes a plugin from the herdr plugin registry without deleting its files.
--- @param plugin_id string
function M.unregister(plugin_id)
    local ok, err = pcall(cmd.exec, shell_command.join({ "herdr", "plugin", "uninstall", plugin_id }))
    if not ok then
        error("could not unregister herdr plugin " .. plugin_id .. ": " .. tostring(err))
    end
end

return M
