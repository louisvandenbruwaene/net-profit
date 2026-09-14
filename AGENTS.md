# Working on Net Profit

## macOS graphics checks

LÖVE needs access to the macOS window server even for offscreen screenshots and automated checks. In this environment, launching it inside the restricted sandbox aborts in AppKit/HIServices `_RegisterApplication` before the Lua game starts and causes a macOS "quit unexpectedly" notification.

Run commands that launch LÖVE (`make smoke`, `make soak`, `make shots`, `make tutorial`, `make audio`, and direct LÖVE launches) with `sandbox_permissions: require_escalated` from the outset. Use an existing approved prefix when available. Do not first attempt a sandboxed graphics launch. Plain Lua `make test` needs no graphics escalation.

Use the existing isolated test modes. Do not run automated actions against the player's companies. Do not replace or rebuild an installed app while it is running.
