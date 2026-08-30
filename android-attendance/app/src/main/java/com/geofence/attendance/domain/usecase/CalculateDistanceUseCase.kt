package com.geofence.attendance.domain.usecase

import javax.inject.Inject

class CalculateDistanceUseCase @Inject constructor() {
    operator fun invoke(
        officeLatitude: Double,
        officeLongitude: Double,
        currentLatitude: Double,
        currentLongitude: Double,
    ): Float {
        TODO("Implement distance calculation in the next phase")
    }
}
