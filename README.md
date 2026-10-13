# eve-hardlink-repro

Minimal reproduction: `eve build` fails when the project's `.eve` directory is on a filesystem that doesn't support hard links.

The compiler writes the authored module map to a temp file and publishes it with `fs.promises.link(tmp, final)`. It only tolerates `EEXIST`, so on any filesystem where `link()` fails (some NFS servers, FUSE mounts, managed storage), the build fails:

```
EPERM: operation not permitted, link '…/.eve/builds/<id>/compiler/.eve/compile/authored-module-map-<sha256>.mjs.<uuid>.tmp' -> '…/.eve/builds/<id>/compiler/.eve/compile/authored-module-map-<sha256>.mjs'
```

The code is in `eve/dist/src/internal/authored-module-map-loader.js` (`hydrateCompiledModuleMapFromManifest`), in eve 0.78.0 and 0.79.0. It only runs when the agent mounts an extension, which is why this app mounts one.

The original failure was on an NFSv4 mount (AWS Bedrock AgentCore Runtime session storage), where `link()` fails with Linux errno 524 (`ENOTSUPP`). This repro uses a FAT image instead because it can be mounted on any Linux machine or CI runner.

## The app

- `agent/agent.ts`, `agent/instructions.md`: a minimal agent. The model is never called.
- `agent/tools/echo.ts`: one tool.
- `agent/extensions/github.ts`: mounts a public extension (`@github-tools/eve-extension`). Any mounted extension takes the failing code path.

## Run it

**CI:** the [repro workflow](../../actions/workflows/repro.yml) runs three jobs on `ubuntu-latest`:

| Job | What it does | Expected |
|---|---|---|
| `normal` | `eve build` on the runner's normal disk | ✅ passes |
| `nolinks` | `eve build` with `.eve` mounted on a FAT image (no hard links) | ❌ fails with the `link()` error |
| `patched` | same as `nolinks`, with the suggested fallback below applied to `node_modules/eve` | ✅ passes |

**Locally (Docker):**

```sh
./repro.sh
```

This runs the same three cases in `node:24-bookworm`. `--privileged` is required for the loop mount.

**Note on the FAT mount:** only `.eve` is on the FAT image, because FAT also lacks symlinks and `npm ci` needs them for `node_modules/.bin`. NFS supports symlinks, so this isn't needed there. Because `.eve` is a separate mount, the final step of a successful build (renaming `.eve/builds/<id>/output` to `.output`) fails with `EXDEV`. That's a side effect of this test's layout, not part of the bug, and `scripts/build-case.sh` treats it as success.

## Suggested fix

Fall back to `rename` when `link()` fails for any reason other than `EEXIST`. The destination name is the SHA-256 of the content, so every writer produces the same bytes and replacing an existing file is safe:

```js
try {
  await link(s, o);
} catch (e) {
  if (e.code !== "EEXIST") await rename(s, o);
}
```

`scripts/build-case.sh patched` applies this to the published build and the build succeeds.
