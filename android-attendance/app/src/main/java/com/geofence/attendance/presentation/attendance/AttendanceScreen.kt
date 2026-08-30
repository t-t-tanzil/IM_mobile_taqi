package com.geofence.attendance.presentation.attendance

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.geofence.attendance.domain.usecase.ValidateAttendanceLocationUseCase
import java.time.LocalTime
import java.time.format.DateTimeFormatter
import kotlin.math.roundToInt

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AttendanceScreen(
    viewModel: AttendanceViewModel = hiltViewModel(),
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val permissionState = rememberLocationPermissionState()
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val snackbarHostState = remember { SnackbarHostState() }

    // Covers both "granted permission then returned" and "enabled location services then returned":
    // on resume we refresh what the OS reports and let the ViewModel's existing retry mechanism
    // re-subscribe - no new GPS subscription is created here, just a signal to the existing one.
    DisposableEffect(lifecycleOwner, viewModel) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                permissionState.refresh()
                viewModel.retryLocationUpdates()
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    LaunchedEffect(uiState.errorMessage) {
        uiState.errorMessage?.let { message -> snackbarHostState.showSnackbar(message) }
    }

    Scaffold(
        topBar = { TopAppBar(title = { Text("Attendance") }) },
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { paddingValues ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues),
        ) {
            when (resolveAttendanceScreenMode(permissionState.status, uiState.locationAvailability)) {
                AttendanceScreenMode.PermissionSettingsRequired -> ReasonCard(
                    icon = Icons.Filled.Warning,
                    title = "Permission Required",
                    message = "Location permission was denied. Enable it from app settings to use " +
                        "attendance tracking.",
                    actionLabel = "Open App Settings",
                    onAction = { context.startActivity(appSettingsIntent(context)) },
                )

                AttendanceScreenMode.RequestPermission -> ReasonCard(
                    icon = Icons.Filled.LocationOn,
                    title = "Location Permission Needed",
                    message = "Attendance is verified using your device's location. Grant location " +
                        "permission to continue.",
                    actionLabel = "Grant Permission",
                    onAction = permissionState.requestPermission,
                )

                AttendanceScreenMode.LocationServicesDisabled -> ReasonCard(
                    icon = Icons.Filled.Warning,
                    title = "Location Services Disabled",
                    message = "Turn on location services to track your distance from the office.",
                    actionLabel = "Open Location Settings",
                    onAction = { context.startActivity(Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS)) },
                )

                AttendanceScreenMode.Content -> AttendanceContent(
                    uiState = uiState,
                    onSetOfficeLocation = viewModel::setOfficeLocation,
                    onMarkAttendance = viewModel::markAttendance,
                    onRetryLocation = viewModel::retryLocationUpdates,
                )
            }
        }
    }
}

@Composable
private fun AttendanceContent(
    uiState: AttendanceUiState,
    onSetOfficeLocation: () -> Unit,
    onMarkAttendance: () -> Unit,
    onRetryLocation: () -> Unit,
) {
    Column(modifier = Modifier.fillMaxSize()) {
        val availability = uiState.locationAvailability
        if (availability is LocationAvailability.Unavailable.TemporarilyUnavailable) {
            StatusBanner(message = availability.message, onRetry = onRetryLocation)
        }

        Box(modifier = Modifier.weight(1f)) {
            if (!uiState.isOfficeLocationConfigured) {
                OfficeSetupCard(
                    isSaving = uiState.isSavingOfficeLocation,
                    onSetOfficeLocation = onSetOfficeLocation,
                )
            } else {
                AttendanceTrackingCard(uiState = uiState, onMarkAttendance = onMarkAttendance)
            }
        }
    }
}

@Composable
private fun StatusBanner(message: String, onRetry: () -> Unit) {
    Surface(color = MaterialTheme.colorScheme.errorContainer, modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                imageVector = Icons.Filled.Warning,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onErrorContainer,
            )
            Spacer(Modifier.width(12.dp))
            Text(
                text = message,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onErrorContainer,
                modifier = Modifier.weight(1f),
            )
            TextButton(onClick = onRetry) { Text("Retry") }
        }
    }
}

@Composable
private fun OfficeSetupCard(isSaving: Boolean, onSetOfficeLocation: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Icon(
            imageVector = Icons.Filled.LocationOn,
            contentDescription = null,
            modifier = Modifier.size(56.dp),
            tint = MaterialTheme.colorScheme.primary,
        )
        Spacer(Modifier.height(16.dp))
        Text("No Office Location Set", style = MaterialTheme.typography.titleLarge, textAlign = TextAlign.Center)
        Spacer(Modifier.height(8.dp))
        Text(
            text = "Set your office location once, using your current GPS position, so attendance " +
                "can be verified against it.",
            style = MaterialTheme.typography.bodyMedium,
            textAlign = TextAlign.Center,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.height(24.dp))
        Button(
            onClick = onSetOfficeLocation,
            enabled = !isSaving,
            modifier = Modifier.heightIn(min = 48.dp),
        ) {
            if (isSaving) {
                CircularProgressIndicator(
                    modifier = Modifier.size(18.dp),
                    strokeWidth = 2.dp,
                    color = MaterialTheme.colorScheme.onPrimary,
                )
                Spacer(Modifier.width(8.dp))
                Text("Getting current location…")
            } else {
                Text("Set Office Location")
            }
        }
    }
}

@Composable
private fun AttendanceTrackingCard(
    uiState: AttendanceUiState,
    onMarkAttendance: () -> Unit,
) {
    var markedAtTime by remember { mutableStateOf<LocalTime?>(null) }
    LaunchedEffect(uiState.attendanceMarked) {
        if (uiState.attendanceMarked && markedAtTime == null) {
            markedAtTime = LocalTime.now()
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(
                imageVector = Icons.Filled.CheckCircle,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.size(20.dp),
            )
            Spacer(Modifier.width(8.dp))
            Text("Office location configured", style = MaterialTheme.typography.bodyMedium)
        }

        Spacer(Modifier.height(32.dp))

        when {
            uiState.distanceMeters != null -> DistanceCard(
                distanceMeters = uiState.distanceMeters,
                isWithinRadius = uiState.isWithinAttendanceRadius,
            )
            uiState.isLoading -> LoadingIndicatorRow(text = "Getting your current location…")
            else -> Text(
                text = "Current location unavailable",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        if (uiState.distanceMeters != null && !uiState.isWithinAttendanceRadius) {
            Spacer(Modifier.height(8.dp))
            val radius = ValidateAttendanceLocationUseCase.ALLOWED_RADIUS_METERS.toInt()
            Text(
                text = "Move within ${radius}m of the office to mark attendance.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )
        }

        Spacer(Modifier.height(32.dp))

        if (uiState.attendanceMarked) {
            SuccessBanner(markedAt = markedAtTime)
        } else {
            Button(
                onClick = onMarkAttendance,
                enabled = uiState.isWithinAttendanceRadius,
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(min = 48.dp),
            ) {
                Text("Mark Attendance")
            }
        }
    }
}

@Composable
private fun DistanceCard(distanceMeters: Float, isWithinRadius: Boolean) {
    val containerColor by animateColorAsState(
        targetValue = if (isWithinRadius) {
            MaterialTheme.colorScheme.primaryContainer
        } else {
            MaterialTheme.colorScheme.surfaceVariant
        },
        label = "distance_card_color",
    )
    val contentColor = if (isWithinRadius) {
        MaterialTheme.colorScheme.onPrimaryContainer
    } else {
        MaterialTheme.colorScheme.onSurfaceVariant
    }

    Surface(
        color = containerColor,
        shape = MaterialTheme.shapes.large,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(
            modifier = Modifier.padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(
                text = formatDistanceMessage(distanceMeters),
                style = MaterialTheme.typography.titleMedium,
                color = contentColor,
                textAlign = TextAlign.Center,
            )
            Spacer(Modifier.height(12.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    imageVector = if (isWithinRadius) Icons.Filled.CheckCircle else Icons.Filled.Info,
                    contentDescription = null,
                    tint = contentColor,
                    modifier = Modifier.size(18.dp),
                )
                Spacer(Modifier.width(6.dp))
                Text(
                    text = if (isWithinRadius) "Within attendance range" else "Outside attendance range",
                    style = MaterialTheme.typography.labelLarge,
                    color = contentColor,
                )
            }
        }
    }
}

@Composable
private fun SuccessBanner(markedAt: LocalTime?) {
    Surface(
        color = MaterialTheme.colorScheme.primaryContainer,
        shape = MaterialTheme.shapes.medium,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row(
            modifier = Modifier.padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                imageVector = Icons.Filled.CheckCircle,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onPrimaryContainer,
            )
            Spacer(Modifier.width(12.dp))
            Column {
                Text(
                    text = "Attendance marked successfully",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onPrimaryContainer,
                )
                markedAt?.let {
                    Text(
                        text = it.format(DateTimeFormatter.ofPattern("h:mm a")),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onPrimaryContainer,
                    )
                }
            }
        }
    }
}

@Composable
private fun LoadingIndicatorRow(text: String) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
        Spacer(Modifier.width(12.dp))
        Text(text, style = MaterialTheme.typography.bodyMedium)
    }
}

@Composable
private fun ReasonCard(
    icon: ImageVector,
    title: String,
    message: String,
    actionLabel: String,
    onAction: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            modifier = Modifier.size(56.dp),
            tint = MaterialTheme.colorScheme.primary,
        )
        Spacer(Modifier.height(16.dp))
        Text(title, style = MaterialTheme.typography.titleLarge, textAlign = TextAlign.Center)
        Spacer(Modifier.height(8.dp))
        Text(
            text = message,
            style = MaterialTheme.typography.bodyMedium,
            textAlign = TextAlign.Center,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.height(24.dp))
        Button(onClick = onAction, modifier = Modifier.heightIn(min = 48.dp)) {
            Text(actionLabel)
        }
    }
}

private fun formatDistanceMessage(distanceMeters: Float): String {
    val roundedMeters = distanceMeters.roundToInt()
    return if (roundedMeters < 1000) {
        "You are ${roundedMeters}m away from the office"
    } else {
        val km = distanceMeters / 1000f
        "You are ${"%.1f".format(km)}km away from the office"
    }
}

private fun appSettingsIntent(context: Context): Intent =
    Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
        data = Uri.fromParts("package", context.packageName, null)
    }
