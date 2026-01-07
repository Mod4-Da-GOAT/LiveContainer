//
//  LCAppSettingsView.swift
//  LiveContainerSwiftUI
//
//  Created by s s on 2024/9/16.
//

import Foundation
import SwiftUI
import CoreLocation
import MapKit
@preconcurrency import AVFoundation
import AVKit
import PhotosUI
import Photos
import UIKit
import UniformTypeIdentifiers


// MARK: GPS Settings Section
class LCLocationHistory: ObservableObject {
    static let shared = LCLocationHistory()
    
    @Published var recentLocations: [LocationHistoryItem] = []
    
    private let maxHistoryItems = 20 // Keep last 20 locations
    private let userDefaults = UserDefaults.standard
    private let historyKey = "LCLocationHistory"
    
    private init() {
        loadHistory()
    }
    
    func addLocation(name: String, latitude: CLLocationDegrees, longitude: CLLocationDegrees, altitude: CLLocationDistance = 0.0) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        
        // Check if location with same name already exists
        if let existingIndex = recentLocations.firstIndex(where: { $0.name.localizedCaseInsensitiveCompare(trimmedName) == .orderedSame }) {
            // Update existing location with new coordinates and move to top
            var updatedLocation = recentLocations[existingIndex]
            updatedLocation.latitude = latitude
            updatedLocation.longitude = longitude
            updatedLocation.altitude = altitude
            updatedLocation.lastUsed = Date()
            
            recentLocations.remove(at: existingIndex)
            recentLocations.insert(updatedLocation, at: 0)
            
            print("🗂️ Updated existing location: \(trimmedName)")
        } else {
            // Add new location at the beginning
            let newLocation = LocationHistoryItem(
                name: trimmedName,
                latitude: latitude,
                longitude: longitude,
                altitude: altitude,
                lastUsed: Date()
            )
            
            recentLocations.insert(newLocation, at: 0)
            
            // Keep only the most recent items
            if recentLocations.count > maxHistoryItems {
                recentLocations = Array(recentLocations.prefix(maxHistoryItems))
            }
            
            print("🗂️ Added new location: \(trimmedName)")
        }
        
        saveHistory()
    }
    
    func removeLocation(at index: Int) {
        guard index < recentLocations.count else { return }
        recentLocations.remove(at: index)
        saveHistory()
    }
    
    func clearHistory() {
        recentLocations.removeAll()
        saveHistory()
    }
    
    private func saveHistory() {
        do {
            let data = try JSONEncoder().encode(recentLocations)
            userDefaults.set(data, forKey: historyKey)
            print("🗂️ Saved \(recentLocations.count) locations to history")
        } catch {
            print("🗂️ Failed to save location history: \(error)")
        }
    }
    
    private func loadHistory() {
        guard let data = userDefaults.data(forKey: historyKey) else {
            print("🗂️ No location history found")
            return
        }
        
        do {
            recentLocations = try JSONDecoder().decode([LocationHistoryItem].self, from: data)
            print("🗂️ Loaded \(recentLocations.count) locations from history")
        } catch {
            print("🗂️ Failed to load location history: \(error)")
            recentLocations = []
        }
    }
}

struct LocationHistoryItem: Codable, Identifiable {
    let id = UUID()
    let name: String
    var latitude: CLLocationDegrees
    var longitude: CLLocationDegrees
    var altitude: CLLocationDistance
    var lastUsed: Date
    
    private enum CodingKeys: String, CodingKey {
        case name, latitude, longitude, altitude, lastUsed
    }
}

// MARK: - GPS Settings Section
struct GPSSettingsSection: View {
    @Binding var spoofGPS: Bool
    @Binding var latitude: CLLocationDegrees
    @Binding var longitude: CLLocationDegrees
    @Binding var altitude: CLLocationDistance
    @Binding var locationName: String
    
    @State private var showMapPicker = false
    @State private var showCityPicker = false
    @State private var showLocationHistory = false
    @State private var isEditingLocationName = false
    @State private var isGettingIPLocation = false
    
    @StateObject private var locationHistory = LCLocationHistory.shared
    
    var body: some View {
        Section {
            Toggle(isOn: $spoofGPS) {
                HStack {
                    Image(systemName: "location")
                        .foregroundColor(.blue)
                        .frame(width: 20)
                    Text("Spoof GPS Location")
                }
            }
            
            if spoofGPS {
                VStack(alignment: .leading, spacing: 12) {
                    // Location name field
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Location Name")
                                .font(.headline)
                            Spacer()
                            Button(isEditingLocationName ? "Done" : "Edit") {
                                isEditingLocationName.toggle()
                                if !isEditingLocationName && !locationName.isEmpty {
                                    // Save to history when done editing
                                    saveCurrentLocationToHistory()
                                }
                            }
                            .font(.caption)
                            .buttonStyle(.bordered)
                        }
                        
                        if isEditingLocationName {
                            TextField("Enter location name", text: $locationName)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .onSubmit {
                                    isEditingLocationName = false
                                    saveCurrentLocationToHistory()
                                }
                        } else {
                            Text(locationName.isEmpty ? "Unknown Location" : locationName)
                        }
                    }
                    
                    Divider()
                    
                    // Quick location picker buttons
                    HStack(spacing: 8) {
                        Button(action: {
                            showMapPicker = true
                        }) {
                            VStack(spacing: 4) {
                                Image(systemName: "map")
                                    .font(.title2)
                                Text("Map")
                                    .font(.caption)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 60)
                        }
                        .buttonStyle(.bordered)
                        
                        Button(action: {
                            showCityPicker = true
                        }) {
                            VStack(spacing: 4) {
                                Image(systemName: "building.2")
                                    .font(.title2)
                                Text("Cities")
                                    .font(.caption)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 60)
                        }
                        .buttonStyle(.bordered)
                        
                        // Add IP Location Button
                        Button(action: {
                            Task {
                                await getLocationFromIP()
                            }
                        }) {
                            VStack(spacing: 4) {
                                if isGettingIPLocation {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "network")
                                        .font(.title2)
                                }
                                Text("IP")
                                    .font(.caption)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 60)
                        }
                        .buttonStyle(.bordered)
                        .disabled(isGettingIPLocation)
                        
                        Button(action: {
                            showLocationHistory = true
                        }) {
                            VStack(spacing: 4) {
                                ZStack {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .font(.title2)
                                    
                                    // Show badge if there are recent locations
                                    if !locationHistory.recentLocations.isEmpty {
                                        VStack {
                                            HStack {
                                                Spacer()
                                                Text("\(locationHistory.recentLocations.count)")
                                                    .font(.caption2)
                                                    .foregroundColor(.white)
                                                    .frame(minWidth: 16, minHeight: 16)
                                                    .background(Color.red)
                                                    .clipShape(Circle())
                                            }
                                            Spacer()
                                        }
                                        .offset(x: 8, y: -8)
                                    }
                                }
                                Text("Recent")
                                    .font(.caption)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 60)
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    Divider()
                    
                    // Manual coordinate entry
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Latitude")
                            Spacer()
                            TextField("37.7749", value: $latitude, format: .number.precision(.fractionLength(6)))
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .frame(maxWidth: 120)
                                .onChange(of: latitude) { _ in
                                    // Auto-save when coordinates change
                                    autoSaveLocationAfterDelay()
                                }
                        }
                        
                        HStack {
                            Text("Longitude")
                            Spacer()
                            TextField("-122.4194", value: $longitude, format: .number.precision(.fractionLength(6)))
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .frame(maxWidth: 120)
                                .onChange(of: longitude) { _ in
                                    autoSaveLocationAfterDelay()
                                }
                        }
                        
                        HStack {
                            Text("Altitude (m)")
                            Spacer()
                            TextField("0.0", value: $altitude, format: .number.precision(.fractionLength(2)))
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .frame(maxWidth: 100)
                                .onChange(of: altitude) { _ in
                                    autoSaveLocationAfterDelay()
                                }
                        }
                    }
                    
                    // Current location display
                    if latitude != 0 || longitude != 0 {
                        HStack {
                            Image(systemName: "location")
                                .foregroundColor(.blue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Coordinates:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("\(latitude, specifier: "%.6f"), \(longitude, specifier: "%.6f")")
                                    .font(.footnote)
                                    .foregroundColor(.primary)
                            }
                            Spacer()
                            
                            // Quick save button
                            Button(action: {
                                saveCurrentLocationToHistory()
                            }) {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(.green)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        } header: {
            Text("Location Settings")
        }
        .sheet(isPresented: $showMapPicker) {
            LCMapPickerView(latitude: $latitude, longitude: $longitude, locationName: $locationName, isPresented: $showMapPicker)
                .onDisappear {
                    saveCurrentLocationToHistory()
                }
        }
        .sheet(isPresented: $showCityPicker) {
            LCCityPickerView(latitude: $latitude, longitude: $longitude, locationName: $locationName, isPresented: $showCityPicker)
                .onDisappear {
                    saveCurrentLocationToHistory()
                }
        }
        .sheet(isPresented: $showLocationHistory) {
            LCLocationHistoryView(
                latitude: $latitude,
                longitude: $longitude,
                locationName: $locationName,
                isPresented: $showLocationHistory
            )
        }
        .onAppear {
            // Only set default name if it's empty
            if locationName.isEmpty {
                locationName = "Unknown Location"
            }
        }
    }
    
    @MainActor
    private func getLocationFromIP() async {
        isGettingIPLocation = true
        
        do {
            let result = try await LCLocationHistory.shared.getLocationFromIP()
            
            // Set coordinates and city name
            latitude = result.latitude
            longitude = result.longitude
            locationName = result.cityName // Use the city name from API
            
            // Automatically save to history
            saveCurrentLocationToHistory()
            
            print("✅ IP Location set: \(result.cityName) (\(result.latitude), \(result.longitude))")
            
        } catch {
            // Silent fail for better UX - just don't update coordinates
            print("❌ IP location failed: \(error.localizedDescription)")
            
            // Optional: Set a generic fallback if you want
            // locationName = "IP Location Failed"
        }
        
        isGettingIPLocation = false
    }

    // MARK: Auto-save functionality
    @State private var autoSaveTask: Task<Void, Never>?
    
    private func autoSaveLocationAfterDelay() {
        // Cancel previous auto-save task
        autoSaveTask?.cancel()
        
        // Start new auto-save task with 2-second delay
        autoSaveTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            
            if !Task.isCancelled {
                await MainActor.run {
                    saveCurrentLocationToHistory()
                }
            }
        }
    }
    
    private func saveCurrentLocationToHistory() {
        guard !locationName.isEmpty && locationName != "Unknown Location" else { return }
        guard latitude != 0 || longitude != 0 else { return }
        
        locationHistory.addLocation(
            name: locationName,
            latitude: latitude,
            longitude: longitude,
            altitude: altitude
        )
    }
}

// MARK: - Location History View
struct LCLocationHistoryView: View {
    @Binding var latitude: CLLocationDegrees
    @Binding var longitude: CLLocationDegrees
    @Binding var locationName: String
    @Binding var isPresented: Bool
    
    @StateObject private var locationHistory = LCLocationHistory.shared
    @State private var showingClearAlert = false
    
    var body: some View {
        NavigationView {
            Group {
                if locationHistory.recentLocations.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 64))
                            .foregroundColor(.secondary)
                        
                        Text("No Recent Locations")
                            .font(.title2)
                            .fontWeight(.medium)
                        
                        Text("Locations you use will appear here for quick access.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(locationHistory.recentLocations) { location in
                            LocationHistoryRow(
                                location: location,
                                onSelect: {
                                    selectLocation(location)
                                }
                            )
                        }
                        .onDelete(perform: deleteLocations)
                    }
                }
            }
            .navigationTitle("Recent Locations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !locationHistory.recentLocations.isEmpty {
                        Button("Clear All") {
                            showingClearAlert = true
                        }
                        .foregroundColor(.red)
                    }
                }
            }
        }
        .alert("Clear Location History", isPresented: $showingClearAlert) {
            Button("Clear All", role: .destructive) {
                locationHistory.clearHistory()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will remove all \(locationHistory.recentLocations.count) saved locations. This action cannot be undone.")
        }
    }
    
    private func selectLocation(_ location: LocationHistoryItem) {
        latitude = location.latitude
        longitude = location.longitude
        locationName = location.name
        
        // Update the last used time
        locationHistory.addLocation(
            name: location.name,
            latitude: location.latitude,
            longitude: location.longitude,
            altitude: location.altitude
        )
        
        isPresented = false
    }
    
    private func deleteLocations(at offsets: IndexSet) {
        for index in offsets {
            locationHistory.removeLocation(at: index)
        }
    }
}

// MARK: - Location History
extension LCLocationHistory {
    // Get locations sorted by distance from current coordinates
    func locationsSortedByDistance(from coordinate: CLLocationCoordinate2D) -> [LocationHistoryItem] {
        return recentLocations.sorted { location1, location2 in
            let distance1 = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                .distance(from: CLLocation(latitude: location1.latitude, longitude: location1.longitude))
            let distance2 = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                .distance(from: CLLocation(latitude: location2.latitude, longitude: location2.longitude))
            return distance1 < distance2
        }
    }
    
    // Search locations by name
    func searchLocations(query: String) -> [LocationHistoryItem] {
        guard !query.isEmpty else { return recentLocations }
        
        return recentLocations.filter { location in
            location.name.localizedCaseInsensitiveContains(query)
        }
    }
    
    // Get favorite locations (most frequently used)
    func favoriteLocations(limit: Int = 5) -> [LocationHistoryItem] {
        // For now, just return the most recent ones
        // Could be enhanced to track usage frequency
        return Array(recentLocations.prefix(limit))
    }
}

// MARK: - IP Location
extension LCLocationHistory {
    
    // MARK: - IP Geolocation Functions
    // Simple IP geolocation with city name - returns coordinates and best available city name
    func getLocationFromIP() async throws -> (latitude: CLLocationDegrees, longitude: CLLocationDegrees, cityName: String) {
        // Try ip-api.com first (most detailed response)
        if let result = try? await ipApiService() {
            return result
        }
        
        // Fallback to ipinfo.io
        if let result = try? await ipInfoService() {
            return result
        }
        
        // Fallback to geojs.io
        if let result = try? await geoJSService() {
            return result
        }
        
        throw NSError(domain: "IPGeolocation", code: 1, userInfo: [NSLocalizedDescriptionKey: "All IP geolocation services failed"])
    }
    
    // Service 1: ip-api.com (most detailed, free)
    private func ipApiService() async throws -> (latitude: CLLocationDegrees, longitude: CLLocationDegrees, cityName: String) {
        guard let url = URL(string: "http://ip-api.com/json/?fields=status,message,country,regionName,city,lat,lon") else {
            throw NSError(domain: "IPGeolocation", code: 1, userInfo: nil)
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        
        struct IPApiResponse: Codable {
            let status: String
            let message: String?
            let country: String?
            let regionName: String?
            let city: String?
            let lat: Double?
            let lon: Double?
        }
        
        let response = try JSONDecoder().decode(IPApiResponse.self, from: data)
        
        guard response.status == "success",
              let lat = response.lat,
              let lon = response.lon else {
            throw NSError(domain: "IPGeolocation", code: 2, userInfo: [NSLocalizedDescriptionKey: response.message ?? "API request failed"])
        }
        
        // Build the best city name from available data
        let cityName = buildCityName(
            city: response.city,
            region: response.regionName,
            country: response.country,
            serviceName: "ip-api"
        )
        
        return (lat, lon, cityName)
    }
    
    // Service 2: ipinfo.io
    private func ipInfoService() async throws -> (latitude: CLLocationDegrees, longitude: CLLocationDegrees, cityName: String) {
        guard let url = URL(string: "https://ipinfo.io/json") else {
            throw NSError(domain: "IPGeolocation", code: 1, userInfo: nil)
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        
        struct IPInfoResponse: Codable {
            let city: String?
            let region: String?
            let country: String?
            let loc: String? // "lat,lon" format
        }
        
        let response = try JSONDecoder().decode(IPInfoResponse.self, from: data)
        
        guard let loc = response.loc else {
            throw NSError(domain: "IPGeolocation", code: 2, userInfo: nil)
        }
        
        let coordinates = loc.split(separator: ",")
        guard coordinates.count == 2,
              let lat = Double(coordinates[0]),
              let lon = Double(coordinates[1]) else {
            throw NSError(domain: "IPGeolocation", code: 3, userInfo: nil)
        }
        
        // Build city name
        let cityName = buildCityName(
            city: response.city,
            region: response.region,
            country: response.country,
            serviceName: "ipinfo"
        )
        
        return (lat, lon, cityName)
    }
    
    // Service 3: geojs.io
    private func geoJSService() async throws -> (latitude: CLLocationDegrees, longitude: CLLocationDegrees, cityName: String) {
        guard let url = URL(string: "https://get.geojs.io/v1/ip/geo.json") else {
            throw NSError(domain: "IPGeolocation", code: 1, userInfo: nil)
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        
        struct GeoJSResponse: Codable {
            let country: String?
            let region: String?
            let city: String?
            let latitude: String?
            let longitude: String?
        }
        
        let response = try JSONDecoder().decode(GeoJSResponse.self, from: data)
        
        guard let latStr = response.latitude,
              let lonStr = response.longitude,
              let lat = Double(latStr),
              let lon = Double(lonStr) else {
            throw NSError(domain: "IPGeolocation", code: 2, userInfo: nil)
        }
        
        // Build city name
        let cityName = buildCityName(
            city: response.city,
            region: response.region,
            country: response.country,
            serviceName: "geojs"
        )
        
        return (lat, lon, cityName)
    }
    
    // Helper function to build the best city name from available data
    private func buildCityName(city: String?, region: String?, country: String?, serviceName: String) -> String {
        var components: [String] = []
        
        // Always prioritize city name if available
        if let city = city, !city.isEmpty {
            components.append(city)
        }
        
        // Add region if different from city
        if let region = region, !region.isEmpty, region != city {
            components.append(region)
        }
        
        // Add country if we don't have city or if it's just a region
        if let country = country, !country.isEmpty {
            // Only add country if we don't have a city, or if we only have region
            if components.isEmpty || (components.count == 1 && city == nil) {
                components.append(country)
            }
        }
        
        // Build final name
        let locationName = components.isEmpty ? "IP Location" : components.joined(separator: ", ")
        
        print("🌍 IP location from \(serviceName): \(locationName)")
        return locationName
    }
}

// MARK: - Location History Row
struct LocationHistoryRow: View {
    let location: LocationHistoryItem
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(location.name)
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Text("\(location.latitude, specifier: "%.6f"), \(location.longitude, specifier: "%.6f")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if location.altitude != 0 {
                            Text("Altitude: \(location.altitude, specifier: "%.1f")m")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(timeAgoString(from: location.lastUsed))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func timeAgoString(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        
        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(interval / 86400)
            if days == 1 {
                return "1 day ago"
            } else {
                return "\(days) days ago"
            }
        }
    }
}

// MARK: - Map Picker View
struct LCMapPickerView: View {
    @Binding var latitude: CLLocationDegrees
    @Binding var longitude: CLLocationDegrees
    @Binding var locationName: String
    @Binding var isPresented: Bool
    
    @State private var region: MKCoordinateRegion
    @State private var pinLocation: CLLocationCoordinate2D
    @State private var currentLocationName = "Loading..."
    @State private var lastGeocodedCoordinate = CLLocationCoordinate2D(latitude: 0, longitude: 0)
    
    init(latitude: Binding<CLLocationDegrees>, longitude: Binding<CLLocationDegrees>, locationName: Binding<String>, isPresented: Binding<Bool>) {
        self._latitude = latitude
        self._longitude = longitude
        self._locationName = locationName
        self._isPresented = isPresented
        
        let coord = CLLocationCoordinate2D(latitude: latitude.wrappedValue, longitude: longitude.wrappedValue)
        self._region = State(initialValue: MKCoordinateRegion(
            center: coord,
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        ))
        self._pinLocation = State(initialValue: coord)
    }
    
    var body: some View {
        NavigationView {
            VStack {
                Map(coordinateRegion: $region, annotationItems: [MapPin(coordinate: pinLocation)]) { pin in
                    MapMarker(coordinate: pin.coordinate, tint: .red)
                }
                .onChange(of: region.center.latitude) { _ in
                    handleRegionChange()
                }
                .onChange(of: region.center.longitude) { _ in
                    handleRegionChange()
                }
                .overlay(
                    // Crosshair in center for better precision
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "target")
                                .font(.title2)
                                .foregroundColor(.red)
                                .background(
                                    Circle()
                                        .fill(Color.white)
                                        .frame(width: 30, height: 30)
                                )
                            Spacer()
                        }
                    }
                    .allowsHitTesting(false)
                )
                
                // Show current location name
                VStack(spacing: 4) {
                    Text("Current Location")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(currentLocationName)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal)
                
                VStack(spacing: 8) {
                    HStack {
                        Text("Coordinates")
                            .font(.headline)
                        Spacer()
                    }
                    
                    HStack {
                        Text("Latitude")
                        Spacer()
                        TextField("Latitude", value: $pinLocation.latitude, format: .number.precision(.fractionLength(6)))
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(maxWidth: 120)
                            .onChange(of: pinLocation.latitude) { newValue in
                                region.center.latitude = newValue
                            }
                    }
                    
                    HStack {
                        Text("Longitude")
                        Spacer()
                        TextField("Longitude", value: $pinLocation.longitude, format: .number.precision(.fractionLength(6)))
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(maxWidth: 120)
                            .onChange(of: pinLocation.longitude) { newValue in
                                region.center.longitude = newValue
                            }
                    }
                    
                    // Add a button to capture the current map center
                    Button(action: {
                        pinLocation = region.center
                    }) {
                        Label("Capture Location", systemImage: "target")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 8)
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(10)
                .padding()
            }
            .navigationTitle("Choose Location")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("OK") {
                        latitude = pinLocation.latitude
                        longitude = pinLocation.longitude
                        locationName = currentLocationName // Use the geocoded name

                        // Save the location to history
                        LCLocationHistory.shared.addLocation(
                            name: currentLocationName,
                            latitude: pinLocation.latitude,
                            longitude: pinLocation.longitude
                        )

                        isPresented = false
                    }
                }
            }
        }
        .onAppear {
            reverseGeocode(coordinate: region.center)
        }
    }
    
    private func handleRegionChange() {
        let currentCenter = region.center
        let distance = sqrt(pow(currentCenter.latitude - lastGeocodedCoordinate.latitude, 2) + 
                           pow(currentCenter.longitude - lastGeocodedCoordinate.longitude, 2))
        
        // Only geocode if moved significantly (about 100m)
        if distance > 0.001 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                // Double-check we haven't moved again
                let finalCenter = region.center
                let finalDistance = sqrt(pow(finalCenter.latitude - currentCenter.latitude, 2) + 
                                       pow(finalCenter.longitude - currentCenter.longitude, 2))
                
                if finalDistance < 0.0001 { // Still in roughly the same place
                    reverseGeocode(coordinate: finalCenter)
                }
            }
        }
    }
    
    private func reverseGeocode(coordinate: CLLocationCoordinate2D) {
        lastGeocodedCoordinate = coordinate
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        
        geocoder.reverseGeocodeLocation(location) { placemarks, error in
            DispatchQueue.main.async {
                if let placemark = placemarks?.first {
                    var locationComponents: [String] = []
                    
                    if let locality = placemark.locality {
                        locationComponents.append(locality)
                    }
                    if let administrativeArea = placemark.administrativeArea {
                        locationComponents.append(administrativeArea)
                    }
                    if let country = placemark.country {
                        locationComponents.append(country)
                    }
                    
                    if !locationComponents.isEmpty {
                        currentLocationName = locationComponents.joined(separator: ", ")
                    } else {
                        currentLocationName = "Unknown Location"
                    }
                } else {
                    currentLocationName = "Unknown Location"
                }
            }
        }
    }
}

// MARK: - Supporting Structures
struct MapPin: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}

struct City {
    let name: String
    let latitude: CLLocationDegrees
    let longitude: CLLocationDegrees
}

// MARK: - City Picker View
struct LCCityPickerView: View {
    @Binding var latitude: CLLocationDegrees
    @Binding var longitude: CLLocationDegrees
    @Binding var locationName: String
    @Binding var isPresented: Bool
    
    static let cities = [
        City(name: "New York, NY, United States", latitude: 40.7128, longitude: -74.0060),
        City(name: "Los Angeles, CA, United States", latitude: 34.0522, longitude: -118.2437),
        City(name: "Chicago, IL, United States", latitude: 41.8781, longitude: -87.6298),
        City(name: "Houston, TX, United States", latitude: 29.7604, longitude: -95.3698),
        City(name: "Phoenix, AZ, United States", latitude: 33.4484, longitude: -112.0740),
        City(name: "Philadelphia, PA, United States", latitude: 39.9526, longitude: -75.1652),
        City(name: "San Antonio, TX, United States", latitude: 29.4241, longitude: -98.4936),
        City(name: "San Diego, CA, United States", latitude: 32.7157, longitude: -117.1611),
        City(name: "Dallas, TX, United States", latitude: 32.7767, longitude: -96.7970),
        City(name: "San Jose, CA, United States", latitude: 37.3382, longitude: -121.8863),
        City(name: "Austin, TX, United States", latitude: 30.2672, longitude: -97.7431),
        City(name: "Jacksonville, FL, United States", latitude: 30.3322, longitude: -81.6557),
        City(name: "San Francisco, CA, United States", latitude: 37.7749, longitude: -122.4194),
        City(name: "Columbus, OH, United States", latitude: 39.9612, longitude: -82.9988),
        City(name: "Fort Worth, TX, United States", latitude: 32.7555, longitude: -97.3308),
        City(name: "Indianapolis, IN, United States", latitude: 39.7684, longitude: -86.1581),
        City(name: "Charlotte, NC, United States", latitude: 35.2271, longitude: -80.8431),
        City(name: "Seattle, WA, United States", latitude: 47.6062, longitude: -122.3321),
        City(name: "Denver, CO, United States", latitude: 39.7392, longitude: -104.9903),
        City(name: "Washington, DC, United States", latitude: 38.9072, longitude: -77.0369),
        City(name: "Boston, MA, United States", latitude: 42.3601, longitude: -71.0589),
        City(name: "El Paso, TX, United States", latitude: 31.7619, longitude: -106.4850),
        City(name: "Detroit, MI, United States", latitude: 42.3314, longitude: -83.0458),
        City(name: "Nashville, TN, United States", latitude: 36.1627, longitude: -86.7816),
        City(name: "Portland, OR, United States", latitude: 45.5152, longitude: -122.6784),
        City(name: "Memphis, TN, United States", latitude: 35.1495, longitude: -90.0490),
        City(name: "Oklahoma City, OK, United States", latitude: 35.4676, longitude: -97.5164),
        City(name: "Las Vegas, NV, United States", latitude: 36.1699, longitude: -115.1398),
        City(name: "Louisville, KY, United States", latitude: 38.2527, longitude: -85.7585),
        City(name: "Baltimore, MD, United States", latitude: 39.2904, longitude: -76.6122),
        City(name: "Milwaukee, WI, United States", latitude: 43.0389, longitude: -87.9065),
        City(name: "Albuquerque, NM, United States", latitude: 35.0844, longitude: -106.6504),
        City(name: "Tucson, AZ, United States", latitude: 32.2226, longitude: -110.9747),
        City(name: "Fresno, CA, United States", latitude: 36.7378, longitude: -119.7871),
        City(name: "Mesa, AZ, United States", latitude: 33.4152, longitude: -111.8315),
        City(name: "Sacramento, CA, United States", latitude: 38.5816, longitude: -121.4944),
        City(name: "Atlanta, GA, United States", latitude: 33.7490, longitude: -84.3880),
        City(name: "Kansas City, MO, United States", latitude: 39.0997, longitude: -94.5786),
        City(name: "Colorado Springs, CO, United States", latitude: 38.8339, longitude: -104.8214),
        City(name: "Miami, FL, United States", latitude: 25.7617, longitude: -80.1918),
        City(name: "Raleigh, NC, United States", latitude: 35.7796, longitude: -78.6382),
        City(name: "Omaha, NE, United States", latitude: 41.2524, longitude: -95.9980),
        City(name: "Long Beach, CA, United States", latitude: 33.7701, longitude: -118.1937),
        City(name: "Virginia Beach, VA, United States", latitude: 36.8529, longitude: -75.9780),
        City(name: "Oakland, CA, United States", latitude: 37.8044, longitude: -122.2711),
        City(name: "Minneapolis, MN, United States", latitude: 44.9778, longitude: -93.2650),
        City(name: "Tulsa, OK, United States", latitude: 36.1540, longitude: -95.9928),
        City(name: "Arlington, TX, United States", latitude: 32.7357, longitude: -97.1081),
        City(name: "Tampa, FL, United States", latitude: 27.9506, longitude: -82.4572),
        City(name: "New Orleans, LA, United States", latitude: 29.9511, longitude: -90.0715),
        
        // United Kingdom - Format: City, Region, Country
        City(name: "London, England, United Kingdom", latitude: 51.5074, longitude: -0.1278),
        City(name: "Manchester, England, United Kingdom", latitude: 53.4808, longitude: -2.2426),
        City(name: "Birmingham, England, United Kingdom", latitude: 52.4862, longitude: -1.8904),
        City(name: "Liverpool, England, United Kingdom", latitude: 53.4084, longitude: -2.9916),
        City(name: "Edinburgh, Scotland, United Kingdom", latitude: 55.9533, longitude: -3.1883),
        City(name: "Glasgow, Scotland, United Kingdom", latitude: 55.8642, longitude: -4.2518),
        City(name: "Cardiff, Wales, United Kingdom", latitude: 51.4816, longitude: -3.1791),
        City(name: "Belfast, Northern Ireland, United Kingdom", latitude: 54.5973, longitude: -5.9301),
        
        // Europe - Format: City, Region/Province, Country
        City(name: "Paris, Île-de-France, France", latitude: 48.8566, longitude: 2.3522),
        City(name: "Berlin, Berlin, Germany", latitude: 52.5200, longitude: 13.4050),
        City(name: "Madrid, Madrid, Spain", latitude: 40.4168, longitude: -3.7038),
        City(name: "Rome, Lazio, Italy", latitude: 41.9028, longitude: 12.4964),
        City(name: "Amsterdam, North Holland, Netherlands", latitude: 52.3676, longitude: 4.9041),
        City(name: "Vienna, Vienna, Austria", latitude: 48.2082, longitude: 16.3738),
        City(name: "Prague, Prague, Czech Republic", latitude: 50.0755, longitude: 14.4378),
        City(name: "Budapest, Budapest, Hungary", latitude: 47.4979, longitude: 19.0402),
        City(name: "Warsaw, Masovian Voivodeship, Poland", latitude: 52.2297, longitude: 21.0122),
        City(name: "Stockholm, Stockholm County, Sweden", latitude: 59.3293, longitude: 18.0686),
        City(name: "Oslo, Oslo, Norway", latitude: 59.9139, longitude: 10.7522),
        City(name: "Copenhagen, Capital Region, Denmark", latitude: 55.6761, longitude: 12.5683),
        City(name: "Helsinki, Uusimaa, Finland", latitude: 60.1699, longitude: 24.9384),
        City(name: "Dublin, Leinster, Ireland", latitude: 53.3498, longitude: -6.2603),
        City(name: "Brussels, Brussels-Capital Region, Belgium", latitude: 50.8503, longitude: 4.3517),
        City(name: "Zurich, Zurich, Switzerland", latitude: 47.3769, longitude: 8.5417),
        City(name: "Barcelona, Catalonia, Spain", latitude: 41.3851, longitude: 2.1734),
        City(name: "Lisbon, Lisbon, Portugal", latitude: 38.7223, longitude: -9.1393),
        City(name: "Athens, Attica, Greece", latitude: 37.9838, longitude: 23.7275),
        City(name: "Istanbul, Istanbul, Turkey", latitude: 41.0082, longitude: 28.9784),
        City(name: "Moscow, Moscow, Russia", latitude: 55.7558, longitude: 37.6176),
        City(name: "Munich, Bavaria, Germany", latitude: 48.1351, longitude: 11.5820),
        City(name: "Milan, Lombardy, Italy", latitude: 45.4642, longitude: 9.1900),
        City(name: "Lyon, Auvergne-Rhône-Alpes, France", latitude: 45.7640, longitude: 4.8357),
        City(name: "Frankfurt, Hesse, Germany", latitude: 50.1109, longitude: 8.6821),
        City(name: "Hamburg, Hamburg, Germany", latitude: 53.5511, longitude: 9.9937),
        City(name: "Cologne, North Rhine-Westphalia, Germany", latitude: 50.9375, longitude: 6.9603),
        City(name: "Rotterdam, South Holland, Netherlands", latitude: 51.9244, longitude: 4.4777),
        City(name: "Antwerp, Flanders, Belgium", latitude: 51.2194, longitude: 4.4025),
        City(name: "Geneva, Geneva, Switzerland", latitude: 46.2044, longitude: 6.1432),
        City(name: "Basel, Basel-Stadt, Switzerland", latitude: 47.5596, longitude: 7.5886),
        City(name: "Luxembourg City, Luxembourg, Luxembourg", latitude: 49.6116, longitude: 6.1319),
        City(name: "Monaco, Monaco, Monaco", latitude: 43.7384, longitude: 7.4246),
        City(name: "Nice, Provence-Alpes-Côte d'Azur, France", latitude: 43.7102, longitude: 7.2620),
        City(name: "Marseille, Provence-Alpes-Côte d'Azur, France", latitude: 43.2965, longitude: 5.3698),
        City(name: "Toulouse, Occitanie, France", latitude: 43.6047, longitude: 1.4442),
        City(name: "Strasbourg, Grand Est, France", latitude: 48.5734, longitude: 7.7521),
        City(name: "Nantes, Pays de la Loire, France", latitude: 47.2184, longitude: -1.5536),
        City(name: "Montpellier, Occitanie, France", latitude: 43.6110, longitude: 3.8767),
        City(name: "Bordeaux, Nouvelle-Aquitaine, France", latitude: 44.8378, longitude: -0.5792),
        City(name: "Lille, Hauts-de-France, France", latitude: 50.6292, longitude: 3.0573),
        City(name: "Rennes, Brittany, France", latitude: 48.1173, longitude: -1.6778),
        City(name: "Naples, Campania, Italy", latitude: 40.8518, longitude: 14.2681),
        City(name: "Turin, Piedmont, Italy", latitude: 45.0703, longitude: 7.6869),
        City(name: "Palermo, Sicily, Italy", latitude: 38.1157, longitude: 13.3613),
        City(name: "Genoa, Liguria, Italy", latitude: 44.4056, longitude: 8.9463),
        City(name: "Bologna, Emilia-Romagna, Italy", latitude: 44.4949, longitude: 11.3426),
        City(name: "Florence, Tuscany, Italy", latitude: 43.7696, longitude: 11.2558),
        City(name: "Bari, Apulia, Italy", latitude: 41.1171, longitude: 16.8719),
        City(name: "Catania, Sicily, Italy", latitude: 37.5079, longitude: 15.0830),
        City(name: "Valencia, Valencia, Spain", latitude: 39.4699, longitude: -0.3763),
        City(name: "Seville, Andalusia, Spain", latitude: 37.3891, longitude: -5.9845),
        City(name: "Zaragoza, Aragon, Spain", latitude: 41.6488, longitude: -0.8891),
        City(name: "Málaga, Andalusia, Spain", latitude: 36.7213, longitude: -4.4214),
        City(name: "Murcia, Murcia, Spain", latitude: 37.9922, longitude: -1.1307),
        City(name: "Palma, Balearic Islands, Spain", latitude: 39.5696, longitude: 2.6502),
        City(name: "Las Palmas, Canary Islands, Spain", latitude: 28.1248, longitude: -15.4300),
        City(name: "Bilbao, Basque Country, Spain", latitude: 43.2627, longitude: -2.9253),
        City(name: "Alicante, Valencia, Spain", latitude: 38.3460, longitude: -0.4907),
        City(name: "Córdoba, Andalusia, Spain", latitude: 37.8882, longitude: -4.7794),
        City(name: "Valladolid, Castile and León, Spain", latitude: 41.6518, longitude: -4.7245),
        City(name: "Vigo, Galicia, Spain", latitude: 42.2406, longitude: -8.7207),
        City(name: "Gijón, Asturias, Spain", latitude: 43.5322, longitude: -5.6611),
        City(name: "Porto, Porto District, Portugal", latitude: 41.1579, longitude: -8.6291),
        City(name: "Braga, Braga District, Portugal", latitude: 41.5518, longitude: -8.4229),
        City(name: "Coimbra, Coimbra District, Portugal", latitude: 40.2033, longitude: -8.4103),
        City(name: "Stuttgart, Baden-Württemberg, Germany", latitude: 48.7758, longitude: 9.1829),
        City(name: "Düsseldorf, North Rhine-Westphalia, Germany", latitude: 51.2277, longitude: 6.7735),
        City(name: "Dortmund, North Rhine-Westphalia, Germany", latitude: 51.5136, longitude: 7.4653),
        City(name: "Essen, North Rhine-Westphalia, Germany", latitude: 51.4556, longitude: 7.0116),
        City(name: "Leipzig, Saxony, Germany", latitude: 51.3397, longitude: 12.3731),
        City(name: "Bremen, Bremen, Germany", latitude: 53.0793, longitude: 8.8017),
        City(name: "Dresden, Saxony, Germany", latitude: 51.0504, longitude: 13.7373),
        City(name: "Hanover, Lower Saxony, Germany", latitude: 52.3759, longitude: 9.7320),
        City(name: "Nuremberg, Bavaria, Germany", latitude: 49.4521, longitude: 11.0767),
        City(name: "Duisburg, North Rhine-Westphalia, Germany", latitude: 51.4344, longitude: 6.7623),
        City(name: "Bochum, North Rhine-Westphalia, Germany", latitude: 51.4819, longitude: 7.2162),
        City(name: "Wuppertal, North Rhine-Westphalia, Germany", latitude: 51.2562, longitude: 7.1508),
        City(name: "Bielefeld, North Rhine-Westphalia, Germany", latitude: 52.0302, longitude: 8.5325),
        City(name: "Bonn, North Rhine-Westphalia, Germany", latitude: 50.7374, longitude: 7.0982),
        
        // Scandinavia
        City(name: "Gothenburg, Västra Götaland County, Sweden", latitude: 57.7089, longitude: 11.9746),
        City(name: "Bergen, Vestland, Norway", latitude: 60.3913, longitude: 5.3221),
        City(name: "Aarhus, Central Denmark Region, Denmark", latitude: 56.1629, longitude: 10.2039),

        // Asia - Format: City, Region/Province, Country
        City(name: "Tokyo, Tokyo, Japan", latitude: 35.6762, longitude: 139.6503),
        City(name: "Seoul, Seoul, South Korea", latitude: 37.5665, longitude: 126.9780),
        City(name: "Beijing, Beijing, China", latitude: 39.9042, longitude: 116.4074),
        City(name: "Shanghai, Shanghai, China", latitude: 31.2304, longitude: 121.4737),
        City(name: "Hong Kong, Hong Kong, Hong Kong", latitude: 22.3193, longitude: 114.1694),
        City(name: "Singapore, Singapore, Singapore", latitude: 1.3521, longitude: 103.8198),
        City(name: "Bangkok, Bangkok, Thailand", latitude: 13.7563, longitude: 100.5018),
        City(name: "Mumbai, Maharashtra, India", latitude: 19.0760, longitude: 72.8777),
        City(name: "Delhi, Delhi, India", latitude: 28.7041, longitude: 77.1025),
        City(name: "Taipei, Taipei, Taiwan", latitude: 25.0330, longitude: 121.5654),
        City(name: "Osaka, Osaka Prefecture, Japan", latitude: 34.6937, longitude: 135.5023),
        City(name: "Busan, Busan, South Korea", latitude: 35.1796, longitude: 129.0756),

        // Middle East & Israel
        City(name: "Tel Aviv, Tel Aviv District, Israel", latitude: 32.0853, longitude: 34.7818),
        City(name: "Jerusalem, Jerusalem District, Israel", latitude: 31.7683, longitude: 35.2137),
        City(name: "Riyadh, Riyadh Province, Saudi Arabia", latitude: 24.7136, longitude: 46.6753),
        City(name: "Jeddah, Makkah Province, Saudi Arabia", latitude: 21.4858, longitude: 39.1925),
        City(name: "Kuwait City, Al Asimah Governorate, Kuwait", latitude: 29.3759, longitude: 47.9774),
        City(name: "Doha, Ad Dawhah, Qatar", latitude: 25.2854, longitude: 51.5310),
        City(name: "Dubai, Dubai, United Arab Emirates", latitude: 25.2048, longitude: 55.2708),
        
        // Australia/Oceania - Format: City, State, Country
        City(name: "Sydney, New South Wales, Australia", latitude: -33.8688, longitude: 151.2093),
        City(name: "Melbourne, Victoria, Australia", latitude: -37.8136, longitude: 144.9631),
        City(name: "Brisbane, Queensland, Australia", latitude: -27.4698, longitude: 153.0251),
        City(name: "Perth, Western Australia, Australia", latitude: -31.9505, longitude: 115.8605),
        City(name: "Auckland, Auckland, New Zealand", latitude: -36.8485, longitude: 174.7633),
        City(name: "Adelaide, South Australia, Australia", latitude: -34.9285, longitude: 138.6007),
        City(name: "Wellington, Wellington, New Zealand", latitude: -41.2865, longitude: 174.7762),
        
        // Canada - Format: City, Province, Country
        City(name: "Toronto, Ontario, Canada", latitude: 43.6532, longitude: -79.3832),
        City(name: "Vancouver, British Columbia, Canada", latitude: 49.2827, longitude: -123.1207),
        City(name: "Montreal, Quebec, Canada", latitude: 45.5017, longitude: -73.5673),
        City(name: "Calgary, Alberta, Canada", latitude: 51.0447, longitude: -114.0719),
        City(name: "Ottawa, Ontario, Canada", latitude: 45.4215, longitude: -75.6972),
        City(name: "Edmonton, Alberta, Canada", latitude: 53.5461, longitude: -113.4938),
        City(name: "Winnipeg, Manitoba, Canada", latitude: 49.8951, longitude: -97.1384),
        City(name: "Quebec City, Quebec, Canada", latitude: 46.8139, longitude: -71.2080),
        City(name: "Halifax, Nova Scotia, Canada", latitude: 44.6488, longitude: -63.5752),
        
        // South America - Format: City, Region/State, Country
        City(name: "Mexico City, Mexico City, Mexico", latitude: 19.4326, longitude: -99.1332),
        City(name: "Guadalajara, Jalisco, Mexico", latitude: 20.6597, longitude: -103.3496),
        City(name: "Monterrey, Nuevo León, Mexico", latitude: 25.6866, longitude: -100.3161),
        City(name: "São Paulo, São Paulo, Brazil", latitude: -23.5558, longitude: -46.6396),
        City(name: "Rio de Janeiro, Rio de Janeiro, Brazil", latitude: -22.9068, longitude: -43.1729),
        City(name: "Medellín, Antioquia, Colombia", latitude: 6.2442, longitude: -75.5812),
        City(name: "Buenos Aires, Buenos Aires, Argentina", latitude: -34.6118, longitude: -58.3960),
        City(name: "Santiago, Santiago Metropolitan, Chile", latitude: -33.4489, longitude: -70.6693),
        City(name: "Lima, Lima, Peru", latitude: -12.0464, longitude: -77.0428),
        
        // Africa - Format: City, Region/Province, Country
        City(name: "Cairo, Cairo Governorate, Egypt", latitude: 30.0444, longitude: 31.2357),
        City(name: "Lagos, Lagos State, Nigeria", latitude: 6.5244, longitude: 3.3792),
        City(name: "Cape Town, Western Cape, South Africa", latitude: -33.9249, longitude: 18.4241),
        City(name: "Johannesburg, Gauteng, South Africa", latitude: -26.2041, longitude: 28.0473),
        City(name: "Casablanca, Casablanca-Settat, Morocco", latitude: 33.5731, longitude: -7.5898)
    ]
    
    @State private var searchText = ""
    
    var filteredCities: [City] {
        if searchText.isEmpty {
            return Self.cities
        } else {
            return Self.cities.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
    }
    
    var body: some View {
        NavigationView {
            List {
                ForEach(filteredCities, id: \.name) { city in
                    Button(action: {
                        latitude = city.latitude
                        longitude = city.longitude
                        locationName = city.name // Set the city name

                        // Save the selected city to history
                        LCLocationHistory.shared.addLocation(
                            name: city.name,
                            latitude: city.latitude,
                            longitude: city.longitude
                        )

                        isPresented = false
                    }) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(city.name)
                                .font(.headline)
                                .foregroundColor(.primary)
                            Text("\(city.latitude, specifier: "%.4f"), \(city.longitude, specifier: "%.4f")")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search cities...")
            .navigationTitle("Choose City")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
        }
    }
}

// RandomSeed for random adjustments
struct SeededRandomGenerator {
    private var state: UInt64
    
    init(seed: Int) {
        self.state = UInt64(seed)
    }
    
    mutating func next() -> UInt64 {
        // Linear congruential generator (simple but effective for our use)
        state = state &* 1103515245 &+ 12345
        return state
    }
    
    mutating func nextDouble(_ min: Double, _ max: Double) -> Double {
        let normalized = Double(next() % 10000) / 9999.0 // 0.0 to 1.0
        return min + normalized * (max - min)
    }
}

// MARK: Camera Settings Section
struct CameraSettingsSection: View {
    @Binding var spoofCamera: Bool
    @Binding var spoofCameraMode: String
    @Binding var spoofCameraType: String
    @Binding var spoofCameraImagePath: String
    @Binding var spoofCameraVideoPath: String
    @Binding var spoofCameraLoop: Bool
    @Binding var spoofCameraTransformOrientation: String
    @Binding var spoofCameraTransformScale: String
    @Binding var spoofCameraTransformFlip: String
    @Binding var isProcessingVideo: Bool
    @Binding var videoProcessingProgress: Double
    @Binding var errorInfo: String
    @Binding var errorShow: Bool
    
    // Remove the callback - handle internally
    // let onVideoTransformChange: () async -> Void
    
    var body: some View {
        Section {
            Toggle(isOn: $spoofCamera) {
                HStack {
                    Image(systemName: "camera")
                        .foregroundColor(.blue)
                        .frame(width: 20)
                    Text("Spoof Camera")
                }
            }
            
            if spoofCamera {
                // Media Type Picker (keep this simple)
                Picker("Camera Type", selection: $spoofCameraType) {
                    Text("Static Image").tag("image")
                    Text("Video").tag("video")
                }
                .pickerStyle(SegmentedPickerStyle())
                
                // Media Selection based on type
                if spoofCameraType == "image" {
                    CameraImagePickerView(
                        imagePath: $spoofCameraImagePath,
                        errorInfo: $errorInfo,
                        errorShow: $errorShow,
                        // Pass transformation bindings to image picker
                        spoofCameraMode: $spoofCameraMode,
                        spoofCameraTransformOrientation: $spoofCameraTransformOrientation,
                        spoofCameraTransformScale: $spoofCameraTransformScale,
                        spoofCameraTransformFlip: $spoofCameraTransformFlip,
                        isProcessingVideo: $isProcessingVideo,
                        videoProcessingProgress: $videoProcessingProgress
                    )
                } else {
                    CameraVideoPickerView(
                        videoPath: $spoofCameraVideoPath,
                        loopVideo: $spoofCameraLoop,
                        errorInfo: $errorInfo,
                        errorShow: $errorShow
                    )
                    
                    // ✅ NEW: Video transformations with Verified Mode as first option
                    if !spoofCameraVideoPath.isEmpty {
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Video Transformations")
                                .font(.headline)
                                .padding(.top, 8)
                            
                            // ✅ Verified Mode as part of transformations
                            HStack {
                                Toggle("Verified Mode", isOn: Binding(
                                    get: { spoofCameraMode == "verified" },
                                    set: { newValue in
                                        spoofCameraMode = newValue ? "verified" : "standard"
                                        Task {
                                            await processVideoTransforms()
                                        }
                                    }
                                ))
                                
                                Spacer()
                                
                                if spoofCameraMode == "verified" {
                                    Label("Anti-Detection", systemImage: "checkmark.shield")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                }
                            }
                            .padding(.bottom, 4)
                            
                            if spoofCameraMode == "verified" {
                                HStack {
                                    Image(systemName: "info.circle")
                                        .foregroundColor(.blue)
                                    Text("Adds Nomix-style random variations to avoid detection")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(6)
                            }
                            
                            // Standard transformation controls
                            Picker("Orientation", selection: Binding(
                                get: { spoofCameraTransformOrientation },
                                set: { newValue in
                                    spoofCameraTransformOrientation = newValue
                                    Task {
                                        await processVideoTransforms()
                                    }
                                }
                            )) {
                                Text("Original").tag("none")
                                Text("Force Portrait").tag("portrait") 
                                Text("Force Landscape").tag("landscape")
                                Text("Rotate 90°").tag("rotate90")
                                Text("Rotate 180°").tag("rotate180")
                                Text("Rotate 270°").tag("rotate270")
                            }
                            
                            Picker("Scale", selection: Binding(
                                get: { spoofCameraTransformScale },
                                set: { newValue in
                                    spoofCameraTransformScale = newValue
                                    Task {
                                        await processVideoTransforms()
                                    }
                                }
                            )) {
                                Text("Fit").tag("fit")
                                Text("Fill").tag("fill")
                                Text("Stretch").tag("stretch")
                            }
                            
                            Picker("Flip", selection: Binding(
                                get: { spoofCameraTransformFlip },
                                set: { newValue in
                                    spoofCameraTransformFlip = newValue
                                    Task {
                                        await processVideoTransforms()
                                    }
                                }
                            )) {
                                Text("None").tag("none")
                                Text("Horizontal").tag("horizontal")
                                Text("Vertical").tag("vertical")
                                Text("Both").tag("both")
                            }
                            
                            // Processing indicator
                            if isProcessingVideo {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                        Text("Processing video transformations...")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    ProgressView(value: videoProcessingProgress)
                                        .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                                    
                                    Text("\(Int(videoProcessingProgress * 100))%")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.top, 4)
                            }
                            
                            // Transform summary
                            if hasAnyTransforms() {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Active Transformations:")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundColor(.secondary)
                                    
                                    HStack {
                                        if spoofCameraMode == "verified" {
                                            Label("Verified", systemImage: "checkmark.shield")
                                                .font(.caption2)
                                                .foregroundColor(.green)
                                        }
                                        
                                        if spoofCameraTransformOrientation != "none" {
                                            Label(orientationLabel(), systemImage: "rotate.3d")
                                                .font(.caption2)
                                                .foregroundColor(.blue)
                                        }
                                        
                                        if spoofCameraTransformFlip != "none" {
                                            Label(spoofCameraTransformFlip.capitalized, systemImage: "arrow.up.and.down.righttriangle.up.righttriangle.down")
                                                .font(.caption2)
                                                .foregroundColor(.purple)
                                        }
                                        
                                        if spoofCameraTransformScale != "fit" {
                                            Label(spoofCameraTransformScale.capitalized, systemImage: "viewfinder")
                                                .font(.caption2)
                                                .foregroundColor(.orange)
                                        }
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(6)
                            }
                            
                            Text("Transformations are applied when settings change. Verified mode adds random variations like Nomix.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.top, 4)
                        }
                    }
                }
                
                if #unavailable(iOS 16.0) {
                    Text("Note: Photo library access requires iOS 16.0 or later. Use Files or manual path entry instead.")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        } header: {
            Text("Camera Settings")
        }
    }
    
    // MARK: VIDEO TRANSFORM FUNCTIONS
    
    @MainActor
    private func processVideoTransforms() async {
        guard spoofCamera && spoofCameraType == "video" && !spoofCameraVideoPath.isEmpty else {
            return
        }
        
        // Check if any transforms are applied
        let hasTransforms = hasAnyTransforms()
        
        guard hasTransforms else { return }
        
        isProcessingVideo = true
        videoProcessingProgress = 0.0
        
        do {
            let transformedPath = try await transformVideo(
                inputPath: spoofCameraVideoPath,
                orientation: spoofCameraTransformOrientation,
                scale: spoofCameraTransformScale,
                flip: spoofCameraTransformFlip,
                isVerifiedMode: spoofCameraMode == "verified"
            )
            
            spoofCameraVideoPath = transformedPath
            
        } catch {
            errorInfo = "Video transformation failed: \(error.localizedDescription)"
            errorShow = true
        }
        
        isProcessingVideo = false
    }

   private func transformVideo(
        inputPath: String,
        orientation: String,
        scale: String,
        flip: String,
        isVerifiedMode: Bool = false
    ) async throws -> String {
        
        let inputURL = URL(fileURLWithPath: inputPath)
        let outputFileName = inputURL.deletingPathExtension().lastPathComponent + "_transformed.mp4"
        let outputURL = inputURL.deletingLastPathComponent().appendingPathComponent(outputFileName)
        
        // Remove existing transformed file
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        
        let asset = AVAsset(url: inputURL)
        let composition = AVMutableComposition()
        let videoComposition = AVMutableVideoComposition()
        
        // Add video track
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw NSError(domain: "VideoTransform", code: 1, userInfo: [NSLocalizedDescriptionKey: "No video track found"])
        }
        
        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw NSError(domain: "VideoTransform", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create composition track"])
        }
        
        let duration = try await asset.load(.duration)
        try compositionVideoTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: duration),
            of: videoTrack,
            at: .zero
        )
        
        // Add audio track if present
        if let audioTrack = try await asset.loadTracks(withMediaType: .audio).first {
            if let compositionAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) {
                try compositionAudioTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: duration),
                    of: audioTrack,
                    at: .zero
                )
            }
        }
        
        // Calculate transform
        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        
        let transformResult = calculateVideoTransform(
            naturalSize: naturalSize,
            preferredTransform: preferredTransform,
            orientation: orientation,
            scale: scale,
            flip: flip,
            isVerifiedMode: isVerifiedMode
        )
        
        // Create video composition
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)
        layerInstruction.setTransform(transformResult.transform, at: .zero)
        
        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]
        videoComposition.renderSize = transformResult.renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        
        // Export with progress monitoring
        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw NSError(domain: "VideoTransform", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create export session"])
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.videoComposition = videoComposition
        
        // Use withCheckedContinuation for proper async/await
        return try await withCheckedThrowingContinuation { continuation in
            // Store references to avoid capture issues
            let session = exportSession
            
            // Monitor progress in a separate task
            let progressTask = Task { @MainActor in
                while !session.status.isFinished {
                    videoProcessingProgress = Double(session.progress)
                    try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                }
                videoProcessingProgress = 1.0
            }
            
            session.exportAsynchronously {
                progressTask.cancel()
                
                switch session.status {
                case .completed:
                    Task { @MainActor in
                        videoProcessingProgress = 1.0
                    }
                    continuation.resume(returning: outputURL.path)
                case .failed:
                    let errorMessage = session.error?.localizedDescription ?? "Unknown export error"
                    let error = NSError(domain: "VideoTransform", code: 4, userInfo: [NSLocalizedDescriptionKey: "Export failed: \(errorMessage)"])
                    continuation.resume(throwing: error)
                case .cancelled:
                    let error = NSError(domain: "VideoTransform", code: 5, userInfo: [NSLocalizedDescriptionKey: "Export was cancelled"])
                    continuation.resume(throwing: error)
                default:
                    let error = NSError(domain: "VideoTransform", code: 6, userInfo: [NSLocalizedDescriptionKey: "Export in unknown state"])
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func calculateVideoTransform(
        naturalSize: CGSize,
        preferredTransform: CGAffineTransform,
        orientation: String,
        scale: String,
        flip: String,
        isVerifiedMode: Bool = false // Add this parameter
    ) -> (transform: CGAffineTransform, renderSize: CGSize) {
        
        var transform = preferredTransform
        var renderSize = naturalSize
        
        // Apply orientation
        switch orientation {
        case "portrait":
            if naturalSize.width > naturalSize.height {
                transform = transform.concatenating(CGAffineTransform(rotationAngle: .pi / 2))
                renderSize = CGSize(width: naturalSize.height, height: naturalSize.width)
            }
        case "landscape":
            if naturalSize.height > naturalSize.width {
                transform = transform.concatenating(CGAffineTransform(rotationAngle: -.pi / 2))
                renderSize = CGSize(width: naturalSize.height, height: naturalSize.width)
            }
        case "rotate90":
            transform = transform.concatenating(CGAffineTransform(rotationAngle: .pi / 2))
            renderSize = CGSize(width: naturalSize.height, height: naturalSize.width)
        case "rotate180":
            transform = transform.concatenating(CGAffineTransform(rotationAngle: .pi))
        case "rotate270":
            transform = transform.concatenating(CGAffineTransform(rotationAngle: -.pi / 2))
            renderSize = CGSize(width: naturalSize.height, height: naturalSize.width)
        default: // "none"
            break
        }
        
        // Apply flip
        switch flip {
        case "horizontal":
            transform = transform.concatenating(CGAffineTransform(scaleX: -1, y: 1))
            transform = transform.concatenating(CGAffineTransform(translationX: renderSize.width, y: 0))
        case "vertical":
            transform = transform.concatenating(CGAffineTransform(scaleX: 1, y: -1))
            transform = transform.concatenating(CGAffineTransform(translationX: 0, y: renderSize.height))
        case "both":
            transform = transform.concatenating(CGAffineTransform(scaleX: -1, y: -1))
            transform = transform.concatenating(CGAffineTransform(translationX: renderSize.width, y: renderSize.height))
        default: // "none"
            break
        }
        
        // ✅ NEW: Apply Verified Mode (Nomix-style) variations
        if isVerifiedMode {
            // Generate subtle random variations to avoid detection
            let seed = Int(Date().timeIntervalSince1970) % 1000 // Change variations over time
            var rng = SeededRandomGenerator(seed: seed)
            
            // 1. Slight rotation variation (±0.5 degrees)
            let rotationVariation = rng.nextDouble(-0.5, 0.5) * .pi / 180.0
            if abs(rotationVariation) > 0.001 {
                let centerX = renderSize.width / 2
                let centerY = renderSize.height / 2
                let rotateTransform = CGAffineTransform(translationX: centerX, y: centerY)
                    .concatenating(CGAffineTransform(rotationAngle: rotationVariation))
                    .concatenating(CGAffineTransform(translationX: -centerX, y: -centerY))
                transform = transform.concatenating(rotateTransform)
            }
            
            // 2. Slight scale variation (0.98x to 1.02x)
            let scaleVariation = rng.nextDouble(0.98, 1.02)
            if abs(scaleVariation - 1.0) > 0.001 {
                let centerX = renderSize.width / 2
                let centerY = renderSize.height / 2
                let scaleTransform = CGAffineTransform(translationX: centerX, y: centerY)
                    .concatenating(CGAffineTransform(scaleX: scaleVariation, y: scaleVariation))
                    .concatenating(CGAffineTransform(translationX: -centerX, y: -centerY))
                transform = transform.concatenating(scaleTransform)
            }
            
            // 3. Small translation variation (±2 pixels)
            let translateX = rng.nextDouble(-2.0, 2.0)
            let translateY = rng.nextDouble(-2.0, 2.0)
            if abs(translateX) > 0.1 || abs(translateY) > 0.1 {
                transform = transform.concatenating(CGAffineTransform(translationX: translateX, y: translateY))
            }
            
            // 4. Slight render size variation (±1 pixel) to break fingerprinting
            let sizeVariationX = rng.nextDouble(-1.0, 1.0)
            let sizeVariationY = rng.nextDouble(-1.0, 1.0)
            renderSize = CGSize(
                width: max(1, renderSize.width + sizeVariationX),
                height: max(1, renderSize.height + sizeVariationY)
            )
            
            print("🎭 Verified mode applied: rotation=\(rotationVariation * 180 / .pi)°, scale=\(scaleVariation), translate=(\(translateX),\(translateY)), size=(\(sizeVariationX),\(sizeVariationY))")
        }
        
        return (transform, renderSize)
    }

    private func hasAnyTransforms() -> Bool {
        return spoofCameraMode == "verified" ||
            spoofCameraTransformOrientation != "none" ||
            spoofCameraTransformFlip != "none" ||
            spoofCameraTransformScale != "fit"
    }

    private func orientationLabel() -> String {
        switch spoofCameraTransformOrientation {
        case "portrait": return "Portrait"
        case "landscape": return "Landscape"
        case "rotate90": return "90°"
        case "rotate180": return "180°"
        case "rotate270": return "270°"
        default: return "Original"
        }
    }
}


// MARK: Network Settings Section
struct NetworkSettingsSection: View {
    @Binding var spoofNetwork: Bool
    @Binding var proxyHost: String
    @Binding var proxyPort: Int32
    @Binding var proxyUsername: String
    @Binding var proxyPassword: String
    
    var body: some View {
        Section {
            Toggle(isOn: $spoofNetwork) {
                HStack {
                    Image(systemName: "network")
                        .foregroundColor(.blue)
                        .frame(width: 20)
                    Text("SOCKS5 Proxy")
                }
            }
            
            if spoofNetwork {
                // Proxy Host
                HStack {
                    Image(systemName: "server.rack")
                        .foregroundColor(.gray)
                        .frame(width: 20)
                    VStack(alignment: .leading) {
                        Text("Proxy Host")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("e.g., 127.0.0.1", text: $proxyHost)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                }
                
                // Proxy Port
                HStack {
                    Image(systemName: "number")
                        .foregroundColor(.gray)
                        .frame(width: 20)
                    VStack(alignment: .leading) {
                        Text("Proxy Port")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("1080", value: $proxyPort, format: .number)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .keyboardType(.numberPad)
                    }
                }
                
                // Authentication (optional)
                DisclosureGroup("Authentication") {
                    HStack {
                        Image(systemName: "person")
                            .foregroundColor(.gray)
                            .frame(width: 20)
                        VStack(alignment: .leading) {
                            Text("Username")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("Optional", text: $proxyUsername)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                    }
                    
                    HStack {
                        Image(systemName: "key")
                            .foregroundColor(.gray)
                            .frame(width: 20)
                        VStack(alignment: .leading) {
                            Text("Password")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            SecureField("Optional", text: $proxyPassword)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                    }
                }
            }
        } header: {
            Text("Network Settings")
        }
    }
}

extension AVAssetExportSession.Status {
    var isFinished: Bool {
        switch self {
        case .completed, .failed, .cancelled:
            return true
        default:
            return false
        }
    }
}

// MARK: Device Section

// MARK: - Device Profile Helper
struct DeviceProfileInfo {
    let model: String
    let memory: String
    let version: String
    let chip: String
}

func getProfileInfo(for profileName: String) -> DeviceProfileInfo {
    switch profileName {
    // iOS 26.x - iPhone 17 Series
    case "iPhone 17 Pro Max":
        return DeviceProfileInfo(model: "iPhone18,2", memory: "12 GB", version: "26.0", chip: "A19 Pro")
    case "iPhone 17 Pro":
        return DeviceProfileInfo(model: "iPhone18,1", memory: "12 GB", version: "26.0", chip: "A19 Pro")
    case "iPhone 17":
        return DeviceProfileInfo(model: "iPhone18,3", memory: "8 GB", version: "26.0", chip: "A19")
    case "iPhone 17 Air":
        return DeviceProfileInfo(model: "iPhone18,4", memory: "8 GB", version: "26.0", chip: "A19")
    // iOS 18.x - iPhone 16 Series
    case "iPhone 16 Pro Max":
        return DeviceProfileInfo(model: "iPhone17,2", memory: "8 GB", version: "18.1", chip: "A18 Pro")
    case "iPhone 16 Pro":
        return DeviceProfileInfo(model: "iPhone17,1", memory: "8 GB", version: "18.1", chip: "A18 Pro")
    case "iPhone 16":
        return DeviceProfileInfo(model: "iPhone17,3", memory: "8 GB", version: "18.1", chip: "A18")
    // iOS 17.x - iPhone 15 Series
    case "iPhone 15 Pro Max":
        return DeviceProfileInfo(model: "iPhone16,2", memory: "8 GB", version: "17.6.1", chip: "A17 Pro")
    case "iPhone 15 Pro":
        return DeviceProfileInfo(model: "iPhone16,1", memory: "8 GB", version: "17.6.1", chip: "A17 Pro")
    // iOS 17.x - iPhone 14 Series
    case "iPhone 14 Pro Max":
        return DeviceProfileInfo(model: "iPhone15,3", memory: "6 GB", version: "17.6.1", chip: "A16 Bionic")
    case "iPhone 14 Pro":
        return DeviceProfileInfo(model: "iPhone15,2", memory: "6 GB", version: "17.6.1", chip: "A16 Bionic")
    // iOS 17.x - iPhone 13 Series
    case "iPhone 13 Pro Max":
        return DeviceProfileInfo(model: "iPhone14,3", memory: "6 GB", version: "17.6.1", chip: "A15 Bionic")
    case "iPhone 13 Pro":
        return DeviceProfileInfo(model: "iPhone14,2", memory: "6 GB", version: "17.6.1", chip: "A15 Bionic")
    // iPad Pro M4 (iPadOS 18.x)
    case "iPad Pro 13-inch (M4)":
        return DeviceProfileInfo(model: "iPad16,5", memory: "16 GB", version: "18.1", chip: "M4")
    case "iPad Pro 11-inch (M4)":
        return DeviceProfileInfo(model: "iPad16,3", memory: "8 GB", version: "18.1", chip: "M4")
    // iPad Pro M2 (iPadOS 17.x)
    case "iPad Pro 12.9 (6th gen)":
        return DeviceProfileInfo(model: "iPad14,5", memory: "16 GB", version: "17.6.1", chip: "M2")
    default:
        return DeviceProfileInfo(model: "Unknown", memory: "Unknown", version: "Unknown", chip: "Unknown")
    }
}

// MARK: - Device Spoofing Section
struct DeviceSpoofingSection: View {
    // Device Spoofing bindings
    @Binding var spoofDevice: Bool
    @Binding var spoofDeviceModel: String
    @Binding var spoofSystemVersion: String
    @Binding var spoofDeviceName: String
    @Binding var spoofCarrierName: String
    @Binding var spoofCustomCarrier: String
    @Binding var spoofBattery: Bool
    @Binding var spoofBatteryLevel: Double
    @Binding var spoofMemory: Bool
    @Binding var spoofMemorySize: Int
    
    // Identifier Spoofing bindings
    @Binding var spoofIdentifiers: Bool
    @Binding var spoofVendorID: String
    @Binding var spoofAdvertisingID: String
    @Binding var spoofAdTrackingEnabled: Bool
    @Binding var spoofInstallationID: String
    @Binding var spoofMACAddress: String
    
    // Fingerprint Protection bindings
    @Binding var spoofFingerprint: Bool
    @Binding var spoofScreen: Bool
    @Binding var spoofScreenScale: Double
    @Binding var spoofScreenSize: String
    @Binding var spoofTimezone: Bool
    @Binding var spoofTimezoneValue: String
    @Binding var spoofLanguage: Bool
    @Binding var spoofPrimaryLanguage: String
    @Binding var spoofRegion: String
    
    var body: some View {
        Section {
            // Master Device Spoofing Toggle
            Toggle(isOn: $spoofDevice) {
                HStack {
                    Image(systemName: "iphone")
                        .foregroundColor(.blue)
                        .frame(width: 20)
                    Text("Device Spoofing")
                }
            }
            
            if spoofDevice {
                VStack(alignment: .leading, spacing: 16) {
                    
                    // MARK: - Basic Device Information
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "gear")
                                .foregroundColor(.gray)
                                .frame(width: 20)
                            Text("Device Information")
                                .font(.headline)
                        }
                        
                        // Device Model Selection
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Device Model")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Picker("Device Model", selection: $spoofDeviceModel) {
                                Text("iPhone 15 Pro").tag("iPhone16,1")
                                Text("iPhone 15").tag("iPhone15,4")
                                Text("iPhone 14 Pro").tag("iPhone15,2")
                                Text("iPhone 14").tag("iPhone14,7")
                                Text("iPhone 13 Pro").tag("iPhone14,2")
                                Text("iPhone 13").tag("iPhone14,5")
                                Text("iPhone 12 Pro Max").tag("iPhone13,4")
                                Text("iPhone 12 Pro").tag("iPhone13,3")
                                Text("iPhone 12").tag("iPhone13,2")
                                Text("iPhone 11 Pro Max").tag("iPhone12,5")
                                Text("iPhone 11 Pro").tag("iPhone12,3")
                                Text("iPhone 11").tag("iPhone12,1")
                            }
                            .pickerStyle(MenuPickerStyle())
                        }
                        
                        // iOS Version Selection
                        VStack(alignment: .leading, spacing: 4) {
                            Text("iOS Version")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Picker("iOS Version", selection: $spoofSystemVersion) {
                                Text("17.2").tag("17.2")
                                Text("17.1.1").tag("17.1.1")
                                Text("17.0").tag("17.0")
                                Text("16.7.2").tag("16.7.2")
                                Text("16.6.1").tag("16.6.1")
                                Text("16.5").tag("16.5")
                                Text("16.4.1").tag("16.4.1")
                                Text("16.3.1").tag("16.3.1")
                                Text("16.2").tag("16.2")
                                Text("15.7.9").tag("15.7.9")
                            }
                            .pickerStyle(MenuPickerStyle())
                        }
                        
                        // Device Name
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Device Name")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("Device Name", text: $spoofDeviceName)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                        
                        // Carrier Name
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Carrier Name")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Picker("Carrier", selection: $spoofCarrierName) {
                                Text("Verizon").tag("Verizon")
                                Text("AT&T").tag("AT&T")
                                Text("T-Mobile").tag("T-Mobile")
                                Text("Sprint").tag("Sprint")
                                Text("Custom").tag("Custom")
                            }
                            .pickerStyle(MenuPickerStyle())
                        }
                        
                        if spoofCarrierName == "Custom" {
                            TextField("Custom Carrier", text: $spoofCustomCarrier)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .padding(.leading, 20)
                        }
                    }
                    
                    Divider()
                    
                    // MARK: - Hardware Spoofing
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "cpu")
                                .foregroundColor(.gray)
                                .frame(width: 20)
                            Text("Hardware Information")
                                .font(.headline)
                        }
                        
                        Toggle("Spoof Battery Level", isOn: $spoofBattery)
                        
                        if spoofBattery {
                            HStack {
                                Text("Battery Level: \(Int(spoofBatteryLevel * 100))%")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Slider(value: $spoofBatteryLevel, in: 0...1)
                                    .frame(maxWidth: 150)
                            }
                            .padding(.leading, 20)
                        }
                        
                        Toggle("Spoof Memory Info", isOn: $spoofMemory)
                        
                        if spoofMemory {
                            HStack {
                                Text("RAM Size")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Picker("RAM", selection: $spoofMemorySize) {
                                    Text("4 GB").tag(4)
                                    Text("6 GB").tag(6)
                                    Text("8 GB").tag(8)
                                    Text("12 GB").tag(12)
                                }
                                .pickerStyle(SegmentedPickerStyle())
                                .frame(maxWidth: 200)
                            }
                            .padding(.leading, 20)
                        }
                    }
                    
                    Divider()
                    
                    // MARK: - Identifier Spoofing
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "qrcode")
                                .foregroundColor(.purple)
                                .frame(width: 20)
                            Text("Device Identifiers")
                                .font(.headline)
                            Spacer()
                            Toggle("", isOn: $spoofIdentifiers)
                                .labelsHidden()
                        }
                        
                        if spoofIdentifiers {
                            // Vendor Identifier
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Vendor Identifier (IDFV)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                HStack {
                                    TextField("IDFV", text: $spoofVendorID)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                        .font(.system(.caption, design: .monospaced))
                                    Button("Generate") {
                                        spoofVendorID = UUID().uuidString
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                            
                            // Advertising Identifier
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Advertising Identifier (IDFA)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                HStack {
                                    TextField("IDFA", text: $spoofAdvertisingID)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                        .font(.system(.caption, design: .monospaced))
                                    Button("Generate") {
                                        spoofAdvertisingID = UUID().uuidString
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                            
                            Toggle("Enable Advertising Tracking", isOn: $spoofAdTrackingEnabled)
                                .padding(.leading, 20)
                            
                            // Installation Identifier
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Installation ID")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                HStack {
                                    TextField("Installation ID", text: $spoofInstallationID)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                        .font(.system(.caption, design: .monospaced))
                                    Button("Generate") {
                                        spoofInstallationID = generateRandomString(16)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                            
                            // MAC Address
                            VStack(alignment: .leading, spacing: 4) {
                                Text("WiFi MAC Address")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                HStack {
                                    TextField("MAC Address", text: $spoofMACAddress)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                        .font(.system(.caption, design: .monospaced))
                                    Button("Generate") {
                                        spoofMACAddress = generateRandomMAC()
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                        }
                    }
                    
                    Divider()
                    
                    // MARK: - Fingerprint Protection
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "hand.raised.fill")
                                .foregroundColor(.orange)
                                .frame(width: 20)
                            Text("Fingerprint Protection")
                                .font(.headline)
                            Spacer()
                            Toggle("", isOn: $spoofFingerprint)
                                .labelsHidden()
                        }
                        
                        if spoofFingerprint {
                            // Screen Info
                            Toggle("Spoof Screen Properties", isOn: $spoofScreen)
                            
                            if spoofScreen {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("Screen Scale")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Picker("Scale", selection: $spoofScreenScale) {
                                            Text("2.0x").tag(2.0)
                                            Text("3.0x").tag(3.0)
                                        }
                                        .pickerStyle(SegmentedPickerStyle())
                                        .frame(maxWidth: 120)
                                    }
                                    
                                    HStack {
                                        Text("Screen Size")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Picker("Size", selection: $spoofScreenSize) {
                                            Text("iPhone 15 Pro").tag("1179x2556")
                                            Text("iPhone 15").tag("1179x2556")
                                            Text("iPhone 14 Pro").tag("1179x2556")
                                            Text("iPhone 13 Pro").tag("1170x2532")
                                            Text("iPhone 12 Pro").tag("1170x2532")
                                            Text("iPhone 11 Pro").tag("1125x2436")
                                            Text("iPhone XR").tag("828x1792")
                                        }
                                        .pickerStyle(MenuPickerStyle())
                                        .frame(maxWidth: 150)
                                    }
                                }
                                .padding(.leading, 20)
                            }
                            
                            // Timezone Spoofing
                            Toggle("Spoof Timezone", isOn: $spoofTimezone)
                            
                            if spoofTimezone {
                                HStack {
                                    Text("Timezone")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Picker("Timezone", selection: $spoofTimezoneValue) {
                                        Text("America/New_York").tag("America/New_York")
                                        Text("America/Los_Angeles").tag("America/Los_Angeles")
                                        Text("America/Chicago").tag("America/Chicago")
                                        Text("Europe/London").tag("Europe/London")
                                        Text("Europe/Paris").tag("Europe/Paris")
                                        Text("Asia/Tokyo").tag("Asia/Tokyo")
                                        Text("Asia/Shanghai").tag("Asia/Shanghai")
                                        Text("Australia/Sydney").tag("Australia/Sydney")
                                    }
                                    .pickerStyle(MenuPickerStyle())
                                    .frame(maxWidth: 200)
                                }
                                .padding(.leading, 20)
                            }
                            
                            // Language Spoofing
                            Toggle("Spoof Language/Locale", isOn: $spoofLanguage)
                            
                            if spoofLanguage {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("Primary Language")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Picker("Language", selection: $spoofPrimaryLanguage) {
                                            Text("English").tag("en")
                                            Text("Spanish").tag("es")
                                            Text("French").tag("fr")
                                            Text("German").tag("de")
                                            Text("Chinese").tag("zh")
                                            Text("Japanese").tag("ja")
                                        }
                                        .pickerStyle(MenuPickerStyle())
                                        .frame(maxWidth: 120)
                                    }
                                    
                                    HStack {
                                        Text("Region")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Picker("Region", selection: $spoofRegion) {
                                            Text("United States").tag("US")
                                            Text("United Kingdom").tag("GB")
                                            Text("Canada").tag("CA")
                                            Text("Australia").tag("AU")
                                            Text("Germany").tag("DE")
                                            Text("France").tag("FR")
                                            Text("Japan").tag("JP")
                                            Text("China").tag("CN")
                                        }
                                        .pickerStyle(MenuPickerStyle())
                                        .frame(maxWidth: 150)
                                    }
                                }
                                .padding(.leading, 20)
                            }
                        }
                    }
                    
                    Divider()
                    
                    // MARK: - Utility Actions
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Button("🎲 Randomize All") {
                                randomizeAllIdentifiers()
                            }
                            .buttonStyle(.bordered)
                            
                            Spacer()
                            
                            Button("🔄 Reset to Default") {
                                resetToDefaultIdentifiers()
                            }
                            .buttonStyle(.bordered)
                        }
                        
                        Text("⚠️ Some changes require app restart to take effect")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }
        } header: {
            Text("Device & Identifier Spoofing")
        } footer: {
            if spoofDevice {
                Text("Protects against device fingerprinting by spoofing various device characteristics, identifiers, and system properties.")
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func generateRandomString(_ length: Int) -> String {
        let letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<length).map{ _ in letters.randomElement()! })
    }
    
    private func generateRandomMAC() -> String {
        return (0..<6).map { _ in
            String(format: "%02x", Int.random(in: 0...255))
        }.joined(separator: ":")
    }
    
    private func randomizeAllIdentifiers() {
        spoofVendorID = UUID().uuidString
        spoofAdvertisingID = UUID().uuidString
        spoofInstallationID = generateRandomString(16)
        spoofMACAddress = generateRandomMAC()
        
        // Randomize device info
        let models = ["iPhone16,1", "iPhone15,4", "iPhone15,2", "iPhone14,7", "iPhone14,2"]
        let versions = ["17.2", "17.1.1", "17.0", "16.7.2", "16.6.1"]
        let carriers = ["Verizon", "AT&T", "T-Mobile", "Sprint"]
        let names = ["iPhone", "John's iPhone", "Sarah's iPhone", "My iPhone"]
        
        spoofDeviceModel = models.randomElement() ?? "iPhone15,2"
        spoofSystemVersion = versions.randomElement() ?? "17.2"
        spoofCarrierName = carriers.randomElement() ?? "Verizon"
        spoofDeviceName = names.randomElement() ?? "iPhone"
        spoofBatteryLevel = Double.random(in: 0.2...0.95)
        
        print("🎲 Randomized all device identifiers and properties")
    }
    
    private func resetToDefaultIdentifiers() {
        spoofVendorID = "12345678-1234-1234-1234-123456789012"
        spoofAdvertisingID = "87654321-4321-4321-4321-210987654321"
        spoofInstallationID = "DEFAULT12345678"
        spoofMACAddress = "02:00:00:00:00:00"
        spoofDeviceModel = "iPhone15,2"
        spoofSystemVersion = "17.2"
        spoofCarrierName = "Verizon"
        spoofDeviceName = "iPhone"
        spoofBatteryLevel = 0.85
        spoofScreenScale = 3.0
        spoofScreenSize = "1179x2556"
        spoofTimezoneValue = "America/New_York"
        spoofPrimaryLanguage = "en"
        spoofRegion = "US"
        
        print("🔄 Reset all device identifiers to defaults")
    }
}

// MARK: Main

struct LCAppSettingsView: View {

    @State private var documentPickerCoordinator = DocumentPickerCoordinator()

    private class DocumentPickerCoordinator: NSObject, UIDocumentPickerDelegate {
        var onDocumentPicked: ((URL) -> Void)?

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onDocumentPicked?(url)
        }
    }
    
    private var appInfo : LCAppInfo
    
    @ObservedObject private var model : LCAppModel
    
    @Binding var appDataFolders: [String]
    @Binding var tweakFolders: [String]
    

    @StateObject private var renameFolderInput = InputHelper()
    @StateObject private var moveToAppGroupAlert = YesNoHelper()
    @StateObject private var moveToPrivateDocAlert = YesNoHelper()
    @StateObject private var signUnsignedAlert = YesNoHelper()
    
    @State private var errorShow = false
    @State private var errorInfo = ""
    @State private var selectUnusedContainerSheetShow = false
    
    @EnvironmentObject private var sharedModel : SharedModel
    
    init(model: LCAppModel, appDataFolders: Binding<[String]>, tweakFolders: Binding<[String]>) {
        self.appInfo = model.appInfo
        self._model = ObservedObject(wrappedValue: model)
        _appDataFolders = appDataFolders
        _tweakFolders = tweakFolders
    }
    
    var body: some View {
        Form {
            Section {
                HStack {
                    Text("lc.appSettings.bundleId".loc)
                    Spacer()
                    Text(appInfo.relativeBundlePath)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.trailing)
                        .textSelection(.enabled)
                }
                HStack {
                    Text("lc.appSettings.remark".loc)
                    Spacer()
                    TextField("lc.appSettings.remarkPlaceholder".loc, text: $model.uiRemark)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.trailing)
                }
                if !model.uiIsShared {
                    Menu {
                        Picker(selection: $model.uiTweakFolder , label: Text("")) {
                            Label("lc.common.none".loc, systemImage: "nosign").tag(Optional<String>(nil))
                            ForEach(tweakFolders, id:\.self) { folderName in
                                Text(folderName).tag(Optional(folderName))
                            }
                        }
                    } label: {
                        HStack {
                            Text("lc.appSettings.tweakFolder".loc)
                                .foregroundColor(.primary)
                            Spacer()
                            Text(model.uiTweakFolder == nil ? "None" : model.uiTweakFolder!)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    
                    
                } else {
                    HStack {
                        Text("lc.appSettings.tweakFolder".loc)
                            .foregroundColor(.primary)
                        Spacer()
                        Text(model.uiTweakFolder == nil ? "lc.common.none".loc : model.uiTweakFolder!)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.trailing)
                    }
                }
                
                if !model.uiIsShared {
                    if LCUtils.isAppGroupAltStoreLike() || LCUtils.store() == .ADP {
                        Button("lc.appSettings.toSharedApp".loc) {
                            Task { await moveToAppGroup()}
                        }
                    }
                } else if sharedModel.multiLCStatus != 2 {
                    Button("lc.appSettings.toPrivateApp".loc) {
                        Task { await movePrivateDoc() }
                    }
                }
            } header: {
                Text("lc.common.data".loc)
            }
            
            Section {
                List{
                    ForEach(model.uiContainers.indices, id:\.self) { i in
                        NavigationLink {
                            LCContainerView(container: model.uiContainers[i], uiDefaultDataFolder: $model.uiDefaultDataFolder, delegate: self)
                        } label: {
                            HStack {
                                // ✅ ADD: Star icon for default container
                                if model.uiContainers[i].folderName == model.uiDefaultDataFolder {
                                    Image(systemName: "star.fill")
                                        .foregroundColor(.blue)
                                        .font(.system(size: 12))
                                }
                                
                                Text(model.uiContainers[i].name)
                                Spacer()
                            }
                        }
                    }
                }
                
                if(model.uiContainers.count < SharedModel.keychainAccessGroupCount) {
                    Button {
                        Task{ await createFolder() }
                    } label: {
                        Text("lc.appSettings.newDataFolder".loc)
                    }
                    if(!model.uiIsShared) {
                        Button {
                            selectUnusedContainerSheetShow = true
                        } label: {
                            Text("lc.container.selectUnused".loc)
                        }
                    }
                }
                
            } header: {
                Text("lc.common.container".loc)
            }
            
            
            // MARK: GPS Settings init
            GPSSettingsSection(
                spoofGPS: $model.uiSpoofGPS,
                latitude: $model.uiSpoofLatitude,
                longitude: $model.uiSpoofLongitude,
                altitude: $model.uiSpoofAltitude,
                locationName: $model.uiSpoofLocationName
            )
            
            // MARK: Camera Settings init
            CameraSettingsSection(
                spoofCamera: $model.uiSpoofCamera,
                spoofCameraMode: $model.uiSpoofCameraMode,
                spoofCameraType: $model.uiSpoofCameraType,
                spoofCameraImagePath: $model.uiSpoofCameraImagePath,
                spoofCameraVideoPath: $model.uiSpoofCameraVideoPath,
                spoofCameraLoop: $model.uiSpoofCameraLoop,
                spoofCameraTransformOrientation: $model.uiSpoofCameraTransformOrientation,
                spoofCameraTransformScale: $model.uiSpoofCameraTransformScale,
                spoofCameraTransformFlip: $model.uiSpoofCameraTransformFlip,
                isProcessingVideo: $model.isProcessingVideo,
                videoProcessingProgress: $model.videoProcessingProgress,
                errorInfo: $errorInfo,
                errorShow: $errorShow
            )
           

            // MARK: Network Settings init
            NetworkSettingsSection(
                spoofNetwork: $model.uiSpoofNetwork,
                proxyHost: $model.uiProxyHost,
                proxyPort: $model.uiProxyPort,
                proxyUsername: $model.uiProxyUsername,
                proxyPassword: $model.uiProxyPassword
            )

            // MARK: Security Section
            Section {
                Toggle(isOn: $model.uiHideLiveContainer) {
                    Text("lc.appSettings.hideLiveContainer".loc)
                } 

                Toggle(isOn: $model.uiDontInjectTweakLoader) {
                    Text("lc.appSettings.dontInjectTweakLoader".loc)
                }
                // }.disabled(model.uiTweakLoaderInjectFailed) // don't force disable
                
                if model.uiDontInjectTweakLoader {
                    Toggle(isOn: $model.uiDontLoadTweakLoader) {
                        Text("lc.appSettings.dontLoadTweakLoader".loc)
                    }
                }
                Toggle(isOn: $model.uiBypassSSLPinning) {
                    Text("Bypass SSL Pinning")
                }
            } header: {
                Text("Security Settings")
            }

            // MARK: Device Spoofing (Profile-Based)
            Section {
                Toggle(isOn: $model.uiDeviceSpoofingEnabled) {
                    HStack {
                        Image(systemName: "iphone")
                            .foregroundColor(.blue)
                            .frame(width: 20)
                        Text("Device Spoofing")
                    }
                }
                
                if model.uiDeviceSpoofingEnabled {
                    // Device Profile Selection
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Device Profile")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Picker("Device Profile", selection: $model.uiDeviceSpoofProfile) {
                            // iOS 26.x - iPhone 17 Series
                            Section(header: Text("iOS 26.x")) {
                                Text("iPhone 17 Pro Max").tag("iPhone 17 Pro Max")
                                Text("iPhone 17 Pro").tag("iPhone 17 Pro")
                                Text("iPhone 17").tag("iPhone 17")
                                Text("iPhone 17 Air").tag("iPhone 17 Air")
                            }
                            // iOS 18.x - iPhone 16 Series
                            Section(header: Text("iOS 18.x")) {
                                Text("iPhone 16 Pro Max").tag("iPhone 16 Pro Max")
                                Text("iPhone 16 Pro").tag("iPhone 16 Pro")
                                Text("iPhone 16").tag("iPhone 16")
                            }
                            // iOS 17.x - iPhone 15 Series
                            Section(header: Text("iOS 17.x")) {
                                Text("iPhone 15 Pro Max").tag("iPhone 15 Pro Max")
                                Text("iPhone 15 Pro").tag("iPhone 15 Pro")
                                Text("iPhone 14 Pro Max").tag("iPhone 14 Pro Max")
                                Text("iPhone 14 Pro").tag("iPhone 14 Pro")
                                Text("iPhone 13 Pro Max").tag("iPhone 13 Pro Max")
                                Text("iPhone 13 Pro").tag("iPhone 13 Pro")
                            }
                            // iPad Pro
                            Section(header: Text("iPad")) {
                                Text("iPad Pro 13-inch (M4)").tag("iPad Pro 13-inch (M4)")
                                Text("iPad Pro 11-inch (M4)").tag("iPad Pro 11-inch (M4)")
                                Text("iPad Pro 12.9 (6th gen)").tag("iPad Pro 12.9 (6th gen)")
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                    }
                    
                    // Profile Info
                    let profileInfo = getProfileInfo(for: model.uiDeviceSpoofProfile)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Model:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 60, alignment: .leading)
                            Text(profileInfo.model)
                                .font(.caption)
                                .foregroundColor(.primary)
                        }
                        HStack {
                            Text("Memory:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 60, alignment: .leading)
                            Text(profileInfo.memory)
                                .font(.caption)
                                .foregroundColor(.primary)
                        }
                        HStack {
                            Text("iOS:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 60, alignment: .leading)
                            Text(profileInfo.version)
                                .font(.caption)
                                .foregroundColor(.primary)
                        }
                        HStack {
                            Text("Chip:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 60, alignment: .leading)
                            Text(profileInfo.chip)
                                .font(.caption)
                                .foregroundColor(.primary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text("Device Fingerprinting Protection")
            } footer: {
                if model.uiDeviceSpoofingEnabled {
                    Text("Spoofs sysctlbyname, sysctl, uname, UIDevice, UIScreen, NSProcessInfo, and ASIdentifierManager to protect against device fingerprinting.")
                }
            }

            // MARK: Identifier Section (Legacy)
            DeviceSpoofingSection(
                spoofDevice: $model.uiSpoofDevice,
                spoofDeviceModel: $model.uiSpoofDeviceModel,
                spoofSystemVersion: $model.uiSpoofSystemVersion,
                spoofDeviceName: $model.uiSpoofDeviceName,
                spoofCarrierName: $model.uiSpoofCarrierName,
                spoofCustomCarrier: $model.uiSpoofCustomCarrier,
                spoofBattery: $model.uiSpoofBattery,
                spoofBatteryLevel: $model.uiSpoofBatteryLevel,
                spoofMemory: $model.uiSpoofMemory,
                spoofMemorySize: $model.uiSpoofMemorySize,
                spoofIdentifiers: $model.uiSpoofIdentifiers,
                spoofVendorID: $model.uiSpoofVendorID,
                spoofAdvertisingID: $model.uiSpoofAdvertisingID,
                spoofAdTrackingEnabled: $model.uiSpoofAdTrackingEnabled,
                spoofInstallationID: $model.uiSpoofInstallationID,
                spoofMACAddress: $model.uiSpoofMACAddress,
                spoofFingerprint: $model.uiSpoofFingerprint,
                spoofScreen: $model.uiSpoofScreen,
                spoofScreenScale: $model.uiSpoofScreenScale,
                spoofScreenSize: $model.uiSpoofScreenSize,
                spoofTimezone: $model.uiSpoofTimezone,
                spoofTimezoneValue: $model.uiSpoofTimezoneValue,
                spoofLanguage: $model.uiSpoofLanguage,
                spoofPrimaryLanguage: $model.uiSpoofPrimaryLanguage,
                spoofRegion: $model.uiSpoofRegion
            )
            
            Section {
                Toggle(isOn: $model.uiIsJITNeeded) {
                    Text("lc.appSettings.launchWithJit".loc)
                }
                if #available(iOS 26.0, *), model.uiIsJITNeeded {
                    HStack {
                        Text("lc.appSettings.jit26.script".loc)
                        Spacer()
                        if let base64String = model.jitLaunchScriptJs, !base64String.isEmpty {
                            // Show a generic name since we're not storing the filename
                            Text("lc.appSettings.jit26.scriptLoaded".loc)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundColor(.primary)

                            Button(action: {
                                model.jitLaunchScriptJs = nil
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.gray)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        } else {
                            Text("No file selected")
                                .foregroundColor(.gray)
                        }
                        Button(action: {
                            // This will trigger the file picker
                            let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.javaScript], asCopy: true)
                            picker.allowsMultipleSelection = false
                            documentPickerCoordinator.onDocumentPicked = { url in
                                do {
                                    let data = try Data(contentsOf: url)
                                    // Store the Base64-encoded string of the file content
                                    model.jitLaunchScriptJs = data.base64EncodedString()
                                } catch {
                                    errorInfo = "Failed to read file: \(error.localizedDescription)"
                                    errorShow = true
                                }
                            }
                            picker.delegate = documentPickerCoordinator

                            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                               let rootViewController = windowScene.windows.first?.rootViewController {
                                rootViewController.present(picker, animated: true)
                            }
                        }) {
                            Text("lc.common.select".loc)
                        }
                    }
                }
            } footer: {

                    if #available(iOS 26.0, *), model.uiIsJITNeeded {
                        Text("lc.appSettings.launchWithJitDesc".loc + "\n" + "lc.appSettings.jit26.scriptDesc".loc)

                    } else {
                        Text("lc.appSettings.launchWithJitDesc".loc)
                    }
                
            }

            Section {
                Toggle(isOn: $model.uiIsLocked) {
                    Text("lc.appSettings.lockApp".loc)
                }
                .onChange(of: model.uiIsLocked, perform: { newValue in
                    Task { await model.setLocked(newLockState: newValue) }
                })

                if model.uiIsLocked {
                    Toggle(isOn: $model.uiIsHidden) {
                        Text("lc.appSettings.hideApp".loc)
                    }
                    .onChange(of: model.uiIsHidden, perform: { _ in
                        Task { await toggleHidden() }
                    })
                    .transition(.opacity.combined(with: .slide)) 
                }
            } footer: {
                if model.uiIsLocked {
                    Text("lc.appSettings.hideAppDesc".loc)
                        .transition(.opacity.combined(with: .slide))
                }
            }

            Section {
                NavigationLink {
                    if let supportedLanguage = model.supportedLanguages {
                        Form {
                            Picker(selection: $model.uiSelectedLanguage) {
                                Text("lc.common.auto".loc).tag("")
                                
                                ForEach(supportedLanguage, id:\.self) { language in
                                    if language != "Base" {
                                        VStack(alignment: .leading) {
                                            Text(Locale(identifier: language).localizedString(forIdentifier: language) ?? language)
                                            Text("\(Locale.current.localizedString(forIdentifier: language) ?? "") - \(language)")
                                                .font(.footnote)
                                                .foregroundStyle(.gray)
                                        }
                                        .tag(language)
                                    }

                                }
                            } label: {
                                Text("lc.common.language".loc)
                            }
                            .pickerStyle(.inline)
                        }

                    } else {
                        Text("lc.common.loading".loc)
                            .onAppear() {
                                Task{ loadSupportedLanguages() }
                            }
                    }
                } label: {
                    HStack {
                        Text("lc.common.language".loc)
                        Spacer()
                        if model.uiSelectedLanguage == "" {
                            Text("lc.common.auto".loc)
                                .foregroundStyle(.gray)
                        } else {
                            Text(Locale.current.localizedString(forIdentifier: model.uiSelectedLanguage) ?? model.uiSelectedLanguage)
                                .foregroundStyle(.gray)
                        }
                    }
                    
                }
            }
            
            Section {
                Toggle(isOn: $model.uiFixFilePickerNew) {
                    Text("lc.appSettings.fixFilePickerNew".loc)
                }
                Toggle(isOn: $model.uiFixLocalNotification) {
                    Text("lc.appSettings.fixLocalNotification".loc)
                }
                Toggle(isOn: $model.uiUseLCBundleId) {
                    Text("lc.appSettings.useLCBundleId".loc)
                }
            } header: {
                Text("lc.appSettings.fixes".loc)
            } footer: {
                Text("lc.appSettings.useLCBundleIdDesc".loc)
            }
            
            if SharedModel.isPhone {
                Section {
                    Picker(selection: $model.uiOrientationLock) {
                        Text("lc.common.disabled".loc).tag(LCOrientationLock.Disabled)
                        Text("lc.apppSettings.orientationLock.landscape".loc).tag(LCOrientationLock.Landscape)
                        Text("lc.apppSettings.orientationLock.portrait".loc).tag(LCOrientationLock.Portrait)
                    } label: {
                        Text("lc.apppSettings.orientationLock".loc)
                    }
                }
            }
            
            Section {
                Toggle(isOn: $model.uiSpoofSDKVersion) {
                    Text("lc.appSettings.spoofSDKVersion".loc)
                }
            } footer: {
                Text("lc.appSettings.fspoofSDKVersionDesc".loc)
            }

            
            Section {
                Toggle(isOn: $model.uiDoSymlinkInbox) {
                    Text("lc.appSettings.fixFilePicker".loc)
                }
            } footer: {
                Text("lc.appSettings.fixFilePickerDesc".loc)
            }
            
            Section {
                Button("lc.appSettings.forceSign".loc) {
                    Task { await forceResign() }
                }
                .disabled(model.isAppRunning)
            } footer: {
                Text("lc.appSettings.forceSignDesc".loc)
            }
            
            Section {
                HStack {
                    Text("lc.appList.sort.lastLaunched".loc)
                    Spacer()
                    Text(formatDate(date: appInfo.lastLaunched))
                        .foregroundStyle(.gray)
                }
                HStack {
                    Text("lc.appList.sort.installationDate".loc)
                    Spacer()
                    Text(formatDate(date: appInfo.installationDate))
                        .foregroundStyle(.gray)
                }
            } header: {
                Text("lc.common.statistics")
            }

        }
        .navigationTitle(appInfo.displayName())
        .navigationBarTitleDisplayMode(.inline)
        .alert("lc.common.error".loc, isPresented: $errorShow) {
            Button("lc.common.ok".loc, action: {
            })
        } message: {
            Text(errorInfo)
        }
        
        .textFieldAlert(
            isPresented: $renameFolderInput.show,
            title: "lc.common.enterNewFolderName".loc,
            text: $renameFolderInput.initVal,
            placeholder: "",
            action: { newText in
                renameFolderInput.close(result: newText!)
            },
            actionCancel: {_ in
                renameFolderInput.close(result: "")
            }
        )
        .alert("lc.appSettings.toSharedApp".loc, isPresented: $moveToAppGroupAlert.show) {
            Button {
                self.moveToAppGroupAlert.close(result: true)
            } label: {
                Text("lc.common.move".loc)
            }
            Button("lc.common.cancel".loc, role: .cancel) {
                self.moveToAppGroupAlert.close(result: false)
            }
        } message: {
            Text("lc.appSettings.toSharedAppDesc".loc)
        }
        .alert("lc.appSettings.toPrivateApp".loc, isPresented: $moveToPrivateDocAlert.show) {
            Button {
                self.moveToPrivateDocAlert.close(result: true)
            } label: {
                Text("lc.common.move".loc)
            }
            Button("lc.common.cancel".loc, role: .cancel) {
                self.moveToPrivateDocAlert.close(result: false)
            }
        } message: {
            Text("lc.appSettings.toPrivateAppDesc".loc)
        }
        .alert("lc.appSettings.forceSign".loc, isPresented: $signUnsignedAlert.show) {
            Button {
                self.signUnsignedAlert.close(result: true)
            } label: {
                Text("lc.common.ok".loc)
            }
            Button("lc.common.cancel".loc, role: .cancel) {
                self.signUnsignedAlert.close(result: false)
            }
        } message: {
            Text("lc.appSettings.signUnsignedDesc".loc)
        }
        .sheet(isPresented: $selectUnusedContainerSheetShow) {
            LCSelectContainerView(isPresent: $selectUnusedContainerSheetShow, delegate: self)
        }
    }

    func createFolder() async {
        let newName = NSUUID().uuidString
        guard let displayName = await renameFolderInput.open(initVal: newName), displayName != "" else {
            return
        }
        let fm = FileManager()
        let dest : URL
        if model.uiIsShared {
            dest = LCPath.lcGroupDataPath.appendingPathComponent(newName)
        } else {
            dest = LCPath.dataPath.appendingPathComponent(newName)
        }
        
        do {
            try fm.createDirectory(at: dest, withIntermediateDirectories: false)
        } catch {
            errorShow = true
            errorInfo = error.localizedDescription
            return
        }
        
        self.appDataFolders.append(newName)
        let newContainer = LCContainer(folderName: newName, name: displayName, isShared: model.uiIsShared, isolateAppGroup: true)
        // assign keychain group
        var keychainGroupSet : Set<Int> = Set(minimumCapacity: 3)
        for i in 0..<SharedModel.keychainAccessGroupCount {
            keychainGroupSet.insert(i)
        }
        for container in model.uiContainers {
            keychainGroupSet.remove(container.keychainGroupId)
        }
        guard let freeKeyChainGroup = keychainGroupSet.randomElement() else {
            errorInfo = "lc.container.notEnoughKeychainGroup".loc
            errorShow = true
            return
        }
        
        model.uiContainers.append(newContainer)
        if model.uiSelectedContainer == nil {
            model.uiSelectedContainer = newContainer;
        }
        if model.uiDefaultDataFolder == nil {
            model.uiDefaultDataFolder = newName
            appInfo.dataUUID = newName
        }
        appInfo.containers = model.uiContainers;
        newContainer.makeLCContainerInfoPlist(appIdentifier: appInfo.bundleIdentifier()!, keychainGroupId: freeKeyChainGroup)
    }

    func moveToAppGroup() async {
        guard let result = await moveToAppGroupAlert.open(), result else {
            return
        }
        
        do {
            try LCPath.ensureAppGroupPaths()
            let fm = FileManager()
            try fm.moveItem(atPath: appInfo.bundlePath(), toPath: LCPath.lcGroupBundlePath.appendingPathComponent(appInfo.relativeBundlePath).path)
            for container in model.uiContainers {
                try fm.moveItem(at: LCPath.dataPath.appendingPathComponent(container.folderName),
                                to: LCPath.lcGroupDataPath.appendingPathComponent(container.folderName))
                appDataFolders.removeAll(where: { s in
                    return s == container.folderName
                })
            }
            if let tweakFolder = appInfo.tweakFolder, tweakFolder.count > 0 {
                try fm.moveItem(at: LCPath.tweakPath.appendingPathComponent(tweakFolder),
                                to: LCPath.lcGroupTweakPath.appendingPathComponent(tweakFolder))
                tweakFolders.removeAll(where: { s in
                    return s == tweakFolder
                })
            }
            appInfo.setBundlePath(LCPath.lcGroupBundlePath.appendingPathComponent(appInfo.relativeBundlePath).path)
            appInfo.isShared = true
            model.uiIsShared = true
            for container in model.uiContainers {
                container.isShared = true
            }
        } catch {
            errorInfo = error.localizedDescription
            errorShow = true
        }
        
    }
    
    func movePrivateDoc() async {
        for container in appInfo.containers {
            if let runningLC = LCUtils.getContainerUsingLCScheme(withFolderName: container.folderName) {                
                errorInfo = "lc.appSettings.appOpenInOtherLc %@ %@".localizeWithFormat(runningLC, runningLC)
                errorShow = true
                return
            }
        }

        guard let result = await moveToPrivateDocAlert.open(), result else {
            return
        }
        
        do {
            let fm = FileManager()
            try fm.moveItem(atPath: appInfo.bundlePath(), toPath: LCPath.bundlePath.appendingPathComponent(appInfo.relativeBundlePath).path)
            for container in model.uiContainers {
                try fm.moveItem(at: LCPath.lcGroupDataPath.appendingPathComponent(container.folderName),
                                to: LCPath.dataPath.appendingPathComponent(container.folderName))
                appDataFolders.append(container.folderName)
            }
            if let tweakFolder = appInfo.tweakFolder, tweakFolder.count > 0 {
                try fm.moveItem(at: LCPath.lcGroupTweakPath.appendingPathComponent(tweakFolder),
                                to: LCPath.tweakPath.appendingPathComponent(tweakFolder))
                tweakFolders.append(tweakFolder)
                model.uiTweakFolder = tweakFolder
            }
            appInfo.setBundlePath(LCPath.bundlePath.appendingPathComponent(appInfo.relativeBundlePath).path)
            appInfo.isShared = false
            model.uiIsShared = false
            for container in model.uiContainers {
                container.isShared = false
            }
        } catch {
            errorShow = true
            errorInfo = error.localizedDescription
        }
        
    }
    
    func loadSupportedLanguages() {
        do {
            try model.loadSupportedLanguages()
        } catch {
            errorShow = true
            errorInfo = error.localizedDescription
            return
        }
    }
    
    func toggleHidden() async {
        await model.toggleHidden()
    }
    
    func forceResign() async {
        if model.uiDontSign {
            guard let result = await signUnsignedAlert.open(), result else {
                return
            }
            model.uiDontSign = false
        }
        
        do {
            try await model.forceResign()
        } catch {
            errorInfo = error.localizedDescription
            errorShow = true
        }
    }

    func formatDate(date: Date?) -> String {
        guard let date else {
            return "lc.common.unknown".loc
        }
        
        let formatter1 = DateFormatter()
        formatter1.dateStyle = .short
        formatter1.timeStyle = .medium
        return formatter1.string(from: date)
    
    }
}



extension LCAppSettingsView : LCContainerViewDelegate {
    func getBundleId() -> String {
        return model.appInfo.bundleIdentifier()!
    }
    
    func unbindContainer(container: LCContainer) {
        model.uiContainers.removeAll { c in
            c === container
        }
        
        // if the deleted container is the default one, we change to another one
        if container.folderName == model.uiDefaultDataFolder && !model.uiContainers.isEmpty{
            setDefaultContainer(container: model.uiContainers[0])
        }
        // if the deleted container is the selected one, we change to the default one
        if model.uiSelectedContainer === container && !model.uiContainers.isEmpty {
            for container in model.uiContainers {
                if container.folderName == model.uiDefaultDataFolder {
                    model.uiSelectedContainer = container
                    break
                }
            }
        }
        
        if model.uiContainers.isEmpty {
            model.uiSelectedContainer = nil
            model.uiDefaultDataFolder = nil
            appInfo.dataUUID = nil
        }
        appInfo.containers = model.uiContainers
    }
    
    func setDefaultContainer(container newDefaultContainer: LCContainer ) {
        if model.uiSelectedContainer?.folderName == model.uiDefaultDataFolder {
            model.uiSelectedContainer = newDefaultContainer
        }
        
        appInfo.dataUUID = newDefaultContainer.folderName
        model.uiDefaultDataFolder = newDefaultContainer.folderName
    }
    
    func saveContainer(container: LCContainer) {
        container.makeLCContainerInfoPlist(appIdentifier: appInfo.bundleIdentifier()!, keychainGroupId: container.keychainGroupId)
        appInfo.containers = model.uiContainers
        model.objectWillChange.send()
    }
    
    func getSettingsBundle() -> Bundle? {
        return Bundle(url: URL(fileURLWithPath: appInfo.bundlePath()).appendingPathComponent("Settings.bundle"))
    }
    
    func getContainerURL(container: LCContainer) -> URL {
        let preferencesFolderUrl = container.containerURL.appendingPathComponent("Library/Preferences")
        let fm = FileManager.default
        do {
            let doExist = fm.fileExists(atPath: preferencesFolderUrl.path)
            if !doExist {
                try fm.createDirectory(at: preferencesFolderUrl, withIntermediateDirectories: true)
            }

        } catch {
            errorInfo = "Cannot create Library/Preferences folder!".loc
            errorShow = true
        }
        return container.containerURL
    }
    
}

extension LCAppSettingsView : LCSelectContainerViewDelegate {
    func addContainers(containers: Set<String>) {
        if containers.count + model.uiContainers.count > SharedModel.keychainAccessGroupCount {
            errorInfo = "lc.container.tooMuchContainers".loc
            errorShow = true
            return
        }
        
        for folderName in containers {
            let newContainer = LCContainer(folderName: folderName, name: folderName, isShared: false, isolateAppGroup: true)
            newContainer.loadName()
            if newContainer.keychainGroupId == -1 {
                // assign keychain group for old containers
                var keychainGroupSet : Set<Int> = Set(minimumCapacity: SharedModel.keychainAccessGroupCount)
                for i in 0..<SharedModel.keychainAccessGroupCount {
                    keychainGroupSet.insert(i)
                }
                for container in model.uiContainers {
                    keychainGroupSet.remove(container.keychainGroupId)
                }
                guard let freeKeyChainGroup = keychainGroupSet.randomElement() else {
                    errorInfo = "lc.container.notEnoughKeychainGroup".loc
                    errorShow = true
                    return
                }
                newContainer.makeLCContainerInfoPlist(appIdentifier: appInfo.bundleIdentifier()!, keychainGroupId: freeKeyChainGroup)
            }

            
            model.uiContainers.append(newContainer)
            if model.uiSelectedContainer == nil {
                model.uiSelectedContainer = newContainer;
            }
            if model.uiDefaultDataFolder == nil {
                model.uiDefaultDataFolder = folderName
                appInfo.dataUUID = folderName
            }


        }
        appInfo.containers = model.uiContainers;

    }
}

struct CameraImagePickerView: View {
    @Binding var imagePath: String
    @Binding var errorInfo: String
    @Binding var errorShow: Bool
    
    // Transformation bindings
    @Binding var spoofCameraMode: String
    @Binding var spoofCameraTransformOrientation: String
    @Binding var spoofCameraTransformScale: String
    @Binding var spoofCameraTransformFlip: String
    @Binding var isProcessingVideo: Bool
    @Binding var videoProcessingProgress: Double
    
    @State private var showingFilePicker = false
    @State private var showingPhotoPicker = false
    @State private var originalImage: UIImage? // Store original
    @State private var transformedImage: UIImage? // Store transformed for preview
    @State private var isTransforming = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Current image display
            if !imagePath.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    // Header with clear button
                    HStack {
                        Text("Current Image:")
                            .font(.headline)
                        Spacer()
                        Button(action: clearImage) {
                            Text("Clear")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.bordered)
                    }
                    
                    // Image preview - show transformed version if available
                    if let previewImage = transformedImage ?? originalImage {
                        Image(uiImage: previewImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 120)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(hasAnyTransforms() ? Color.blue : Color.secondary.opacity(0.3), lineWidth: hasAnyTransforms() ? 2 : 1)
                            )
                            .overlay(
                                // Show transform indicator
                                Group {
                                    if hasAnyTransforms() && !isTransforming {
                                        VStack {
                                            Spacer()
                                            HStack {
                                                Spacer()
                                                Label("Transformed", systemImage: "wand.and.rays")
                                                    .font(.caption2)
                                                    .foregroundColor(.white)
                                                    .padding(4)
                                                    .background(Color.blue.opacity(0.8))
                                                    .cornerRadius(4)
                                                    .padding(4)
                                            }
                                        }
                                    }
                                    
                                    if isTransforming {
                                        ZStack {
                                            Color.black.opacity(0.3)
                                            VStack {
                                                ProgressView()
                                                    .scaleEffect(0.8)
                                                Text("Applying...")
                                                    .font(.caption)
                                                    .foregroundColor(.white)
                                            }
                                        }
                                        .cornerRadius(8)
                                    }
                                }
                            )
                    } else {
                        HStack {
                            Image(systemName: "photo")
                                .foregroundColor(.secondary)
                            Text(URL(fileURLWithPath: imagePath).lastPathComponent)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding()
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                    }
                    
                    // File path
                    Text("Path: \(imagePath)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }
            }
            
            // Picker buttons
            HStack(spacing: 12) {
                if #available(iOS 16.0, *) {
                    PhotosPickerWrapper(
                        onPhotoSelected: { photoItem in
                            Task {
                                await loadSelectedPhoto(photoItem)
                            }
                        }
                    )
                } else {
                    Button(action: {
                        errorInfo = "Photo picker requires iOS 16.0 or later. Please use the Files option instead."
                        errorShow = true
                    }) {
                        Label("Photos (iOS 16+)", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(true)
                }
                
                Button(action: {
                    showingFilePicker = true
                }) {
                    Label("Files", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            
            // Manual path entry
            VStack(alignment: .leading, spacing: 4) {
                Text("Manual Path")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("Path to image file", text: $imagePath)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onChange(of: imagePath) { newPath in
                        loadImageFromPath(newPath)
                    }
            }
            
            // ✅ SIMPLIFIED: Image transformations that apply immediately
            if !imagePath.isEmpty {
                Divider()
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Image Transformations")
                        .font(.headline)
                        .padding(.top, 8)
                    
                    Text("Transformations are applied to the image in real-time")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 4)
                    
                    // Verified Mode toggle
                    HStack {
                        Toggle("Verified Mode", isOn: Binding(
                            get: { spoofCameraMode == "verified" },
                            set: { newValue in
                                spoofCameraMode = newValue ? "verified" : "standard"
                                applyTransformations()
                            }
                        ))
                        
                        Spacer()
                        
                        if spoofCameraMode == "verified" {
                            Label("Anti-Detection", systemImage: "checkmark.shield")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                    .disabled(isTransforming)
                    .padding(.bottom, 4)
                    
                    if spoofCameraMode == "verified" {
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundColor(.blue)
                            Text("Adds subtle random variations to avoid detection")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(6)
                    }
                    
                    // Standard transformation controls
                    Picker("Orientation", selection: Binding(
                        get: { spoofCameraTransformOrientation },
                        set: { newValue in
                            spoofCameraTransformOrientation = newValue
                            applyTransformations()
                        }
                    )) {
                        Text("Original").tag("none")
                        Text("Force Portrait").tag("portrait") 
                        Text("Force Landscape").tag("landscape")
                        Text("Rotate 90°").tag("rotate90")
                        Text("Rotate 180°").tag("rotate180")
                        Text("Rotate 270°").tag("rotate270")
                    }
                    .disabled(isTransforming)
                    
                    Picker("Scale", selection: Binding(
                        get: { spoofCameraTransformScale },
                        set: { newValue in
                            spoofCameraTransformScale = newValue
                            applyTransformations()
                        }
                    )) {
                        Text("Fit").tag("fit")
                        Text("Fill").tag("fill")
                        Text("Stretch").tag("stretch")
                    }
                    .disabled(isTransforming)
                    
                    Picker("Flip", selection: Binding(
                        get: { spoofCameraTransformFlip },
                        set: { newValue in
                            spoofCameraTransformFlip = newValue
                            applyTransformations()
                        }
                    )) {
                        Text("None").tag("none")
                        Text("Horizontal").tag("horizontal")
                        Text("Vertical").tag("vertical")
                        Text("Both").tag("both")
                    }
                    .disabled(isTransforming)
                    
                    // Transform summary
                    if hasAnyTransforms() {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Active Transformations:")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                            
                            HStack {
                                if spoofCameraMode == "verified" {
                                    Label("Verified", systemImage: "checkmark.shield")
                                        .font(.caption2)
                                        .foregroundColor(.green)
                                }
                                
                                if spoofCameraTransformOrientation != "none" {
                                    Label(orientationLabel(), systemImage: "rotate.3d")
                                        .font(.caption2)
                                        .foregroundColor(.blue)
                                }
                                
                                if spoofCameraTransformFlip != "none" {
                                    Label(spoofCameraTransformFlip.capitalized, systemImage: "arrow.up.and.down.righttriangle.up.righttriangle.down")
                                        .font(.caption2)
                                        .foregroundColor(.purple)
                                }
                                
                                if spoofCameraTransformScale != "fit" {
                                    Label(spoofCameraTransformScale.capitalized, systemImage: "viewfinder")
                                        .font(.caption2)
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(6)
                    }
                    
                    // Reset button
                    if hasAnyTransforms() {
                        Button("Reset to Original") {
                            resetTransformations()
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                        .disabled(isTransforming)
                    }
                    
                    Text("The transformed image will be converted to a looping video when camera spoofing is enabled.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
            }
        }
        .onAppear {
            if !imagePath.isEmpty {
                loadImageFromPath(imagePath)
            }
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
    }
    
    // MARK: - Helper Functions
    
    private func clearImage() {
        if FileManager.default.fileExists(atPath: imagePath) {
            do {
                try FileManager.default.removeItem(atPath: imagePath)
            } catch {
                errorInfo = "Failed to remove image file: \(error.localizedDescription)"
                errorShow = true
            }
        }
        imagePath = ""
        originalImage = nil
        transformedImage = nil
    }
    
    private func hasAnyTransforms() -> Bool {
        return spoofCameraMode == "verified" ||
               spoofCameraTransformOrientation != "none" ||
               spoofCameraTransformFlip != "none" ||
               spoofCameraTransformScale != "fit"
    }
    
    private func orientationLabel() -> String {
        switch spoofCameraTransformOrientation {
        case "portrait": return "Portrait"
        case "landscape": return "Landscape"
        case "rotate90": return "90°"
        case "rotate180": return "180°"
        case "rotate270": return "270°"
        default: return "Original"
        }
    }
    
    private func loadImageFromPath(_ path: String) {
        guard !path.isEmpty else {
            originalImage = nil
            transformedImage = nil
            return
        }
        
        guard FileManager.default.fileExists(atPath: path) else {
            originalImage = nil
            transformedImage = nil
            DispatchQueue.main.async {
                errorInfo = "Image file not found at path: \(path)"
                errorShow = true
            }
            return
        }
        
        // Load image asynchronously
        DispatchQueue.global(qos: .userInitiated).async {
            if let image = UIImage(contentsOfFile: path) {
                DispatchQueue.main.async {
                    originalImage = image
                    applyTransformations() // Apply transformations when loading
                }
            } else {
                DispatchQueue.main.async {
                    originalImage = nil
                    transformedImage = nil
                    errorInfo = "Failed to load image from file. File may be corrupted or not a valid image format."
                    errorShow = true
                }
            }
        }
    }
    
    // ✅ SIMPLIFIED: Apply transformations directly to the image
    private func applyTransformations() {
        guard let original = originalImage else {
            transformedImage = nil
            return
        }
        
        // If no transformations, use original
        if !hasAnyTransforms() {
            transformedImage = original
            return
        }
        
        isTransforming = true
        
        // Apply transformations in background
        DispatchQueue.global(qos: .userInitiated).async {
            let transformed = applyImageTransforms(image: original)
            
            DispatchQueue.main.async {
                transformedImage = transformed
                isTransforming = false
                
                // Save the transformed image to a temp file for use by the video system
                saveTransformedImageForVideo(transformed)
            }
        }
    }
    
    private func applyImageTransforms(image: UIImage) -> UIImage {
        let originalSize = image.size
        var targetSize = originalSize
        var transform = CGAffineTransform.identity
        
        // 1. Apply orientation transforms
        switch spoofCameraTransformOrientation {
        case "portrait":
            if originalSize.width > originalSize.height {
                // Rotate landscape to portrait
                transform = transform.concatenating(CGAffineTransform(rotationAngle: .pi / 2))
                targetSize = CGSize(width: originalSize.height, height: originalSize.width)
            }
        case "landscape":
            if originalSize.height > originalSize.width {
                // Rotate portrait to landscape
                transform = transform.concatenating(CGAffineTransform(rotationAngle: .pi / 2))
                targetSize = CGSize(width: originalSize.height, height: originalSize.width)
            }
        case "rotate90":
            transform = transform.concatenating(CGAffineTransform(rotationAngle: .pi / 2))
            targetSize = CGSize(width: originalSize.height, height: originalSize.width)
        case "rotate180":
            transform = transform.concatenating(CGAffineTransform(rotationAngle: .pi))
        case "rotate270":
            transform = transform.concatenating(CGAffineTransform(rotationAngle: -.pi / 2))
            targetSize = CGSize(width: originalSize.height, height: originalSize.width)
        default:
            break
        }
        
        // 2. Apply flip transforms
        switch spoofCameraTransformFlip {
        case "horizontal":
            transform = transform.concatenating(CGAffineTransform(scaleX: -1, y: 1))
        case "vertical":
            transform = transform.concatenating(CGAffineTransform(scaleX: 1, y: -1))
        case "both":
            transform = transform.concatenating(CGAffineTransform(scaleX: -1, y: -1))
        default:
            break
        }
        
        // 3. Apply scale transforms
        var finalSize = targetSize
        switch spoofCameraTransformScale {
        case "fill":
            // Scale to fill screen (crop if necessary)
            let screenAspect = UIScreen.main.bounds.width / UIScreen.main.bounds.height
            let imageAspect = targetSize.width / targetSize.height
            
            if imageAspect > screenAspect {
                // Image is wider, scale to height
                let scale = UIScreen.main.bounds.height / targetSize.height
                finalSize = CGSize(width: targetSize.width * scale, height: UIScreen.main.bounds.height)
            } else {
                // Image is taller, scale to width
                let scale = UIScreen.main.bounds.width / targetSize.width
                finalSize = CGSize(width: UIScreen.main.bounds.width, height: targetSize.height * scale)
            }
        case "stretch":
            // Stretch to fill screen
            finalSize = UIScreen.main.bounds.size
        default: // "fit"
            // Keep original size or fit proportionally
            break
        }
        
        // 4. Apply verified mode variations
        if spoofCameraMode == "verified" {
            let seed = Int(Date().timeIntervalSince1970) % 1000
            var rng = SeededRandomGenerator(seed: seed)
            
            // Slight rotation (±1 degree)
            let rotationVariation = rng.nextDouble(-1.0, 1.0) * .pi / 180.0
            transform = transform.concatenating(CGAffineTransform(rotationAngle: rotationVariation))
            
            // Slight scale (0.98x to 1.02x)
            let scaleVariation = rng.nextDouble(0.98, 1.02)
            transform = transform.concatenating(CGAffineTransform(scaleX: scaleVariation, y: scaleVariation))
            
            // Slight translation (±3 pixels)
            let translateX = rng.nextDouble(-3.0, 3.0)
            let translateY = rng.nextDouble(-3.0, 3.0)
            transform = transform.concatenating(CGAffineTransform(translationX: translateX, y: translateY))
            
            print("🎭 Verified mode applied: rotation=\(rotationVariation * 180 / .pi)°, scale=\(scaleVariation), translate=(\(translateX),\(translateY))")
        }
        
        // 5. Render the transformed image
        UIGraphicsBeginImageContextWithOptions(finalSize, false, 1.0)
        defer { UIGraphicsEndImageContext() }
        
        guard let context = UIGraphicsGetCurrentContext() else { return image }
        
        // Apply transforms around center
        context.translateBy(x: finalSize.width / 2, y: finalSize.height / 2)
        context.concatenate(transform)
        context.translateBy(x: -finalSize.width / 2, y: -finalSize.height / 2)
        
        // Draw the image
        let drawRect = CGRect(
            x: (finalSize.width - targetSize.width) / 2,
            y: (finalSize.height - targetSize.height) / 2,
            width: targetSize.width,
            height: targetSize.height
        )
        image.draw(in: drawRect)
        
        return UIGraphicsGetImageFromCurrentImageContext() ?? image
    }
    
    private func resetTransformations() {
        spoofCameraMode = "standard"
        spoofCameraTransformOrientation = "none"
        spoofCameraTransformScale = "fit"
        spoofCameraTransformFlip = "none"
        transformedImage = originalImage
    }
    
    // Save transformed image for video conversion
    private func saveTransformedImageForVideo(_ image: UIImage) {
        guard let jpegData = image.jpegData(compressionQuality: 0.9) else { return }
        
        let tempDir = NSTemporaryDirectory()
        let transformedImagePath = tempDir.appending("lc_transformed_image.jpg")
        
        do {
            try jpegData.write(to: URL(fileURLWithPath: transformedImagePath))
            
            // Update the image path to point to the transformed version
            // This will be used by the AVFoundation hooks
            imagePath = transformedImagePath
        } catch {
            print("Failed to save transformed image: \(error)")
        }
    }
    
    @available(iOS 16.0, *)
    private func loadSelectedPhoto(_ item: PhotosPickerItem) async {
        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                // Validate image data
                guard UIImage(data: data) != nil else {
                    await MainActor.run {
                        errorInfo = "Selected file is not a valid image format"
                        errorShow = true
                    }
                    return
                }
                
                let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                let cameraImagesFolder = documentsPath.appendingPathComponent("CameraSpoof/Images")
                
                try FileManager.default.createDirectory(at: cameraImagesFolder, withIntermediateDirectories: true)
                
                let timestamp = Int(Date().timeIntervalSince1970)
                let fileName = "camera_image_\(timestamp).jpg"
                let filePath = cameraImagesFolder.appendingPathComponent(fileName)
                
                if let image = UIImage(data: data),
                   let jpegData = image.jpegData(compressionQuality: 0.9) {
                    try jpegData.write(to: filePath)
                    
                    await MainActor.run {
                        imagePath = filePath.path
                        originalImage = image
                        applyTransformations()
                    }
                } else {
                    throw NSError(domain: "ImageProcessing", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to process image data"])
                }
            }
        } catch {
            await MainActor.run {
                errorInfo = "Failed to import image: \(error.localizedDescription)"
                errorShow = true
            }
        }
    }
    
    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            
            guard url.startAccessingSecurityScopedResource() else {
                errorInfo = "Unable to access selected file"
                errorShow = true
                return
            }
            
            defer { url.stopAccessingSecurityScopedResource() }
            
            do {
                guard let image = UIImage(contentsOfFile: url.path) else {
                    errorInfo = "Selected file is not a valid image format"
                    errorShow = true
                    return
                }
                
                let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                let cameraImagesFolder = documentsPath.appendingPathComponent("CameraSpoof/Images")
                
                try FileManager.default.createDirectory(at: cameraImagesFolder, withIntermediateDirectories: true)
                
                let originalName = url.deletingPathExtension().lastPathComponent
                let extensionName = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
                let timestamp = Int(Date().timeIntervalSince1970)
                let fileName = "\(originalName)_\(timestamp).\(extensionName)"
                let destinationPath = cameraImagesFolder.appendingPathComponent(fileName)
                
                if FileManager.default.fileExists(atPath: destinationPath.path) {
                    try FileManager.default.removeItem(at: destinationPath)
                }
                try FileManager.default.copyItem(at: url, to: destinationPath)
                
                imagePath = destinationPath.path
                originalImage = image
                applyTransformations()
                
            } catch {
                errorInfo = "Failed to import image file: \(error.localizedDescription)"
                errorShow = true
            }
            
        case .failure(let error):
            errorInfo = "File selection failed: \(error.localizedDescription)"
            errorShow = true
        }
    }
}

struct CameraVideoPickerView: View {
    @Binding var videoPath: String
    @Binding var loopVideo: Bool
    @Binding var errorInfo: String
    @Binding var errorShow: Bool
    
    @State private var showingFilePicker = false
    @State private var videoThumbnail: UIImage?
    @State private var videoDuration: String = ""
    @State private var showingVideoPlayer = false // Add this for preview
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Current video display
            if !videoPath.isEmpty {
                HStack {
                    Text("Current Video:")
                        .font(.headline)
                    Spacer()
                    Button("Clear") {
                        // Remove the file from filesystem before clearing the path
                        if FileManager.default.fileExists(atPath: videoPath) {
                            do {
                                try FileManager.default.removeItem(atPath: videoPath)
                            } catch {
                                errorInfo = "Failed to remove video file: \(error.localizedDescription)"
                                errorShow = true
                            }
                        }
                        videoPath = ""
                        videoThumbnail = nil
                        videoDuration = ""
                    }
                    .font(.caption)
                    .foregroundColor(.red)
                }
                
                if let videoThumbnail = videoThumbnail {
                    Button(action: {
                        showingVideoPlayer = true
                    }) {
                        ZStack {
                            Image(uiImage: videoThumbnail)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxHeight: 120)
                                .cornerRadius(8)
                            
                            // Play button overlay
                            ZStack {
                                Circle()
                                    .fill(Color.black.opacity(0.6))
                                    .frame(width: 50, height: 50)
                                
                                Image(systemName: "play.fill")
                                    .font(.title2)
                                    .foregroundColor(.white)
                            }
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            if !videoDuration.isEmpty {
                                Text(videoDuration)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                        
                        Spacer()
                        
                        // Show if this is a transformed video
                        if videoPath.contains("_transformed") {
                            Label("Transformed", systemImage: "wand.and.rays")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                } else {
                    HStack {
                        Image(systemName: "video")
                            .foregroundColor(.secondary)
                        VStack(alignment: .leading) {
                            Text(URL(fileURLWithPath: videoPath).lastPathComponent)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Button("Preview Video") {
                                showingVideoPlayer = true
                            }
                            .font(.caption)
                            .buttonStyle(.bordered)
                        }
                        Spacer()
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                }
                
                Text("Path: \(videoPath)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }
            
            // Video settings
            if !videoPath.isEmpty {
                Toggle("Loop Video", isOn: $loopVideo)
            }
            
            // Picker buttons - FIXED VERSION
            HStack(spacing: 12) {
                if #available(iOS 16.0, *) {
                    VideoPickerWrapper(
                        onVideoSelected: { videoItem in
                            Task {
                                await loadSelectedVideo(videoItem)
                            }
                        }
                    )
                } else {
                    Button(action: {
                        errorInfo = "Photo picker requires iOS 16.0 or later. Please use the Files option instead."
                        errorShow = true
                    }) {
                        Label("Photos (iOS 16+)", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(true)
                }
                
                Button(action: {
                    showingFilePicker = true
                }) {
                    Label("Files", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            
            // Manual path entry
            VStack(alignment: .leading, spacing: 4) {
                Text("Manual Path")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("Path to video file", text: $videoPath)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onChange(of: videoPath) { newPath in
                        loadVideoPreview(from: newPath)
                    }
            }
        }
        .onAppear {
            if !videoPath.isEmpty {
                loadVideoPreview(from: videoPath)
            }
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.movie, .video],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .sheet(isPresented: $showingVideoPlayer) {
            if !videoPath.isEmpty {
                VideoPlayerView(videoPath: videoPath, isPresented: $showingVideoPlayer)
            }
        }
    }
    
    @available(iOS 16.0, *)
    private func loadSelectedVideo(_ item: PhotosPickerItem) async {
        do {
            if let movieData = try await item.loadTransferable(type: Data.self) {
                let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                let cameraVideosFolder = documentsPath.appendingPathComponent("CameraSpoof/Videos")
                
                // Create directory if it doesn't exist
                try FileManager.default.createDirectory(at: cameraVideosFolder, withIntermediateDirectories: true)
                
                // Generate unique filename
                let fileName = "camera_video_\(Date().timeIntervalSince1970).mp4"
                let filePath = cameraVideosFolder.appendingPathComponent(fileName)
                
                // Save the video
                try movieData.write(to: filePath)
                
                await MainActor.run {
                    videoPath = filePath.path
                    loadVideoPreview(from: videoPath)
                }
            }
        } catch {
            await MainActor.run {
                errorInfo = "Failed to import video: \(error.localizedDescription)"
                errorShow = true
            }
        }
    }
    
    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            
            do {
                let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                let cameraVideosFolder = documentsPath.appendingPathComponent("CameraSpoof/Videos")
                
                // Create directory if it doesn't exist
                try FileManager.default.createDirectory(at: cameraVideosFolder, withIntermediateDirectories: true)
                
                let fileName = url.lastPathComponent
                let destinationPath = cameraVideosFolder.appendingPathComponent(fileName)
                
                // Copy file to documents
                if FileManager.default.fileExists(atPath: destinationPath.path) {
                    try FileManager.default.removeItem(at: destinationPath)
                }
                try FileManager.default.copyItem(at: url, to: destinationPath)
                
                videoPath = destinationPath.path
                loadVideoPreview(from: videoPath)
                
            } catch {
                errorInfo = "Failed to import video file: \(error.localizedDescription)"
                errorShow = true
            }
            
        case .failure(let error):
            errorInfo = "File selection failed: \(error.localizedDescription)"
            errorShow = true
        }
    }
    
    private func loadVideoPreview(from path: String) {
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else {
            videoThumbnail = nil
            videoDuration = ""
            return
        }
        
        let url = URL(fileURLWithPath: path)
        let asset = AVAsset(url: url)
        
        // Generate thumbnail
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: 300, height: 300) // Add size limit for better performance
        
        Task {
            do {
                let cgImage = try imageGenerator.copyCGImage(at: CMTime.zero, actualTime: nil)
                await MainActor.run {
                    videoThumbnail = UIImage(cgImage: cgImage)
                }
            } catch {
                await MainActor.run {
                    videoThumbnail = nil
                }
            }
            
            // Get comprehensive video information
            do {
                // Get duration
                let duration = try await asset.load(.duration)
                let seconds = CMTimeGetSeconds(duration)
                
                // Get video track information
                let videoTracks = try await asset.loadTracks(withMediaType: .video)
                let audioTracks = try await asset.loadTracks(withMediaType: .audio)
                
                var videoInfo = ""
                
                if let videoTrack = videoTracks.first {
                    let naturalSize = try await videoTrack.load(.naturalSize)
                    let preferredTransform = try await videoTrack.load(.preferredTransform)
                    let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
                    
                    // Calculate actual display size after transformation
                    let displaySize = naturalSize.applying(preferredTransform)
                    let actualWidth = abs(displaySize.width)
                    let actualHeight = abs(displaySize.height)
                    
                    // Determine video orientation
                    let isRotated = preferredTransform.b != 0 || preferredTransform.c != 0
                    let orientation = isRotated ? "Rotated" : "Normal"
                    
                    // Get file size
                    let fileAttributes = try FileManager.default.attributesOfItem(atPath: path)
                    let fileSize = fileAttributes[.size] as? Int64 ?? 0
                    let fileSizeMB = Double(fileSize) / (1024 * 1024)
                    
                    // Build info string
                    videoInfo = String(format: "%.1fs", seconds)
                    videoInfo += "\n\(Int(actualWidth))×\(Int(actualHeight))"
                    videoInfo += " (\(orientation))"
                    videoInfo += String(format: "\n%.1f fps", nominalFrameRate)
                    videoInfo += String(format: "\n%.1f MB", fileSizeMB)
                    
                    // Add codec information if available
                    if let formatDescriptions = try? await videoTrack.load(.formatDescriptions) {
                        for formatDescription in formatDescriptions {
                            let codecType = CMFormatDescriptionGetMediaSubType(formatDescription)
                            let codecString = fourCharCodeToString(codecType)
                            videoInfo += "\n\(codecString)"
                            break // Just show the first codec
                        }
                    }
                    
                    // Add audio info if available
                    if !audioTracks.isEmpty {
                        videoInfo += "\n🎵 Audio"
                    } else {
                        videoInfo += "\n🔇 No Audio"
                    }
                    
                    // Add transform info if video is transformed
                    if path.contains("_transformed") {
                        videoInfo += "\n✨ Processed"
                    }
                    
                } else {
                    videoInfo = String(format: "%.1fs", seconds)
                    videoInfo += "\nNo video track"
                }
                
                await MainActor.run {
                    videoDuration = videoInfo
                }
                
            } catch {
                await MainActor.run {
                    videoDuration = "Error loading info"
                }
            }
        }
    }

    // Helper function to convert FourCharCode to readable string
    private func fourCharCodeToString(_ code: FourCharCode) -> String {
        let bytes = [
            UInt8((code >> 24) & 0xFF),
            UInt8((code >> 16) & 0xFF),
            UInt8((code >> 8) & 0xFF),
            UInt8(code & 0xFF)
        ]
        
        // Try to create a readable string
        if let string = String(bytes: bytes, encoding: .ascii) {
            return string.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // Fallback to common codec names
        switch code {
        case 1635148593: return "H.264" // 'avc1'
        case 1752589105: return "H.264" // 'hvc1' 
        case 1211250227: return "H.265" // 'hev1'
        case 1129727304: return "ProRes" // 'ap4h'
        default: return "Unknown"
        }
    }
}

@available(iOS 16.0, *)
struct PhotosPickerWrapper: View {
    let onPhotoSelected: (PhotosPickerItem) -> Void
    @State private var selectedItem: PhotosPickerItem?
    
    var body: some View {
        PhotosPicker(
            selection: $selectedItem,
            matching: .images
        ) {
            Label("Photos", systemImage: "photo.on.rectangle")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .onChange(of: selectedItem) { newItem in
            if let item = newItem {
                onPhotoSelected(item)
                selectedItem = nil // Reset selection
            }
        }
    }
}

@available(iOS 16.0, *)
struct VideoPickerWrapper: View {
    let onVideoSelected: (PhotosPickerItem) -> Void
    @State private var selectedItem: PhotosPickerItem?
    
    var body: some View {
        PhotosPicker(
            selection: $selectedItem,
            matching: .videos
        ) {
            Label("Photos", systemImage: "photo.on.rectangle")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .onChange(of: selectedItem) { newItem in
            if let item = newItem {
                onVideoSelected(item)
                selectedItem = nil // Reset selection
            }
        }
    }
}

struct VideoPlayerView: View {
    let videoPath: String
    @Binding var isPresented: Bool
    @State private var player: AVPlayer?
    
    var body: some View {
        NavigationView {
            Group {
                if let player = player {
                    VideoPlayer(player: player)
                        .onAppear {
                            player.play()
                        }
                        .onDisappear {
                            player.pause()
                        }
                } else {
                    VStack {
                        ProgressView("Loading video...")
                        Text(URL(fileURLWithPath: videoPath).lastPathComponent)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top)
                    }
                }
            }
            .navigationTitle("Video Preview")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("Done") {
                    player?.pause()
                    isPresented = false
                }
            )
        }
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
    
    private func setupPlayer() {
        guard FileManager.default.fileExists(atPath: videoPath) else {
            return
        }
        
        let url = URL(fileURLWithPath: videoPath)
        player = AVPlayer(url: url)
        
        // Set up looping if needed
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player?.currentItem,
            queue: .main
        ) { _ in
            player?.seek(to: .zero)
            player?.play()
        }
    }
}
