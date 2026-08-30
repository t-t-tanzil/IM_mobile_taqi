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
    locationAvailability == LocationAvailability.Unavailable.LocationServicesDisabled ->
        AttendanceScreenMode.LocationServicesDisabled
    else -> AttendanceScreenMode.Content
}
