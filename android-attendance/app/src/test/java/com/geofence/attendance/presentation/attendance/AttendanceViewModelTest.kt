package com.geofence.attendance.presentation.attendance

import com.geofence.attendance.domain.model.LocationData
import com.geofence.attendance.domain.model.LocationPermissionMissingException
import com.geofence.attendance.domain.model.LocationServicesDisabledException
import com.geofence.attendance.domain.model.LocationUnavailableException
import com.geofence.attendance.domain.model.OfficeLocation
import com.geofence.attendance.domain.repository.AttendanceRepository
import com.geofence.attendance.domain.usecase.CalculateDistanceUseCase
import com.geofence.attendance.domain.usecase.GetCurrentLocationUseCase
import com.geofence.attendance.domain.usecase.GetOfficeLocationUseCase
import com.geofence.attendance.domain.usecase.SaveOfficeLocationUseCase
import com.geofence.attendance.domain.usecase.ValidateAttendanceLocationUseCase
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.io.IOException
import kotlin.math.PI

private const val EARTH_RADIUS_METERS = 6_371_000.0
private const val METERS_PER_DEGREE_LATITUDE = EARTH_RADIUS_METERS * PI / 180.0

@OptIn(ExperimentalCoroutinesApi::class)
class AttendanceViewModelTest {

    private val testDispatcher = StandardTestDispatcher()
    private val office = OfficeLocation(latitude = 37.7749, longitude = -122.4194)

    @Before
    fun setUp() {
        Dispatchers.setMain(testDispatcher)
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    private fun degreesForMeters(meters: Double) = meters / METERS_PER_DEGREE_LATITUDE

    private fun locationAtOffsetMeters(meters: Double) = LocationData(
        latitude = office.latitude + degreesForMeters(meters),
        longitude = office.longitude,
        accuracy = 5f,
        timestamp = 0L,
    )

    private fun createViewModel(repository: FakeAttendanceRepository) = AttendanceViewModel(
        getOfficeLocationUseCase = GetOfficeLocationUseCase(repository),
        saveOfficeLocationUseCase = SaveOfficeLocationUseCase(repository),
        getCurrentLocationUseCase = GetCurrentLocationUseCase(repository),
        calculateDistanceUseCase = CalculateDistanceUseCase(),
        validateAttendanceLocationUseCase = ValidateAttendanceLocationUseCase(CalculateDistanceUseCase()),
    )

    @Test
    fun `no office location shows setup required state`() = runTest {
        val repository = FakeAttendanceRepository()
        val viewModel = createViewModel(repository)
        testDispatcher.scheduler.advanceUntilIdle()

        val state = viewModel.uiState.value
        assertFalse(state.isOfficeLocationConfigured)
        assertNull(state.officeLocation)
        assertNull(state.distanceMeters)
        assertFalse(state.isWithinAttendanceRadius)
    }

    @Test
    fun `current location inside 50m is eligible`() = runTest {
        val repository = FakeAttendanceRepository(officeLocation = office)
        val viewModel = createViewModel(repository)

        repository.emitCurrentLocation(locationAtOffsetMeters(11.0))
        testDispatcher.scheduler.advanceUntilIdle()

        val state = viewModel.uiState.value
        assertTrue(state.isWithinAttendanceRadius)
        assertTrue((state.distanceMeters ?: Float.MAX_VALUE) <= 50f)
    }

    @Test
    fun `current location outside 50m is not eligible`() = runTest {
        val repository = FakeAttendanceRepository(officeLocation = office)
        val viewModel = createViewModel(repository)

        repository.emitCurrentLocation(locationAtOffsetMeters(1_100.0))
        testDispatcher.scheduler.advanceUntilIdle()

        assertFalse(viewModel.uiState.value.isWithinAttendanceRadius)
    }

    @Test
    fun `distance and eligibility update as current location changes`() = runTest {
        val repository = FakeAttendanceRepository(officeLocation = office)
        val viewModel = createViewModel(repository)

        val sequenceMeters = listOf(120.0, 80.0, 55.0, 49.0, 51.0)
        val expectedEligibility = listOf(false, false, false, true, false)

        sequenceMeters.forEachIndexed { index, meters ->
            repository.emitCurrentLocation(locationAtOffsetMeters(meters))
            testDispatcher.scheduler.advanceUntilIdle()

            assertEquals(
                "at ${meters}m",
                expectedEligibility[index],
                viewModel.uiState.value.isWithinAttendanceRadius,
            )
        }
    }

    @Test
    fun `set office location succeeds using the latest current location`() = runTest {
        val repository = FakeAttendanceRepository()
        val viewModel = createViewModel(repository)
        val current = locationAtOffsetMeters(0.0)
        repository.emitCurrentLocation(current)
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.setOfficeLocation()
        testDispatcher.scheduler.advanceUntilIdle()

        assertEquals(1, repository.savedOfficeLocations.size)
        assertEquals(current.latitude, repository.savedOfficeLocations.first().latitude, 0.0000001)
        assertEquals(current.longitude, repository.savedOfficeLocations.first().longitude, 0.0000001)
        assertFalse(viewModel.uiState.value.isSavingOfficeLocation)
        assertTrue(viewModel.uiState.value.isOfficeLocationConfigured)
    }

    @Test
    fun `set office location fails when current location is unavailable`() = runTest {
        val repository = FakeAttendanceRepository()
        repository.currentLocationFailure = IOException("no fix")
        val viewModel = createViewModel(repository)

        viewModel.setOfficeLocation()
        testDispatcher.scheduler.advanceUntilIdle()

        assertTrue(repository.savedOfficeLocations.isEmpty())
        assertFalse(viewModel.uiState.value.isOfficeLocationConfigured)
        assertFalse(viewModel.uiState.value.isSavingOfficeLocation)
        assertNotNull(viewModel.uiState.value.errorMessage)
    }

    @Test
    fun `mark attendance inside radius succeeds`() = runTest {
        val repository = FakeAttendanceRepository(officeLocation = office)
        val viewModel = createViewModel(repository)
        repository.emitCurrentLocation(locationAtOffsetMeters(10.0))
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.markAttendance()

        assertTrue(viewModel.uiState.value.attendanceMarked)
    }

    @Test
    fun `mark attendance outside radius does not mark attendance`() = runTest {
        val repository = FakeAttendanceRepository(officeLocation = office)
        val viewModel = createViewModel(repository)
        repository.emitCurrentLocation(locationAtOffsetMeters(500.0))
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.markAttendance()

        assertFalse(viewModel.uiState.value.attendanceMarked)
        assertNotNull(viewModel.uiState.value.errorMessage)
    }

    @Test
    fun `missing permission is reported distinctly from other location failures`() = runTest {
        val repository = FakeAttendanceRepository(officeLocation = office)
        repository.currentLocationFailure = LocationPermissionMissingException()
        val viewModel = createViewModel(repository)
        testDispatcher.scheduler.advanceUntilIdle()

        assertEquals(
            LocationAvailability.Unavailable.PermissionMissing,
            viewModel.uiState.value.locationAvailability,
        )
    }

    @Test
    fun `disabled location services are reported distinctly from other location failures`() = runTest {
        val repository = FakeAttendanceRepository(officeLocation = office)
        repository.currentLocationFailure = LocationServicesDisabledException()
        val viewModel = createViewModel(repository)
        testDispatcher.scheduler.advanceUntilIdle()

        assertEquals(
            LocationAvailability.Unavailable.LocationServicesDisabled,
            viewModel.uiState.value.locationAvailability,
        )
    }

    @Test
    fun `temporary location failure is reported distinctly with its message`() = runTest {
        val repository = FakeAttendanceRepository(officeLocation = office)
        repository.currentLocationFailure = LocationUnavailableException()
        val viewModel = createViewModel(repository)
        testDispatcher.scheduler.advanceUntilIdle()

        val availability = viewModel.uiState.value.locationAvailability
        assertTrue(availability is LocationAvailability.Unavailable.TemporarilyUnavailable)
    }

    @Test
    fun `retrying after a temporary failure resubscribes and recovers`() = runTest {
        val repository = FakeAttendanceRepository(officeLocation = office)
        repository.currentLocationFailure = LocationPermissionMissingException()
        val viewModel = createViewModel(repository)
        testDispatcher.scheduler.advanceUntilIdle()

        assertEquals(
            LocationAvailability.Unavailable.PermissionMissing,
            viewModel.uiState.value.locationAvailability,
        )

        repository.currentLocationFailure = null
        viewModel.retryLocationUpdates()
        repository.emitCurrentLocation(locationAtOffsetMeters(10.0))
        testDispatcher.scheduler.advanceUntilIdle()

        val state = viewModel.uiState.value
        assertEquals(LocationAvailability.Available, state.locationAvailability)
        assertNotNull(state.currentLocation)
        assertTrue(state.isWithinAttendanceRadius)
    }
}

private class FakeAttendanceRepository(
    officeLocation: OfficeLocation? = null,
) : AttendanceRepository {

    private val officeLocationState = MutableStateFlow(officeLocation)
    private val currentLocationState = MutableSharedFlow<LocationData>(replay = 1, extraBufferCapacity = 8)

    var currentLocationFailure: Throwable? = null
    val savedOfficeLocations = mutableListOf<OfficeLocation>()

    override suspend fun saveOfficeLocation(officeLocation: OfficeLocation) {
        savedOfficeLocations += officeLocation
        officeLocationState.value = officeLocation
    }

    override fun observeOfficeLocation(): Flow<OfficeLocation?> = officeLocationState

    override fun observeCurrentLocation(): Flow<LocationData> =
        currentLocationFailure?.let { throwable -> flow { throw throwable } } ?: currentLocationState

    fun emitCurrentLocation(locationData: LocationData) {
        currentLocationState.tryEmit(locationData)
    }
}
