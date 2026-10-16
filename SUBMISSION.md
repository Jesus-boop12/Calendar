# App Store submission checklist

Everything needed to take Voice Calendar from this repository to App Review. Items marked **you** need an Apple account or a Mac and cannot be done from the repository.

## 1. Prepared in the repository

- [x] `VoiceCalendar/PrivacyInfo.xcprivacy` privacy manifest (no tracking, no collected data, `UserDefaults` reason CA92.1).
- [x] Usage strings for microphone, speech recognition, calendar and reminders in `VoiceCalendar/Info.plist`.
- [x] `ITSAppUsesNonExemptEncryption` = false (no export compliance questions at upload).
- [x] No background modes. Wake-word listening runs only while the app is open, which is what App Review guideline 2.5.4 allows.
- [x] App icon (1024×1024) in the asset catalog. Category set to Productivity. Version 1.0, build 1.
- [x] Privacy policy text in `docs/privacy-policy.md`.

## 2. Before you archive (**you**)

1. Enroll in the Apple Developer Program (developer.apple.com, US$99/year).
2. Open `VoiceCalendar.xcodeproj` in Xcode 16+, select the VoiceCalendar target → Signing & Capabilities, choose your team. Change `PRODUCT_BUNDLE_IDENTIFIER` if `com.jcmarketingspecialists.voicecalendar` is taken.
3. Build and run on a physical iPhone. Fix any compile issues (the project was authored without a compiler). Run the tests with ⌘U.
4. Fill in `[YOUR SUPPORT EMAIL]` in `docs/privacy-policy.md` and host the page. GitHub Pages works: Settings → Pages → deploy from `main` `/docs`, then the URL is `https://<your-user>.github.io/Calendar/privacy-policy`.
5. Walk through the smoke test below on the device.

### Smoke test

- Onboarding: allow all five permissions.
- Say "Hey Calendar, add coffee with Alex tomorrow at 9 AM" → event appears in Apple Calendar.
- Say "remind me to call Mom at 6 PM" → reminder appears in Reminders.
- Say "add buy milk to my tasks", "take a note: gift ideas", "what's on my schedule tomorrow?".
- Tap the mic button and speak without the wake phrase.
- Create and edit an event manually; delete it.
- Change the accent colour and dark mode in Settings.
- Wait for an event alert and a task notification to fire.
- Deny microphone access in iOS Settings and confirm the app explains what is missing instead of crashing.

## 3. App Store Connect listing (**you**)

Create the app under My Apps → "+" with the same bundle ID, then paste the copy below.

**Name**: Voice Calendar (if taken, try "Voice Calendar – Hey Calendar" or "VoiceCal").

**Subtitle** (30 chars): Say it, it's on your calendar

**Promotional text**: Add events, reminders, tasks and notes just by talking. Say "Hey Calendar" and your day is organised.

**Description**:

> Voice Calendar is the fastest way to get things onto your calendar. Say "Hey Calendar, add dentist tomorrow at 3 PM" and it's done, straight into the iPhone Calendar app and every device you sync with.
>
> TALK, DON'T TYPE
> • "Add lunch with Sam at Chipotle tomorrow at noon"
> • "Schedule a meeting with the team every weekday at 9 AM"
> • "Remind me to call Mom at 6 PM"
> • "Add buy milk to my tasks"
> • "Take a note: gift ideas for Dad"
> • "What's on my schedule tomorrow?"
>
> STAYS IN SYNC
> Events go into your iPhone calendar and reminders into the Reminders app, so they appear everywhere you already look.
>
> NEVER MISS A THING
> Alerts before events and reminders, task-due notifications with a one-tap "Mark Done", and a morning briefing of the day ahead.
>
> MADE FOR YOU
> Pick your accent colour, light or dark mode, your own wake phrase, default event length and alert timing.
>
> PRIVATE BY DESIGN
> No account, no tracking, no servers. Speech is processed by Apple's speech recognition, on-device where your iPhone supports it. Your notes and tasks never leave your phone.

**Keywords** (100 chars): voice calendar,speech,schedule,reminders,tasks,notes,planner,agenda,dictate,hands free,assistant

**Category**: Productivity. **Secondary**: Utilities.

**Age rating**: 4+ (no objectionable content).

**Support URL**: a page or email contact you control. **Privacy policy URL**: the hosted `privacy-policy` page.

**App Privacy questionnaire**: "Data Not Collected". The app has no analytics, no account and no developer servers.

**Screenshots**: required for 6.7" (iPhone 15 Pro Max / 16 Pro Max) and 6.5" (iPhone 11 Pro Max / XS Max). Capture on device or Simulator: Today screen, voice overlay mid-command, Calendar, Tasks, Settings with the accent picker. Optional 1080×1920 app preview video of a voice command.

## 4. Upload and review (**you**)

1. Xcode: Product → Archive → Distribute App → App Store Connect → Upload.
2. TestFlight: add yourself as an internal tester, use the app for a few days, especially voice commands in noisy places.
3. In App Store Connect select the build, add the release notes ("Initial release.") and submit.

**Review notes** (paste into "Notes" for the reviewer):

> Voice Calendar needs microphone and speech recognition permission to hear commands. To test: allow all permissions in onboarding, then say "Hey Calendar, add dentist tomorrow at 3 PM" or tap the microphone button and speak. Events are written to the device calendar via EventKit; reminders to the Reminders app. Speech is processed by Apple's Speech framework (on-device when available). The app has no account, no servers and collects no data. No demo account is required.

**Sign-in**: not required. **Contact**: your phone and email.

## 5. After approval

Release manually or automatically. For updates, bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in the project's build settings, archive and upload again.
