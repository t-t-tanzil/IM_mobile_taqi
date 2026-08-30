package com.geofence.attendance.domain.usecase

import com.geofence.attendance.domain.model.OfficeLocation
import com.geofence.attendance.domain.repository.AttendanceRepository
import kotlinx.coroutines.flow.Flow
import javax.inject.Inject

class GetOfficeLocationUseCase @Inject constructor(
    private val repository: AttendanceRepository,
) {
    operator fun invoke(): Flow<OfficeLocation?> = repository.observeOfficeLocation()
}
