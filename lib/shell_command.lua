local cmd = require("cmd")
local strings = require("strings")

local M = {}

--- Environment variables that connect a process to a running herdr server or plugin invocation.
local HERDR_RUNTIME_ENV_VARS = {
    "HERDR_SOCKET_PATH",
    "HERDR_CLIENT_SOCKET_PATH",
    "HERDR_SESSION",
    "HERDR_BIN_PATH",
    "HERDR_ENV",
    "HERDR_WORKSPACE_ID",
    "HERDR_TAB_ID",
    "HERDR_PANE_ID",
}

--- Quotes a value as a single POSIX shell word.
--- @param value string
--- @return string
function M.quote(value)
    return "'" .. (string.gsub(value, "'", "'\\''")) .. "'"
end

--- Quotes each argument and joins them into a POSIX shell command line.
--- @param argv string[]
--- @return string
function M.join(argv)
    local words = {}
    for _, arg in ipairs(argv) do
        table.insert(words, M.quote(arg))
    end
    return table.concat(words, " ")
end

--- Shell prefix that removes herdr server and plugin runtime variables from the environment.
--- @return string
function M.unset_herdr_runtime_env()
    return "unset "
        .. table.concat(HERDR_RUNTIME_ENV_VARS, " ")
        .. "; for name in $(env | sed -n 's/^\\(HERDR_PLUGIN_[A-Za-z0-9_]*\\)=.*/\\1/p'); do unset \"$name\"; done; "
end

--- Runs a shell command and returns its stdout.
--- On failure, the error message includes both stdout and stderr.
--- @param command string
--- @param opts? CmdExecOpts
--- @return string
function M.exec(command, opts)
    local wrapped = "if output=$("
        .. command
        .. "); then printf '%s\\n' \"$output\"; "
        .. 'else status=$?; printf \'%s\\n\' "$output" >&2; exit "$status"; fi'
    return cmd.exec(wrapped, opts or {})
end

--- Removes a directory tree if it exists, then creates an empty directory at the same path.
--- @param path string
function M.reset_dir(path)
    cmd.exec("rm -rf " .. M.quote(path) .. " && mkdir -p " .. M.quote(path))
end

--- Creates a new empty directory in the system temporary directory.
--- @return string
function M.make_temp_dir()
    return strings.trim_space(cmd.exec('mktemp -d "${TMPDIR:-/tmp}/mise-herdr.XXXXXX"'))
end

--- Removes a directory tree if it exists.
--- @param path string
function M.remove_dir(path)
    cmd.exec("rm -rf " .. M.quote(path))
end

--- Resolves symlinks in the path of an existing directory.
--- @param path string
--- @return string
function M.canonical_dir(path)
    return strings.trim_space(cmd.exec("cd " .. M.quote(path) .. " && pwd -P"))
end

return M
