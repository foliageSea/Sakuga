# Local Jellyfin account integration fixture

Official ARM64 `jellyfin/jellyfin:latest`, resolved and pinned by digest in compose. The service binds only http://127.0.0.1:18097 and leaves Emby on 18096 intact. Select Jellyfin in Sakuga and use that URL with the ordinary `sakuga` account. The local test password is SakugaTest-2026! (also supplied in the ignored live configuration). The `admin` account has a random password stored only in the ignored session file (mode 0600).

```sh
docker compose -f tool/jellyfin-test/compose.yaml up -d
python3 tool/jellyfin-test/setup.py
```

Configuration and cache persist locally in ignored directories. Existing legal media from `tool/emby-test/media` is mounted read-only; see the existing Emby media provenance documentation. Both movie and TV libraries use local NFO/artwork with external metadata/image fetchers disabled. Resume thresholds are 1–95% and a 30-second minimum duration.

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
