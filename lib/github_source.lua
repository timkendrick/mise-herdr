local cmd = require("cmd")
local semver = require("semver")
local strings = require("strings")
local shell_command = require("shell_command")

local M = {}

local SHORT_COMMIT_LENGTH = 7
local GIT_ENV = { GIT_TERMINAL_PROMPT = "0" }

---@class GithubSource
---@field owner string
---@field repo string
---@field subdir string|nil Path of the plugin directory inside the repository

---@class RemoteRefs
---@field head string Full commit SHA of the default branch
---@field tags string[] Tag names

--- @param label string
--- @param value string
local function validate_github_segment(label, value)
    if value == "" or value == "." or value == ".." or not value:match("^[%w%._%-]+$") then
        error("invalid GitHub " .. label .. ": '" .. value .. "'")
    end
end

--- @param value string
local function validate_subdir_segment(value)
    if value == "" or value == "." or value == ".." or value:find("\\", 1, true) then
        error("invalid plugin subdirectory segment: '" .. value .. "'")
    end
end

--- Parses a tool name of the form `owner/repo[/subdir...]`.
--- @param tool string
--- @return GithubSource
function M.parse(tool)
    local parts = strings.split(tool, "/")
    if #parts < 2 then
        error("expected a tool name of the form owner/repo[/subdir], got '" .. tool .. "'")
    end
    validate_github_segment("owner", parts[1])
    validate_github_segment("repository", parts[2])
    local subdir_parts = {}
    for index = 3, #parts do
        validate_subdir_segment(parts[index])
        table.insert(subdir_parts, parts[index])
    end
    return {
        owner = parts[1],
        repo = parts[2],
        subdir = #subdir_parts > 0 and table.concat(subdir_parts, "/") or nil,
    }
end

--- @param source GithubSource
--- @return string
function M.remote_url(source)
    return "https://github.com/" .. source.owner .. "/" .. source.repo .. ".git"
end

--- Lists the default branch commit and the tags of the source repository.
--- @param source GithubSource
--- @return RemoteRefs
function M.list_remote_refs(source)
    local url = M.remote_url(source)
    local ok, output =
        pcall(cmd.exec, "git ls-remote " .. shell_command.quote(url) .. " HEAD 'refs/tags/*'", { env = GIT_ENV })
    if not ok then
        error("could not list refs of " .. url .. ": " .. tostring(output))
    end
    local head = nil
    local tags = {}
    for line in output:gmatch("[^\r\n]+") do
        local sha, ref = line:match("^(%x+)%s+(%S+)$")
        if ref == "HEAD" then
            head = sha
        elseif ref ~= nil then
            local tag = ref:match("^refs/tags/(.+)$")
            if tag ~= nil and not strings.has_suffix(tag, "^{}") then
                table.insert(tags, tag)
            end
        end
    end
    if head == nil then
        error("repository " .. url .. " has no default branch")
    end
    return { head = head, tags = tags }
end

--- @param refs RemoteRefs
--- @param tag string
--- @return boolean
local function has_tag(refs, tag)
    for _, candidate in ipairs(refs.tags) do
        if candidate == tag then
            return true
        end
    end
    return false
end

--- @param refs RemoteRefs
--- @return string
local function short_head(refs)
    return refs.head:sub(1, SHORT_COMMIT_LENGTH)
end

--- Lists installable versions, oldest first.
--- Release tags of the form `vX.Y.Z` or `X.Y.Z` are listed without the `v` prefix.
--- A repository without release tags lists the abbreviated default branch commit.
--- @param refs RemoteRefs
--- @return string[]
function M.versions(refs)
    local seen = {}
    local versions = {}
    for _, tag in ipairs(refs.tags) do
        local version = tag:match("^v?(%d+%.%d+%.%d+)$")
        if version ~= nil and not seen[version] then
            seen[version] = true
            table.insert(versions, version)
        end
    end
    if #versions == 0 then
        return { short_head(refs) }
    end
    return semver.sort(versions)
end

--- Resolves a requested version to a git ref that can be fetched.
--- @param refs RemoteRefs
--- @param version string
--- @return string
function M.resolve_ref(refs, version)
    local requested = version:match("^ref:(.+)$") or version
    if has_tag(refs, requested) then
        return "refs/tags/" .. requested
    end
    if has_tag(refs, "v" .. requested) then
        return "refs/tags/v" .. requested
    end
    if requested == short_head(refs) then
        return refs.head
    end
    if requested:match("^%x+$") and #requested < 40 and #requested >= SHORT_COMMIT_LENGTH then
        error(
            "cannot fetch abbreviated commit '"
                .. requested
                .. "': it is not the current default branch commit. Use the full 40-character SHA."
        )
    end
    return requested
end

--- Fetches a single ref of the source repository into an empty checkout directory.
--- @param source GithubSource
--- @param ref string
--- @param checkout_dir string
function M.fetch(source, ref, checkout_dir)
    shell_command.reset_dir(checkout_dir)
    local git = "git -C " .. shell_command.quote(checkout_dir) .. " "
    local command = git
        .. "init -q && "
        .. git
        .. "remote add origin "
        .. shell_command.quote(M.remote_url(source))
        .. " && "
        .. git
        .. "fetch -q --depth 1 origin "
        .. shell_command.quote(ref)
        .. " && "
        .. git
        .. "checkout -q --detach FETCH_HEAD"
    local ok, err = pcall(cmd.exec, command, { env = GIT_ENV })
    if not ok then
        error("could not fetch '" .. ref .. "' from " .. M.remote_url(source) .. ": " .. tostring(err))
    end
end

return M
