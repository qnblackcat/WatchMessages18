# WatchMessages18

Keeps the Messages app on Apple Watches running watchOS 11.4 or newer when the paired iPhone is on iOS 15 – 18.3.

watchOS 11.4 treats Messages as a removable system app that the watch keeps only while the iPhone reports its Messages
app as available. iOS 18.4+ does that; older iOS does not, so the watch loses Messages (or it disappears again after you
reinstall it from the App Store on the watch).

## How it works
One hook in `appconduitd`: `-[ACXAvailableApplicationManager possibleCompanionDeletableSystemAppToWatchCounterpartsMap]`
gets `com.apple.MobileSMS → {com.apple.MobileSMS}`, the entry iOS 18.4 has natively. The watch picks it up on the next
sync, which `appconduitd` runs on its own whenever the watch connects. No re-pairing needed.

## Notes
- This does not make an iPhone pair with a newer watchOS; pairing is a separate problem. Use [watched](https://github.com/34306/watched); [Nugget](https://github.com/leminlimez/Nugget), or Legizmo TrollStore?
- If Messages is already gone from the watch, reinstall it from the App Store on the watch after installing the tweak.

## License
GPLv3, see [LICENSE](LICENSE).
