# collectibles

A flea-market triage tool for comics: **photo → identify → price range across grades → you decide.**

Not a valuation oracle, and not a marketplace. The numbers it will show are **guide values, not sold comps**: the price source has no sales history, and a phone photo cannot establish grade. So the app shows a range across grades and lets you pick.

## Status

**No features yet.** This build is the infrastructure ported from HealthTracker: capture from camera or library, a hardened photo decode, a bring-your-own-key call with validate → retry once → fall back to the raw reply, a timing trace, a three-state outcome modal, local storage with export/restore, and the gate suite that proves them. See `DECISIONS.md` (D1) and `GATES.md`.

## Keys and privacy

- You bring your own **Grok (xAI) API key** and **PriceCharting API token**. Each is stored on this device only, **never included in an export or backup**, never logged, and sent only to its own provider when you tap something that needs it.
- The PriceCharting token is a paid-subscription credential and is readable by anyone with access to this browser. Do not use this app with your token on a device that is not yours. Sharing it beyond its subscriber requires a server (D1), which does not exist.
- All data stays in this browser. No accounts, no telemetry. Your export is your backup.

## Running it

Static HTML/CSS/JS, no build step, no dependencies. Open `index.html`, or serve the folder from any static host.

Gates: `bash tests/run-all-gates.sh` (needs Chrome or Edge).
