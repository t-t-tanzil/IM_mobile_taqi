package com.geofence.attendance.domain.usecase

import com.geofence.attendance.domain.model.LocationData
import com.geofence.attendance.domain.repository.AttendanceRepository
import kotlinx.coroutines.flow.Flow
import javax.inject.Inject

class GetCurrentLocationUseCase @Inject constructor(
    private val repository: AttendanceRepository,
) {
    operator fun invoke(): Flow<LocationData> = repository.observeCurrentLocation()
}
