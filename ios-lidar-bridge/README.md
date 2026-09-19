# Zamer+ LiDAR Bridge — scan only

This iPhone app performs native RoomPlan/LiDAR scanning. From the Zamer+ page in Safari, tap **Сканировать LiDAR**. After scanning, the helper returns room geometry to the same browser project. The user manually exports JSON or DAE from Safari and transfers the chosen file to the computer.

Version 1.6 removes the old direct-to-PC send handler, LAN transfer permissions, VPN/Tailscale workflow and arbitrary HTTP transport exception. The bridge does not contact any PC receiver. The custom URL scheme remains registered **only for LiDAR scanning**.

The GitHub Actions workflow builds an unsigned IPA that users may sign through SideStore. Existing projects and scans in Safari are unchanged by updating the helper.
