# WorkManager 2.7.0 brings Room 2.2.5 through Google Mobile Ads.
# Keep the generated database and runtime wiring intact in R8 release builds.
-keep class androidx.work.** { *; }
-keep class androidx.room.** { *; }
-keep class androidx.sqlite.** { *; }
