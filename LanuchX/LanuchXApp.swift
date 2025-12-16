//
//  LanuchXApp.swift
//  LanuchX
//
//  Created by Eric on 2025/12/16.
//

import SwiftUI
import CoreData

@main
struct LanuchXApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
