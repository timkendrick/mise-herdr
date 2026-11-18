local github_source = require("github_source")

--- Lists the installable versions of a herdr plugin repository.
--- @param ctx BackendListVersionsCtx
--- @return BackendListVersionsResult
function PLUGIN:BackendListVersions(ctx)
    local source = github_source.parse(ctx.tool)
    return { versions = github_source.versions(github_source.list_remote_refs(source)) }
end
