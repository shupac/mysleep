#!/usr/bin/env python3
"""Generate a dependency-free Xcode project for the native apps and Watch complication."""
from pathlib import Path
import json
import subprocess
import re
root = Path(__file__).resolve().parents[1] / 'native'
project = root / 'mysleep.xcodeproj'
project.mkdir(exist_ok=True)
# Preserve personal signing and shared identity when regenerating source lists.
preserved = {}
base_bundle = 'com.meetshu.mysleep'
app_name = 'MySleep'
existing = project / 'project.pbxproj'
if existing.exists():
    data = json.loads(subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', str(existing)]))
    old = data['objects']
    root_settings = old[old[data['rootObject']]['buildConfigurationList']]
    for config in root_settings['buildConfigurations']:
        settings = old[config]['buildSettings']
        base_bundle = settings.get('SLEEP_BUNDLE_IDENTIFIER', base_bundle)
        app_name = settings.get('SLEEP_APP_NAME', app_name)
    for target in old.values():
        if target.get('isa') != 'PBXNativeTarget': continue
        for config in old[target['buildConfigurationList']]['buildConfigurations']:
            item = old[config]
            preserved[(target['name'], item['name'])] = {
                k: v for k, v in item['buildSettings'].items()
                if k.startswith(('CODE_SIGN', 'PROVISIONING_PROFILE')) or k == 'DEVELOPMENT_TEAM'
            }
serial = 0
objects = []
def uid():
    global serial
    serial += 1
    return f'{serial:024X}'
def obj(kind, body):
    key = uid()
    objects.append((key, f'isa = {kind}; {body}'))
    return key
def array(values): return '(' + ','.join(values) + ')'
def configlist(settings, target=None):
    configs = []
    for name in ['Debug', 'Release']:
        extra = 'SWIFT_OPTIMIZATION_LEVEL = "-Onone"; SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;' if name == 'Debug' else 'SWIFT_OPTIMIZATION_LEVEL = "-O";'
        saved_settings = preserved.get((target, name), {})
        if target == 'MySleepComplication' and 'DEVELOPMENT_TEAM' not in saved_settings:
            watch_signing = preserved.get(('MySleepWatch', name), {})
            saved_settings = {**{k: v for k, v in watch_signing.items() if k in ('DEVELOPMENT_TEAM', 'CODE_SIGN_STYLE')}, **saved_settings}
        current = settings
        for key in saved_settings:
            current = re.sub(r'\b' + re.escape(key) + r'\s*=\s*[^;]+;', '', current)
        saved = ' '.join(f'{key} = {json.dumps(value)};' for key, value in saved_settings.items())
        configs.append(obj('XCBuildConfiguration', f'name = {name}; buildSettings = {{ {current} {extra} {saved} }};'))
    return obj('XCConfigurationList', f'buildConfigurations = {array(configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
files = sorted((root / 'Core').glob('*.swift')) + sorted((root / 'App').glob('*.swift'))
refs = [obj('PBXFileReference', f'lastKnownFileType = sourcecode.swift; path = "{p.relative_to(root)}"; sourceTree = "<group>";') for p in files]
resource = obj('PBXFileReference', 'lastKnownFileType = text.json; path = Fixtures/demo.json; sourceTree = "<group>";')
assetref = obj('PBXFileReference', 'lastKnownFileType = folder.assetcatalog; path = App/MySleepAssets.xcassets; sourceTree = "<group>";')
products, targets, targetids = [], [], {}
# A WidgetKit extension is embedded in the Watch app, which is embedded in iPhone.
widgetfiles = [root / 'Core/Report.swift', root / 'Core/SleepScoreSnapshot.swift', root / 'Complication/SleepScoreComplication.swift']
widgetrefs = [obj('PBXFileReference', f'lastKnownFileType = sourcecode.swift; path = "{p.relative_to(root)}"; sourceTree = "<group>";') for p in widgetfiles]
widgetbuilds = [obj('PBXBuildFile', f'fileRef = {ref};') for ref in widgetrefs]
widgetsources = obj('PBXSourcesBuildPhase', f'buildActionMask = 2147483647; files = {array(widgetbuilds)}; runOnlyForDeploymentPostprocessing = 0;')
widgetproduct = obj('PBXFileReference', 'explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = MySleepComplication.appex; sourceTree = BUILT_PRODUCTS_DIR;')
products.append(widgetproduct)
widgetconfig = configlist('''CODE_SIGN_STYLE = Automatic; CODE_SIGN_ENTITLEMENTS = Complication/Watch.entitlements;
CURRENT_PROJECT_VERSION = 1; MARKETING_VERSION = 1.0; GENERATE_INFOPLIST_FILE = YES; INFOPLIST_FILE = Complication/Info.plist;
INFOPLIST_KEY_CFBundleDisplayName = "Sleep Score"; PRODUCT_BUNDLE_IDENTIFIER = "$(SLEEP_BUNDLE_IDENTIFIER).watchkitapp.sleepscore-f3a2atfuqe";
PRODUCT_NAME = "$(TARGET_NAME)"; SDKROOT = watchos; SUPPORTED_PLATFORMS = "watchos watchsimulator";
TARGETED_DEVICE_FAMILY = 4; WATCHOS_DEPLOYMENT_TARGET = 10.0; SWIFT_VERSION = 5.0;
APPLICATION_EXTENSION_API_ONLY = YES; SKIP_INSTALL = YES;
LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks";''', target='MySleepComplication')
widgettarget = obj('PBXNativeTarget', f'buildConfigurationList = {widgetconfig}; buildPhases = ({widgetsources}); buildRules = (); dependencies = (); name = MySleepComplication; productName = MySleepComplication; productReference = {widgetproduct}; productType = "com.apple.product-type.app-extension";')
targets.append(widgettarget)

for name, sdk, family, bundle, platform in [
    ('MySleepWatch', 'watchos', '4', '"$(SLEEP_BUNDLE_IDENTIFIER).watchkitapp"', '"watchos watchsimulator"'),
    ('MySleep', 'iphoneos', '"1,2"', '"$(SLEEP_BUNDLE_IDENTIFIER)"', '"iphoneos iphonesimulator"')]:
    product = obj('PBXFileReference', f'explicitFileType = wrapper.application; includeInIndex = 0; path = {name}.app; sourceTree = BUILT_PRODUCTS_DIR;')
    products.append(product)
    if sdk == 'watchos': watchproduct = product
    builds = [obj('PBXBuildFile', f'fileRef = {ref};') for ref in refs]
    sources = obj('PBXSourcesBuildPhase', f'buildActionMask = 2147483647; files = {array(builds)}; runOnlyForDeploymentPostprocessing = 0;')
    frameworks = obj('PBXFrameworksBuildPhase', 'buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
    resourcebuild = obj('PBXBuildFile', f'fileRef = {resource};')
    assetbuild = obj('PBXBuildFile', f'fileRef = {assetref};')
    resources = obj('PBXResourcesBuildPhase', f'buildActionMask = 2147483647; files = ({resourcebuild},{assetbuild}); runOnlyForDeploymentPostprocessing = 0;')
    phases = [sources, frameworks, resources]
    dependencies = []
    if sdk == 'watchos':
        widgetembed = obj('PBXBuildFile', f'fileRef = {widgetproduct}; settings = {{ ATTRIBUTES = (CodeSignOnCopy,RemoveHeadersOnCopy); }};')
        phases.append(obj('PBXCopyFilesBuildPhase', f'buildActionMask = 2147483647; dstPath = ""; dstSubfolderSpec = 13; files = ({widgetembed}); name = "Embed Complication"; runOnlyForDeploymentPostprocessing = 0;'))
        dependencies.append(obj('PBXTargetDependency', f'target = {widgettarget};'))
    if sdk == 'iphoneos':
        watchbuild = obj('PBXBuildFile', f'fileRef = {watchproduct}; settings = {{ ATTRIBUTES = (RemoveHeadersOnCopy); }};')
        phases.append(obj('PBXCopyFilesBuildPhase', f'buildActionMask = 2147483647; dstPath = "$(CONTENTS_FOLDER_PATH)/Watch"; dstSubfolderSpec = 16; files = ({watchbuild}); name = "Embed Watch Content"; runOnlyForDeploymentPostprocessing = 0;'))
        dependencies.append(obj('PBXTargetDependency', f'target = {targetids["MySleepWatch"]};'))
    settings = f'''CODE_SIGN_STYLE = Automatic; CURRENT_PROJECT_VERSION = 1; MARKETING_VERSION = 1.0; GENERATE_INFOPLIST_FILE = YES;
    INFOPLIST_KEY_CFBundleDisplayName = "$(SLEEP_APP_NAME)"; PRODUCT_BUNDLE_IDENTIFIER = {bundle}; PRODUCT_NAME = "$(TARGET_NAME)";
    SDKROOT = {sdk}; SUPPORTED_PLATFORMS = {platform}; TARGETED_DEVICE_FAMILY = {family};
    SWIFT_VERSION = 5.0; SWIFT_EMIT_LOC_STRINGS = YES; ENABLE_USER_SCRIPT_SANDBOXING = YES;
    LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/Frameworks";'''
    if sdk == 'watchos':
        settings += 'CODE_SIGN_ENTITLEMENTS = Complication/Watch.entitlements; INFOPLIST_FILE = Complication/WatchInfo.plist; ASSETCATALOG_COMPILER_APPICON_NAME = MySleepWatchIcon; WATCHOS_DEPLOYMENT_TARGET = 10.0; INFOPLIST_KEY_WKApplication = YES; INFOPLIST_KEY_WKRunsIndependentlyOfCompanionApp = YES; INFOPLIST_KEY_WKCompanionAppBundleIdentifier = "$(SLEEP_BUNDLE_IDENTIFIER)";'
    else:
        settings += 'ASSETCATALOG_COMPILER_APPICON_NAME = MySleepIcon; IPHONEOS_DEPLOYMENT_TARGET = 17.0; INFOPLIST_KEY_UILaunchScreen_Generation = YES; INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;'
    configs = configlist(settings, target=name)
    target = obj('PBXNativeTarget', f'buildConfigurationList = {configs}; buildPhases = {array(phases)}; buildRules = (); dependencies = {array(dependencies)}; name = {name}; productName = {name}; productReference = {product}; productType = "com.apple.product-type.application";')
    targets.append(target); targetids[name] = target
# iPhone UI tests run entirely against Debug fixtures, without provider requests.
uitestref = obj('PBXFileReference', 'lastKnownFileType = sourcecode.swift; path = UITests/AppUITests.swift; sourceTree = "<group>";')
refs.append(uitestref)
uitestbuild = obj('PBXBuildFile', f'fileRef = {uitestref};')
uitestsources = obj('PBXSourcesBuildPhase', f'buildActionMask = 2147483647; files = ({uitestbuild}); runOnlyForDeploymentPostprocessing = 0;')
uitestproduct = obj('PBXFileReference', 'explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = MySleepUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
products.append(uitestproduct)
uitestconfig = configlist('CODE_SIGN_STYLE = Automatic; GENERATE_INFOPLIST_FILE = YES; PRODUCT_BUNDLE_IDENTIFIER = "$(SLEEP_BUNDLE_IDENTIFIER).uitests"; PRODUCT_NAME = "$(TARGET_NAME)"; SDKROOT = iphoneos; SUPPORTED_PLATFORMS = "iphoneos iphonesimulator"; TARGETED_DEVICE_FAMILY = "1,2"; IPHONEOS_DEPLOYMENT_TARGET = 17.0; SWIFT_VERSION = 5.0; TEST_TARGET_NAME = MySleep;', target='MySleepUITests')
uitestdependency = obj('PBXTargetDependency', f'target = {targetids["MySleep"]};')
uitest = obj('PBXNativeTarget', f'buildConfigurationList = {uitestconfig}; buildPhases = ({uitestsources}); buildRules = (); dependencies = ({uitestdependency}); name = MySleepUITests; productName = MySleepUITests; productReference = {uitestproduct}; productType = "com.apple.product-type.bundle.ui-testing";')
targets.append(uitest)
productsgroup = obj('PBXGroup', f'name = Products; children = {array(products)}; sourceTree = "<group>";')
main = obj('PBXGroup', f'children = {array(refs + widgetrefs + [resource, assetref, productsgroup])}; sourceTree = "<group>";')
configs = configlist(f'CLANG_ENABLE_MODULES = YES; SWIFT_VERSION = 5.0; SLEEP_BUNDLE_IDENTIFIER = {json.dumps(base_bundle)}; SLEEP_APP_NAME = {json.dumps(app_name)};')
projectid = obj('PBXProject', f'buildConfigurationList = {configs}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base); mainGroup = {main}; productRefGroup = {productsgroup}; projectDirPath = ""; projectRoot = ""; targets = {array(targets)}; attributes = {{ BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 2630; }};')
text = '// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'
text += '\n'.join(f'{key} = {{ {body} }};' for key, body in objects)
text += f'\n}}; rootObject = {projectid}; }}\n'
(project / 'project.pbxproj').write_text(text)
schemes = project / 'xcshareddata/xcschemes'
schemes.mkdir(parents=True, exist_ok=True)
for name, target in targetids.items():
    testaction = ''
    if name == 'MySleep':
        testaction = f'<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uitest}" BuildableName="MySleepUITests.xctest" BlueprintName="MySleepUITests" ReferencedContainer="container:mysleep.xcodeproj"/></TestableReference></Testables></TestAction>'
    ref = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="{name}.app" BlueprintName="{name}" ReferencedContainer="container:mysleep.xcodeproj"/>'
    (schemes / f'{name}.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2630" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref}</BuildActionEntry></BuildActionEntries></BuildAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></LaunchAction>
{testaction}
<AnalyzeAction buildConfiguration="Debug"/>
<ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
''')
print(project)
