// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Sakuga';

  @override
  String get home => 'Home';

  @override
  String get library => 'Library';

  @override
  String get backToLibrary => 'Back to library';

  @override
  String get search => 'Search';

  @override
  String get downloads => 'Downloads';

  @override
  String get noServer => 'No server connected';

  @override
  String get emptyLibrary => 'No items';

  @override
  String get emptySearch => 'Search your library';

  @override
  String get emptyDownloads => 'No downloads';

  @override
  String get servers => 'Servers';

  @override
  String get addServer => 'Add server';

  @override
  String get editServer => 'Edit server';

  @override
  String get currentServer => 'Current';

  @override
  String get switchServer => 'Switch';

  @override
  String get serverName => 'Name';

  @override
  String get serverUrl => 'Server address';

  @override
  String get secureConnection => 'Secure connection';

  @override
  String get serverType => 'Server type';

  @override
  String get serverTypeFnMovie => 'fnOS Media';

  @override
  String get serverAuthMethod => 'Authentication method';

  @override
  String get serverAccountPassword => 'Account/password';

  @override
  String get serverUsername => 'Username';

  @override
  String get serverPassword => 'Password';

  @override
  String get serverUsernameRequired => 'Enter a username.';

  @override
  String get serverPasswordHelp =>
      'Your password is used only to sign in and is never saved. Leave it blank to keep an existing session.';

  @override
  String get serverLoginRequired =>
      'Sign-in failed or your session expired. Enter your password and save to sign in again.';

  @override
  String get apiKey => 'API key';

  @override
  String get noApiKey => 'Add an API key for this server.';

  @override
  String get refresh => 'Refresh';

  @override
  String get loadMore => 'Load more';

  @override
  String get continueWatching => 'Continue watching';

  @override
  String get recentlyAdded => 'Recently added';

  @override
  String get searchHint => 'Search movies and series';

  @override
  String get libraryFilters => 'Filters';

  @override
  String get libraryProgress => 'Progress';

  @override
  String get libraryUnwatched => 'Unwatched';

  @override
  String get libraryWatched => 'Watched';

  @override
  String get markAsPlayed => 'Mark as played';

  @override
  String markAsPlayedConfirm(String name) {
    return 'Mark “$name” as played?';
  }

  @override
  String get markAsUnplayed => 'Mark as unplayed';

  @override
  String libraryDuration(int count) {
    return '$count min';
  }

  @override
  String get libraryYear => 'Year';

  @override
  String get librarySort => 'Sort';

  @override
  String get librarySortName => 'Name';

  @override
  String get librarySortNewest => 'Recently added';

  @override
  String get librarySortYear => 'Release year';

  @override
  String get librarySortRating => 'Rating';

  @override
  String get librarySortAscending => 'Ascending';

  @override
  String get librarySortDescending => 'Descending';

  @override
  String get libraryGridView => 'Poster view';

  @override
  String get libraryListView => 'List view';

  @override
  String libraryCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count titles',
      one: '1 title',
    );
    return '$_temp0';
  }

  @override
  String librarySeasonCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count seasons',
      one: '1 season',
    );
    return '$_temp0';
  }

  @override
  String libraryEpisodeCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count episodes',
      one: '1 episode',
    );
    return '$_temp0';
  }

  @override
  String get libraryYearsLoadError => 'Could not load years. Try again';

  @override
  String get libraryMoreYears => 'More years';

  @override
  String get libraryFewerYears => 'Fewer years';

  @override
  String get genre => 'Genre';

  @override
  String get allGenres => 'All genres';

  @override
  String get genresLoadError => 'Could not load genres. Try again';

  @override
  String get synopsis => 'Synopsis';

  @override
  String get cast => 'Cast';

  @override
  String get seasons => 'Seasons';

  @override
  String get season => 'Season';

  @override
  String get specials => 'Specials';

  @override
  String seasonNumber(int number) {
    return 'Season $number';
  }

  @override
  String episodeTitle(int number, String title) {
    return '$number. $title';
  }

  @override
  String get episodes => 'Episodes';

  @override
  String get studios => 'Studio';

  @override
  String get noItems => 'No items';

  @override
  String get testConnection => 'Test';

  @override
  String get serverNameRequired => 'Enter a name.';

  @override
  String get serverUrlInvalid => 'Enter a valid IP address or domain.';

  @override
  String get serverUnreachable => 'Could not reach the server.';

  @override
  String get noServers => 'No servers';

  @override
  String get deleteServer => 'Delete server?';

  @override
  String get deleteServerBody => 'This removes the saved server.';

  @override
  String get connectedServer => 'Connected';

  @override
  String get authError =>
      'Authentication expired or rejected. Edit the server in Settings to sign in again or update its API key.';

  @override
  String get permissionError =>
      'This account does not have permission to access this resource.';

  @override
  String get overview => 'Overview';

  @override
  String get components => 'Components';

  @override
  String get examples => 'Examples';

  @override
  String get settings => 'Settings';

  @override
  String get general => 'General';

  @override
  String get explore => 'Explore components';

  @override
  String get openTasks => 'Open task workspace';

  @override
  String get allTasks => 'All tasks';

  @override
  String get completed => 'Completed';

  @override
  String get pending => 'In progress';

  @override
  String get taskWorkspace => 'Task workspace';

  @override
  String get newTask => 'New task';

  @override
  String get editTask => 'Edit task';

  @override
  String get title => 'Title';

  @override
  String get description => 'Description';

  @override
  String get dueDate => 'Due date';

  @override
  String get save => 'Save';

  @override
  String get saving => 'Saving…';

  @override
  String get cancel => 'Cancel';

  @override
  String get delete => 'Delete';

  @override
  String get edit => 'Edit';

  @override
  String get requiredTitle => 'Enter a title.';

  @override
  String get searchTasks => 'Search tasks…';

  @override
  String get emptyTasks => 'No tasks yet';

  @override
  String get noResults => 'No matching results';

  @override
  String get clearFilters => 'Clear filters';

  @override
  String get deleteTitle => 'Delete this task?';

  @override
  String get deleteBody => 'This task will be removed from this device.';

  @override
  String get noDate => 'No due date';

  @override
  String get errorTitle => 'Something needs attention';

  @override
  String get retry => 'Try again';

  @override
  String get storageError =>
      'Could not save or read local data. Your current input is preserved. Please try again.';

  @override
  String get networkError =>
      'Connection failed. Check your network and try again.';

  @override
  String get timeoutError => 'The request timed out. Please try again.';

  @override
  String get serverError => 'The server returned an error. Please try again.';

  @override
  String get invalidDataError => 'The response or configuration is invalid.';

  @override
  String get cancelledError => 'Request cancelled.';

  @override
  String get searchComponents => 'Search components…';

  @override
  String get all => 'All';

  @override
  String get basic => 'Essentials';

  @override
  String get input => 'Forms';

  @override
  String get content => 'Content';

  @override
  String get navigation => 'Navigation';

  @override
  String get feedback => 'Feedback';

  @override
  String get preview => 'Live preview';

  @override
  String get source => 'Source code';

  @override
  String get copyCode => 'Copy code';

  @override
  String get copied => 'Copied to clipboard';

  @override
  String get documentation => 'Documentation';

  @override
  String get back => 'Back';

  @override
  String get defaultState => 'Default';

  @override
  String get disabled => 'Disabled';

  @override
  String get loading => 'Loading…';

  @override
  String get playbackError => 'Unable to play this video.';

  @override
  String get superResolution => 'Video super resolution';

  @override
  String get gpuSystemUsage => 'System GPU usage';

  @override
  String get superResolutionOff => 'Super resolution off';

  @override
  String get superResolutionEfficiency => 'Efficiency';

  @override
  String get superResolutionQuality => 'Quality';

  @override
  String get superResolutionEfficiencyActive => 'SR · Efficiency';

  @override
  String get superResolutionQualityActive => 'SR · Quality';

  @override
  String get superResolutionError => 'Could not change super resolution mode.';

  @override
  String get audioTracks => 'Audio tracks';

  @override
  String get audioTrack => 'Audio track';

  @override
  String get audioAutomatic => 'Automatic';

  @override
  String get audioOff => 'Audio off';

  @override
  String get noAudioTracks => 'No audio tracks';

  @override
  String get audioTrackError => 'Could not switch audio tracks.';

  @override
  String get playbackQuality => 'Playback quality';

  @override
  String get playbackQualityMaximum => 'Maximum';

  @override
  String get trackLanguageChinese => 'Chinese';

  @override
  String get trackLanguageChineseSimplified => 'Chinese (Simplified)';

  @override
  String get trackLanguageChineseTraditional => 'Chinese (Traditional)';

  @override
  String get trackLanguageJapanese => 'Japanese';

  @override
  String get trackLanguageEnglish => 'English';

  @override
  String get trackLanguageKorean => 'Korean';

  @override
  String get trackLanguageCantonese => 'Cantonese';

  @override
  String get trackLanguageFrench => 'French';

  @override
  String get trackLanguageGerman => 'German';

  @override
  String get trackLanguageSpanish => 'Spanish';

  @override
  String get trackLanguagePortuguese => 'Portuguese';

  @override
  String get trackLanguageRussian => 'Russian';

  @override
  String get trackLanguageItalian => 'Italian';

  @override
  String get trackLanguageArabic => 'Arabic';

  @override
  String get trackLanguageThai => 'Thai';

  @override
  String get trackLanguageVietnamese => 'Vietnamese';

  @override
  String get trackMono => 'Mono';

  @override
  String get trackStereo => 'Stereo';

  @override
  String trackChannelCount(int count) {
    return '$count channels';
  }

  @override
  String get subtitles => 'Subtitles';

  @override
  String get subtitlesOff => 'Subtitles off';

  @override
  String get subtitlesAutomatic => 'Automatic';

  @override
  String get subtitleTrack => 'Subtitle';

  @override
  String get externalSubtitle => 'External subtitle';

  @override
  String get subtitleError => 'Could not switch subtitles.';

  @override
  String get selectEpisode => 'Select episode';

  @override
  String get nextEpisode => 'Next episode';

  @override
  String get playPlayback => 'Play';

  @override
  String get pausePlayback => 'Pause';

  @override
  String get mute => 'Mute';

  @override
  String get unmute => 'Unmute';

  @override
  String get enterFullscreen => 'Enter fullscreen';

  @override
  String get exitFullscreen => 'Exit fullscreen';

  @override
  String get playbackPosition => 'Playback position';

  @override
  String get playerBrightness => 'Brightness';

  @override
  String get playerVolume => 'Volume';

  @override
  String get playerAdjustmentError => 'Could not adjust playback settings.';

  @override
  String get subtitleStyle => 'Subtitle style';

  @override
  String get subtitleBackgroundOpacity => 'Background opacity';

  @override
  String get subtitleVerticalPosition => 'Vertical position';

  @override
  String get subtitleShadow => 'Text shadow';

  @override
  String get selected => 'Selected';

  @override
  String get action => 'Try it';

  @override
  String get success => 'Success';

  @override
  String get sampleText => 'Make room for good ideas.';

  @override
  String get name => 'Name';

  @override
  String get email => 'Email';

  @override
  String get emailInvalid => 'Enter a valid email address.';

  @override
  String get submit => 'Submit';

  @override
  String get submitted => 'Form submitted';

  @override
  String get optionA => 'Design';

  @override
  String get optionB => 'Develop';

  @override
  String get optionC => 'Ship';

  @override
  String get openOverlay => 'Open overlay';

  @override
  String get close => 'Close';

  @override
  String get appearance => 'Appearance';

  @override
  String get fontSize => 'Font size';

  @override
  String get fontSizeSmall => 'Small';

  @override
  String get fontSizeStandard => 'Standard';

  @override
  String get fontSizeLarge => 'Large';

  @override
  String get fontSizePreview => 'Preview';

  @override
  String get theme => 'Theme';

  @override
  String get system => 'System';

  @override
  String get light => 'Light';

  @override
  String get dark => 'Dark';

  @override
  String get language => 'Language';

  @override
  String get compactSidebar => 'Compact sidebar';

  @override
  String get about => 'About Sakuga';

  @override
  String get version => 'Version';

  @override
  String get openSourceLicenses => 'Third-party notices';

  @override
  String get fonts => 'Font notice';

  @override
  String get fontNotice =>
      'This app uses the MiSans font. © Xiaomi Technology Co., Ltd. Used under the MiSans Font Intellectual Property License Agreement.';

  @override
  String get runtimeEnvironment => 'Runtime environment';

  @override
  String get operatingSystem => 'Operating system';

  @override
  String get systemVersion => 'System version';

  @override
  String get dartVersion => 'Dart version';

  @override
  String get buildMode => 'Build mode';

  @override
  String get buildModeDebug => 'Debug';

  @override
  String get buildModeProfile => 'Profile';

  @override
  String get buildModeRelease => 'Release';

  @override
  String get processorCount => 'Logical processors';

  @override
  String get windowSize => 'Window size (logical pixels)';

  @override
  String get devicePixelRatio => 'Device pixel ratio';

  @override
  String get systemLocale => 'System locale';

  @override
  String get appLocale => 'App language';

  @override
  String get linkError => 'Could not open the link.';

  @override
  String get networkDemo => 'Network playground';

  @override
  String get mockMode => 'Offline mock';

  @override
  String get liveMode => 'Live API';

  @override
  String get empty => 'Empty';

  @override
  String get timeout => 'Timeout';

  @override
  String get serverFailure => 'Server error';

  @override
  String get reload => 'Reload';

  @override
  String get emptyNetwork => 'The request succeeded with no items.';

  @override
  String get tasks => 'Tasks';

  @override
  String get network => 'Network';

  @override
  String get minimize => 'Minimize';

  @override
  String get maximize => 'Maximize';

  @override
  String get restore => 'Restore';

  @override
  String get notFound => 'Page not found';

  @override
  String get goHome => 'Go to overview';

  @override
  String get themeColor => 'Theme color';

  @override
  String get radiusScale => 'Corner radius scale';

  @override
  String get colorNeutral => 'Neutral';

  @override
  String get colorBlue => 'Blue';

  @override
  String get colorGreen => 'Green';

  @override
  String get colorViolet => 'Violet';

  @override
  String get colorOrange => 'Orange';

  @override
  String get colorRose => 'Rose';

  @override
  String get logs => 'Logs';

  @override
  String get searchLogs => 'Search logs…';

  @override
  String get pauseLogs => 'Pause';

  @override
  String get resumeLogs => 'Resume';

  @override
  String get autoScrollLogs => 'Auto-scroll';

  @override
  String get copyVisibleLogs => 'Copy results';

  @override
  String get copyLogEntry => 'Copy log entry';

  @override
  String get clearLogView => 'Clear view';

  @override
  String get noLiveLogs => 'No logs to display';

  @override
  String get logCopyError => 'Could not copy logs. Please try again.';

  @override
  String logEntryCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entries',
      one: '1 entry',
    );
    return '$_temp0';
  }

  @override
  String get exportLogs => 'Export logs';

  @override
  String get exportingLogs => 'Exporting logs…';

  @override
  String get noLogsToExport => 'No logs available to export.';

  @override
  String get logsExported => 'Log archive saved.';

  @override
  String get logsShared => 'Log archive shared.';

  @override
  String get logShareOpened =>
      'Log sharing opened. Complete the export in the system share sheet.';

  @override
  String get logExportError =>
      'Could not export logs. Check available storage and try again.';

  @override
  String get playbackShortcuts => 'Playback shortcuts';

  @override
  String get playbackBuffer => 'Playback buffer';

  @override
  String get playbackBufferStandard => 'Standard';

  @override
  String get playbackBufferLarge => 'Large';

  @override
  String get playbackBufferExtraLarge => 'Extra large';

  @override
  String get seekBackwardSeconds => 'Backward seconds (←)';

  @override
  String get seekForwardSeconds => 'Forward seconds (→)';

  @override
  String get seekSecondsInvalid => 'Enter a whole number from 1 to 600.';

  @override
  String get screenshotShortcut => 'Copy screenshot with subtitles';

  @override
  String get copyScreenshot => 'Copy screenshot with subtitles (S)';

  @override
  String get screenshotCopied => 'Screenshot copied to clipboard.';

  @override
  String get screenshotFailed =>
      'Could not copy the screenshot. Please try again.';

  @override
  String get saveScreenshot => 'Save screenshot with subtitles to gallery (S)';

  @override
  String get saveScreenshotShortcut =>
      'Save screenshot with subtitles to gallery';

  @override
  String get screenshotSaved => 'Screenshot saved to gallery.';

  @override
  String get screenshotSaveFailed =>
      'Could not save the screenshot. Check storage permission and available space, then try again.';
}
