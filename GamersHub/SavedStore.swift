//
//  SavedStore.swift
//  GamersHub
//
//  Created by Jaiden Kumar on 14/11/26.
//


import SwiftUI
import Observation

/// Listings this person saved. Kept on the device only, like hidden items.
@MainActor
@Observable
final class SavedStore {
    private(set) var ids: [UUID]
    private let key = "savedListings.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let list = try? JSONDecoder().decode([UUID].self, from: data) {
            ids = list
        } else {
            ids = []
        }
    }

    func isSaved(_ l: Listing) -> Bool { ids.contains(l.id) }

    func toggle(_ l: Listing) {
        if let i = ids.firstIndex(of: l.id) { ids.remove(at: i) } else { ids.append(l.id) }
        if let data = try? JSONEncoder().encode(ids) { UserDefaults.standard.set(data, forKey: key) }
    }
}
