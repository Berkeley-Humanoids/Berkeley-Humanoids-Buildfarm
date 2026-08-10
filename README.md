# Berkeley Humanoids Buildfarm

This repository builds the ROS packages that RoboStack does not carry, and
uploads them to the [prefix.dev](https://prefix.dev) channel
`berkeley-humanoids`. The product repositories install the binaries with
`pixi add`. They do not clone or build these sources.

A conda package has the name `ros-jazzy-<package name with dashes>`. For
example, `joy_teleop` becomes `ros-jazzy-joy-teleop`.

The build chain is
[`pixi-build-ros`](https://pixi.prefix.dev/latest/build/backends/pixi-build-ros/)
into `rattler-build` into a `.conda` file.

## What belongs here

This repository builds **only packages that we do not author**: upstream
packages that RoboStack skipped, and our maintenance forks of other people's
packages.

| Package | Published by |
|---|---|
| `humanoid_*`, `specialist_*`, `pianist_*` | the product repository that holds it |
| `lite_description`, and other descriptions we author | the description repository that holds it |
| `teleop_tools`, `mujoco_*`, `ethercat_*`, `libethercat` | **this repository** |

The rule exists because a conda package name has no owner. If two repositories
both publish `ros-jazzy-mujoco-sim-ros2`, the upload skips whichever arrives
second and reports success, so one repository silently builds against the
other's commit. One publisher per package name prevents this.

Prefer upstreaming over adding a package here. `teleop_tools` is an official
`ros-teleop` package that RoboStack has not picked up. A RoboStack recipe would
serve everybody, and would remove it from this list. Keep this repository for what
RoboStack will not take.

> **`lite_description` is here temporarily.** We author it, so it belongs to
> `Berkeley-Humanoids/Lite-Description`. It stays here until that repository has
> a publish workflow, because removing it first would stop it reaching the
> channel.

## No sources are cloned

Each directory under `deps/` holds one manifest, and that manifest names the git
source of the package:

```toml
[package.build.source]
git = "https://github.com/ros-teleop/teleop_tools.git"
rev = "99d16d74c16e044a7cf10cb3300579eb27cca807"
subdirectory = "joy_teleop"

[package.build.backend]
name = "pixi-build-ros"
version = "==0.5.0"
channels = ["https://prefix.dev/conda-forge"]

[package.build.config]
distro = "jazzy"
```

pixi fetches the source during the build. The backend reads the name, the
version, and the dependencies from the upstream `package.xml` in that
subdirectory. Upstream needs no manifest of its own, and this repository holds
no copy of any source.

To debug a build, point the manifest at a local checkout for a moment. Change
the source block to `path = "/path/to/checkout"` and build again.

## Build the packages on your computer

No account is needed.

```bash
pixi run package                  # -> output/*.conda, linux-64
pixi run package linux-aarch64
```

Upload them, with `PREFIX_API_KEY` set:

```bash
pixi run publish
```

### Install the result without uploading it

Index the output into a channel of its own. Do not reuse `local-channel`:
`build.sh` empties that one.

```bash
mkdir -p test-channel/linux-64 && find output -name '*.conda' -exec cp {} test-channel/linux-64/ \;
pixi exec --spec conda-index -- python -m conda_index test-channel

pixi init /tmp/consume -c "file://$PWD/test-channel" \
                       -c https://prefix.dev/robostack-jazzy \
                       -c https://prefix.dev/conda-forge
cd /tmp/consume && pixi add ros-jazzy-joy-teleop
```

## Add a package

1. Create `deps/<name>/pixi.toml` with the block shown above. Pin `rev` to a
   commit. Use `branch` only for a repository that we control.
2. Add the path to `packages.txt`, **after everything it needs**.
3. Run `pixi run package` and check that it builds.
4. Open a pull request. The merge to `main` builds and uploads it.

If the package needs something that a `package.xml` cannot state, add it to the
manifest. Two cases occur:

- A CMake `find_package()` or `find_library()` dependency that is not a rosdep.
  Add it to `[package.host-dependencies]`, as `ethercat_interface` does for
  `libethercat`.
- A build tool. Add it to `[package.build-dependencies]`, as `mujoco_ament` does
  for `patchelf`.

## Layout

```
Berkeley-Humanoids-Buildfarm/
├── pixi.toml             # the build workspace: channels, dependencies, tasks
├── pixi.lock             # committed, for a reproducible toolchain
├── packages.txt          # what the buildfarm builds, in dependency order
├── local-channel/        # committed empty index, filled during a build
├── deps/                 # one manifest per package, each naming a git source
├── recipes/              # rattler-build recipes for packages that are not ROS packages
└── scripts/              # build, publish
```

## Constraints

### A moved fork needs a new version

The upload skips a package that the channel already holds, and never replaces
one. A rebuild at an unchanged version therefore publishes nothing and reports
success.

This matters for a fork that follows `branch = "main"`. If you patch the fork
but leave its `package.xml` version alone, the buildfarm rebuilds it and the
upload drops the result. **Raise the version in the fork's `package.xml` with
every patch.** We own those forks, so this costs one line.

### A chain builds in one run, through ./local-channel

`pixi build` reads build dependencies from a channel, and it has no `--channel`
option. A git-source package cannot serve as a source dependency either. A
package can therefore build only against what a channel already holds.

`scripts/build.sh` works around this. After it builds a package, it copies the
result into `./local-channel` and indexes it. The workspace lists that directory
as its first channel, so the next package in `packages.txt` builds against
everything above it. A whole chain therefore builds in one run:
`libethercat` into `ethercat_interface` into the rest, and `mujoco_ament` into
`mujoco_sim_ros2` into `mujoco_ros2_control`.

**The order of `packages.txt` matters.** Put a package after everything it needs.

`local-channel` is committed with an empty index, and `build.sh` empties it
again when it finishes. pixi reads every channel before it runs any task, so the
directory has to exist and carry a valid `repodata.json` on a fresh clone. The
`.conda` files it holds during a build are ignored by git.

### Toolchain pins

`pixi` is pinned to `v0.70.1` in the workflow. The `pixi-build-ros` backend is
pinned to `==0.5.0` in every manifest. A floating version pulled a nightly
backend that broke the build API. Change the two pins together.

`pixi build` is deprecated in favour of `pixi publish`, but it works in the
pinned version. Change it deliberately, and test both architectures.

### The channel keeps old packages

`rattler-build upload` never deletes. Remove a package on the prefix.dev web
page.

## Setup

The workflow needs one secret on this repository:

- `PREFIX_API_KEY`, to upload to prefix.dev. prefix.dev trusted publishing works
  instead. The job already requests `id-token: write`.
