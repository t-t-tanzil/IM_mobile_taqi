package com.geofence.attendance.data.location

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import android.os.Looper
import androidx.core.content.ContextCompat
import androidx.core.location.LocationManagerCompat
import com.geofence.attendance.domain.model.LocationData
import com.geofence.attendance.domain.model.LocationPermissionMissingException
import com.geofence.attendance.domain.model.LocationServicesDisabledException
import com.geofence.attendance.domain.model.LocationUnavailableException
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.LocationAvailability
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.Priority
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Job
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

private const val UPDATE_INTERVAL_MS = 5_000L
private const val MIN_UPDATE_INTERVAL_MS = 2_000L

/**
 * Play Services routinely reports isLocationAvailable=false for a brief moment right after a
 * fresh registration (before it has warmed up), even when a fix arrives moments later. Treating
 * that as fatal immediately would make retryLocationUpdates() effectively unable to recover.
 * Only close the flow if unavailability persists past this grace period.
 */
private const val UNAVAILABLE_GRACE_PERIOD_MS = 8_000L

class FusedLocationDataSource @Inject constructor(
    @ApplicationContext private val context: Context,
    private val fusedLocationClient: FusedLocationProviderClient,
) : LocationDataSource {

    override fun observeLocationUpdates(): Flow<LocationData> = callbackFlow {
        if (!hasLocationPermission()) {
            close(LocationPermissionMissingException())
            return@callbackFlow
        }

        if (!isLocationServicesEnabled()) {
            close(LocationServicesDisabledException())
            return@callbackFlow
        }

        val locationRequest = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, UPDATE_INTERVAL_MS)
            .setMinUpdateIntervalMillis(MIN_UPDATE_INTERVAL_MS)
            .build()

        val producerScope = this
        var unavailabilityJob: Job? = null

        val callback = object : LocationCallback() {
            override fun onLocationResult(result: LocationResult) {
                result.lastLocation?.let { location ->
                    unavailabilityJob?.cancel()
                    trySend(location.toLocationData())
                }
            }

            override fun onLocationAvailability(availability: LocationAvailability) {
                if (availability.isLocationAvailable) {
                    unavailabilityJob?.cancel()
                } else if (unavailabilityJob?.isActive != true) {
                    unavailabilityJob = producerScope.launch {
                        delay(UNAVAILABLE_GRACE_PERIOD_MS)
                        close(LocationUnavailableException())
                    }
                }
            }
        }

        try {
            fusedLocationClient.requestLocationUpdates(locationRequest, callback, Looper.getMainLooper())
        } catch (exception: SecurityException) {
            close(LocationPermissionMissingException())
        }

        awaitClose {
            unavailabilityJob?.cancel()
            fusedLocationClient.removeLocationUpdates(callback)
        }
    }

    private fun hasLocationPermission(): Boolean =
        ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.ACCESS_FINE_LOCATION,
        ) == PackageManager.PERMISSION_GRANTED

    private fun isLocationServicesEnabled(): Boolean {
        val locationManager = context.getSystemService(LocationManager::class.java) ?: return false
        return LocationManagerCompat.isLocationEnabled(locationManager)
    }

    private fun Location.toLocationData() = LocationData(
        latitude = latitude,
        longitude = longitude,
        accuracy = accuracy,
        timestamp = time,
    )
}
