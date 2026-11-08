# Verified local Jellyfin results

Tested 2026-11-08 on macOS ARM64 with FVM Flutter 3.47.6, real media_kit/libmpv, official Jellyfin 12.4.0. The official latest image resolved to `jellyfin/jellyfin@sha256:fea863d0cd9ec445985d9c75fc6ed64e38a1d2766cf0c250a33d553f4fc1b771`; compose pins that digest and `linux/arm64`.

The native `fvm flutter drive` run exited 0 and reported all tests passed. The generated log includes the Flutter integration_test plugin-detection warning during teardown, followed by both app-side and driver-side passing results. No media_kit error events were observed.

Verified through actual JellyfinAuthService and JellyfinClient:

- Ordinary username/password login, with client.users returning only the authenticated identity. The test profile stores the returned token/user identity; no password field is persisted in an application profile. The stable device base ID is passed through the production account-identity derivation.
- Movie and TV libraries, one-item paging plus an empty next page, search, latest, random items, genres, production years, and combined genre/year filtering. Year filtering passed on this server.
- Movie detail, series, season and exactly two episodes, plus poster HTTP retrieval.
- Big Buck Bunny, Color Sweep and Orbit Grid: native playback from 30 seconds reaching at least 32 seconds, pause, seek to 120 seconds, duration at least six minutes, two external captions each retrieved by HTTP and loaded with native sub-add. Visual caption appearance was not inspected.
- Playback start/progress/stop reports, user progress write/read at exactly 120 seconds, resume membership, watched/unwatched transitions.

A separate API verification after the native run confirmed the ordinary account policy and all three items remaining unwatched with 120-second progress and two external subtitle streams each. Session/live-configuration files are ignored and mode 0600. Both libraries retain empty external metadata/image fetcher lists; local NFO and artwork were scanned. Resume minimum duration is 30 seconds, with 1–95% thresholds.

Docker inspection confirmed 127.0.0.1:18097 only, read-only /media, writable persistent /config and /cache. Existing Emby remains running at 127.0.0.1:18096. Jellyfin remains running for manual use at http://127.0.0.1:18097. Viewer username: sakuga. Credentials are available in ignored local session/live-config files. Admin username: admin, random private password in the session file.

The ordinary macOS application was rebuilt with lib/main.dart after the native integration run. Android debug build also passed.

Evidence retained locally under ignored results/: native-test-sanitized.log and server-verification.json. `python3 tool/jellyfin-test/sanitize-log.py` refreshes sanitized output; `python3 tool/jellyfin-test/verify.py` prints sanitized server state.

Static analysis and 121 account/server/media regression tests passed. Five targeted home refresh and library shell cases also passed, including account and API-key sessions at mobile and desktop widths. Manual browser/main-application UI login, Android/iOS playback, remote access, transcoding fallback and visual subtitle appearance were not verified by this native fixture.
