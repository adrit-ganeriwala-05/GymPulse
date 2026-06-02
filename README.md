# GymPulse

A clean, minimal workout tracking app built with Flutter.

## Features

- **Workout logging** — create and track workouts with exercises, sets, reps, and weight
- **Active workout session** — live workout timer, rest timer between sets, and exercise log
- **Streak tracking** — daily workout streak with badge display
- **Workout history** — browse past workouts with summary cards
- **Calendar view** — visualize workout days on a monthly calendar
- **Weight unit settings** — toggle between kg and lbs
- **Onboarding** — first-launch setup flow

## Tech Stack

- **Flutter** + **Dart**
- **flutter_bloc** — state management
- **get_it** — dependency injection
- **go_router** — navigation
- **sqflite** — local SQLite database
- **shared_preferences** — lightweight persistent storage
- **table_calendar** — calendar widget
- **google_fonts** — Playfair Display + DM Sans typography
- **flutter_animate** — UI animations

## Architecture

Clean Architecture with three layers:

```
lib/
├── data/           # Models, datasources, repository implementations
├── domain/         # Entities, repository interfaces, use cases
└── presentation/   # Screens, widgets, BLoCs
```

## Getting Started

**Prerequisites:** Flutter SDK 3.x, Dart SDK ^3.11.4

```bash
git clone "https://github.com/adrit-ganeriwala-05/GymPulse"
cd gympulse
flutter pub get
flutter run
```
