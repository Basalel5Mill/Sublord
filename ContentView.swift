//
//  ContentView.swift
//  Sublord
//
//  Created by Basalel MIltonreji on 2025-03-31.
//

//
//  ContentView.swift
//  Sublord
//
//  Created by Basalel MIltonreji on 2025-03-31.
//

import SwiftUI
import Foundation
import AVFoundation
// import ProExtensionHost // <- REMOVED: This import should not be in the main app target

struct ContentView: View {
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Use a placeholder or a generic icon if 'Fcpx-icon' is specific to the extension
                // Or ensure 'Fcpx-icon' is also part of the main app's assets
                Image("Fcpx-icon") // Make sure this asset is available to the Sublord target
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 100, height: 100)

                Text("Sublord")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Automatic Subtitle Generation for Final Cut Pro")
                    .font(.headline)
                    .multilineTextAlignment(.center)

                Spacer()

                VStack(alignment: .leading, spacing: 10) {
                    Text("This is the standalone application for Sublord.")
                        .font(.body)

                    Text("To use Sublord with Final Cut Pro, please launch Final Cut Pro and access the extension from the Extensions menu.")
                        .font(.body)
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(10)

                Spacer()

                HStack {
                    Text("© 2025 Basalel MIltonreji")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            .padding()
            .frame(minWidth: 600, minHeight: 400)
            // Consider removing the NavigationView if it's not needed for the standalone info screen
            // .navigationTitle("Sublord") // Navigation title might require NavigationView
        }
        // Apply frame to the NavigationView if you keep it
        // .frame(minWidth: 600, minHeight: 400)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
