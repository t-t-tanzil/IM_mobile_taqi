package com.geofence.attendance.domain.usecase

import com.geofence.attendance.domain.model.LocationData
import com.geofence.attendance.domain.model.OfficeLocation
import javax.inject.Inject
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

private const val EARTH_RADIUS_METERS = 6_371_000.0

/**
 * Great-circle distance between two coordinates using the Haversine formula,
 * which accounts for Earth's curvature (unlike a flat lat/lon subtraction).
 */
open class CalculateDistanceUseCase @Inject constructor() {
    open operator fun invoke(
        officeLocation: OfficeLocation,
        currentLocation: LocationData,
    ): Float {
        val lat1Rad = Math.toRadians(officeLocation.latitude)
        val lat2Rad = Math.toRadians(currentLocation.latitude)
        val deltaLatRad = Math.toRadians(currentLocation.latitude - officeLocation.latitude)
        val deltaLonRad = Math.toRadians(currentLocation.longitude - officeLocation.longitude)

        val a = sin(deltaLatRad / 2) * sin(deltaLatRad / 2) +
            cos(lat1Rad) * cos(lat2Rad) * sin(deltaLonRad / 2) * sin(deltaLonRad / 2)
        val centralAngle = 2 * atan2(sqrt(a), sqrt(1 - a))

        return (EARTH_RADIUS_METERS * centralAngle).toFloat()
    }
}
