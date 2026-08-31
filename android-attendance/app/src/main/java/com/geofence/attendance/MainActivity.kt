package com.geofence.attendance

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.animation.Crossfade
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import com.geofence.attendance.presentation.attendance.AttendanceScreen
import com.geofence.attendance.presentation.splash.SplashScreen
import com.geofence.attendance.ui.theme.AttendanceTheme
import dagger.hilt.android.AndroidEntryPoint

@AndroidEntryPoint
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            // Forced dark, regardless of system setting - the attendance screen's design
            // is dark-first by explicit requirement, not adaptive to device theme.
            AttendanceTheme(darkTheme = true) {
                var showSplash by remember { mutableStateOf(true) }
                Crossfade(targetState = showSplash, label = "splashToAttendance") { splashVisible ->
                    if (splashVisible) {
                        SplashScreen(onTimeout = { showSplash = false })
                    } else {
                        AttendanceScreen()
                    }
                }
            }
        }
    }
}
