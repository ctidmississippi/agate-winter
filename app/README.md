# Agate (iPhone app)

Live scores, standings and polls from ESPN's public feeds, in the look of The Agate Page.
Four tabs: Scores (any date, every league listed in Data/Leagues.swift, including ATP and WTA tennis), Standings, Polls, Settings (favorite teams,
text size, which leagues to show). Pull down on any screen to refresh.

## Run it
1. Install Xcode (free, Mac App Store) and open `Agate.xcodeproj`.
2. Click the blue "Agate" project, then the Agate target, then Signing & Capabilities.
   Choose your Apple ID under Team (Xcode > Settings > Accounts > + to add it).
   If Xcode says the bundle identifier is taken, change `com.nicholas.agate` to anything unique.
3. Pick an iPhone Simulator at the top and press Run (Cmd-R) to try it with no phone.
4. To install on your phone: plug it in, turn on Developer Mode
   (Settings > Privacy & Security > Developer Mode), pick your iPhone at the top, press Run.
   First launch: Settings > General > VPN & Device Management > trust your Apple ID.

A free Apple ID build lasts 7 days. Plug in and press Run again to renew it.

## Notes
- Requires iOS 17 or later. Portrait, light appearance (like the paper page).
- Fonts bundled in `Agate/Resources/Fonts` are open-licensed (SIL OFL): Chomsky, Frank Ruhl Libre,
  Roboto Condensed, Libre Franklin.
- ESPN's feeds are unofficial and can change. A league that fails to load is listed at the bottom of Scores.
- Files: `Data/` (ESPN models, client, league catalog, line builders), `Views/` (screens).
  To add a league, add one line to `Data/Leagues.swift`.

## Refreshing winter
The Winter tab has no live feed (ESPN doesn't carry these sports). It shows `Agate/Resources/winter.json`,
which is compiled on request: tell Claude "refresh winter" and it rebuilds that file from the governing
bodies (FIS, IBU, ISU, FIL) and news reports. Then rebuild the app in Xcode (Cmd-R) to pick it up.
To skip the rebuild, host `winter.json` at any web address and paste it into Settings > Winter data URL.
Format: `{"updated": "...", "note": "...", "sports": [{"name": "...", "blocks": [{"title": "...",
"rows": [{"kind": "line|sub|note|live", "left": "...", "right": "..."}]}]}]}`.
Covers the 15 Winter Olympic sports. Some are marked "ask for a refresh" until data is confirmed.


## Added later
- Dark mode (Settings > Appearance), share-a-score image, records/odds/TV network on games, team schedules and full box scores (tap a game), swipe between days. The Polls tab was removed.
- NFL standings by division, Calendar tab (a week at a time per league), Scores 'By time' slate and close-game banner, Olympics tab (Winter + Summer, data in Resources/summer.json, optional URL in Settings), WidgetSource/ (home-screen widget, see README.txt there).
