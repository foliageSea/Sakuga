#!/usr/bin/env python3
"""Prepare a separate Jellyfin fixture without modifying Emby's media."""
import argparse
from pathlib import Path
import shutil
import urllib.request


ROOT = Path(__file__).resolve().parent
MOVIE = Path('Movies/Big Buck Bunny (2008)')
SOURCE_SEASON = Path('TV/Sakuga Signal Lab (2026)/Season 01')
SERIES = Path('TV/葬送的芙莉莲 (2023)')
SEASON = SERIES / 'Season 01'
CDN = 'https://image.tmdb.org/t/p/'
ARTWORK = {
    MOVIE / 'poster.jpg': 'w500/i9jJzvoXET4D9pOkoEwncSdNNER.jpg',
    MOVIE / 'fanart.jpg': 'w1280/xtdybjRRZ15mCrPOvEld305myys.jpg',
    MOVIE / 'logo.png': 'w1280/fW0heBZpksNXSNAeLl0wT2N7cD3.png',
    SERIES / 'poster.jpg': 'w500/1TtrtRIwXz5BB0gXEl8zgBypl9c.jpg',
    SERIES / 'fanart.jpg': 'w1280/rBOnrVlck7BIlGeWVlzYiZeg4l2.jpg',
    # Simplified Chinese title art from the series' TMDB Logos gallery.
    SERIES / 'logo.png': 'w1280/lMgzzHxSEvjcJb6ZWDdngoBfuvL.png',
    SEASON / 'poster.jpg': 'w500/jvueXfiDeeifwGCySYsQdcw2fCz.jpg',
    SEASON / 'S01E01-thumb.jpg': 'w780/7SfqQVmW125ugsktoRVTnRXpAkd.jpg',
    SEASON / 'S01E02-thumb.jpg': 'w780/jVeDv4dZI5KbRQw3eD8RRiojUZ5.jpg',
}
NFO_FILES = (
    MOVIE / 'movie.nfo',
    SERIES / 'tvshow.nfo',
    SEASON / 'season.nfo',
    SEASON / 'S01E01.nfo',
    SEASON / 'S01E02.nfo',
)


def fixture_files():
    name = MOVIE.name
    for extension in ('.mp4', '.en.srt', '.zh.srt'):
        path = MOVIE / (name + extension)
        yield path, path
    for original, episode, container in (
        ('Sakuga Signal Lab - S01E01 - Color Sweep', 'S01E01', '.mp4'),
        ('Sakuga Signal Lab - S01E02 - Orbit Grid', 'S01E02', '.mkv'),
    ):
        for extension in (container, '.en.srt', '.zh.srt'):
            yield SOURCE_SEASON / (original + extension), SEASON / (episode + extension)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=ROOT.parent / 'emby-test/media',
                        help='directory containing the original Emby fixture files')
    args = parser.parse_args()
    media = ROOT / 'media'
    files = list(fixture_files())
    for origin, _ in files:
        if not (args.source / origin).is_file():
            parser.error(f'Missing fixture: {args.source / origin}; see tool/emby-test/MEDIA.md')

    artwork = {}
    for destination, remote in ARTWORK.items():
        url = CDN + remote
        with urllib.request.urlopen(url, timeout=30) as response:
            data = response.read()
        if destination.suffix == '.png':
            valid = data.startswith(b'\x89PNG\r\n\x1a\n')
        else:
            valid = data.startswith(b'\xff\xd8\xff') and data.endswith(b'\xff\xd9')
        if not valid:
            raise RuntimeError(f'Invalid {destination.suffix} image from {url}')
        artwork[destination] = data

    for origin, destination in files:
        target = media / destination
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(args.source / origin, target)
    for destination in NFO_FILES:
        shutil.copyfile(ROOT / 'nfo' / destination.name, media / destination)
    for destination, data in artwork.items():
        (media / destination).write_bytes(data)
    print(f'Prepared Jellyfin media at {media}')


if __name__ == '__main__':
    main()
