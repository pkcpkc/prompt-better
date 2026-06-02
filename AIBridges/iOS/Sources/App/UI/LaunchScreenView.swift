import SwiftUI

struct LaunchScreenView: View {
  var body: some View {
    ZStack {
      // Solid white background covering the safe area
      Color.white
        .edgesIgnoringSafeArea(.all)
      
      // Fully visible background image with 20px padding/margin
      Image("LaunchBackground")
        .resizable()
        .aspectRatio(contentMode: .fit)
        .padding(20)
    }
  }
}
