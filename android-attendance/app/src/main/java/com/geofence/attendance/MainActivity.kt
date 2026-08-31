package com.geofence.attendance

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import com.geofence.attendance.presentation.attendance.AttendanceScreen
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
                AttendanceScreen()
            }
        }
    }
}
