local file = require("file")
local json = require("json")

local M = {}

local RECORD_FILENAME = "herdr-mise.json"

---@class InstallRecord
---@field plugin_id string
---@field plugin_root string Plugin directory as registered with herdr

--- @param install_path string
--- @return string
local function record_path(install_path)
    return file.join_path(install_path, RECORD_FILENAME)
end

--- @param install_path string
--- @param record InstallRecord
function M.write(install_path, record)
    local path = record_path(install_path)
    local handle, err = io.open(path, "w")
    if handle == nil then
        error("could not write " .. path .. ": " .. tostring(err))
    end
    handle:write(json.encode({ plugin_id = record.plugin_id, plugin_root = record.plugin_root }))
    handle:close()
end

--- Reads the record of an install, or returns nil when the install did not complete.
--- @param install_path string
--- @return InstallRecord|nil
function M.read(install_path)
    local path = record_path(install_path)
    if not file.exists(path) then
        return nil
    end
    local ok, value = pcall(json.decode, file.read(path))
    if not ok or type(value) ~= "table" then
        error("invalid install record: " .. path)
    end
    if type(value.plugin_id) ~= "string" or type(value.plugin_root) ~= "string" then
        error("invalid install record: " .. path)
    end
    return { plugin_id = value.plugin_id, plugin_root = value.plugin_root }
end

return M
