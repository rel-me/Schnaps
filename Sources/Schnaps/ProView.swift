import SwiftUI
import MeasurementCore

struct ProSection: View {
    @ObservedObject var membership: ProMembership

    var body: some View {
        Section {
            if let tier = membership.tier {
                HStack(spacing: 18) {
                    Keepsake(tier: tier).frame(width: 68, height: 84)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Schnaps Pro · \(tier.name)").font(.headline)
                        Text(tier.keepsake).foregroundStyle(.secondary)
                        Text("Excellent taste.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
            }
            ForEach(ProTier.allCases) { tier in
                LabeledContent {
                    if let owned = membership.tier, owned.rank >= tier.rank {
                        Label("On your shelf", systemImage: "checkmark").foregroundStyle(.secondary)
                    } else {
                        Text("Coming soon")
                            .foregroundStyle(.secondary)
                    }
                } label: {
                    HStack(spacing: 10) {
                        Keepsake(tier: tier).frame(width: 24, height: 30).accessibilityHidden(true)
                        Text("Pro \(tier.name)")
                    }
                }
            }
        } header: {
            Text("A little extra spirit")
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                Text("All the tools, always free. A little something for your shelf.")
                Text("Pro purchases are temporarily unavailable while we set up a new payment provider.")
            }
            .font(.footnote)
            .padding(.top, -7)
        }
    }
}

private struct Keepsake: View {
    let tier: ProTier
    private var tint: Color {
        switch tier { case .sip: Color(red: 0.65, green: 0.43, blue: 0.24)
        case .pour: Color(red: 0.25, green: 0.66, blue: 0.67)
        case .reserve: Color(red: 0.89, green: 0.66, blue: 0.22) }
    }
    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width, h = geometry.size.height
            ZStack {
                if tier == .sip {
                    RoundedRectangle(cornerRadius: w * 0.12)
                        .fill(tint.gradient).frame(width: w * 0.58, height: h * 0.5)
                        .overlay { Image(systemName: "sparkle").font(.system(size: w * 0.23)).foregroundStyle(.white.opacity(0.65)) }
                        .rotationEffect(.degrees(-12))
                } else {
                    RoundedRectangle(cornerRadius: w * 0.12)
                        .fill(tint.gradient).frame(width: w * (tier == .reserve ? 0.8 : 0.6), height: h * 0.58)
                        .offset(y: h * 0.13)
                    RoundedRectangle(cornerRadius: w * 0.04)
                        .fill(tint.gradient).frame(width: w * 0.25, height: h * 0.35).offset(y: -h * 0.2)
                    RoundedRectangle(cornerRadius: w * 0.04)
                        .fill(tier == .reserve ? Color.yellow.gradient : Color.brown.gradient)
                        .frame(width: w * 0.34, height: h * 0.1).offset(y: -h * 0.38)
                    Image(systemName: tier == .reserve ? "sparkles" : "sparkle")
                        .font(.system(size: w * 0.26)).foregroundStyle(.white.opacity(0.8)).offset(y: h * 0.12)
                }
            }
            .frame(width: w, height: h)
        }
        .accessibilityLabel(tier.keepsake)
    }
}
