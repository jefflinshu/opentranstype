//
//  opentranstypeApp.swift
//  opentranstype
//
//  Created by 林树 on 2026/6/3.
//

import SwiftUI

@main
struct opentranstypeApp: App {
    @NSApplicationDelegateAdaptor(AppCoordinator.self) private var appCoordinator

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
