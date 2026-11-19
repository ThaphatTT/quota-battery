# Release plan

This folder will hold the release scripts. For now it holds only this plan. No script exists yet, and nothing in this folder runs.

## Flow

1. Build the app as a Release build, signed ad hoc or with a free Apple ID. No paid Developer ID is used.
2. Pack the app into a drag-to-Applications `.dmg`: the app next to a link to `/Applications`.
3. Upload the `.dmg` to GitHub Releases with `gh release create`.

The version number comes from `MARKETING_VERSION` in `mac/project.yml`.

## Rules

- The `.dmg` is never committed to the repository. It is attached to a GitHub Release only.
- A Team id and a signing identity are never committed (see `AGENTS.md`).
- `scripts/build-mac.sh` stays the build for your own Mac, signed with your own Team id. The release build is a separate step.

## What users must do

The app has no Developer ID signature and is not notarized, so macOS blocks it the first time it is opened. Each user must allow it once:

1. Open the app. macOS blocks it.
2. Open System Settings › Privacy & Security, and click **Open Anyway** next to the app's name.

## Not yet tested

Widget loading from such a build is still untested. Do not promise users that the widget works from this build until it has been tested on a clean Mac.
