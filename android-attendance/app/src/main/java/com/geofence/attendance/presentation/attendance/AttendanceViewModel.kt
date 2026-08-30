package com.geofence.attendance.presentation.attendance

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.geofence.attendance.domain.model.LocationData
import com.geofence.attendance.domain.model.LocationPermissionMissingException
import com.geofence.attendance.domain.model.LocationServicesDisabledException
import com.geofence.attendance.domain.model.LocationUnavailableException
import com.geofence.attendance.domain.model.OfficeLocation
import com.geofence.attendance.domain.usecase.CalculateDistanceUseCase
import com.geofence.attendance.domain.usecase.GetCurrentLocationUseCase
import com.geofence.attendance.domain.usecase.GetOfficeLocationUseCase
import com.geofence.attendance.domain.usecase.SaveOfficeLocationUseCase
import com.geofence.attendance.domain.usecase.ValidateAttendanceLocationUseCase
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

/** Purely derived from the office/current location flows - kept separate from action-triggered UI state (saving/marking/errors). */
private data class LocationSnapshot(
    val officeLocation: OfficeLocation? = null,
    val currentLocation: LocationData? = null,
    val distanceMeters: Float? = null,
    val isWithinAttendanceRadius: Boolean = false,
    val locationAvailability: LocationAvailability = LocationAvailability.Unknown,
)

@OptIn(ExperimentalCoroutinesApi::class)
@HiltViewModel
class AttendanceViewModel @Inject constructor(
    private val getOfficeLocationUseCase: GetOfficeLocationUseCase,
    private val saveOfficeLocationUseCase: SaveOfficeLocationUseCase,
    private val getCurrentLocationUseCase: GetCurrentLocationUseCase,
    private val calculateDistanceUseCase: CalculateDistanceUseCase,
    private val validateAttendanceLocationUseCase: ValidateAttendanceLocationUseCase,
) : ViewModel() {

    private val _uiState = MutableStateFlow(AttendanceUiState())
    val uiState: StateFlow<AttendanceUiState> = _uiState.asStateFlow()

    /**
     * The current-location flow terminates whenever [getCurrentLocationUseCase] fails
     * (missing permission, services disabled, provider error). Re-emitting here via
     * [retryLocationUpdates] makes flatMapLatest cancel the dead flow and open a fresh
     * subscription, so the presentation layer can recover without recreating the ViewModel.
     */
    private val locationRetrySignal = MutableSharedFlow<Unit>(replay = 1, extraBufferCapacity = 1).apply {
        tryEmit(Unit)
    }

    private val currentLocationEvents: Flow<Result<LocationData>> = locationRetrySignal.flatMapLatest {
        getCurrentLocationUseCase()
            .map<LocationData, Result<LocationData>> { location -> Result.success(location) }
            .catch { throwable -> emit(Result.failure(throwable)) }
    }

    private val locationSnapshot: StateFlow<LocationSnapshot> = combine(
        getOfficeLocationUseCase(),
        currentLocationEvents,
    ) { officeLocation, currentLocationResult ->
        buildSnapshot(officeLocation, currentLocationResult)
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), LocationSnapshot())

    init {
        viewModelScope.launch {
            locationSnapshot.collect { snapshot ->
                _uiState.update { state ->
                    state.copy(
                        officeLocation = snapshot.officeLocation,
                        currentLocation = snapshot.currentLocation,
                        distanceMeters = snapshot.distanceMeters,
                        isWithinAttendanceRadius = snapshot.isWithinAttendanceRadius,
                        locationAvailability = snapshot.locationAvailability,
                    )
                }
            }
        }
    }

    private fun buildSnapshot(
        officeLocation: OfficeLocation?,
        currentLocationResult: Result<LocationData>,
    ): LocationSnapshot {
        val currentLocation = currentLocationResult.getOrNull()
        val availability = if (currentLocation != null) {
            LocationAvailability.Available
        } else {
            currentLocationResult.exceptionOrNull().toLocationAvailability()
        }

        return LocationSnapshot(
            officeLocation = officeLocation,
            currentLocation = currentLocation,
            distanceMeters = if (officeLocation != null && currentLocation != null) {
                calculateDistanceUseCase(officeLocation, currentLocation)
            } else {
                null
            },
            isWithinAttendanceRadius = officeLocation != null &&
                currentLocation != null &&
                validateAttendanceLocationUseCase(officeLocation, currentLocation),
            locationAvailability = availability,
        )
    }

    fun setOfficeLocation() {
        if (_uiState.value.isSavingOfficeLocation) return

        viewModelScope.launch {
            _uiState.update { it.copy(isSavingOfficeLocation = true, errorMessage = null) }

            runCatching { getCurrentLocationUseCase().first() }
                .onSuccess { location ->
                    runCatching {
                        saveOfficeLocationUseCase(
                            OfficeLocation(latitude = location.latitude, longitude = location.longitude),
                        )
                    }.onFailure { throwable ->
                        _uiState.update { it.copy(errorMessage = throwable.toUserMessage()) }
                    }
                }
                .onFailure { throwable ->
                    _uiState.update { it.copy(errorMessage = throwable.toUserMessage()) }
                }

            _uiState.update { it.copy(isSavingOfficeLocation = false) }
        }
    }

    fun markAttendance() {
        val state = _uiState.value
        when {
            state.officeLocation == null -> _uiState.update {
                it.copy(errorMessage = "Set an office location before marking attendance.")
            }
            state.currentLocation == null -> _uiState.update {
                it.copy(errorMessage = "Current location is not available yet.")
            }
            !state.isWithinAttendanceRadius -> _uiState.update {
                val radius = ValidateAttendanceLocationUseCase.ALLOWED_RADIUS_METERS.toInt()
                it.copy(errorMessage = "You are outside the ${radius}m attendance radius.")
            }
            else -> _uiState.update { it.copy(attendanceMarked = true, errorMessage = null) }
        }
    }

    /**
     * Re-subscribes to the current-location flow. Intended to be called by the presentation
     * layer after a permission grant, a return from location settings, or a manual retry action.
     */
    fun retryLocationUpdates() {
        locationRetrySignal.tryEmit(Unit)
    }

    private fun Throwable?.toLocationAvailability(): LocationAvailability.Unavailable = when (this) {
        is LocationPermissionMissingException -> LocationAvailability.Unavailable.PermissionMissing
        is LocationServicesDisabledException -> LocationAvailability.Unavailable.LocationServicesDisabled
        is LocationUnavailableException -> LocationAvailability.Unavailable.TemporarilyUnavailable(
            message ?: "Location is temporarily unavailable.",
        )
        else -> LocationAvailability.Unavailable.TemporarilyUnavailable(
            this?.message ?: "An unexpected location error occurred.",
        )
    }

    private fun Throwable.toUserMessage(): String = when (this) {
        is LocationPermissionMissingException -> "Location permission is required to track your position."
        is LocationServicesDisabledException -> "Location services are turned off. Please enable them in settings."
        is LocationUnavailableException -> "Location is currently unavailable. Check that GPS is enabled."
        else -> message ?: "An unexpected location error occurred."
    }
}
