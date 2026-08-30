package com.geofence.attendance.presentation.attendance

import org.junit.Assert.assertEquals
import org.junit.Test

class AttendanceScreenStateTest {

    @Test
    fun `denied permission requests permission regardless of location availability`() {
        assertEquals(
            AttendanceScreenMode.RequestPermission,
            resolveAttendanceScreenMode(LocationPermissionStatus.Denied, LocationAvailability.Unknown),
        )
    }

    @Test
    fun `permanently denied permission requires opening settings`() {
        assertEquals(
            AttendanceScreenMode.PermissionSettingsRequired,
            resolveAttendanceScreenMode(LocationPermissionStatus.PermanentlyDenied, LocationAvailability.Available),
        )
    }

    @Test
    fun `permanently denied takes priority over location services being disabled`() {
        assertEquals(
            AttendanceScreenMode.PermissionSettingsRequired,
            resolveAttendanceScreenMode(
                LocationPermissionStatus.PermanentlyDenied,
                LocationAvailability.Unavailable.LocationServicesDisabled,
            ),
        )
    }

    @Test
    fun `granted permission with disabled location services shows the location services state`() {
        assertEquals(
            AttendanceScreenMode.LocationServicesDisabled,
            resolveAttendanceScreenMode(
                LocationPermissionStatus.Granted,
                LocationAvailability.Unavailable.LocationServicesDisabled,
            ),
        )
    }

    @Test
    fun `granted permission with available location shows content`() {
        assertEquals(
            AttendanceScreenMode.Content,
            resolveAttendanceScreenMode(LocationPermissionStatus.Granted, LocationAvailability.Available),
        )
    }

    @Test
    fun `granted permission with a temporary failure still shows content so the screen can render a status banner`() {
        assertEquals(
            AttendanceScreenMode.Content,
            resolveAttendanceScreenMode(
                LocationPermissionStatus.Granted,
                LocationAvailability.Unavailable.TemporarilyUnavailable("GPS signal lost"),
            ),
        )
    }
}
