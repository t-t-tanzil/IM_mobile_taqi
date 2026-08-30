package com.geofence.attendance.domain.usecase

import com.geofence.attendance.domain.model.OfficeLocation
import com.geofence.attendance.domain.repository.AttendanceRepository
import javax.inject.Inject

class SaveOfficeLocationUseCase @Inject constructor(
    private val repository: AttendanceRepository,
) {
    suspend operator fun invoke(officeLocation: OfficeLocation) =
        repository.saveOfficeLocation(officeLocation)
}
