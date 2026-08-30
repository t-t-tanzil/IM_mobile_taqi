package com.geofence.attendance.presentation.attendance

import com.geofence.attendance.domain.model.LocationData
import com.geofence.attendance.domain.model.OfficeLocation

sealed interface LocationAvailability {
    data object Unknown : LocationAvailability
    data object Available : LocationAvailability

    /** Distinguishes *why* location is unavailable so the UI can offer the right action. */
    sealed interface Unavailable : LocationAvailability {
        data object PermissionMissing : Unavailable
        data object LocationServicesDisabled : Unavailable
        data class TemporarilyUnavailable(val message: String) : Unavailable
    }
}

data class AttendanceUiState(
    val officeLocation: OfficeLocation? = null,
    val currentLocation: LocationData? = null,
    val distanceMeters: Float? = null,
    val isWithinAttendanceRadius: Boolean = false,
    val isSavingOfficeLocation: Boolean = false,
    val attendanceMarked: Boolean = false,
    val locationAvailability: LocationAvailability = LocationAvailability.Unknown,
    val errorMessage: String? = null,
) {
    val isOfficeLocationConfigured: Boolean get() = officeLocation != null
    val isLoading: Boolean get() = locationAvailability == LocationAvailability.Unknown
}
