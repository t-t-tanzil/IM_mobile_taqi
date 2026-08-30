package com.geofence.attendance.data.di

import android.content.Context
import com.geofence.attendance.data.location.FusedLocationDataSource
import com.geofence.attendance.data.location.LocationDataSource
import com.geofence.attendance.data.repository.AttendanceRepositoryImpl
import com.geofence.attendance.domain.repository.AttendanceRepository
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.LocationServices
import dagger.Binds
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
abstract class DataModule {

    @Binds
    abstract fun bindAttendanceRepository(
        impl: AttendanceRepositoryImpl,
    ): AttendanceRepository

    @Binds
    abstract fun bindLocationDataSource(
        impl: FusedLocationDataSource,
    ): LocationDataSource

    companion object {
        @Provides
        @Singleton
        fun provideFusedLocationProviderClient(
            @ApplicationContext context: Context,
        ): FusedLocationProviderClient = LocationServices.getFusedLocationProviderClient(context)
    }
}
