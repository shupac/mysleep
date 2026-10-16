#!/usr/bin/env python3
"""Validate the nested app identity that Apple's device installer enforces."""
import argparse
from pathlib import Path
import plistlib

parser = argparse.ArgumentParser()
parser.add_argument('app', type=Path, help='Built iPhone .app directory')
args = parser.parse_args()
def info(app):
    with (app / 'Info.plist').open('rb') as file:
        return plistlib.load(file)
phone = info(args.app)
watches = list((args.app / 'Watch').glob('*.app'))
assert len(watches) == 1, 'Expected one embedded Watch app'
watch = info(watches[0])
assert watch['WKCompanionAppBundleIdentifier'] == phone['CFBundleIdentifier'], 'Watch companion ID does not match the iPhone bundle ID'
assert watch['CFBundleIdentifier'].startswith(phone['CFBundleIdentifier'] + '.'), 'Watch bundle ID must extend the iPhone bundle ID'
assert phone['CFBundleDisplayName'] == watch['CFBundleDisplayName'], 'App display names differ'
assert watch.get('WKRunsIndependentlyOfCompanionApp') is True, 'Watch independence is disabled'
print('Verified app name:', phone['CFBundleDisplayName'])
print('iPhone:', phone['CFBundleIdentifier'])
print('Watch:', watch['CFBundleIdentifier'])
print('Watch companion:', watch['WKCompanionAppBundleIdentifier'])

complications = list((watches[0] / 'PlugIns').glob('*.appex'))
assert len(complications) == 1, 'Expected one embedded Watch complication'
complication = info(complications[0])
assert complication['CFBundleIdentifier'].startswith(watch['CFBundleIdentifier'] + '.'), 'Complication bundle ID must extend the Watch bundle ID'
assert complication['NSExtension']['NSExtensionPointIdentifier'] == 'com.apple.widgetkit-extension', 'Expected a WidgetKit extension'
assert complication['SleepAppGroup'] == watch['SleepAppGroup'], 'Watch and complication App Groups differ'
print('Complication:', complication['CFBundleIdentifier'])
print('Shared App Group:', complication['SleepAppGroup'])
