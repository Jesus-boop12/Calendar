# Voice Calendar

A smart calendar for iPhone with its own always-listening voice assistant. Say **“Hey Calendar, add dentist tomorrow at 3 PM”** and the event lands in your iPhone calendar. Add reminders, daily tasks and notes by voice or by hand, get notified before everything, and stay in sync with the built-in Calendar and Reminders apps.

Built with SwiftUI, SwiftData, EventKit, Speech and UserNotifications. iOS 17+.

## What it does

| Area | Details |
| --- | --- |
| Wake phrase | Listens for “Hey Calendar” (customisable) while the app is open; optional background listening. Tap the mic button to skip the wake phrase. |
| Natural language | “add dentist tomorrow at 3 PM for an hour”, “schedule a meeting with Sam on Friday at 10 AM”, “add team standup every weekday at 9 AM”, “add lunch with Sam at Chipotle tomorrow at noon”. |
| Calendar sync | Events are written to the iPhone calendar through EventKit, so they appear in Apple Calendar and on every device signed into your iCloud/Google/Exchange account. |
| Reminders | “remind me to call Mom at 6 PM” creates a reminder in the Reminders app. |
| Tasks | “add buy milk to my tasks” stores a local daily task with optional due time, priority and notification. |
| Notes | “take a note: gift ideas for Dad” creates a note; notes support pinning, search and sharing. |
| Queries | “what's on my schedule tomorrow?”, “what's next?”, “am I free this weekend?” — answered on screen and out loud. |
| Delete | “cancel dentist tomorrow”. |
| Notifications | Alerts before events and reminders (via Calendar/Reminders alarms or the app's own notifications), task-due alerts with a “Mark Done” action, and a morning briefing for the day ahead. |
| Manual UI | Today dashboard, month calendar, task list (with EventKit reminders), notes, settings and onboarding. |
| Customisation | Accent colour palettes, light/dark/system appearance, rounded typeface, custom wake phrase, alert timing, morning briefing time. |

## Project layout

```
VoiceCalendar.xcodeproj
VoiceCalendar/
  App/            VoiceCalendarApp (entry, SwiftData container, notification delegate), RootView, AppSettings
  Models/         Note, TaskItem (SwiftData)
  Services/
    SpeechService     AVAudioEngine + SFSpeechRecognizer streaming transcripts
    VoiceAssistant    Wake-word loop, command capture, execution, spoken feedback
    CommandParser     Transcript -> VoiceIntent (event / reminder / task / note / query / delete)
    DateParser        NSDataDetector + heuristics for dates, durations and recurrence
    CalendarService   EventKit events & reminders, change observation
    NotificationService  Local notifications and the daily briefing
    PermissionsManager   Status + requests for mic, speech, calendar, reminders, notifications
    SpeechOutput      AVSpeechSynthesizer feedback
  Views/          Today, Calendar, Tasks (+ Reminders), Notes, Settings, Voice overlay, Onboarding
  Resources/      Asset catalog (app icon, accent colour)
VoiceCalendarTests/  Unit tests for the command parser and date parser
```

## Getting started

1. Open `VoiceCalendar.xcodeproj` in **Xcode 16** or later.
2. Select the `VoiceCalendar` target → *Signing & Capabilities* and choose your Apple ID / team. Change the bundle identifier if Xcode reports it is taken.
3. Pick your iPhone as the run destination and press **Run**. Speech recognition and the microphone need a real device; the Simulator can show the UI but cannot listen.
4. On first launch, tap **Allow access & get started** and accept the microphone, speech, calendar, reminders and notification prompts.
5. Say “Hey Calendar, add coffee with Alex tomorrow at 9 AM” or tap the microphone button.

Run the unit tests with **⌘U** (they only need the Simulator).

## How the voice pipeline works

1. `SpeechService` opens the microphone with `AVAudioEngine` and streams buffers into `SFSpeechRecognizer` with partial results enabled (on-device when available).
2. `VoiceAssistant` watches every partial transcript for the wake phrase (plus common mis-hearings such as “hey calender”). Once heard, the words after it become the command. The mic button starts a command directly.
3. After ~1.6 s of silence (or a final result) the command is parsed by `CommandParser`, which classifies the intent and uses `DateParser` to pull out dates, times, durations, locations and recurrence.
4. The intent is executed against EventKit (`CalendarService`) or SwiftData (tasks and notes), notifications are scheduled, and the response is shown in the overlay and spoken with `AVSpeechSynthesizer`.
5. Listening resumes automatically. Apple's recogniser ends a session after roughly a minute, so the loop transparently restarts it.

## Settings

* **Appearance** — pick one of eight accent palettes (each tuned for light and dark), force light or dark mode or follow the system, and switch to the rounded system typeface.
* **Wake phrase** — any short phrase; default “Hey Calendar”.
* **Keep listening in background** — keeps the microphone open after you leave the app (uses the `audio` background mode; the orange microphone indicator stays visible and battery use increases).
* **Prefer on-device recognition** — private and offline when the device supports it.
* **Deliver alerts via Calendar & Reminders** — on by default: alarms are attached to the items themselves so iOS delivers them even when the app is closed. Turn it off to have Voice Calendar send its own notifications instead.
* **Morning briefing** — a notification each morning summarising the day's events and tasks.

## Limitations and notes

* iOS does not let third-party apps run a true always-on “Hey Siri”-style wake word when the app is not running. The wake phrase works while the app is open, and optionally while it is in the background with the microphone active. It cannot wake the app from a terminated state.
* Speech recognition quality depends on the device, language and (when not on-device) network conditions. The parser is tuned for English phrasing.
* If Reminders access is denied, spoken reminders are saved as local tasks so nothing is lost.
* The default calendar for new events is the one set in iOS Settings → Calendar → Default Calendar.

## Ideas for next steps

* Siri Shortcuts / App Intents so Siri itself can hand commands to the app.
* A Home Screen widget with the next event and today's tasks.
* Rescheduling by voice (“move dentist to Friday”).
* Additional languages for the command parser.
