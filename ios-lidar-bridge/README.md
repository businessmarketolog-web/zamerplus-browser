# Zamer+ Safari LiDAR Bridge

Safari does not expose Apple RoomPlan/LiDAR to JavaScript.

Flow:
1. Open Zamer+ in Safari.
2. Tap Scan LiDAR.
3. Safari opens zamerpluslidar://scan.
4. Helper presents Apple RoomPlan.
5. Result is encoded into the HTTPS callback fragment.
6. Safari reopens Zamer+ and imports the geometry.

No App Group is required.

The included workflow builds an unsigned IPA. Install/sign it with SideStore.

Returned data:
- walls and wall endpoints
- room height
- doors/windows/open openings
- opening offsets and bottom heights
- floor polygon
