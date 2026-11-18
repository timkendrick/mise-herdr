local herdr_cli = require("herdr_cli")
local install_record = require("install_record")

--- Unregisters the plugin from herdr when herdr still uses this install.
--- @param ctx BackendUninstallCtx
function PLUGIN:BackendUninstall(ctx)
    local record = install_record.read(ctx.install_path)
    if record == nil then
        return
    end
    local registered = herdr_cli.find_registered(record.plugin_id)
    if registered ~= nil and registered.plugin_root == record.plugin_root then
        herdr_cli.unregister(record.plugin_id)
    end
end
