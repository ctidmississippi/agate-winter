Adding the widget (about 5 minutes, done once in Xcode)

A widget is a separate "extension" inside the project, and Xcode creates it for you:

1. In Xcode: File > New > Target... > iOS > Widget Extension. Click Next.
2. Product Name: AgateWidget. Uncheck "Include Live Activity" and "Include Configuration App Intent". Finish.
   If asked to activate the scheme, click Activate.
3. In the left sidebar, open the new AgateWidget folder. Delete the template files Xcode made
   (AgateWidget.swift, AgateWidgetBundle.swift, AgateWidgetLiveActivity.swift, AppIntent.swift if present).
   Choose "Move to Trash".
4. Drag AgateWidget.swift from this WidgetSource folder into the AgateWidget folder in Xcode.
   In the dialog, make sure "AgateWidget" is checked under "Add to targets" (and Agate is not).
5. Select the AgateWidget target > Signing & Capabilities and choose your Personal Team.
6. Nothing to edit: the widget reads events.json from your agate-winter GitHub repo (a few kilobytes, at most every 6 hours).
7. Choose the "Agate" scheme and run on your iPhone. Then touch and hold the home screen > + > Don't Miss.

Notes: the widget refreshes about every 15 minutes (iOS decides the exact timing). It reads ESPN directly
It has no settings of its own, so it never needs an App Group.

Lock-screen widget and Live Activity (added)
- AgateWidget.swift now also offers lock-screen sizes. Long-press the lock screen > Customize > add "Don't Miss".
- The Live Activity needs one more step: in Xcode, click Agate/Data/GameActivity.swift, open the File inspector
  (right panel), and under Target Membership tick both Agate and AgateWidget.
- Start it from a live game: open the game and tap the lock-screen icon at the top right.
  Without push (free Apple ID) it only updates while the app is refreshing, then goes stale.

Alerts that run in the background (close-game alerts, nightly summary)
They work while the app is open with no setup. To let iOS wake the app in the background:
1. Select the Agate target > Info tab > add the row "Permitted background task scheduler identifiers"
   (BGTaskSchedulerPermittedIdentifiers) with one item: com.nicholas.agate.refresh
2. Signing & Capabilities > + Capability > Background Modes > tick "Background fetch".
3. In the app: Settings > Notifications, switch on what you want and allow notifications.
iOS decides when to run it (roughly every 15 minutes or longer, less when battery is low).
