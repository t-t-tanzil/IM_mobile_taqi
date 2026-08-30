package com.geofence.attendance.domain.model

class LocationPermissionMissingException : Exception("Location permission has not been granted")

class LocationServicesDisabledException : Exception("Location services are turned off")

class LocationUnavailableException : Exception("Location provider is currently unavailable")
