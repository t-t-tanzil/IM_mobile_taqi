package com.geofence.attendance.data.repository

import com.geofence.attendance.data.local.OfficeLocationDataStore
import com.geofence.attendance.data.location.LocationDataSource
import com.geofence.attendance.domain.model.LocationData
import com.geofence.attendance.domain.model.OfficeLocation
import com.geofence.attendance.domain.repository.AttendanceRepository
import kotlinx.coroutines.flow.Flow
import javax.inject.Inject

class AttendanceRepositoryImpl @Inject constructor(
    private val officeLocationDataStore: OfficeLocationDataStore,
    private val locationDataSource: LocationDataSource,
) : AttendanceRepository {

    override suspend fun saveOfficeLocation(officeLocation: OfficeLocation) =
        officeLocationDataStore.saveOfficeLocation(officeLocation)

    override fun observeOfficeLocation(): Flow<OfficeLocation?> =
        officeLocationDataStore.observeOfficeLocation()

    override fun observeCurrentLocation(): Flow<LocationData> =
        locationDataSource.observeLocationUpdates()
}
