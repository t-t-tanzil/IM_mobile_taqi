package com.geofence.attendance.domain.repository

import com.geofence.attendance.domain.model.LocationData
import com.geofence.attendance.domain.model.OfficeLocation
import kotlinx.coroutines.flow.Flow

interface AttendanceRepository {
    suspend fun saveOfficeLocation(officeLocation: OfficeLocation)
    fun observeOfficeLocation(): Flow<OfficeLocation?>
    fun observeCurrentLocation(): Flow<LocationData>
}
