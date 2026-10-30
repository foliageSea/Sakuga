import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Sakuga'**
  String get appTitle;

  /// No description provided for @home.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get home;

  /// No description provided for @library.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get library;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @downloads.
  ///
  /// In en, this message translates to:
  /// **'Downloads'**
  String get downloads;

  /// No description provided for @noServer.
  ///
  /// In en, this message translates to:
  /// **'No server connected'**
  String get noServer;

  /// No description provided for @emptyLibrary.
  ///
  /// In en, this message translates to:
  /// **'No items'**
  String get emptyLibrary;

  /// No description provided for @emptySearch.
  ///
  /// In en, this message translates to:
  /// **'Search your library'**
  String get emptySearch;

  /// No description provided for @emptyDownloads.
  ///
  /// In en, this message translates to:
  /// **'No downloads'**
  String get emptyDownloads;

  /// No description provided for @servers.
  ///
  /// In en, this message translates to:
  /// **'Servers'**
  String get servers;

  /// No description provided for @addServer.
  ///
  /// In en, this message translates to:
  /// **'Add server'**
  String get addServer;

  /// No description provided for @editServer.
  ///
  /// In en, this message translates to:
  /// **'Edit server'**
  String get editServer;

  /// No description provided for @currentServer.
  ///
  /// In en, this message translates to:
  /// **'Current'**
  String get currentServer;

  /// No description provided for @switchServer.
  ///
  /// In en, this message translates to:
  /// **'Switch'**
  String get switchServer;

  /// No description provided for @serverName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get serverName;

  /// No description provided for @serverUrl.
  ///
  /// In en, this message translates to:
  /// **'Server address'**
  String get serverUrl;

  /// No description provided for @secureConnection.
  ///
  /// In en, this message translates to:
  /// **'Secure connection'**
  String get secureConnection;

  /// No description provided for @apiKey.
  ///
  /// In en, this message translates to:
  /// **'API key'**
  String get apiKey;

  /// No description provided for @noApiKey.
  ///
  /// In en, this message translates to:
  /// **'Add an API key for this server.'**
  String get noApiKey;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @loadMore.
  ///
  /// In en, this message translates to:
  /// **'Load more'**
  String get loadMore;

  /// No description provided for @continueWatching.
  ///
  /// In en, this message translates to:
  /// **'Continue watching'**
  String get continueWatching;

  /// No description provided for @recentlyAdded.
  ///
  /// In en, this message translates to:
  /// **'Recently added'**
  String get recentlyAdded;

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Search movies and series'**
  String get searchHint;

  /// No description provided for @libraryFilters.
  ///
  /// In en, this message translates to:
  /// **'Filters'**
  String get libraryFilters;

  /// No description provided for @libraryProgress.
  ///
  /// In en, this message translates to:
  /// **'Progress'**
  String get libraryProgress;

  /// No description provided for @libraryUnwatched.
  ///
  /// In en, this message translates to:
  /// **'Unwatched'**
  String get libraryUnwatched;

  /// No description provided for @libraryWatched.
  ///
  /// In en, this message translates to:
  /// **'Watched'**
  String get libraryWatched;

  /// No description provided for @libraryDuration.
  ///
  /// In en, this message translates to:
  /// **'{count} min'**
  String libraryDuration(int count);

  /// No description provided for @libraryYear.
  ///
  /// In en, this message translates to:
  /// **'Year'**
  String get libraryYear;

  /// No description provided for @librarySort.
  ///
  /// In en, this message translates to:
  /// **'Sort'**
  String get librarySort;

  /// No description provided for @librarySortName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get librarySortName;

  /// No description provided for @librarySortNewest.
  ///
  /// In en, this message translates to:
  /// **'Recently added'**
  String get librarySortNewest;

  /// No description provided for @librarySortYear.
  ///
  /// In en, this message translates to:
  /// **'Release year'**
  String get librarySortYear;

  /// No description provided for @librarySortRating.
  ///
  /// In en, this message translates to:
  /// **'Rating'**
  String get librarySortRating;

  /// No description provided for @librarySortAscending.
  ///
  /// In en, this message translates to:
  /// **'Ascending'**
  String get librarySortAscending;

  /// No description provided for @librarySortDescending.
  ///
  /// In en, this message translates to:
  /// **'Descending'**
  String get librarySortDescending;

  /// No description provided for @libraryGridView.
  ///
  /// In en, this message translates to:
  /// **'Poster view'**
  String get libraryGridView;

  /// No description provided for @libraryListView.
  ///
  /// In en, this message translates to:
  /// **'List view'**
  String get libraryListView;

  /// No description provided for @libraryCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 title} other{{count} titles}}'**
  String libraryCount(int count);

  /// No description provided for @librarySeasonCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 season} other{{count} seasons}}'**
  String librarySeasonCount(int count);

  /// No description provided for @libraryEpisodeCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 episode} other{{count} episodes}}'**
  String libraryEpisodeCount(int count);

  /// No description provided for @libraryYearsLoadError.
  ///
  /// In en, this message translates to:
  /// **'Could not load years. Try again'**
  String get libraryYearsLoadError;

  /// No description provided for @libraryMoreYears.
  ///
  /// In en, this message translates to:
  /// **'More years'**
  String get libraryMoreYears;

  /// No description provided for @libraryFewerYears.
  ///
  /// In en, this message translates to:
  /// **'Fewer years'**
  String get libraryFewerYears;

  /// No description provided for @genre.
  ///
  /// In en, this message translates to:
  /// **'Genre'**
  String get genre;

  /// No description provided for @allGenres.
  ///
  /// In en, this message translates to:
  /// **'All genres'**
  String get allGenres;

  /// No description provided for @genresLoadError.
  ///
  /// In en, this message translates to:
  /// **'Could not load genres. Try again'**
  String get genresLoadError;

  /// No description provided for @synopsis.
  ///
  /// In en, this message translates to:
  /// **'Synopsis'**
  String get synopsis;

  /// No description provided for @cast.
  ///
  /// In en, this message translates to:
  /// **'Cast'**
  String get cast;

  /// No description provided for @seasons.
  ///
  /// In en, this message translates to:
  /// **'Seasons'**
  String get seasons;

  /// No description provided for @season.
  ///
  /// In en, this message translates to:
  /// **'Season'**
  String get season;

  /// No description provided for @specials.
  ///
  /// In en, this message translates to:
  /// **'Specials'**
  String get specials;

  /// No description provided for @seasonNumber.
  ///
  /// In en, this message translates to:
  /// **'Season {number}'**
  String seasonNumber(int number);

  /// No description provided for @episodeTitle.
  ///
  /// In en, this message translates to:
  /// **'{number}. {title}'**
  String episodeTitle(int number, String title);

  /// No description provided for @episodes.
  ///
  /// In en, this message translates to:
  /// **'Episodes'**
  String get episodes;

  /// No description provided for @studios.
  ///
  /// In en, this message translates to:
  /// **'Studio'**
  String get studios;

  /// No description provided for @noItems.
  ///
  /// In en, this message translates to:
  /// **'No items'**
  String get noItems;

  /// No description provided for @testConnection.
  ///
  /// In en, this message translates to:
  /// **'Test'**
  String get testConnection;

  /// No description provided for @serverNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a name.'**
  String get serverNameRequired;

  /// No description provided for @serverUrlInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid IP address or domain.'**
  String get serverUrlInvalid;

  /// No description provided for @serverUnreachable.
  ///
  /// In en, this message translates to:
  /// **'Could not reach the server.'**
  String get serverUnreachable;

  /// No description provided for @noServers.
  ///
  /// In en, this message translates to:
  /// **'No servers'**
  String get noServers;

  /// No description provided for @deleteServer.
  ///
  /// In en, this message translates to:
  /// **'Delete server?'**
  String get deleteServer;

  /// No description provided for @deleteServerBody.
  ///
  /// In en, this message translates to:
  /// **'This removes the saved server.'**
  String get deleteServerBody;

  /// No description provided for @connectedServer.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get connectedServer;

  /// No description provided for @authError.
  ///
  /// In en, this message translates to:
  /// **'API key rejected.'**
  String get authError;

  /// No description provided for @overview.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get overview;

  /// No description provided for @components.
  ///
  /// In en, this message translates to:
  /// **'Components'**
  String get components;

  /// No description provided for @examples.
  ///
  /// In en, this message translates to:
  /// **'Examples'**
  String get examples;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @general.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get general;

  /// No description provided for @explore.
  ///
  /// In en, this message translates to:
  /// **'Explore components'**
  String get explore;

  /// No description provided for @openTasks.
  ///
  /// In en, this message translates to:
  /// **'Open task workspace'**
  String get openTasks;

  /// No description provided for @allTasks.
  ///
  /// In en, this message translates to:
  /// **'All tasks'**
  String get allTasks;

  /// No description provided for @completed.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get completed;

  /// No description provided for @pending.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get pending;

  /// No description provided for @taskWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Task workspace'**
  String get taskWorkspace;

  /// No description provided for @newTask.
  ///
  /// In en, this message translates to:
  /// **'New task'**
  String get newTask;

  /// No description provided for @editTask.
  ///
  /// In en, this message translates to:
  /// **'Edit task'**
  String get editTask;

  /// No description provided for @title.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get title;

  /// No description provided for @description.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get description;

  /// No description provided for @dueDate.
  ///
  /// In en, this message translates to:
  /// **'Due date'**
  String get dueDate;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @saving.
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get saving;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @requiredTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter a title.'**
  String get requiredTitle;

  /// No description provided for @searchTasks.
  ///
  /// In en, this message translates to:
  /// **'Search tasks…'**
  String get searchTasks;

  /// No description provided for @emptyTasks.
  ///
  /// In en, this message translates to:
  /// **'No tasks yet'**
  String get emptyTasks;

  /// No description provided for @noResults.
  ///
  /// In en, this message translates to:
  /// **'No matching results'**
  String get noResults;

  /// No description provided for @clearFilters.
  ///
  /// In en, this message translates to:
  /// **'Clear filters'**
  String get clearFilters;

  /// No description provided for @deleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this task?'**
  String get deleteTitle;

  /// No description provided for @deleteBody.
  ///
  /// In en, this message translates to:
  /// **'This task will be removed from this device.'**
  String get deleteBody;

  /// No description provided for @noDate.
  ///
  /// In en, this message translates to:
  /// **'No due date'**
  String get noDate;

  /// No description provided for @errorTitle.
  ///
  /// In en, this message translates to:
  /// **'Something needs attention'**
  String get errorTitle;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get retry;

  /// No description provided for @storageError.
  ///
  /// In en, this message translates to:
  /// **'Could not save or read local data. Your current input is preserved. Please try again.'**
  String get storageError;

  /// No description provided for @networkError.
  ///
  /// In en, this message translates to:
  /// **'Connection failed. Check your network and try again.'**
  String get networkError;

  /// No description provided for @timeoutError.
  ///
  /// In en, this message translates to:
  /// **'The request timed out. Please try again.'**
  String get timeoutError;

  /// No description provided for @serverError.
  ///
  /// In en, this message translates to:
  /// **'The server returned an error. Please try again.'**
  String get serverError;

  /// No description provided for @invalidDataError.
  ///
  /// In en, this message translates to:
  /// **'The response or configuration is invalid.'**
  String get invalidDataError;

  /// No description provided for @cancelledError.
  ///
  /// In en, this message translates to:
  /// **'Request cancelled.'**
  String get cancelledError;

  /// No description provided for @searchComponents.
  ///
  /// In en, this message translates to:
  /// **'Search components…'**
  String get searchComponents;

  /// No description provided for @all.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get all;

  /// No description provided for @basic.
  ///
  /// In en, this message translates to:
  /// **'Essentials'**
  String get basic;

  /// No description provided for @input.
  ///
  /// In en, this message translates to:
  /// **'Forms'**
  String get input;

  /// No description provided for @content.
  ///
  /// In en, this message translates to:
  /// **'Content'**
  String get content;

  /// No description provided for @navigation.
  ///
  /// In en, this message translates to:
  /// **'Navigation'**
  String get navigation;

  /// No description provided for @feedback.
  ///
  /// In en, this message translates to:
  /// **'Feedback'**
  String get feedback;

  /// No description provided for @preview.
  ///
  /// In en, this message translates to:
  /// **'Live preview'**
  String get preview;

  /// No description provided for @source.
  ///
  /// In en, this message translates to:
  /// **'Source code'**
  String get source;

  /// No description provided for @copyCode.
  ///
  /// In en, this message translates to:
  /// **'Copy code'**
  String get copyCode;

  /// No description provided for @copied.
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard'**
  String get copied;

  /// No description provided for @documentation.
  ///
  /// In en, this message translates to:
  /// **'Documentation'**
  String get documentation;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @defaultState.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get defaultState;

  /// No description provided for @disabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get disabled;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get loading;

  /// No description provided for @playbackError.
  ///
  /// In en, this message translates to:
  /// **'Unable to play this video.'**
  String get playbackError;

  /// No description provided for @superResolution.
  ///
  /// In en, this message translates to:
  /// **'Video super resolution'**
  String get superResolution;

  /// No description provided for @gpuSystemUsage.
  ///
  /// In en, this message translates to:
  /// **'System GPU usage'**
  String get gpuSystemUsage;

  /// No description provided for @superResolutionOff.
  ///
  /// In en, this message translates to:
  /// **'Super resolution off'**
  String get superResolutionOff;

  /// No description provided for @superResolutionEfficiency.
  ///
  /// In en, this message translates to:
  /// **'Efficiency'**
  String get superResolutionEfficiency;

  /// No description provided for @superResolutionQuality.
  ///
  /// In en, this message translates to:
  /// **'Quality'**
  String get superResolutionQuality;

  /// No description provided for @superResolutionEfficiencyActive.
  ///
  /// In en, this message translates to:
  /// **'SR · Efficiency'**
  String get superResolutionEfficiencyActive;

  /// No description provided for @superResolutionQualityActive.
  ///
  /// In en, this message translates to:
  /// **'SR · Quality'**
  String get superResolutionQualityActive;

  /// No description provided for @superResolutionError.
  ///
  /// In en, this message translates to:
  /// **'Could not change super resolution mode.'**
  String get superResolutionError;

  /// No description provided for @audioTracks.
  ///
  /// In en, this message translates to:
  /// **'Audio tracks'**
  String get audioTracks;

  /// No description provided for @audioTrack.
  ///
  /// In en, this message translates to:
  /// **'Audio track'**
  String get audioTrack;

  /// No description provided for @audioAutomatic.
  ///
  /// In en, this message translates to:
  /// **'Automatic'**
  String get audioAutomatic;

  /// No description provided for @audioOff.
  ///
  /// In en, this message translates to:
  /// **'Audio off'**
  String get audioOff;

  /// No description provided for @noAudioTracks.
  ///
  /// In en, this message translates to:
  /// **'No audio tracks'**
  String get noAudioTracks;

  /// No description provided for @audioTrackError.
  ///
  /// In en, this message translates to:
  /// **'Could not switch audio tracks.'**
  String get audioTrackError;

  /// No description provided for @trackLanguageChinese.
  ///
  /// In en, this message translates to:
  /// **'Chinese'**
  String get trackLanguageChinese;

  /// No description provided for @trackLanguageChineseSimplified.
  ///
  /// In en, this message translates to:
  /// **'Chinese (Simplified)'**
  String get trackLanguageChineseSimplified;

  /// No description provided for @trackLanguageChineseTraditional.
  ///
  /// In en, this message translates to:
  /// **'Chinese (Traditional)'**
  String get trackLanguageChineseTraditional;

  /// No description provided for @trackLanguageJapanese.
  ///
  /// In en, this message translates to:
  /// **'Japanese'**
  String get trackLanguageJapanese;

  /// No description provided for @trackLanguageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get trackLanguageEnglish;

  /// No description provided for @trackLanguageKorean.
  ///
  /// In en, this message translates to:
  /// **'Korean'**
  String get trackLanguageKorean;

  /// No description provided for @trackLanguageCantonese.
  ///
  /// In en, this message translates to:
  /// **'Cantonese'**
  String get trackLanguageCantonese;

  /// No description provided for @trackLanguageFrench.
  ///
  /// In en, this message translates to:
  /// **'French'**
  String get trackLanguageFrench;

  /// No description provided for @trackLanguageGerman.
  ///
  /// In en, this message translates to:
  /// **'German'**
  String get trackLanguageGerman;

  /// No description provided for @trackLanguageSpanish.
  ///
  /// In en, this message translates to:
  /// **'Spanish'**
  String get trackLanguageSpanish;

  /// No description provided for @trackLanguagePortuguese.
  ///
  /// In en, this message translates to:
  /// **'Portuguese'**
  String get trackLanguagePortuguese;

  /// No description provided for @trackLanguageRussian.
  ///
  /// In en, this message translates to:
  /// **'Russian'**
  String get trackLanguageRussian;

  /// No description provided for @trackLanguageItalian.
  ///
  /// In en, this message translates to:
  /// **'Italian'**
  String get trackLanguageItalian;

  /// No description provided for @trackLanguageArabic.
  ///
  /// In en, this message translates to:
  /// **'Arabic'**
  String get trackLanguageArabic;

  /// No description provided for @trackLanguageThai.
  ///
  /// In en, this message translates to:
  /// **'Thai'**
  String get trackLanguageThai;

  /// No description provided for @trackLanguageVietnamese.
  ///
  /// In en, this message translates to:
  /// **'Vietnamese'**
  String get trackLanguageVietnamese;

  /// No description provided for @trackMono.
  ///
  /// In en, this message translates to:
  /// **'Mono'**
  String get trackMono;

  /// No description provided for @trackStereo.
  ///
  /// In en, this message translates to:
  /// **'Stereo'**
  String get trackStereo;

  /// No description provided for @trackChannelCount.
  ///
  /// In en, this message translates to:
  /// **'{count} channels'**
  String trackChannelCount(int count);

  /// No description provided for @subtitles.
  ///
  /// In en, this message translates to:
  /// **'Subtitles'**
  String get subtitles;

  /// No description provided for @subtitlesOff.
  ///
  /// In en, this message translates to:
  /// **'Subtitles off'**
  String get subtitlesOff;

  /// No description provided for @subtitlesAutomatic.
  ///
  /// In en, this message translates to:
  /// **'Automatic'**
  String get subtitlesAutomatic;

  /// No description provided for @subtitleTrack.
  ///
  /// In en, this message translates to:
  /// **'Subtitle'**
  String get subtitleTrack;

  /// No description provided for @externalSubtitle.
  ///
  /// In en, this message translates to:
  /// **'External subtitle'**
  String get externalSubtitle;

  /// No description provided for @subtitleError.
  ///
  /// In en, this message translates to:
  /// **'Could not switch subtitles.'**
  String get subtitleError;

  /// No description provided for @selectEpisode.
  ///
  /// In en, this message translates to:
  /// **'Select episode'**
  String get selectEpisode;

  /// No description provided for @nextEpisode.
  ///
  /// In en, this message translates to:
  /// **'Next episode'**
  String get nextEpisode;

  /// No description provided for @playPlayback.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get playPlayback;

  /// No description provided for @pausePlayback.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get pausePlayback;

  /// No description provided for @mute.
  ///
  /// In en, this message translates to:
  /// **'Mute'**
  String get mute;

  /// No description provided for @unmute.
  ///
  /// In en, this message translates to:
  /// **'Unmute'**
  String get unmute;

  /// No description provided for @enterFullscreen.
  ///
  /// In en, this message translates to:
  /// **'Enter fullscreen'**
  String get enterFullscreen;

  /// No description provided for @exitFullscreen.
  ///
  /// In en, this message translates to:
  /// **'Exit fullscreen'**
  String get exitFullscreen;

  /// No description provided for @playbackPosition.
  ///
  /// In en, this message translates to:
  /// **'Playback position'**
  String get playbackPosition;

  /// No description provided for @playerBrightness.
  ///
  /// In en, this message translates to:
  /// **'Brightness'**
  String get playerBrightness;

  /// No description provided for @playerVolume.
  ///
  /// In en, this message translates to:
  /// **'Volume'**
  String get playerVolume;

  /// No description provided for @playerAdjustmentError.
  ///
  /// In en, this message translates to:
  /// **'Could not adjust playback settings.'**
  String get playerAdjustmentError;

  /// No description provided for @subtitleStyle.
  ///
  /// In en, this message translates to:
  /// **'Subtitle style'**
  String get subtitleStyle;

  /// No description provided for @subtitleBackgroundOpacity.
  ///
  /// In en, this message translates to:
  /// **'Background opacity'**
  String get subtitleBackgroundOpacity;

  /// No description provided for @subtitleVerticalPosition.
  ///
  /// In en, this message translates to:
  /// **'Vertical position'**
  String get subtitleVerticalPosition;

  /// No description provided for @selected.
  ///
  /// In en, this message translates to:
  /// **'Selected'**
  String get selected;

  /// No description provided for @action.
  ///
  /// In en, this message translates to:
  /// **'Try it'**
  String get action;

  /// No description provided for @success.
  ///
  /// In en, this message translates to:
  /// **'Success'**
  String get success;

  /// No description provided for @sampleText.
  ///
  /// In en, this message translates to:
  /// **'Make room for good ideas.'**
  String get sampleText;

  /// No description provided for @name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get name;

  /// No description provided for @email.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// No description provided for @emailInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email address.'**
  String get emailInvalid;

  /// No description provided for @submit.
  ///
  /// In en, this message translates to:
  /// **'Submit'**
  String get submit;

  /// No description provided for @submitted.
  ///
  /// In en, this message translates to:
  /// **'Form submitted'**
  String get submitted;

  /// No description provided for @optionA.
  ///
  /// In en, this message translates to:
  /// **'Design'**
  String get optionA;

  /// No description provided for @optionB.
  ///
  /// In en, this message translates to:
  /// **'Develop'**
  String get optionB;

  /// No description provided for @optionC.
  ///
  /// In en, this message translates to:
  /// **'Ship'**
  String get optionC;

  /// No description provided for @openOverlay.
  ///
  /// In en, this message translates to:
  /// **'Open overlay'**
  String get openOverlay;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// No description provided for @fontSize.
  ///
  /// In en, this message translates to:
  /// **'Font size'**
  String get fontSize;

  /// No description provided for @fontSizeSmall.
  ///
  /// In en, this message translates to:
  /// **'Small'**
  String get fontSizeSmall;

  /// No description provided for @fontSizeStandard.
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get fontSizeStandard;

  /// No description provided for @fontSizeLarge.
  ///
  /// In en, this message translates to:
  /// **'Large'**
  String get fontSizeLarge;

  /// No description provided for @fontSizePreview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get fontSizePreview;

  /// No description provided for @theme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get theme;

  /// No description provided for @system.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get system;

  /// No description provided for @light.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get light;

  /// No description provided for @dark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get dark;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @compactSidebar.
  ///
  /// In en, this message translates to:
  /// **'Compact sidebar'**
  String get compactSidebar;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About Sakuga'**
  String get about;

  /// No description provided for @version.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get version;

  /// No description provided for @openSourceLicenses.
  ///
  /// In en, this message translates to:
  /// **'Third-party notices'**
  String get openSourceLicenses;

  /// No description provided for @fonts.
  ///
  /// In en, this message translates to:
  /// **'Font notice'**
  String get fonts;

  /// No description provided for @fontNotice.
  ///
  /// In en, this message translates to:
  /// **'This app uses the MiSans font. © Xiaomi Technology Co., Ltd. Used under the MiSans Font Intellectual Property License Agreement.'**
  String get fontNotice;

  /// No description provided for @runtimeEnvironment.
  ///
  /// In en, this message translates to:
  /// **'Runtime environment'**
  String get runtimeEnvironment;

  /// No description provided for @operatingSystem.
  ///
  /// In en, this message translates to:
  /// **'Operating system'**
  String get operatingSystem;

  /// No description provided for @systemVersion.
  ///
  /// In en, this message translates to:
  /// **'System version'**
  String get systemVersion;

  /// No description provided for @dartVersion.
  ///
  /// In en, this message translates to:
  /// **'Dart version'**
  String get dartVersion;

  /// No description provided for @buildMode.
  ///
  /// In en, this message translates to:
  /// **'Build mode'**
  String get buildMode;

  /// No description provided for @buildModeDebug.
  ///
  /// In en, this message translates to:
  /// **'Debug'**
  String get buildModeDebug;

  /// No description provided for @buildModeProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get buildModeProfile;

  /// No description provided for @buildModeRelease.
  ///
  /// In en, this message translates to:
  /// **'Release'**
  String get buildModeRelease;

  /// No description provided for @processorCount.
  ///
  /// In en, this message translates to:
  /// **'Logical processors'**
  String get processorCount;

  /// No description provided for @windowSize.
  ///
  /// In en, this message translates to:
  /// **'Window size (logical pixels)'**
  String get windowSize;

  /// No description provided for @devicePixelRatio.
  ///
  /// In en, this message translates to:
  /// **'Device pixel ratio'**
  String get devicePixelRatio;

  /// No description provided for @systemLocale.
  ///
  /// In en, this message translates to:
  /// **'System locale'**
  String get systemLocale;

  /// No description provided for @appLocale.
  ///
  /// In en, this message translates to:
  /// **'App language'**
  String get appLocale;

  /// No description provided for @openDocs.
  ///
  /// In en, this message translates to:
  /// **'Forui documentation'**
  String get openDocs;

  /// No description provided for @linkError.
  ///
  /// In en, this message translates to:
  /// **'Could not open the link.'**
  String get linkError;

  /// No description provided for @networkDemo.
  ///
  /// In en, this message translates to:
  /// **'Network playground'**
  String get networkDemo;

  /// No description provided for @mockMode.
  ///
  /// In en, this message translates to:
  /// **'Offline mock'**
  String get mockMode;

  /// No description provided for @liveMode.
  ///
  /// In en, this message translates to:
  /// **'Live API'**
  String get liveMode;

  /// No description provided for @empty.
  ///
  /// In en, this message translates to:
  /// **'Empty'**
  String get empty;

  /// No description provided for @timeout.
  ///
  /// In en, this message translates to:
  /// **'Timeout'**
  String get timeout;

  /// No description provided for @serverFailure.
  ///
  /// In en, this message translates to:
  /// **'Server error'**
  String get serverFailure;

  /// No description provided for @reload.
  ///
  /// In en, this message translates to:
  /// **'Reload'**
  String get reload;

  /// No description provided for @emptyNetwork.
  ///
  /// In en, this message translates to:
  /// **'The request succeeded with no items.'**
  String get emptyNetwork;

  /// No description provided for @tasks.
  ///
  /// In en, this message translates to:
  /// **'Tasks'**
  String get tasks;

  /// No description provided for @network.
  ///
  /// In en, this message translates to:
  /// **'Network'**
  String get network;

  /// No description provided for @minimize.
  ///
  /// In en, this message translates to:
  /// **'Minimize'**
  String get minimize;

  /// No description provided for @maximize.
  ///
  /// In en, this message translates to:
  /// **'Maximize'**
  String get maximize;

  /// No description provided for @restore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get restore;

  /// No description provided for @notFound.
  ///
  /// In en, this message translates to:
  /// **'Page not found'**
  String get notFound;

  /// No description provided for @goHome.
  ///
  /// In en, this message translates to:
  /// **'Go to overview'**
  String get goHome;

  /// No description provided for @themeColor.
  ///
  /// In en, this message translates to:
  /// **'Theme color'**
  String get themeColor;

  /// No description provided for @radiusScale.
  ///
  /// In en, this message translates to:
  /// **'Corner radius scale'**
  String get radiusScale;

  /// No description provided for @colorNeutral.
  ///
  /// In en, this message translates to:
  /// **'Neutral'**
  String get colorNeutral;

  /// No description provided for @colorBlue.
  ///
  /// In en, this message translates to:
  /// **'Blue'**
  String get colorBlue;

  /// No description provided for @colorGreen.
  ///
  /// In en, this message translates to:
  /// **'Green'**
  String get colorGreen;

  /// No description provided for @colorViolet.
  ///
  /// In en, this message translates to:
  /// **'Violet'**
  String get colorViolet;

  /// No description provided for @colorOrange.
  ///
  /// In en, this message translates to:
  /// **'Orange'**
  String get colorOrange;

  /// No description provided for @colorRose.
  ///
  /// In en, this message translates to:
  /// **'Rose'**
  String get colorRose;

  /// No description provided for @logs.
  ///
  /// In en, this message translates to:
  /// **'Logs'**
  String get logs;

  /// No description provided for @searchLogs.
  ///
  /// In en, this message translates to:
  /// **'Search logs…'**
  String get searchLogs;

  /// No description provided for @pauseLogs.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get pauseLogs;

  /// No description provided for @resumeLogs.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get resumeLogs;

  /// No description provided for @autoScrollLogs.
  ///
  /// In en, this message translates to:
  /// **'Auto-scroll'**
  String get autoScrollLogs;

  /// No description provided for @copyVisibleLogs.
  ///
  /// In en, this message translates to:
  /// **'Copy results'**
  String get copyVisibleLogs;

  /// No description provided for @copyLogEntry.
  ///
  /// In en, this message translates to:
  /// **'Copy log entry'**
  String get copyLogEntry;

  /// No description provided for @clearLogView.
  ///
  /// In en, this message translates to:
  /// **'Clear view'**
  String get clearLogView;

  /// No description provided for @noLiveLogs.
  ///
  /// In en, this message translates to:
  /// **'No logs to display'**
  String get noLiveLogs;

  /// No description provided for @logCopyError.
  ///
  /// In en, this message translates to:
  /// **'Could not copy logs. Please try again.'**
  String get logCopyError;

  /// No description provided for @logEntryCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 entry} other{{count} entries}}'**
  String logEntryCount(int count);

  /// No description provided for @exportLogs.
  ///
  /// In en, this message translates to:
  /// **'Export logs'**
  String get exportLogs;

  /// No description provided for @exportingLogs.
  ///
  /// In en, this message translates to:
  /// **'Exporting logs…'**
  String get exportingLogs;

  /// No description provided for @noLogsToExport.
  ///
  /// In en, this message translates to:
  /// **'No logs available to export.'**
  String get noLogsToExport;

  /// No description provided for @logsExported.
  ///
  /// In en, this message translates to:
  /// **'Log archive saved.'**
  String get logsExported;

  /// No description provided for @logsShared.
  ///
  /// In en, this message translates to:
  /// **'Log archive shared.'**
  String get logsShared;

  /// No description provided for @logShareOpened.
  ///
  /// In en, this message translates to:
  /// **'Log sharing opened. Complete the export in the system share sheet.'**
  String get logShareOpened;

  /// No description provided for @logExportError.
  ///
  /// In en, this message translates to:
  /// **'Could not export logs. Check available storage and try again.'**
  String get logExportError;

  /// No description provided for @playbackShortcuts.
  ///
  /// In en, this message translates to:
  /// **'Playback shortcuts'**
  String get playbackShortcuts;

  /// No description provided for @seekBackwardSeconds.
  ///
  /// In en, this message translates to:
  /// **'Backward seconds (←)'**
  String get seekBackwardSeconds;

  /// No description provided for @seekForwardSeconds.
  ///
  /// In en, this message translates to:
  /// **'Forward seconds (→)'**
  String get seekForwardSeconds;

  /// No description provided for @seekSecondsInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a whole number from 1 to 600.'**
  String get seekSecondsInvalid;

  /// No description provided for @screenshotShortcut.
  ///
  /// In en, this message translates to:
  /// **'S: copy screenshot with subtitles'**
  String get screenshotShortcut;

  /// No description provided for @copyScreenshot.
  ///
  /// In en, this message translates to:
  /// **'Copy screenshot with subtitles (S)'**
  String get copyScreenshot;

  /// No description provided for @screenshotCopied.
  ///
  /// In en, this message translates to:
  /// **'Screenshot copied to clipboard.'**
  String get screenshotCopied;

  /// No description provided for @screenshotFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not copy the screenshot. Please try again.'**
  String get screenshotFailed;

  /// No description provided for @saveScreenshot.
  ///
  /// In en, this message translates to:
  /// **'Save screenshot with subtitles to gallery (S)'**
  String get saveScreenshot;

  /// No description provided for @saveScreenshotShortcut.
  ///
  /// In en, this message translates to:
  /// **'S: save screenshot with subtitles to gallery'**
  String get saveScreenshotShortcut;

  /// No description provided for @screenshotSaved.
  ///
  /// In en, this message translates to:
  /// **'Screenshot saved to gallery.'**
  String get screenshotSaved;

  /// No description provided for @screenshotSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save the screenshot. Check storage permission and available space, then try again.'**
  String get screenshotSaveFailed;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
