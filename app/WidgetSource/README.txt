The widget is already part of the Xcode project (target "AgateWidget", source in the AgateWidget folder).

To use it:
1. Select the AgateWidget target > Signing & Capabilities and choose your Personal Team (same as the Agate target).
2. Run the Agate scheme on your iPhone.
3. Touch and hold the home screen > + > Don't Miss. For the lock screen: long-press it > Customize > add Don't Miss.

AgateWidget/GameActivity.swift holds a copy of the Live Activity attributes type from Agate/Data/GameActivity.swift. If that type changes, change both.
The widget reads events.json from the agate-winter GitHub repo, at most every 6 hours, and keeps its own copy for offline use.

Background alerts (close-game alerts, nightly summary):
1. Select the Agate target > Info tab > add "Permitted background task scheduler identifiers" (BGTaskSchedulerPermittedIdentifiers) with one item: com.nicholas.agate.refresh
2. Signing & Capabilities > + Capability > Background Modes > tick "Background fetch".
3. In the app: Settings > Notifications, switch on what you want and allow notifications.
