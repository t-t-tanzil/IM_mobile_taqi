package com.geofence.attendance.domain.usecase

import com.geofence.attendance.domain.model.LocationData
import com.geofence.attendance.domain.model.OfficeLocation
import com.geofence.attendance.domain.repository.AttendanceRepository
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Test

class GetCurrentLocationUseCaseTest {

    private class FakeAttendanceRepository(
        private val currentLocation: Flow<LocationData>,
    ) : AttendanceRepository {
        override suspend fun saveOfficeLocation(officeLocation: OfficeLocation) = Unit
        override fun observeOfficeLocation(): Flow<OfficeLocation?> = flowOf(null)
        override fun observeCurrentLocation(): Flow<LocationData> = currentLocation
    }

    @Test
    fun `invoke forwards the repository's current location flow`() = runBlocking {
        val expected = LocationData(latitude = 1.0, longitude = 2.0, accuracy = 5f, timestamp = 1_234L)
        val useCase = GetCurrentLocationUseCase(FakeAttendanceRepository(flowOf(expected)))

        val actual = useCase().first()

        assertEquals(expected, actual)
    }
}
