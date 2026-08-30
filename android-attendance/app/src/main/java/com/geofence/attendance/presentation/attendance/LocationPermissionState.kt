package com.geofence.attendance.presentation.attendance

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat

/** Runtime status of the fine location permission, as far as it can be determined by the OS. */
sealed interface LocationPermissionStatus {
    data object Granted : LocationPermissionStatus

    /** Not granted, but the system permission dialog can still be shown. */
    data object Denied : LocationPermissionStatus

    /** Not granted and the OS will no longer show its own dialog - the user must open Settings. */
    data object PermanentlyDenied : LocationPermissionStatus
}

/** Presentation-layer state holder for the fine location permission. Holds no UI. */
class LocationPermissionState internal constructor(
    private val statusProvider: () -> LocationPermissionStatus,
    val requestPermission: () -> Unit,
    val refresh: () -> Unit,
) {
    val status: LocationPermissionStatus get() = statusProvider()
}

@Composable
fun rememberLocationPermissionState(): LocationPermissionState {
    val context = LocalContext.current
    val activity = context as? ComponentActivity

    var status by remember { mutableStateOf(initialPermissionStatus(context)) }

    val launcher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestPermission(),
    ) { isGranted ->
        status = when {
            isGranted -> LocationPermissionStatus.Granted
            activity != null && ActivityCompat.shouldShowRequestPermissionRationale(
                activity,
                Manifest.permission.ACCESS_FINE_LOCATION,
            ) -> LocationPermissionStatus.Denied
            else -> LocationPermissionStatus.PermanentlyDenied
        }
    }

    return remember {
        LocationPermissionState(
            statusProvider = { status },
            requestPermission = { launcher.launch(Manifest.permission.ACCESS_FINE_LOCATION) },
            refresh = {
                status = when {
                    isPermissionGranted(context) -> LocationPermissionStatus.Granted
                    // Permission was revoked while the app was backgrounded (e.g. via
                    // system Settings) - downgrade the stale Granted status so the UI
                    // routes back to the request flow instead of trusting it silently.
                    // PermanentlyDenied is left as-is; it only changes via the launcher.
                    status == LocationPermissionStatus.Granted -> LocationPermissionStatus.Denied
                    else -> status
                }
            },
        )
    }
}

private fun initialPermissionStatus(context: Context): LocationPermissionStatus =
    if (isPermissionGranted(context)) LocationPermissionStatus.Granted else LocationPermissionStatus.Denied

private fun isPermissionGranted(context: Context): Boolean =
    ContextCompat.checkSelfPermission(
        context,
        Manifest.permission.ACCESS_FINE_LOCATION,
    ) == PackageManager.PERMISSION_GRANTED
