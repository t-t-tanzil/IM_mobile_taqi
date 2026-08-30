package com.geofence.attendance.domain.usecase

import com.geofence.attendance.domain.model.LocationData
import com.geofence.attendance.domain.model.OfficeLocation
import javax.inject.Inject

class ValidateAttendanceLocationUseCase @Inject constructor(
    private val calculateDistanceUseCase: CalculateDistanceUseCase,
) {
    companion object {
        const val ALLOWED_RADIUS_METERS = 50f
    }

    operator fun invoke(
        officeLocation: OfficeLocation,
        currentLocation: LocationData,
    ): Boolean {
        TODO("Implement radius validation in the next phase")
    }
}
