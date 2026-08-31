package com.geofence.attendance.presentation.attendance

import org.junit.Assert.assertEquals
import org.junit.Test

class DistanceGaugeProgressTest {

    @Test
    fun `zero distance is zero progress`() {
        assertEquals(0f, distanceGaugeProgress(0f), 0.0001f)
    }

    @Test
    fun `progress scales linearly with distance below the max`() {
        // 120m is the exact example distance from the assignment's reference screenshot.
        assertEquals(120f / 200f, distanceGaugeProgress(120f), 0.0001f)
    }

    @Test
    fun `distance at the max is full progress`() {
        assertEquals(1f, distanceGaugeProgress(DISTANCE_GAUGE_MAX_METERS), 0.0001f)
    }

    @Test
    fun `distance beyond the max is clamped to full progress, not overflowing the ring`() {
        assertEquals(1f, distanceGaugeProgress(DISTANCE_GAUGE_MAX_METERS * 5), 0.0001f)
    }

    @Test
    fun `distance within the 50m radius is a small fraction of the ring, not full`() {
        val progress = distanceGaugeProgress(50f)
        assertEquals(0.25f, progress, 0.0001f)
        assert(progress < 1f)
    }
}
