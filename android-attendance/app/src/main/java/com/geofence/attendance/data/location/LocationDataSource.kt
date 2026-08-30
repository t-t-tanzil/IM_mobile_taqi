package com.geofence.attendance.data.location

import com.geofence.attendance.domain.model.LocationData
import kotlinx.coroutines.flow.Flow

interface LocationDataSource {
    fun observeLocationUpdates(): Flow<LocationData>
}
