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
