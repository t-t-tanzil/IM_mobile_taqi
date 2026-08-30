package com.geofence.attendance.presentation.attendance

/** Which top-level screen mode to show, driven by permission + location-service state. */
enum class AttendanceScreenMode {
    RequestPermission,
    PermissionSettingsRequired,
    LocationServicesDisabled,
    Content,
}

/**
 * Pure decision function kept separate from Compose so it can be unit tested directly.
 * [AttendanceScreen] must use this rather than re-deriving the same branching inline.
 */
fun resolveAttendanceScreenMode(
    permissionStatus: LocationPermissionStatus,
    locationAvailability: LocationAvailability,
): AttendanceScreenMode = when {
    permissionStatus == LocationPermissionStatus.PermanentlyDenied -> AttendanceScreenMode.PermissionSettingsRequired
    permissionStatus == LocationPermissionStatus.Denied -> AttendanceScreenMode.RequestPermission
    // Covers the case where permissionStatus is still stale-Granted (not yet
    // refreshed) but a location call has already surfaced a real permission
    // failure - e.g. revoked via Settings while the app was backgrounded.
    locationAvailability == LocationAvailability.Unavailable.PermissionMissing ->
        AttendanceScreenMode.RequestPermission
    locationAvailability == LocationAvailability.Unavailable.LocationServicesDisabled ->
        AttendanceScreenMode.LocationServicesDisabled
    else -> AttendanceScreenMode.Content
}
