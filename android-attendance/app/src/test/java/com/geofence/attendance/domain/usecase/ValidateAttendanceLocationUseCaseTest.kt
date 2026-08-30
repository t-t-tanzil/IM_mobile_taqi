package com.geofence.attendance.domain.usecase

import com.geofence.attendance.domain.model.LocationData
import com.geofence.attendance.domain.model.OfficeLocation
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ValidateAttendanceLocationUseCaseTest {

    private val office = OfficeLocation(latitude = 37.7749, longitude = -122.4194)
    private val anyCurrentLocation = LocationData(
        latitude = office.latitude,
        longitude = office.longitude,
        accuracy = 5f,
        timestamp = 0L,
    )

    private class FixedDistanceUseCase(private val distanceMeters: Float) : CalculateDistanceUseCase() {
        override fun invoke(officeLocation: OfficeLocation, currentLocation: LocationData): Float = distanceMeters
    }

    private fun useCaseWithFixedDistance(distanceMeters: Float) =
        ValidateAttendanceLocationUseCase(FixedDistanceUseCase(distanceMeters))

    @Test
    fun `zero distance is eligible`() {
        val useCase = useCaseWithFixedDistance(0f)

        assertTrue(useCase(office, anyCurrentLocation))
    }

    @Test
    fun `distance exactly at the radius is eligible`() {
        val useCase = useCaseWithFixedDistance(ValidateAttendanceLocationUseCase.ALLOWED_RADIUS_METERS)

        assertTrue(useCase(office, anyCurrentLocation))
    }

    @Test
    fun `distance just past the radius is not eligible`() {
        val useCase = useCaseWithFixedDistance(50.01f)

        assertFalse(useCase(office, anyCurrentLocation))
    }

    @Test
    fun `distance clearly outside the radius is not eligible`() {
        val useCase = useCaseWithFixedDistance(500f)

        assertFalse(useCase(office, anyCurrentLocation))
    }

    @Test
    fun `real coordinates well within the radius are eligible`() {
        val useCase = ValidateAttendanceLocationUseCase(CalculateDistanceUseCase())
        val current = LocationData(
            latitude = office.latitude + 0.0001, // ~11m north, comfortably inside 50m
            longitude = office.longitude,
            accuracy = 5f,
            timestamp = 0L,
        )

        assertTrue(useCase(office, current))
    }

    @Test
    fun `real coordinates well outside the radius are not eligible`() {
        val useCase = ValidateAttendanceLocationUseCase(CalculateDistanceUseCase())
        val current = LocationData(
            latitude = office.latitude + 0.01, // ~1.1km north, well outside 50m
            longitude = office.longitude,
            accuracy = 5f,
            timestamp = 0L,
        )

        assertFalse(useCase(office, current))
    }
}
