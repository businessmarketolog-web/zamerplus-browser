# Zamer+ Safari LiDAR Bridge

This helper exists because Safari does not expose Apple RoomPlan/LiDAR to JavaScript.

## User flow
1. Open Zamer+ in Safari.
2. Tap **Scan LiDAR**.
3. Safari opens `zamerpluslidar://scan?...`.
4. The helper app presents Apple RoomPlan.
5. When scanning finishes, the helper encodes a compact room JSON payload into the callback URL fragment.
6. Safari reopens the Zamer+ site and imports the LiDAR geometry into the current object.

No App Group or paid Apple Developer capability is required by this bridge design.

## Build
The included GitHub Actions workflow builds an **unsigned IPA**. SideStore can sign/install the IPA with the user's Apple ID.

## Data returned
- wall length / height
- wall endpoints and heading
- room height
- doors, windows, open openings
- opening offsets and bottom heights
- floor polygon

Critical furniture dimensions should still be confirmed with Bosch GLM.

## Version 1.4: local SketchUp transfer

The installed iOS helper also accepts a `zamerpluslidar://send?...` URL from a real user tap in the web app. It validates a private LAN IPv4 address, fixed port 8787 and a 48-hex pairing code, then submits a limited-size Zamer+ JSON payload directly to the user's Windows receiver. The web app receives only the result `accepted/rejected/offline` in its HTTPS callback URL. **Accepted means queued on the PC, not imported into SketchUp.** No room geometry is uploaded to GitHub or the public cloud.

Use only on a trusted private Wi-Fi network. The LAN HTTP transport is not encrypted; do not forward the receiver port through the router or expose it on public Wi-Fi. Payloads exceeding the custom-URL limit must use the existing manual JSON workflow.

Version 1.4 requires an IPA rebuild and a SideStore update on the iPhone; the older installed v1.3 app does not have the `send` handler. Existing RoomPlan scans remain intact after updating.


### Version 1.5: remote Tailscale transfer

The deep link optionally accepts `remoteIp` in the Tailscale CGNAT IPv4 range `100.64.0.0/10`. The iOS helper sends only to the explicitly selected address: the remote Tailscale IP (22-second timeout) or an allowed home RFC1918 address (18-second timeout). It never falls back to an untrusted local address when remote mode is selected. Install and sign in to Tailscale on iPhone and Windows in the same private tailnet; the payload is encrypted on the WireGuard transport. The Windows receiver additionally requires its existing 48-hex pairing code and queues incoming scans without overwriting an active SketchUp model.

Version 1.5 must be built as a new IPA and updated through SideStore. Manual JSON/DAE export remains independent of VPN and the receiver.
