# Flutter engine + plugin registrant
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-dontwarn io.flutter.embedding.**

# Play Core is not bundled; Flutter references it for deferred components.
-dontwarn com.google.android.play.core.**

# sqflite
-keep class com.tekartik.sqflite.** { *; }

# workmanager background dispatcher entrypoint
-keep class be.tramckrijte.workmanager.** { *; }
-keep class dev.fluttercommunity.workmanager.** { *; }

# Kotlin metadata used by plugins via reflection
-keep class kotlin.Metadata { *; }
