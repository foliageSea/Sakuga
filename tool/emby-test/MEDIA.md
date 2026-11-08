# Local Emby media fixtures

This fixture set provides one complete openly licensed movie and an original two-episode synthetic TV series. It is prepared for local library scans, playback, seek/resume, artwork, and subtitle-selection tests. All artwork and metadata are local; no online metadata lookup is needed.

## Inventory and verified streams

| Item | Duration | Video | Audio | Size |
| --- | --- | --- | --- | --- |
| Big Buck Bunny (2008), MP4 | 596.458333 s (9:56.46) | H.264 Constrained Baseline, 320×180, 24 fps, yuv420p | AAC LC, 48 kHz stereo | 64,657,027 bytes |
| Sakuga Signal Lab S01E01 — Color Sweep, MP4 | 366.000 s (6:06) | H.264 High, 320×180, 12 fps, yuv420p | AAC LC, 32 kHz mono, 32 kb/s target | 2,568,335 bytes |
| Sakuga Signal Lab S01E02 — Orbit Grid, MKV | 366.032 s (6:06.03) | H.264 High, 320×180, 12 fps, yuv420p | AAC LC, 32 kHz mono, 32 kb/s target | 6,010,464 bytes |

The MKV contains an embedded SubRip text subtitle stream tagged `eng` and titled “English TEST captions (not official translations).” Both TV episodes have six minutes six seconds of video; the extra 32 ms reported by the MKV container is AAC padding.

The complete media directory is approximately **73.37 MB (70 MiB)**, well below 200 MB. The downloaded ZIP was removed after successful extraction so it does not duplicate the film on disk. Included sidecars: five NFO XML files, six UTF-8 external SRTs, and seven original PNG images. See the machine-readable [verification report](media/verification.json) for exact stream details, file sizes, and SHA-256 hashes.

## Movie source, license, and attribution

**Big Buck Bunny (2008) — © copyright 2008, Blender Foundation / [www.bigbuckbunny.org](https://www.bigbuckbunny.org/).**

- Official project website: <https://peach.blender.org/>
- Official download page: <https://peach.blender.org/download/>
- Official source directory, verified with HTTP 200: <https://download.blender.org/peach/bigbuckbunny_movies/>
- Exact downloaded official archive: <https://download.blender.org/peach/bigbuckbunny_movies/BigBuckBunny_320x180.mp4.zip>
- Official license and required-attribution statement: <https://peach.blender.org/about/>
- Creative Commons Attribution 3.0 Unported (CC BY 3.0): <https://creativecommons.org/licenses/by/3.0/>
- Full license text: <https://creativecommons.org/licenses/by/3.0/legalcode>
- Blender Foundation attribution link: <https://www.blender.org/>

The requested bare <https://download.blender.org/peach/bigbuckbunny_movies/BigBuckBunny_320x180.mp4> returned HTTP 404 during preparation. The official directory instead lists the 64,657,225-byte ZIP above. Its sole member is `BigBuckBunny_320x180.mp4` (64,657,027 bytes). That member was extracted unchanged and renamed to [Big Buck Bunny (2008).mp4](<media/Movies/Big Buck Bunny (2008)/Big Buck Bunny (2008).mp4>); the full original ending credits remain intact. No trimming, re-encoding, remuxing, soundtrack alteration, or captions burned into the movie was performed.

Extracted film SHA-256:

```text
f78f39603e6774907f2faafabf26a667f4a6fc31769ec304a8a8f7c62d280508
```

The official attribution guidance requires the entire ending credits when screening the entire movie. Preserve those credits and this attribution when sharing the fixture. The movie's added English/Chinese sidecars are original test captions, **not official dialogue or translations**. Its poster and backdrop are newly generated geometric artwork and do not use Blender logos, official DVD covers, characters, or external images. The official page specifically excludes logos/trademarks and the DVD cover/disc print from its CC license.

## Original TV, artwork, and caption fixtures

**Sakuga Signal Lab (2026)** is an original synthetic test series with stable local title/year/overview/genres. Season 01 contains:

1. **Color Sweep**: FFmpeg `testsrc` moving color pattern and a quiet 330 Hz tone, MP4 with fast-start indexing.
2. **Orbit Grid**: distinct FFmpeg `testsrc2` moving geometric pattern and a quiet 440 Hz tone, MKV with embedded English test captions.

The generated video, tones, artwork, captions, metadata, and generator/verification scripts are dedicated to **CC0 1.0 Universal**, to the extent copyright applies: <https://creativecommons.org/publicdomain/zero/1.0/>. They contain no third-party film, TV, music, or artwork. This CC0 dedication does **not** change the Blender movie's CC BY 3.0 license.

The generated tone uses FFmpeg sine's native amplitude followed by `volume=0.08`. Episode 1's first ten seconds measured −43.0 dBFS mean and −39.0 dBFS peak after AAC decoding. The Blender film retains its original soundtrack and volume.

Every video has matching `.en.srt` and `.zh.srt` sidecars. Four deliberately sparse cues occur at 00:00, 00:30, 03:00, and 05:50, with visible English “TEST CAPTION” or Chinese “测试字幕” labels. Both languages are original fixture text. The MKV's embedded English stream repeats its external English fixture, allowing embedded/external subtitle selection testing. Chinese rendering depends on fonts available to the player or subtitle renderer.

## Layout and local library setup

- Movie library root: [Movies](media/Movies/), containing [Big Buck Bunny (2008)](<media/Movies/Big Buck Bunny (2008)/>) with the complete MP4, [movie.nfo](<media/Movies/Big Buck Bunny (2008)/movie.nfo>), local poster/backdrop, and English/Chinese SRTs.
- TV library root: [TV](media/TV/), containing [Sakuga Signal Lab (2026)](<media/TV/Sakuga Signal Lab (2026)/>) with [tvshow.nfo](<media/TV/Sakuga Signal Lab (2026)/tvshow.nfo>), show poster/backdrop, and [Season 01](<media/TV/Sakuga Signal Lab (2026)/Season 01/>) with two named episodes, episode NFOs/thumbnails, season NFO/poster, and SRTs.

Point Emby's Movies and TV Shows libraries at the corresponding paths inside the existing media bind mount. Enable local NFO metadata and local images, and disable internet metadata/image providers and automatic subtitle downloads for deterministic offline scans. NFOs also set `lockdata=true`. No external provider IDs are used. The TV release dates are invented fixed fixture values. PNG poster/backdrop names and matching episode stems follow Emby's local-file conventions.

Media preparation verified the files without running Docker or Flutter. Subsequent real-server verification against Docker Emby 4.9.3.0 passed library discovery, native playback, seeking, subtitle loading, and progress synchronization; see the [integration results](RESULTS.md).

## Regeneration and verification

[generate-fixtures.py](media/generate-fixtures.py) regenerates only original TV media, artwork, metadata, and captions; it does not download or modify the Blender film. It requires Python with Pillow and FFmpeg at `/opt/homebrew/bin/ffmpeg`. The prepared assets used bundled Python/Pillow without installing packages.

[verify-fixtures.py](media/verify-fixtures.py) probes all three videos with `/opt/homebrew/bin/ffprobe`, asserts durations ≥360 seconds and AAC audio, checks the MKV English SubRip track, fully decodes every audio/video stream with FFmpeg error checking, validates NFO XML/SRT UTF-8/PNG integrity, and checks the directory stays below 200,000,000 bytes. It writes [verification.json](media/verification.json). All checks passed on the prepared files.

Run either script with a Python interpreter that provides Pillow. To restore the movie, download the exact official ZIP linked above, extract its sole MP4 member into the movie directory using the existing local filename, verify the published SHA-256 above, and remove the temporary archive. Retain the complete film and the attribution in this document.
