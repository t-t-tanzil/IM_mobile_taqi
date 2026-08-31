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

/**
 * The circular distance gauge is a "how far out of range" indicator, not a "how close"
 * one: progress increases as the user gets farther from the office, reaching full ring
 * at [DISTANCE_GAUGE_MAX_METERS] and beyond. Kept pure and separate from the Composable
 * so it's unit-testable without Compose in the loop.
 */
const val DISTANCE_GAUGE_MAX_METERS = 200f

fun distanceGaugeProgress(distanceMeters: Float): Float =
    (distanceMeters / DISTANCE_GAUGE_MAX_METERS).coerceIn(0f, 1f)
