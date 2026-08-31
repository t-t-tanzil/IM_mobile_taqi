package com.geofence.attendance.presentation.attendance

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import android.widget.Toast
import androidx.activity.compose.BackHandler
import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.geofence.attendance.domain.model.OfficeLocation
import com.geofence.attendance.domain.usecase.ValidateAttendanceLocationUseCase
import java.time.LocalTime
import java.time.format.DateTimeFormatter
import kotlin.math.roundToInt

// Explicit brand colors for the out-of-range state, called out by design review as needing
// to match exactly rather than derive from the M3 error/errorContainer tonal roles (which
// read as pale pink text on real hardware, not a clearly "red" warning).
private val OutOfRangeRed = Color(0xFFEF6969)
private val OutOfRangeLightBackground = Color(0xFFFAF5F6)

// Signals the attendance action card is actually available to tap, not just present.
private val AvailableGreen = Color(0xFF4CAF50)

private const val DOUBLE_BACK_PRESS_INTERVAL_MS = 2000L

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

    // Single screen, no back stack to pop - the system default would exit immediately
    // on the first press. Require a second press within the interval instead.
    var lastBackPressTimeMs by remember { mutableStateOf(0L) }
    BackHandler {
        val now = System.currentTimeMillis()
        if (now - lastBackPressTimeMs <= DOUBLE_BACK_PRESS_INTERVAL_MS) {
            (context as? Activity)?.finish()
        } else {
            lastBackPressTimeMs = now
            Toast.makeText(context, "Press back again to exit", Toast.LENGTH_SHORT).show()
        }
    }

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
                .background(MaterialTheme.colorScheme.background)
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
            .verticalScroll(rememberScrollState())
            .padding(20.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(Modifier.height(48.dp))

        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
            Icon(
                imageVector = Icons.Filled.CheckCircle,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.size(18.dp),
            )
            Spacer(Modifier.width(8.dp))
            Text(
                "Office location configured",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurface,
            )
        }

        Spacer(Modifier.height(16.dp))

        uiState.officeLocation?.let { office ->
            OfficeMapPreview(officeLocation = office, modifier = Modifier.fillMaxWidth())
            Spacer(Modifier.height(24.dp))
        }

        when {
            uiState.distanceMeters != null -> {
                DistanceGauge(
                    distanceMeters = uiState.distanceMeters,
                    isWithinRadius = uiState.isWithinAttendanceRadius,
                )
                Spacer(Modifier.height(16.dp))
                RangeStatusSection(
                    distanceMeters = uiState.distanceMeters,
                    isWithinRadius = uiState.isWithinAttendanceRadius,
                )
            }
            uiState.isLoading -> LoadingIndicatorRow(text = "Getting your current location…")
            else -> Text(
                text = "Current location unavailable",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        Spacer(Modifier.height(24.dp))

        if (uiState.attendanceMarked) {
            SuccessBanner(markedAt = markedAtTime)
        } else {
            AttendanceActionCard(
                enabled = uiState.isWithinAttendanceRadius,
                onMarkAttendance = onMarkAttendance,
            )
        }
        Spacer(Modifier.height(16.dp))
    }
}

/**
 * Static, illustrative map placeholder - not a live map. No Google Maps dependency is
 * wired up: `play-services-maps`/`maps-compose` aren't in this project and there's no API
 * key to configure them with, so adding the real SDK now would either crash or render a
 * broken/blank tile view. To swap this for a real map once a key is available:
 * 1. Add `com.google.android.gms:play-services-maps` and
 *    `com.google.maps.android:maps-compose` to `app/build.gradle.kts`.
 * 2. Add `<meta-data android:name="com.google.android.geo.API_KEY"
 *    android:value="${MAPS_API_KEY}" />` inside the `<application>` tag in
 *    `AndroidManifest.xml`.
 * 3. Supply `MAPS_API_KEY=<your-key>` in `android-attendance/local.properties`
 *    (gitignored, machine-specific - same pattern already used for `sdk.dir`) and read it
 *    into the manifest placeholder via `manifestPlaceholders` in `app/build.gradle.kts`.
 * 4. Replace the `Canvas` block below with a `GoogleMap` composable centered on
 *    `officeLocation`, with a `Marker` at that same position.
 */
@Composable
private fun OfficeMapPreview(officeLocation: OfficeLocation, modifier: Modifier = Modifier) {
    val gridLineColor = MaterialTheme.colorScheme.outline.copy(alpha = 0.25f)
    val pinColor = MaterialTheme.colorScheme.error
    Surface(
        modifier = modifier.height(120.dp),
        shape = RoundedCornerShape(16.dp),
        color = MaterialTheme.colorScheme.surfaceVariant,
    ) {
        Box(modifier = Modifier.fillMaxSize()) {
            Canvas(modifier = Modifier.fillMaxSize()) {
                val columns = 6
                val step = size.width / columns
                for (i in 1 until columns) {
                    drawLine(
                        color = gridLineColor,
                        start = Offset(step * i, 0f),
                        end = Offset(step * i, size.height),
                        strokeWidth = 1.dp.toPx(),
                    )
                }
                val rows = 3
                val rowStep = size.height / rows
                for (i in 1 until rows) {
                    drawLine(
                        color = gridLineColor,
                        start = Offset(0f, rowStep * i),
                        end = Offset(size.width, rowStep * i),
                        strokeWidth = 1.dp.toPx(),
                    )
                }
            }
            Icon(
                imageVector = Icons.Filled.LocationOn,
                contentDescription = "Office location on map",
                tint = pinColor,
                modifier = Modifier
                    .align(Alignment.Center)
                    .size(32.dp),
            )
            Surface(
                modifier = Modifier
                    .align(Alignment.TopStart)
                    .padding(8.dp),
                shape = RoundedCornerShape(8.dp),
                color = MaterialTheme.colorScheme.surface.copy(alpha = 0.92f),
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
                ) {
                    Icon(
                        imageVector = Icons.Filled.LocationOn,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.size(14.dp),
                    )
                    Spacer(Modifier.width(4.dp))
                    Text(
                        text = "Lat: ${"%.4f".format(officeLocation.latitude)}, " +
                            "Lon: ${"%.4f".format(officeLocation.longitude)}",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurface,
                    )
                }
            }
        }
    }
}

/**
 * Progress increases as the user gets farther from the office (see
 * [distanceGaugeProgress]) and the ring turns red past the 50m radius - paired with the
 * "AWAY" label and [RangeStatusSection]'s text/icon below, so range is never conveyed by
 * ring color alone.
 */
@Composable
private fun DistanceGauge(distanceMeters: Float, isWithinRadius: Boolean, modifier: Modifier = Modifier) {
    val progress = distanceGaugeProgress(distanceMeters)
    val ringColor by animateColorAsState(
        targetValue = if (isWithinRadius) MaterialTheme.colorScheme.primary else OutOfRangeRed,
        label = "gauge_ring_color",
    )
    val discColor by animateColorAsState(
        targetValue = if (isWithinRadius) Color.Transparent else OutOfRangeLightBackground,
        label = "gauge_disc_color",
    )
    val trackColor = MaterialTheme.colorScheme.surfaceVariant
    val textColor = if (isWithinRadius) MaterialTheme.colorScheme.onSurface else OutOfRangeRed
    val labelColor = if (isWithinRadius) MaterialTheme.colorScheme.onSurfaceVariant else OutOfRangeRed

    Box(modifier = modifier.size(160.dp), contentAlignment = Alignment.Center) {
        Canvas(modifier = Modifier.fillMaxSize()) {
            val strokeWidth = 10.dp.toPx()
            // Light red fill inside the ring when out of range, inset so it never
            // shows through under the track/progress stroke.
            if (discColor != Color.Transparent) {
                drawCircle(color = discColor, radius = (size.minDimension / 2f) - strokeWidth)
            }
            drawArc(
                color = trackColor,
                startAngle = -90f,
                sweepAngle = 360f,
                useCenter = false,
                style = Stroke(width = strokeWidth, cap = StrokeCap.Round),
            )
            if (progress > 0f) {
                drawArc(
                    color = ringColor,
                    startAngle = -90f,
                    sweepAngle = 360f * progress,
                    useCenter = false,
                    style = Stroke(width = strokeWidth, cap = StrokeCap.Round),
                )
            }
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(
                text = "${distanceMeters.roundToInt()}m",
                style = MaterialTheme.typography.headlineMedium,
                color = textColor,
            )
            Text(
                text = "AWAY",
                style = MaterialTheme.typography.labelMedium,
                color = labelColor,
            )
        }
    }
}

@Composable
private fun RangeStatusSection(distanceMeters: Float, isWithinRadius: Boolean) {
    if (isWithinRadius) {
        Surface(
            color = MaterialTheme.colorScheme.primaryContainer,
            shape = MaterialTheme.shapes.large,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Column(
                modifier = Modifier
                    .padding(20.dp)
                    .fillMaxWidth(),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text(
                    text = formatDistanceMessage(distanceMeters),
                    style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.onPrimaryContainer,
                    textAlign = TextAlign.Center,
                )
                Spacer(Modifier.height(8.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(
                        imageVector = Icons.Filled.CheckCircle,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.onPrimaryContainer,
                        modifier = Modifier.size(18.dp),
                    )
                    Spacer(Modifier.width(6.dp))
                    Text(
                        text = "Within attendance range",
                        style = MaterialTheme.typography.labelLarge,
                        color = MaterialTheme.colorScheme.onPrimaryContainer,
                    )
                }
            }
        }
    } else {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Surface(
                color = OutOfRangeLightBackground,
                shape = MaterialTheme.shapes.small,
            ) {
                Row(
                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(
                        imageVector = Icons.Filled.Warning,
                        contentDescription = null,
                        tint = OutOfRangeRed,
                        modifier = Modifier.size(14.dp),
                    )
                    Spacer(Modifier.width(6.dp))
                    Text(
                        text = "OUT OF RANGE",
                        style = MaterialTheme.typography.labelMedium,
                        color = OutOfRangeRed,
                    )
                }
            }
            Spacer(Modifier.height(8.dp))
            val radius = ValidateAttendanceLocationUseCase.ALLOWED_RADIUS_METERS.toInt()
            Text(
                text = "Move within ${radius}m of the office to mark attendance.",
                style = MaterialTheme.typography.bodySmall,
                color = OutOfRangeRed,
                textAlign = TextAlign.Center,
            )
        }
    }
}

@Composable
private fun AttendanceActionCard(
    enabled: Boolean,
    onMarkAttendance: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Box(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.3f))
            .dashedBorder(
                color = MaterialTheme.colorScheme.outline,
                cornerRadius = 16.dp,
            ),
    ) {
        Column(
            modifier = Modifier
                .padding(20.dp)
                .fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Icon(
                imageVector = Icons.Filled.Lock,
                contentDescription = if (enabled) "Attendance unlocked" else "Attendance locked",
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(28.dp),
            )
            Spacer(Modifier.height(12.dp))
            Button(
                onClick = onMarkAttendance,
                enabled = enabled,
                colors = ButtonDefaults.buttonColors(
                    containerColor = AvailableGreen,
                    contentColor = Color.White,
                ),
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(min = 48.dp),
            ) {
                Text("Mark Attendance")
            }
            Spacer(Modifier.height(8.dp))
            Text(
                text = "AVAILABLE 09:00 AM - 10:30 AM",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

/** Dashed rounded-rect border, matching the reference design's attendance card treatment. */
private fun Modifier.dashedBorder(
    color: Color,
    cornerRadius: Dp,
    strokeWidth: Dp = 1.5.dp,
): Modifier = drawWithContent {
    drawContent()
    drawRoundRect(
        color = color,
        cornerRadius = CornerRadius(cornerRadius.toPx()),
        style = Stroke(
            width = strokeWidth.toPx(),
            pathEffect = PathEffect.dashPathEffect(floatArrayOf(14f, 10f), 0f),
        ),
    )
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
