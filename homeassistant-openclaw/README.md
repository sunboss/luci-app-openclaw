# OpenClaw for Home Assistant

Run OpenClaw as a Home Assistant add-on with persistent data storage and ingress access to the native OpenClaw web UI.

## What it does

- Installs OpenClaw into the add-on image at build time
- Stores config and state in `/data/openclaw`
- Opens the OpenClaw control UI through Home Assistant ingress
- Reuses parts of the original `luci-app-openclaw` migration logic to keep OpenClaw config compatible across upgrades

## Notes

- This is an early Home Assistant port of the OpenWrt/LuCI project
- The LuCI-specific pages are intentionally not carried over one-to-one
- The current focus is stable OpenClaw runtime behavior inside Home Assistant

See [DOCS.md](./DOCS.md) for setup details and limitations.
