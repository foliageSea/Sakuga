#!/usr/bin/env python3
"""Initialize only the isolated local test container; never an arbitrary server."""
import json
import os
from pathlib import Path
import secrets
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parent
BASE = 'http://127.0.0.1:18096/emby'
STATE = ROOT / 'session.json'
IDENTITY = 'Emby Client="Sakuga Test Setup", Device="Docker Fixture", DeviceId="sakuga-fixture-setup", Version="1.0"'

def api(method, path, body=None, token=None):
    headers = {'X-Emby-Authorization': IDENTITY}
    if token:
        headers['X-Emby-Token'] = token
    data = None
    if body is not None:
        headers['Content-Type'] = 'application/json'
        data = json.dumps(body).encode()
    request = urllib.request.Request(BASE + path, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            payload = response.read()
            return json.loads(payload) if payload else None
    except urllib.error.HTTPError as error:
        raise RuntimeError(f'{method} {path.split("?")[0]}: HTTP {error.code}') from None

def save(state):
    descriptor = os.open(STATE, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(descriptor, 'w') as output:
        json.dump(state, output, indent=2)
    os.chmod(STATE, 0o600)

def authenticate(account):
    response = api('POST', '/Users/AuthenticateByName', {'Username': account['username'], 'Pw': account['password']})
    account.update(accessToken=response['AccessToken'], userId=response['User']['Id'])
    return response

def main():
    if STATE.exists():
        state = json.loads(STATE.read_text())
    else:
        state = {'admin': {'username': 'sakuga-admin', 'password': secrets.token_urlsafe(24)}, 'viewer': {'username': 'sakuga', 'password': 'SakugaTest-2026!'}}
        # Persist before initialization so a failed setup can resume safely.
        save(state)
    admin = state['admin']
    if not admin.get('userId'):
        api('POST', '/Startup/Configuration', {'UICulture': 'en-us', 'MetadataCountryCode': 'US', 'PreferredMetadataLanguage': 'en'})
        api('POST', '/Startup/User', {'Name': admin['username'], 'Password': admin['password']})
        api('POST', '/Startup/RemoteAccess', {'EnableRemoteAccess': False, 'EnableAutomaticPortMapping': False})
        api('POST', '/Startup/Complete', {})
    authenticate(admin)
    save(state)
    token = admin['accessToken']
    configuration = api('GET', '/System/Configuration', token=token)
    configuration.update(ServerName='Sakuga Emby Test', EnableRemoteAccess=False, EnableUPnP=False)
    api('POST', '/System/Configuration', configuration, token)
    users = api('GET', '/Users', token=token)
    viewer = state['viewer']
    user = next((user for user in users if user['Name'] == viewer['username']), None)
    if user is None:
        user = api('POST', '/Users/New', {'Name': viewer['username']}, token)
        api('POST', f'/Users/{user["Id"]}/Password', {'Id': user['Id'], 'CurrentPw': '', 'NewPw': viewer['password'], 'ResetPassword': False}, token)
    policy = user.get('Policy', {})
    policy.update(IsAdministrator=False, EnableAllFolders=True, EnableMediaPlayback=True, EnableVideoPlaybackTranscoding=True, EnableAudioPlaybackTranscoding=True, EnablePlaybackRemuxing=True, EnableRemoteAccess=False, IsDisabled=False)
    api('POST', f'/Users/{user["Id"]}/Policy', policy, token)
    authenticate(viewer)
    save(state)
    folders = api('GET', '/Library/VirtualFolders', token=token)
    for name, collection, folder in [('Test Movies', 'movies', 'Movies'), ('Test TV', 'tvshows', 'TV')]:
        (ROOT / 'media' / folder).mkdir(parents=True, exist_ok=True)
        if any(existing['Name'] == name for existing in folders):
            continue
        types = ['Movie'] if collection == 'movies' else ['Series', 'Season', 'Episode']
        options = {
            'EnableRealtimeMonitor': True,
            'EnableChapterImageExtraction': False,
            'ExtractChapterImagesDuringLibraryScan': False,
            'EnableMarkerDetection': False,
            'SaveLocalMetadata': False,
            'PreferredMetadataLanguage': 'en',
            'MetadataCountryCode': 'US',
            'MinResumePct': 1,
            'MaxResumePct': 95,
            'MinResumeDurationSeconds': 30,
            'TypeOptions': [{'Type': kind, 'MetadataFetchers': [], 'ImageFetchers': []} for kind in types],
            'PathInfos': [{'Path': '/media/' + folder}],
        }
        api('POST', '/Library/VirtualFolders', {'Name': name, 'CollectionType': collection, 'Paths': ['/media/' + folder], 'RefreshLibrary': False, 'LibraryOptions': options}, token)
    api('POST', '/Library/Refresh', token=token)
    results = ROOT / 'results'
    results.mkdir(exist_ok=True)
    config = results / 'live-config.json'
    with os.fdopen(os.open(config, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), 'w') as output:
        json.dump({'EMBY_LIVE_TEST': 'true', 'EMBY_TEST_URL': BASE.removesuffix('/emby'), 'EMBY_TEST_USERNAME': viewer['username'], 'EMBY_TEST_PASSWORD': viewer['password']}, output, indent=2)
    info = api('GET', '/System/Info/Public')
    print(json.dumps({'name': info['ServerName'], 'version': info['Version'], 'url': BASE.removesuffix('/emby'), 'username': viewer['username'], 'administrator': False, 'libraries': [entry['Name'] for entry in api('GET', '/Library/VirtualFolders', token=token)]}, indent=2))

if __name__ == '__main__':
    main()
