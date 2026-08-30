package com.geofence.attendance.data.local

import android.content.Context
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.doublePreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.emptyPreferences
import androidx.datastore.preferences.preferencesDataStore
import com.geofence.attendance.domain.model.OfficeLocation
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.map
import java.io.IOException
import javax.inject.Inject

private val Context.dataStore by preferencesDataStore(name = "attendance_prefs")

internal object OfficeLocationKeys {
    val LATITUDE = doublePreferencesKey("office_latitude")
    val LONGITUDE = doublePreferencesKey("office_longitude")
}

internal fun Preferences.toOfficeLocationOrNull(): OfficeLocation? {
    val latitude = this[OfficeLocationKeys.LATITUDE]
    val longitude = this[OfficeLocationKeys.LONGITUDE]
    return if (latitude != null && longitude != null) {
        OfficeLocation(latitude = latitude, longitude = longitude)
    } else {
        null
    }
}

class OfficeLocationDataStore @Inject constructor(
    @ApplicationContext private val context: Context,
) {
    fun observeOfficeLocation(): Flow<OfficeLocation?> =
        context.dataStore.data
            .catch { exception ->
                if (exception is IOException) {
                    emit(emptyPreferences())
                } else {
                    throw exception
                }
            }
            .map { preferences -> preferences.toOfficeLocationOrNull() }

    suspend fun saveOfficeLocation(officeLocation: OfficeLocation) {
        context.dataStore.edit { preferences ->
            preferences[OfficeLocationKeys.LATITUDE] = officeLocation.latitude
            preferences[OfficeLocationKeys.LONGITUDE] = officeLocation.longitude
        }
    }
}
