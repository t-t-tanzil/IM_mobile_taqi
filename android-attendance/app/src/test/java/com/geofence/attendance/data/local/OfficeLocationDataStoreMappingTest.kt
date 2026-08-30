package com.geofence.attendance.data.local

import androidx.datastore.preferences.core.emptyPreferences
import androidx.datastore.preferences.core.preferencesOf
import com.geofence.attendance.domain.model.OfficeLocation
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class OfficeLocationDataStoreMappingTest {

    @Test
    fun `emits OfficeLocation when both latitude and longitude are present`() {
        val preferences = preferencesOf(
            OfficeLocationKeys.LATITUDE to 1.23,
            OfficeLocationKeys.LONGITUDE to 4.56,
        )

        assertEquals(
            OfficeLocation(latitude = 1.23, longitude = 4.56),
            preferences.toOfficeLocationOrNull(),
        )
    }

    @Test
    fun `emits null when longitude is missing`() {
        val preferences = preferencesOf(OfficeLocationKeys.LATITUDE to 1.23)

        assertNull(preferences.toOfficeLocationOrNull())
    }

    @Test
    fun `emits null when latitude is missing`() {
        val preferences = preferencesOf(OfficeLocationKeys.LONGITUDE to 4.56)

        assertNull(preferences.toOfficeLocationOrNull())
    }

    @Test
    fun `emits null when preferences are empty`() {
        assertNull(emptyPreferences().toOfficeLocationOrNull())
    }
}
