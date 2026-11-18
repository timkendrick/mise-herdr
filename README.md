# mise-herdr

A [mise](https://mise.jdx.dev) backend plugin that manages [herdr](https://herdr.dev) plugins declaratively.

Install herdr plugins in `mise.toml` instead of running `herdr plugin install` by hand:

```toml
[tools]
"aqua:herdrdev/herdr" = "latest"
"herdr:plannotator/herdr-annotate" = "latest"
"herdr:beyondlex/herdr-recent-navigator" = "0.8.0"
"herdr:ogulcancelik/herdr-plugin-examples/agent-telegram-notify" = "latest"
```

Plugins are downloaded from GitHub into the mise install directory, built, and linked into herdr with `herdr plugin link`.

## Install the plugin

```sh
mise plugin install herdr https://github.com/timkendrick/mise-herdr
```

Each herdr plugin is then available as `herdr:<owner>/<repo>`. If the plugin is in a subdirectory of the repository, add the subdirectory: `herdr:<owner>/<repo>/<subdir>`. This is the same source format that `herdr plugin install` accepts.

### The herdr CLI tool name

When this plugin is installed as `herdr`, mise reads the bare tool name `herdr` as a reference to the plugin, not to the herdr CLI.

Install the CLI with its full backend name instead:

```toml
[tools]
# Before
herdr = "latest"

# After
"aqua:herdrdev/herdr" = "latest"
```

The plugin runs the `herdr` CLI to validate and link plugins. If `"aqua:herdrdev/herdr"` is in your config, mise installs it first and puts it on `PATH` for the plugin. Otherwise the plugin uses the `herdr` on your `PATH`.

## Versions

The plugin uses the release tags of the GitHub repository as versions. A release tag has the form `vX.Y.Z` or `X.Y.Z`. The plugin removes the `v` prefix.

Some repositories have no release tags. Other repositories have only tags with another form, such as `beta/v0.4.23-beta.1` or `rust-lite-v0.2.4`. For these repositories, the only version is the abbreviated commit hash of the default branch, such as `eab9400`.

| mise version | Installs |
| --- | --- |
| `0.8.0` | The tag `v0.8.0` or `0.8.0` |
| `latest` | The newest release tag, or the current commit of the default branch if the repository has no release tags |
| `eab9400` | The current commit of the default branch, if it is `eab9400` |
| `main` or `ref:main` | The current commit of the branch `main` |
| `v1.0.0-rc.1` | Any tag of the repository, by its full name |
| `5940b98ed52b8f87404699bda61eb46badd83605` | The commit with this full hash |

`mise ls-remote herdr:<owner>/<repo>` lists the versions, for example:

```sh
$ mise ls-remote herdr:beyondlex/herdr-recent-navigator
0.1.0
0.2.0
...
0.8.0

$ mise ls-remote herdr:plannotator/herdr-annotate
dd147a9
```

The plugin does not read the `version` field of `herdr-plugin.toml`. This field can be different from the release tags.

## How install works

For `"herdr:plannotator/herdr-annotate" = "latest"`, install does these steps:

1. List the tags and the default branch commit of `https://github.com/plannotator/herdr-annotate.git` with `git ls-remote`.
2. Find the git ref for the version. Here the repository has no release tags, so `latest` is the default branch commit.
3. Fetch only that commit into `checkout/` in the mise install directory, such as `~/.local/share/mise/installs/herdr-plannotator-herdr-annotate/dd147a9/checkout/`. The checkout keeps its `.git` directory.
4. Validate `herdr-plugin.toml` with herdr. The plugin links the checkout into a temporary herdr configuration, so your herdr configuration does not change. herdr rejects the plugin here if it needs a newer herdr version.
5. Run the `[[build]]` commands of the manifest that apply to the current platform, in the plugin directory. These are the same commands that `herdr plugin install` runs. If a command fails, install fails.
6. Link the plugin directory into herdr with `herdr plugin link`. If a herdr server is running, it uses the plugin immediately.
7. Write `herdr-mise.json` in the install directory. This file records the plugin id and the linked directory for uninstall.

For a plugin in a subdirectory, the plugin fetches the whole repository and links the subdirectory. Build commands can use files outside the subdirectory, as they can with `herdr plugin install`.

The plugin does not add anything to `PATH`. Binaries that a plugin keeps in its own `bin/` directory stay private to herdr.

### Enabled state

`herdr plugin link` enables a plugin by default. If herdr already has the plugin and it is disabled, install links the new version as disabled. Use `herdr plugin enable` and `herdr plugin disable` to change the state.

### Replace an installed plugin

herdr registers one plugin for each plugin id. If herdr already has the plugin from another source, install replaces it and shows a warning such as:

```text
annotate was installed by herdr (github) at ~/.config/herdr/plugins/github-installations/annotate-4e1d0c6a8b2f/68957-0/checkout; replacing it with plannotator/herdr-annotate@dd147a9
```

To move a plugin from `herdr plugin install` to mise, add it to `mise.toml` and run `mise install`. herdr removes the old installation files later, when no herdr server uses them.

There is no warning when install replaces another mise install of the same tool, for example during `mise upgrade`.

## How uninstall works

`mise uninstall` and `mise prune` unregister the plugin from herdr, but only if herdr still uses the version that mise removes. For example, `mise upgrade` installs and links the new version first. Then it removes the old version, and herdr keeps the new version.

Uninstall does not remove the config and state directories of the plugin. `herdr plugin uninstall` also keeps these directories.

## Platforms

The plugin supports macOS and Linux. It needs `git` and the `herdr` CLI. Build commands can need more tools, such as `cargo`, `npm` or `bash`. Windows is not supported.

## Limitations

- **Moving refs:** a branch version such as `main` is fixed when mise installs it. mise does not install it again when the branch changes. To get the new commit, run `mise install --force herdr:<owner>/<repo>@main`.
- **Abbreviated commit versions:** GitHub fetches commits only by full hash. After the default branch moves, an abbreviated commit version such as `eab9400` cannot be installed again, for example from a lockfile on a new machine. Use `latest` or a full commit hash instead.
- **No release dates:** versions have no release date. mise shows a warning for each install if [`minimum_release_age`](https://mise.jdx.dev/configuration/settings.html#minimum_release_age) is set, and allows the version.
- **Changes in herdr:** mise does not detect changes that you make with the herdr CLI. If you run `herdr plugin uninstall`, run `mise install --force herdr:<owner>/<repo>` to link the plugin again.
- **Updates in herdr:** `herdr plugin update` does not update linked plugins. Use `mise upgrade` instead.
- **Running plugin commands:** `mise upgrade` removes the files of the old version. A plugin command or pane that still runs from the old version can fail. `herdr plugin update` keeps old files until no herdr server uses them.

## Development

Link your working copy:

```sh
mise plugin link --force herdr .
```

| Task | Description |
| --- | --- |
| `mise run test` | Install, upgrade and uninstall real herdr plugins from GitHub in an isolated mise and herdr environment |
| `mise run lint` | Check formatting, types and GitHub Actions workflows |
| `mise run ci` | Run all checks |

The test uses a temporary `XDG_CONFIG_HOME`, so it does not change your herdr configuration. It needs network access, `git`, `herdr`, `jq` and `cargo`. Use `mise run test -- --keep` to keep the temporary directory.

## License

MIT
