package com.geofence.attendance.domain.usecase

import com.geofence.attendance.domain.model.LocationData
import com.geofence.attendance.domain.model.OfficeLocation
import org.junit.Assert.assertEquals
import org.junit.Test
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sqrt

private const val EARTH_RADIUS_METERS = 6_371_000.0
private const val METERS_PER_DEGREE_LATITUDE = EARTH_RADIUS_METERS * PI / 180.0

class CalculateDistanceUseCaseTest {

    private val useCase = CalculateDistanceUseCase()

    private fun locationAt(latitude: Double, longitude: Double) = LocationData(
        latitude = latitude,
        longitude = longitude,
        accuracy = 5f,
        timestamp = 0L,
    )

    @Test
    fun `same coordinates produce approximately zero distance`() {
        val office = OfficeLocation(latitude = 37.7749, longitude = -122.4194)
        val current = locationAt(37.7749, -122.4194)

        assertEquals(0f, useCase(office, current), 0.01f)
    }

    @Test
    fun `short north-south offset matches expected arc length`() {
        val office = OfficeLocation(latitude = 0.0, longitude = 0.0)
        val deltaDegrees = 0.001 // ~111m at the equator
        val current = locationAt(deltaDegrees, 0.0)

        val expected = (deltaDegrees * METERS_PER_DEGREE_LATITUDE).toFloat()
        assertEquals(expected, useCase(office, current), 1f)
    }

    @Test
    fun `larger north-south offset scales proportionally`() {
        val office = OfficeLocation(latitude = 0.0, longitude = 0.0)
        val deltaDegrees = 1.0 // ~111km at the equator
        val current = locationAt(deltaDegrees, 0.0)

        val expected = (deltaDegrees * METERS_PER_DEGREE_LATITUDE).toFloat()
        assertEquals(expected, useCase(office, current), 50f)
    }

    @Test
    fun `combined latitude and longitude offset matches flat-earth approximation at short range`() {
        val officeLat = 37.7749
        val officeLon = -122.4194
        val deltaLatDeg = 0.01
        val deltaLonDeg = 0.01
        val office = OfficeLocation(latitude = officeLat, longitude = officeLon)
        val current = locationAt(officeLat + deltaLatDeg, officeLon + deltaLonDeg)

        val metersPerDegreeLongitude = METERS_PER_DEGREE_LATITUDE * cos(Math.toRadians(officeLat + deltaLatDeg / 2))
        val northMeters = deltaLatDeg * METERS_PER_DEGREE_LATITUDE
        val eastMeters = deltaLonDeg * metersPerDegreeLongitude
        val expected = sqrt(northMeters * northMeters + eastMeters * eastMeters).toFloat()

        assertEquals(expected, useCase(office, current), 1f)
    }
}
