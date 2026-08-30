package com.geofence.attendance.presentation.attendance

import com.geofence.attendance.domain.model.OfficeLocation

data class AttendanceUiState(
    val officeLocation: OfficeLocation? = null,
    val distanceMeters: Float? = null,
    val isWithinRange: Boolean = false,
    val isLoading: Boolean = false,
    val errorMessage: String? = null,
)
