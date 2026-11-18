local file = require("file")
local log = require("log")
local github_source = require("github_source")
local herdr_cli = require("herdr_cli")
local install_record = require("install_record")
local shell_command = require("shell_command")

--- @param path string
--- @return string
local function parent_dir(path)
    local parent = path:match("^(.*)/[^/]+/*$")
    if parent == nil or parent == "" then
        error("path has no parent directory: " .. path)
    end
    return parent
end

--- @param plugin HerdrPlugin
--- @return string
local function describe_registration(plugin)
    if plugin.source_kind == "local" then
        return "linked from " .. plugin.plugin_root
    end
    return "installed by herdr (" .. plugin.source_kind .. ") at " .. plugin.plugin_root
end

--- Installs a herdr plugin from GitHub, builds it, and links it into herdr.
--- @param ctx BackendInstallCtx
--- @return BackendInstallResult
function PLUGIN:BackendInstall(ctx)
    herdr_cli.current_platform()
    local source = github_source.parse(ctx.tool)
    local ref = github_source.resolve_ref(github_source.list_remote_refs(source), ctx.version)

    local checkout_dir = file.join_path(ctx.install_path, "checkout")
    github_source.fetch(source, ref, checkout_dir)
    local plugin_dir = checkout_dir
    if source.subdir ~= nil then
        plugin_dir = file.join_path(checkout_dir, source.subdir)
    end
    if not file.exists(file.join_path(plugin_dir, "herdr-plugin.toml")) then
        error("no herdr-plugin.toml found in " .. ctx.tool .. " at " .. ref)
    end

    local manifest = herdr_cli.read_manifest(plugin_dir)
    herdr_cli.run_build_steps(manifest, plugin_dir)

    local existing = herdr_cli.find_registered(manifest.plugin_id)
    local enabled = true
    if existing ~= nil then
        enabled = existing.enabled
        local tool_installs_dir = shell_command.canonical_dir(parent_dir(ctx.install_path)) .. "/"
        local owned = existing.source_kind == "local"
            and existing.plugin_root:sub(1, #tool_installs_dir) == tool_installs_dir
        if not owned then
            log.warn(
                manifest.plugin_id
                    .. " was "
                    .. describe_registration(existing)
                    .. "; replacing it with "
                    .. ctx.tool
                    .. "@"
                    .. ctx.version
            )
        end
    end

    local linked = herdr_cli.link(plugin_dir, enabled)
    install_record.write(ctx.install_path, { plugin_id = linked.plugin_id, plugin_root = linked.plugin_root })
    return {}
end
