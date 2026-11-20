# Online icon fallback: analysis and design

Status: interface and UI-independent gatekeeper are implemented in
`lib/services/pack_online_icons.dart`, with unit tests and a fake provider.
The only real provider (`PlayListingIconProvider`) is **disabled**, and no
network request is made by the app for this feature.

## Question

When a generated icon looks bad, can the app fetch the app's own icon from the
internet and put it into the user's pack?

## Findings

1. **Google Play has no public icon API.** The listing icon is only visible on
   the store pages. Reading it means fetching and parsing store pages, which
   the Google Play terms do not allow: automated access and scraping are
   restricted, and the icons are copyrighted works of the developers.
2. **Icons belong to their owners.** Each app icon is the property of its
   developer (and often a trademark). Using it in a pack that is shared or
   redistributed is a copyright and trademark question, not a technical one.
3. **Bulk use is a different risk.** Fetching many icons, or fetching
   automatically, looks like crawling. Store operators treat it as abuse.
4. **Privacy.** A request that carries only a package name reveals which apps
   the user has installed to whoever runs the server. That is acceptable only
   when the user asks for it, one icon at a time.

## Decision

- The fallback is **user-initiated, one icon per tap**. Never automatic,
  never in bulk, never on import, never when a pack opens.
- It is behind a Settings toggle that is **off by default**. The `AppState`
  field `onlineIconsEnabled` (default `false`, saved in the state JSON and the
  backup) exists, but **no Settings row is shown**: the only provider is
  disabled, so a toggle would do nothing. The row is added only together with
  an enabled provider.
- A disclaimer is shown before the first use: "Icons belong to their owners;
  fetched only for your personal pack; never bundled in the app."
- The result is kept only in the user's local pack. It is never bundled in the
  app or in a release artifact.
- Only the package name leaves the device. No account, no device identifier,
  no personal data. Requests must use a descriptive User-Agent that contains no
  personal data.
- Requests are throttled: at most one per user action and a minimum gap
  between two requests (`OnlineIconService.minGap`).
- Package names are validated before any request.

## Provider status

| Provider | Status | Reason |
| --- | --- | --- |
| `PlayListingIconProvider` (Google Play listing, 512 px) | disabled | No icon API; the listing pages and their images are not offered for automated access. Risk judged too high. |

A future provider must be a licensed source (an API that permits icon use, or
the developer's own icon pack) and must be reviewed against its terms before it
is enabled. Enabling a provider is a one-line change in its `enabled` getter.

## Privacy section of the README

The README privacy section lists the network cases of the app. Nothing is added
there yet, because no network request is made by this feature. When a provider
is enabled, the README must list this case: "On request, for one icon at a
time, the package name of the app is sent to the icon source."

## Still to do before a provider can be enabled

- Wire `OnlineIconService` into the UI once a provider is enabled.
- Settings row (owned by the Settings screen), added with the enabled provider,
  that opens the disclaimer on the first switch-on.
- A "Try the online icon" action on a poorly generated row, shown only when
  the toggle is on.
