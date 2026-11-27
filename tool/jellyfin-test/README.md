# Local Jellyfin account integration fixture

The official Jellyfin image is pinned to a multi-architecture digest in Compose (AMD64 and ARM64). The service binds only http://127.0.0.1:18097 and leaves Emby on 18096 intact. Select Jellyfin in Sakuga and use that URL with the ordinary `sakuga` account. The local test password is SakugaTest-2026! (also supplied in the ignored live configuration). The `admin` account has a random password stored only in the ignored session file (mode 0600).

First prepare the source clips and subtitles as described in the [Emby media guide](../emby-test/MEDIA.md). Restore the five local NFO templates (`movie.nfo`, `tvshow.nfo`, `season.nfo`, `S01E01.nfo`, and `S01E02.nfo`) under `tool/jellyfin-test/nfo/` from your fixture copy; they are not tracked in Git. Then run:

```sh
python3 tool/jellyfin-test/prepare-media.py
docker compose -f tool/jellyfin-test/compose.yaml up -d
python3 tool/jellyfin-test/setup.py
```

The script copies the test videos and subtitles into a separate ignored directory, mounted read-only; it does not change Emby. It downloads the real TMDB posters for [Big Buck Bunny](https://www.themoviedb.org/movie/10378-big-buck-bunny), [葬送的芙莉莲](https://www.themoviedb.org/tv/209867?language=zh-CN), and its [first season](https://www.themoviedb.org/tv/209867/season/1?language=zh-CN). The movie is the full Blender Foundation short (CC BY 3.0). The TV files `S01E01.mp4` and `S01E02.mkv` are synthetic playback samples, **not** episodes of the show; Jellyfin infers season and episode numbers from the filenames. Both episodes retain their two matching SRT sidecars.

The [NFO templates](nfo/) provide local metadata for the movie, series, season and both episodes. The episode titles, dates and plot summaries correspond to the [first](https://www.themoviedb.org/tv/209867/season/1/episode/1?language=zh-CN) and [second](https://www.themoviedb.org/tv/209867/season/1/episode/2?language=zh-CN) TMDB episodes. Along with the posters, the script downloads the movie and series backdrops, their transparent title logos, and the two episode stills as matching `S01E01-thumb.jpg` and `S01E02-thumb.jpg` sidecars.

Jellyfin reads NFO and artwork locally with external metadata/image fetchers disabled; only artwork preparation needs TMDB access, and no API key is required. If upgrading from an older fixture with a locked movie, use Jellyfin's Edit Metadata to unlock that movie, then refresh its metadata **without** choosing “Replace all metadata” so Jellyfin reads the local NFO. Configuration and cache persist locally. Resume thresholds are 1–95% and a 30-second minimum duration.

Run the native integration test:

```sh
fvm flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/jellyfin_server_test.dart \
  --dart-define-from-file=tool/jellyfin-test/results/live-config.json -d macos
```

This uses the real JellyfinAuthService/JellyfinClient and media_kit/libmpv. Passwords are never persisted in an application profile; access tokens and account metadata use shared_preferences. The client derives its own account device identity; the test supplies a stable base ID. The native test replaces the macOS debug entry point temporarily. Restore the ordinary application after testing:

```sh
fvm flutter build macos --debug -t lib/main.dart
```

Stop while retaining local configuration:

```sh
docker compose -f tool/jellyfin-test/compose.yaml down
```

See RESULTS.md for actual verified coverage and limitations.
